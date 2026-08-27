import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ads/ads.dart';
import '../../core/data/history_store.dart';
import '../../core/data/settings_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
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
  int _currentIndex = 0;

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
    _cancel?.cancel();
    _extracted?.delete(recursive: true).catchError((_) => Directory(''));
    super.dispose();
  }

  // ------------------------------------------------------------ selection

  void _addPaths(List<String> paths, {String? label}) {
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

  /// Targets every selected file can actually be converted into.
  List<FileFormat> _commonTargets() {
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
    final result = await FilePicker.platform.pickFiles(allowMultiple: true);
    _addPaths([
      for (final f in result?.files ?? <PlatformFile>[])
        if (f.path != null) f.path!,
    ]);
  }

  Future<void> _pickZip() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['zip'],
    );
    final path = result?.files.firstOrNull?.path;
    if (path == null) return;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
      final dir = await Directory(
        p.join((await ConversionEngine.tempDir()).path, 'zip_${DateTime.now().millisecondsSinceEpoch}'),
      ).create(recursive: true);
      _extracted = dir;

      final extracted = <String>[];
      for (final f in archive.files) {
        if (!f.isFile) continue;
        // Flatten to basenames so a crafted entry name cannot escape the
        // extraction directory.
        final name = p.basename(f.name);
        if (name.isEmpty || name.startsWith('.')) continue;
        if (FormatRegistry.byExt(p.extension(name)) == null) continue;
        final out = File(p.join(dir.path, name));
        await out.writeAsBytes(f.content as List<int>, flush: true);
        extracted.add(out.path);
      }

      if (extracted.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('No convertible files were found in that ZIP.')),
        );
        return;
      }
      _addPaths(extracted, label: p.basename(path));
      messenger.showSnackBar(
        SnackBar(content: Text('Added ${extracted.length} files from ${p.basename(path)}')),
      );
    } catch (e) {
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
      _currentIndex = 0;
      for (final i in _items) {
        i.job = null;
      }
    });

    final outputDir = context.read<SettingsStore>().outputDir;
    var succeeded = 0;

    for (var i = 0; i < _items.length; i++) {
      if (cancel.isCancelled) break;
      final item = _items[i];
      if (item.format == null) continue;

      final job = ConversionJob(
        id: '${DateTime.now().microsecondsSinceEpoch}_$i',
        sourcePath: item.path,
        source: item.format,
        target: target,
        options: _options,
      );
      setState(() {
        _currentIndex = i;
        item.job = job;
      });

      await ConversionEngine.instance.run(
        job,
        cancel: cancel,
        outputDirectory: outputDir,
        onUpdate: () {
          if (mounted) setState(() {});
        },
      );
      await HistoryStore.instance.record(job);
      if (job.status == JobStatus.done) succeeded++;
    }

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

  List<_Item> get _done => _items.where((i) => i.job?.status == JobStatus.done).toList();

  Future<void> _shareAll() async {
    final files = [
      for (final i in _done)
        if (i.job?.outputPath != null) XFile(i.job!.outputPath!),
    ];
    if (files.isEmpty) return;
    await Share.shareXFiles(files, subject: 'Converted with OneKit');
  }

  /// Packs every successful output into one ZIP for a single share/save.
  Future<void> _zipResults() async {
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

    final dir = await ConversionEngine.outputDir();
    await dir.create(recursive: true);
    final zipPath = p.join(
      dir.path,
      'OneKit_${_target?.upper ?? 'batch'}_${DateTime.now().millisecondsSinceEpoch}.zip',
    );
    await File(zipPath).writeAsBytes(encoded, flush: true);

    messenger.showSnackBar(SnackBar(content: Text('Saved ${p.basename(zipPath)}')));
    await Share.shareXFiles([XFile(zipPath)]);
  }

  Future<void> _openOptions() async {
    final target = _target;
    final source = _items.firstOrNull?.format;
    if (target == null || source == null) return;
    final updated = await showModalBottomSheet<ConvertOptions>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OptionsSheet(source: source, target: target, options: _options),
    );
    if (updated != null && mounted) setState(() => _options = updated);
  }

  // ----------------------------------------------------------------- view

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    final targets = _commonTargets();

    return Column(
      children: [
        PageHeader(
          title: 'Batch',
          subtitle: _items.isEmpty
              ? 'Convert many files at once'
              : '${_items.length} file${_items.length == 1 ? '' : 's'} queued',
          actions: [
            if (_items.isNotEmpty && !_running)
              IconButton(
                tooltip: 'Clear queue',
                onPressed: () => setState(() {
                  _items.clear();
                  _target = null;
                }),
                icon: const Icon(Icons.delete_sweep_outlined),
              ),
          ],
        ),
        Expanded(
          child: _items.isEmpty ? _empty() : _queue(targets),
        ),
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
          message: 'Add several files, or drop in a ZIP and OneKit will\nconvert everything inside it.',
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
        const OneKitBanner(),
      ],
    );
  }

  Widget _queue(List<FileFormat> targets) {
    final t = context.tokens;
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      children: [
        if (_running)
          Panel(
            child: Column(
              children: [
                PulseProgress(progress: _overall, size: 170, label: 'File ${_currentIndex + 1} of ${_items.length}'),
                const SizedBox(height: 8),
                Text(
                  'Converting to ${_target?.upper ?? ''}',
                  style: TextStyle(fontSize: 13, color: t.textFaint, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          )
        else ...[
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
            targets.isEmpty ? 'No shared target format' : 'Convert everything to',
          ),
          if (targets.isEmpty)
            Panel(
              child: Text(
                'These files have no target format in common. Remove the odd one out, or convert them in separate batches.',
                style: TextStyle(fontSize: 13.5, height: 1.5, color: t.textFaint),
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
        for (final item in _items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _ItemRow(
              item: item,
              onRemove: _running ? null : () => setState(() => _items.remove(item)),
            ),
          ),
        if (_done.isNotEmpty && !_running) ...[
          const SectionTitle('Results'),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shareAll,
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: Text('Share ${_done.length}'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _zipResults,
                  icon: const Icon(Icons.folder_zip_rounded, size: 18),
                  label: const Text('Save as ZIP'),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        const OneKitBanner(),
      ],
    );
  }

  Widget _bottomBar(dynamic t, List<FileFormat> targets) {
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.viewPaddingOf(context).bottom + 14),
      decoration: BoxDecoration(
        color: t.background.withValues(alpha: 0.95),
        border: Border(top: BorderSide(color: t.border)),
      ),
      child: _running
          ? SizedBox(
              width: double.infinity,
              child: OutlinedButton(onPressed: _cancelAll, child: const Text('Cancel batch')),
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
                    onPressed: _target == null || targets.isEmpty ? null : _runAll,
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
  _Item({required this.path, required this.format, this.label});
  final String path;
  final FileFormat? format;

  /// Set when the file came out of a ZIP, so the source is visible in the row.
  final String? label;
  ConversionJob? job;
}

class _TargetPill extends StatelessWidget {
  const _TargetPill({required this.format, required this.selected, required this.onTap});
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
              FormatBadge(item.format?.ext ?? '?', size: 38),
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
                      style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600, color: t.textPrimary),
                    ),
                    const SizedBox(height: 2),
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
              child: LinearProgressIndicator(
                value: job.indeterminate ? null : job.progress,
                minHeight: 3,
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _status(BuildContext context, ConversionJob? job, bool unsupported) {
    if (unsupported) return 'Unsupported file type';
    final size = File(item.path).existsSync() ? humanBytes(File(item.path).lengthSync()) : '';
    if (job == null) return [if (item.label != null) 'from ${item.label}', size].join(' · ');
    return switch (job.status) {
      JobStatus.queued => 'Waiting',
      JobStatus.running => job.indeterminate
          ? 'Converting'
          : 'Converting ${(job.progress * 100).toStringAsFixed(0)}%',
      JobStatus.done => 'Done · ${humanBytes(job.outputBytes)} · ${humanDuration(job.elapsed)}',
      JobStatus.cancelled => 'Cancelled',
      JobStatus.failed => job.error ?? 'Failed',
    };
  }
}
