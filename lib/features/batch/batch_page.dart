import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ads/ads.dart';
import '../../core/data/history_store.dart';
import '../../core/data/settings_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/file_preview.dart';
import '../../core/widgets/pulse.dart';
import '../../engine/converters/converter.dart';
import '../../engine/engine.dart';
import '../../engine/format.dart';
import '../../engine/job.dart';
import '../../engine/registry.dart';
import '../convert/options_sheet.dart';

/// Bulk conversion: many files at once, or every file inside a ZIP.
///
/// Jobs run one at a time. Conversion is CPU- and memory-heavy, and running
/// four videos in parallel on a phone is slower overall than running them in
/// sequence — plus a serial queue gives an honest overall percentage.
class BatchPage extends StatefulWidget {
  const BatchPage({super.key});

  /// Files handed over from the Convert tab before navigating here.
  static List<String> _pending = const [];
  static void seed(List<String> paths) => _pending = paths;

  @override
  State<BatchPage> createState() => _BatchPageState();
}

class _BatchPageState extends State<BatchPage> {
  final List<_Item> _items = [];
  FileFormat? _target;
  ConvertOptions _options = const ConvertOptions();

  bool _running = false;
  CancelToken? _cancel;

  /// Files finished so far. With jobs running concurrently there is no single
  /// "current" file to point at, so the queue reports completions instead.
  int _completed = 0;

  /// Temp directory holding files extracted from a ZIP, cleaned up on dispose.
  Directory? _extracted;

  @override
  void initState() {
    super.initState();
    if (BatchPage._pending.isNotEmpty) {
      _addPaths(BatchPage._pending);
      BatchPage._pending = const [];
    }
  }

  @override
  void dispose() {
    _overallProgress.dispose();
    _cancel?.cancel();
    // Do not delete extracted inputs while a cancelled converter may still be
    // unwinding. The run loop cleans them after all workers have stopped.
    if (!_running) {
      _extracted?.delete(recursive: true).catchError((_) => Directory(''));
    }
    super.dispose();
  }

  // ------------------------------------------------------------ selection

  void _addPaths(List<String> paths, {String? label}) {
    _commonTargetsCache = null;
    for (final path in paths) {
      if (_items.any((i) => i.path == path)) continue;
      final format = FormatRegistry.byExt(p.extension(path));
      _items.add(_Item(path: path, format: format, label: label));
    }
    _pruneTarget();
    if (mounted) setState(() {});
  }

  /// Drops the chosen target if a newly added file cannot reach it.
  void _pruneTarget() {
    final target = _target;
    if (target == null) return;
    if (!_commonTargets().any((f) => f.ext == target.ext)) _target = null;
  }

  /// Cached result of [_computeCommonTargets]. The queue changes rarely; build
  /// runs many times a second while a conversion reports progress.
  List<FileFormat>? _commonTargetsCache;

  /// Targets every selected file can actually be converted into.
  List<FileFormat> _commonTargets() =>
      _commonTargetsCache ??= _computeCommonTargets();

  List<FileFormat> _computeCommonTargets() {
    final sources = _items.map((i) => i.format).whereType<FileFormat>().toSet();
    if (sources.isEmpty) return const [];
    List<FileFormat>? common;
    for (final s in sources) {
      final reachable = FormatRegistry.targetsFor(s)
          .where((f) => ConversionEngine.instance.canConvert(s, f))
          .toSet();
      common = common == null
          ? reachable.toList()
          : common.where((f) => reachable.any((r) => r.ext == f.ext)).toList();
    }
    return common ?? const [];
  }

  Future<void> _pickFiles() async {
    final files = await FilePicker.pickFiles();
    _addPaths([
      for (final f in files)
        if (f.path != null) f.path!,
    ]);
  }

  Future<void> _pickZip() async {
    final picked = await FilePicker.pickFile();
    final path = picked?.path;
    if (path == null) return;
    if (!mounted) return;
    if (p.extension(path).toLowerCase() != '.zip') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a ZIP file to unpack.')),
      );
      return;
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dir = await Directory(
        p.join(
          (await ConversionEngine.tempDir()).path,
          'zip_${DateTime.now().millisecondsSinceEpoch}',
        ),
      ).create(recursive: true);
      _extracted = dir;
      // Parse/decompress/write in a background isolate. The archive decoder
      // reads from disk and writes each entry in bounded chunks, so a 2 GB ZIP
      // does not become a 2 GB Dart byte array or freeze the UI isolate.
      final extracted = await Isolate.run(
        () => _extractZipToDisk(path, dir.path),
      );
      if (extracted.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('No convertible files were found in that ZIP.'),
          ),
        );
        return;
      }
      _addPaths(extracted, label: p.basename(path));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Added ${extracted.length} files from ${p.basename(path)}',
          ),
        ),
      );
    } catch (e) {
      final extractedDir = _extracted;
      _extracted = null;
      if (extractedDir != null && await extractedDir.exists()) {
        await extractedDir.delete(recursive: true);
      }
      messenger.showSnackBar(
        const SnackBar(content: Text('That ZIP could not be opened.')),
      );
    }
  }

  // -------------------------------------------------------------- running

  Future<void> _runAll() async {
    final target = _target;
    if (target == null || _items.isEmpty) return;

    final cancel = CancelToken();
    setState(() {
      _running = true;
      _cancel = cancel;
      _completed = 0;
      for (final i in _items) {
        i.job = null;
      }
    });

    final outputDir = context.read<SettingsStore>().outputDir;
    var succeeded = 0;
    var started = 0;

    final queue = [
      for (var i = 0; i < _items.length; i++)
        if (_items[i].format != null) _items[i],
    ];

    Future<void> runOne(_Item item, int index) async {
      final job = ConversionJob(
        id: '${DateTime.now().microsecondsSinceEpoch}_$index',
        sourcePath: item.path,
        source: item.format,
        target: target,
        options: _options,
      );
      if (mounted) setState(() => item.job = job);
      await ConversionEngine.instance.run(
        job,
        cancel: cancel,
        outputDirectory: outputDir,
        // Per-file rows and the overall dial both listen to the job's
        // notifier, so a progress tick no longer rebuilds the whole queue.
        onUpdate: _onJobTick,
      );
      await HistoryStore.instance.record(job);
      if (job.status == JobStatus.done) succeeded++;
      if (mounted) setState(() => _completed++);
      _onJobTick();
    }

    // Light jobs run several at a time; video and very large files stay serial
    // because FFmpeg already saturates every core, so running four at once is
    // slower overall and makes the phone hot.
    Future<void> drain(int concurrency) async {
      final workers = List.generate(concurrency.clamp(1, 4), (_) async {
        while (true) {
          if (cancel.isCancelled) return;
          final index = started++;
          if (index >= queue.length) return;
          await runOne(queue[index], index);
        }
      });
      await Future.wait(workers);
    }

    await drain(_concurrencyFor(queue, target));

    if (!mounted) return;
    setState(() {
      _running = false;
      _cancel = null;
    });

    if (succeeded > 0) {
      HapticFeedback.mediumImpact();
      await context.read<SettingsStore>().bumpConversionCount(succeeded);
      if (mounted) await AdManager.instance.onBatchComplete(context);
    }
  }

  void _cancelAll() {
    _cancel?.cancel();
    HapticFeedback.lightImpact();
  }

  /// Overall batch progress, driven straight from the per-job notifiers so the
  /// page itself does not rebuild on every tick.
  final ValueNotifier<double> _overallProgress = ValueNotifier<double>(0);

  void _onJobTick() {
    if (!mounted) return;
    _overallProgress.value = _overall;
  }

  /// How many jobs to run at once. Video is left strictly serial; FFmpeg
  /// already uses every core for a single clip, so overlapping them only adds
  /// memory pressure and heat.
  static int _concurrencyFor(List<_Item> queue, FileFormat target) {
    const heavyBytes = 100 * 1024 * 1024;
    final heavy =
        target.family == Family.video ||
        queue.any(
          (i) => i.format?.family == Family.video || i.sizeBytes > heavyBytes,
        );
    if (heavy) return 1;
    return (Platform.numberOfProcessors ~/ 2).clamp(1, 4);
  }

  /// Overall progress across the queue: finished files plus the live fraction
  /// of the one currently running.
  double get _overall {
    if (_items.isEmpty) return 0;
    var sum = 0.0;
    for (final i in _items) {
      final job = i.job;
      if (job == null) continue;
      sum += job.isTerminal ? 1.0 : job.progress;
    }
    return (sum / _items.length).clamp(0.0, 1.0);
  }

  List<_Item> get _done =>
      _items.where((i) => i.job?.status == JobStatus.done).toList();

  List<_Item> get _failed =>
      _items.where((i) => i.job?.status == JobStatus.failed).toList();

  List<_Item> get _cancelled =>
      _items.where((i) => i.job?.status == JobStatus.cancelled).toList();

  bool get _hasFinished => _items.any((i) => i.job?.isTerminal ?? false);

  void _openFiles() {
    if (mounted) context.go('/files');
  }

  Future<void> _shareAll() async {
    final files = [
      for (final i in _done)
        if (i.job?.outputPath != null) XFile(i.job!.outputPath!),
    ];
    if (files.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(files: files, subject: 'Converted with Local File Converter'),
    );
  }

  /// Packs every successful output into one ZIP for a single share/save.
  Future<void> _zipResults() async {
    final configuredDir = context.read<SettingsStore>().outputDir;
    final outputs = [
      for (final i in _done)
        if (i.job?.outputPath != null) i.job!.outputPath!,
    ];
    if (outputs.isEmpty) return;

    final messenger = ScaffoldMessenger.of(context);
    final archive = Archive();
    for (final path in outputs) {
      final bytes = await File(path).readAsBytes();
      archive.addFile(ArchiveFile(p.basename(path), bytes.length, bytes));
    }
    final encoded = ZipEncoder().encode(archive);

    final dir = configuredDir == null || configuredDir.isEmpty
        ? await ConversionEngine.outputDir()
        : Directory(configuredDir);
    await dir.create(recursive: true);
    final zipPath = p.join(
      dir.path,
      'LocalFileConverter_${_target?.upper ?? 'batch'}_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    await File(zipPath).writeAsBytes(encoded, flush: true);

    messenger.showSnackBar(
      SnackBar(content: Text('Saved ${p.basename(zipPath)}')),
    );
    await SharePlus.instance.share(ShareParams(files: [XFile(zipPath)]));
  }

  Future<void> _openOptions() async {
    final target = _target;
    final source = _items.firstOrNull?.format;
    if (target == null || source == null) return;
    final updated = await showModalBottomSheet<ConvertOptions>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          OptionsSheet(source: source, target: target, options: _options),
    );
    if (updated != null && mounted) setState(() => _options = updated);
  }

  // ----------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final targets = _commonTargets();
    final done = _done.length;
    final failed = _failed.length;
    final cancelled = _cancelled.length;

    return Column(
      children: [
        const AppBanner(),
        PageHeader(
          title: 'Batch',
          subtitle: _items.isEmpty
              ? 'Convert many files at once'
              : _running
                  ? '${_items.length} file${_items.length == 1 ? '' : 's'} queued'
                  : _hasFinished
                      ? '$done converted · $failed failed${cancelled == 0 ? '' : ' · $cancelled cancelled'}'
                      : '${_items.length} file${_items.length == 1 ? '' : 's'} queued',
          actions: [
            if (_items.isNotEmpty && !_running)
              IconButton(
                tooltip: 'Clear queue',
                onPressed: () => setState(() {
                  _items.clear();
                  _target = null;
                  _commonTargetsCache = null;
                }),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
          ],
        ),
        Expanded(child: _items.isEmpty ? _empty() : _queue(targets)),
        if (_items.isNotEmpty) _bottomBar(t, targets),
      ],
    );
  }

  Widget _empty() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
      children: [
        EmptyState(
          icon: Icons.layers_outlined,
          title: 'Nothing queued',
          message: 'Add several files, or drop in a ZIP and this app will\nconvert everything inside it.',
        ),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _pickFiles,
                icon: const Icon(Icons.add_rounded, size: 20),
                label: const Text('Add files'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _pickZip,
                icon: const Icon(Icons.folder_zip_outlined, size: 19),
                label: const Text('From ZIP'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 20),
        const AppBanner(),
      ],
    );
  }

  Widget _queue(List<FileFormat> targets) {
    final t = context.tokens;
    // Computed once per build; it was previously re-scanned three times.
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        if (_running)
          Panel(
            child: Column(
              children: [
                PulseProgressListener(
                  progress: _overallProgress,
                  size: 170,
                  label: '$_completed of ${_items.length} done',
                ),
                const SizedBox(height: 8),
                Text(
                  'Converting to ${_target?.upper ?? ''}',
                  style: TextStyle(
                    fontSize: 13,
                    color: t.textFaint,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          )
        else ...[
          if (_hasFinished) _completionSummary(),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickFiles,
                  icon: const Icon(Icons.add_rounded, size: 19),
                  label: const Text('Add'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickZip,
                  icon: const Icon(Icons.folder_zip_outlined, size: 18),
                  label: const Text('From ZIP'),
                ),
              ),
            ],
          ),
          SectionTitle(
            targets.isEmpty
                ? 'No shared target format'
                : 'Convert everything to',
          ),
          if (targets.isEmpty)
            Panel(
              child: Text(
                'These files have no target format in common. Remove the odd one out, or convert them in separate batches.',
                style: TextStyle(
                  fontSize: 13.5,
                  height: 1.5,
                  color: t.textFaint,
                ),
              ),
            )
          else
            Wrap(
              spacing: 9,
              runSpacing: 9,
              children: [
                for (final f in targets.take(40))
                  _TargetPill(
                    format: f,
                    selected: _target?.ext == f.ext,
                    onTap: () => setState(() => _target = f),
                  ),
              ],
            ),
        ],
        const SectionTitle('Queue'),
        // Virtualised: a 200-file queue used to build every row on every
        // progress tick.
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _items.length,
          itemBuilder: (context, i) {
            final item = _items[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _ItemRow(
                item: item,
                onRemove: _running
                    ? null
                    : () => setState(() {
                        _items.remove(item);
                        _commonTargetsCache = null;
                      }),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        const AppBanner(),
      ],
    );
  }

  Widget _completionSummary() {
    final t = context.tokens;
    final done = _done.length;
    final failed = _failed.length;
    final cancelled = _cancelled.length;
    final configuredDir = context.read<SettingsStore>().outputDir;
    final location = configuredDir == null || configuredDir.isEmpty
        ? 'App folder in storage'
        : configuredDir;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  failed == 0 && cancelled == 0
                      ? Icons.check_circle_outline_rounded
                      : Icons.info_outline_rounded,
                  color: failed == 0 && cancelled == 0
                      ? t.accent
                      : t.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    failed == 0 && cancelled == 0
                        ? 'Conversion complete'
                        : 'Conversion finished with issues',
                    style: TextStyle(
                      color: t.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              '$done converted${failed == 0 ? '' : ' · $failed failed'}${cancelled == 0 ? '' : ' · $cancelled cancelled'}',
              style: TextStyle(
                color: t.textSecondary,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Saved to: $location',
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: t.textFaint, fontSize: 12.5, height: 1.35),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _openFiles,
                    icon: const Icon(Icons.folder_open_rounded, size: 18),
                    label: const Text('View files'),
                  ),
                ),
                if (done > 0) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _shareAll,
                      icon: const Icon(Icons.ios_share_rounded, size: 18),
                      label: Text('Share $done'),
                    ),
                  ),
                ],
              ],
            ),
            if (done > 0) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _zipResults,
                  icon: const Icon(Icons.folder_zip_rounded, size: 18),
                  label: const Text('Save as ZIP and share'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _bottomBar(dynamic t, List<FileFormat> targets) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.viewPaddingOf(context).bottom + 14,
      ),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: _running
          ? SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _cancelAll,
                child: const Text('Cancel batch'),
              ),
            )
          : Row(
              children: [
                if (_target != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: OutlinedButton(
                      onPressed: _openOptions,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(54, 54),
                        padding: EdgeInsets.zero,
                      ),
                      child: const Icon(Icons.tune_rounded, size: 21),
                    ),
                  ),
                Expanded(
                  child: FilledButton(
                    onPressed: _target == null || targets.isEmpty
                        ? null
                        : _runAll,
                    child: Text(
                      _target == null
                          ? 'Pick a format'
                          : 'Convert ${_items.length} to ${_target!.upper}',
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Item {
  _Item({required this.path, required this.format, this.label})
    : sizeBytes = _sizeOf(path);

  final String path;
  final FileFormat? format;

  /// Read once when the file is queued. Reading it inside build meant a
  /// synchronous stat per row on every progress tick — hundreds of blocking
  /// syscalls a second during a batch.
  final int sizeBytes;

  /// Set when the file came out of a ZIP, so the source is visible in the row.
  final String? label;
  ConversionJob? job;

  static int _sizeOf(String path) {
    try {
      return File(path).lengthSync();
    } on FileSystemException {
      return 0;
    }
  }
}

/// Extracts only convertible ZIP entries to disk. This function is top-level
/// so it can run in [Isolate.run] without capturing widget state.
Future<List<String>> _extractZipToDisk(
  String archivePath,
  String outputPath,
) async {
  final input = InputFileStream(archivePath);
  try {
    final archive = ZipDecoder().decodeStream(input);
    final extracted = <String>[];
    final usedPaths = <String>{};

    for (final f in archive.files) {
      if (!f.isFile || f.isSymbolicLink) continue;
      final name = _safeArchiveName(f.name);
      if (name == null || FormatRegistry.byExt(p.extension(name)) == null) {
        continue;
      }

      var relative = name;
      var out = File(p.join(outputPath, relative));
      var n = 1;
      while (usedPaths.contains(out.path) || await out.exists()) {
        final ext = p.extension(name);
        final stem = p.basenameWithoutExtension(name);
        final parent = p.dirname(name);
        relative = p.join(parent, '$stem ($n)$ext');
        out = File(p.join(outputPath, relative));
        n++;
      }
      usedPaths.add(out.path);
      await out.parent.create(recursive: true);

      final output = OutputFileStream(out.path);
      try {
        // Archive writes through its own bounded stream rather than materialising
        // the decompressed entry as a List<int>.
        f.writeContent(output, freeMemory: true);
      } finally {
        output.closeSync();
      }
      extracted.add(out.path);
    }
    return extracted;
  } finally {
    await input.close();
  }
}

/// Returns a safe relative archive path, or null for traversal/hidden
/// entries that should not become conversion inputs.
String? _safeArchiveName(String raw) {
  final normalized = raw.replaceAll('\\', '/');
  final parts = normalized
      .split('/')
      .where((part) => part.isNotEmpty && part != '.')
      .toList();
  if (parts.isEmpty ||
      parts.any((part) => part == '..' || part.startsWith('.'))) {
    return null;
  }
  return p.joinAll(parts);
}

class _TargetPill extends StatelessWidget {
  const _TargetPill({
    required this.format,
    required this.selected,
    required this.onTap,
  });
  final FileFormat format;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? t.accent : Colors.transparent,
          border: Border.all(color: selected ? t.accent : t.border),
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: Text(
          format.upper,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w800,
            color: selected ? t.onAccent : t.textPrimary,
          ),
        ),
      ),
    );
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({required this.item, this.onRemove});
  final _Item item;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final job = item.job;
    final unsupported = item.format == null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
      ),
      child: Column(
        children: [
          Row(
            children: [
              FilePreview(path: item.path, format: item.format, size: 38),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      p.basename(item.path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: t.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    if (job != null && job.status == JobStatus.running)
                      ValueListenableBuilder<double>(
                        valueListenable: job.progressNotifier,
                        builder: (context, _, __) => Text(
                          _status(context, job, unsupported),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: t.textFaint),
                        ),
                      )
                    else
                      Text(
                        _status(context, job, unsupported),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11.5, color: t.textFaint),
                      ),
                  ],
                ),
              ),
              if (job?.status == JobStatus.done)
                Icon(Icons.check_circle_rounded, size: 20, color: t.textPrimary)
              else if (job?.status == JobStatus.failed || unsupported)
                Icon(Icons.error_outline_rounded, size: 20, color: t.textFaint)
              else if (onRemove != null)
                IconButton(
                  onPressed: onRemove,
                  icon: const Icon(Icons.close_rounded, size: 18),
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          if (job != null && job.status == JobStatus.running) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              // Listens to the job directly: the page no longer rebuilds on
              // every tick, so the bar has to drive itself.
              child: ValueListenableBuilder<double>(
                valueListenable: job.progressNotifier,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: job.indeterminate ? null : value,
                  minHeight: 3,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _status(BuildContext context, ConversionJob? job, bool unsupported) {
    if (unsupported) return 'Unsupported file type';
    final size = item.sizeBytes > 0 ? humanBytes(item.sizeBytes) : '';
    if (job == null) {
      return [
        if (item.label != null) 'from ${item.label}',
        size,
      ].where((s) => s.isNotEmpty).join(' · ');
    }
    return switch (job.status) {
      JobStatus.queued => 'Waiting',
      JobStatus.running =>
        job.indeterminate
            ? 'Converting'
            : 'Converting ${(job.progress * 100).toStringAsFixed(0)}%',
      JobStatus.done =>
        'Done · ${humanBytes(job.outputBytes)} · ${humanDuration(job.elapsed)}',
      JobStatus.cancelled => 'Cancelled',
      JobStatus.failed => job.error ?? 'Failed',
    };
  }
}
