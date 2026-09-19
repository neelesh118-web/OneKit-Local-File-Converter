import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
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
import '../../engine/job.dart';
import '../../engine/pdf/pdf_plan.dart';
import '../../engine/pdf/pdf_toolbox.dart';

/// The PDF toolbox: merge, split, rotate and compress, all through the pdfium
/// build the app already bundles.
///
/// Merge, split and rotate are container work — pdfium imports, rotates and
/// deletes whole pages and writes the file back out — so text, fonts and
/// vectors survive untouched. Compress offers that same lossless re-save, and
/// separately a rasterising mode that really shrinks a scan at the cost of the
/// text layer, spelled out where it is offered rather than buried.
class PdfToolsPage extends StatefulWidget {
  const PdfToolsPage({super.key, this.initialPaths = const []});

  /// Files handed over from another screen, in the order they were selected.
  final List<String> initialPaths;

  @override
  State<PdfToolsPage> createState() => _PdfToolsPageState();
}

class _PdfToolsPageState extends State<PdfToolsPage> {
  PdfTool _tool = PdfTool.merge;
  final List<PdfSource> _sources = [];

  /// Paths currently being measured by pdfium, so the row can show it.
  final Set<String> _inspecting = {};

  SplitMode _splitMode = SplitMode.perRange;
  final _ranges = TextEditingController();
  final _rotatePages = TextEditingController();
  int _quarterTurns = 1;
  CompressMode _compressMode = CompressMode.rebuild;
  int _dpi = 150;

  /// JPEG quality for the rasterising compress. Seeded from the app's own image
  /// quality setting in [initState], because it is the same decision.
  late int _quality;

  final _progress = ValueNotifier<double>(0);
  bool _indeterminate = false;
  bool _busy = false;
  CancelToken? _cancel;

  PdfPlan? _plan;
  PdfToolResult? _result;
  String? _error;

  @override
  void initState() {
    super.initState();
    _quality = context.read<SettingsStore>().imageQuality;
    if (widget.initialPaths.isNotEmpty) _addPaths(widget.initialPaths);
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _progress.dispose();
    _ranges.dispose();
    _rotatePages.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------- selection

  /// Adds [paths] as sources, measuring each one with pdfium first so the page
  /// count — and therefore every range the user can type — is a real number.
  Future<void> _addPaths(List<String> paths) async {
    final wanted = <String>[];
    for (final path in paths) {
      if (p.extension(path).toLowerCase() != '.pdf') {
        _snack('${p.basename(path)} is not a PDF. Only PDFs can be used here.');
        continue;
      }
      if (!wanted.contains(path)) wanted.add(path);
    }
    if (wanted.isEmpty) return;

    setState(() => _inspecting.addAll(wanted));
    final loaded = <PdfSource>[];
    for (final path in wanted) {
      try {
        loaded.add(await PdfToolbox.inspect(path));
      } on ConversionException catch (e) {
        _snack(e.message);
      } finally {
        if (mounted) setState(() => _inspecting.remove(path));
      }
    }
    if (!mounted || loaded.isEmpty) return;

    setState(() {
      for (final source in loaded) {
        _sources.removeWhere((s) => s.path == source.path);
        _sources.add(source);
      }
      _trimForTool();
      _result = null;
      _plan = null;
      _error = null;
    });
  }

  /// Only merge takes more than one file; every other tool works on one, so the
  /// most recently added one wins.
  void _trimForTool() {
    if (_tool == PdfTool.merge) return;
    if (_sources.length > 1) {
      final keep = _sources.last;
      _sources
        ..clear()
        ..add(keep);
    }
  }

  Future<void> _pick({required bool multiple}) async {
    // Deliberately unfiltered, like the rest of the app: Android maps
    // extensions onto MIME types, and a filtered picker that decides nothing is
    // selectable is worse than checking the extension afterwards.
    final paths = <String>[];
    if (multiple) {
      for (final file in await FilePicker.pickFiles()) {
        if (file.path != null) paths.add(file.path!);
      }
    } else {
      final file = await FilePicker.pickFile();
      if (file?.path != null) paths.add(file!.path!);
    }
    if (paths.isEmpty || !mounted) return;
    await _addPaths(paths);
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  // ------------------------------------------------------------------- run

  PdfPlan? _buildPlan() {
    try {
      return switch (_tool) {
        PdfTool.merge => PdfPlanner.merge(_sources),
        PdfTool.split => PdfPlanner.split(
            _sources.first,
            mode: _splitMode,
            ranges: _ranges.text,
          ),
        PdfTool.rotate => PdfPlanner.rotate(
            _sources.first,
            quarterTurns: _quarterTurns,
            pages: _rotatePages.text,
          ),
        PdfTool.compress => PdfPlanner.compress(
            _sources.first,
            mode: _compressMode,
            dpi: _dpi,
            quality: _quality,
          ),
      };
    } on ConversionException catch (e) {
      setState(() => _error = e.message);
      return null;
    }
  }

  Future<void> _run() async {
    final plan = _buildPlan();
    if (plan == null) return;

    final settings = context.read<SettingsStore>();
    final cancel = CancelToken();
    setState(() {
      _busy = true;
      _plan = plan;
      _result = null;
      _error = null;
      // pdfium imports and saves in one call each, so a single-output job has
      // nothing honest to show between "started" and "written".
      _indeterminate = plan.outputs.length == 1;
      _progress.value = 0;
      _cancel = cancel;
    });

    PdfToolResult? result;
    Object? failure;
    final started = DateTime.now();
    try {
      final dir = settings.outputDir ?? (await ConversionEngine.outputDir()).path;
      result = await PdfToolbox.run(
        plan,
        outputDirectory: dir,
        cancel: cancel,
        onProgress: (value) {
          if (mounted) _progress.value = value;
        },
      );
    } catch (e) {
      failure = e;
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _indeterminate = false;
      _cancel = null;
      _result = result;
      if (failure != null) {
        _error = failure is ConversionException
            ? failure.message
            : 'The PDF could not be written.';
      }
    });

    if (result != null) {
      await HistoryStore.instance.recordTool(
        tool: plan.tool,
        name: p.basename(result.outputs.first),
        status: JobStatus.done,
        elapsed: result.elapsed,
        sourceBytes: result.sourceBytes,
        outputBytes: result.outputBytes,
        outputs: result.outputs,
      );
    } else if (failure != null) {
      // A failed run is written down too, with the engine's own account of why.
      // It is what the report screen reads back, and without it a merge that
      // dies half way through would leave no trace anywhere in the app.
      var sourceBytes = 0;
      for (final source in _sources) {
        try {
          sourceBytes += await File(source.path).length();
        } catch (_) {
          // A size that cannot be read is not worth failing the record over.
        }
      }
      await HistoryStore.instance.recordTool(
        tool: plan.tool,
        name: _sources.isEmpty ? 'document.pdf' : _sources.first.name,
        status: JobStatus.failed,
        elapsed: DateTime.now().difference(started),
        sourceBytes: sourceBytes,
        outputBytes: 0,
        outputs: const [],
        error: _error,
        errorDetail: failure is ConversionException ? failure.detail : null,
      );
    }
  }

  Future<void> _open(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      _snack('No app on this device can open PDF files.');
    }
  }

  Future<void> _share(List<String> paths) async {
    await SharePlus.instance.share(
      ShareParams(files: [for (final path in paths) XFile(path)]),
    );
  }

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return Scaffold(
      backgroundColor: t.background,
      body: SafeArea(
        child: Column(
          children: [
            const AppBanner(),
            PageHeader(
              title: 'PDF tools',
              subtitle: 'Merge, split, rotate and compress — on this device',
              onBack: () => context.pop(),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                children: [
                  _toolRow(),
                  const SectionTitle('Files'),
                  _filesPanel(),
                  ..._options(),
                  const SizedBox(height: 18),
                  if (_busy)
                    _runningPanel()
                  else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _canRun ? _run : null,
                        child: Text(_runLabel),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Panel(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.priority_high_rounded, size: 18, color: t.textSecondary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _error!,
                              style: TextStyle(fontSize: 13.5, height: 1.45, color: t.textPrimary),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  if (_result != null) ...[
                    const SizedBox(height: 14),
                    _resultPanel(_result!),
                  ],
                  const SizedBox(height: 16),
                  const SupportCard(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolRow() {
    const tools = [
      (PdfTool.merge, 'Merge', Icons.merge_rounded),
      (PdfTool.split, 'Split', Icons.call_split_rounded),
      (PdfTool.rotate, 'Rotate', Icons.rotate_90_degrees_cw_rounded),
      (PdfTool.compress, 'Compress', Icons.compress_rounded),
    ];
    final t = context.tokens;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final (tool, label, icon) in tools)
            InkWell(
              onTap: _busy
                  ? null
                  : () => setState(() {
                        _tool = tool;
                        _trimForTool();
                        _plan = null;
                        _result = null;
                        _error = null;
                      }),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _tool == tool ? t.accent : Colors.transparent,
                  border: Border.all(color: _tool == tool ? t.accent : t.border),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icon,
                      size: 17,
                      color: _tool == tool ? t.onAccent : t.textSecondary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: _tool == tool ? t.onAccent : t.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _filesPanel() {
    final t = context.tokens;
    final multiple = _tool == PdfTool.merge;

    return Panel(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_sources.isEmpty && _inspecting.isEmpty)
            Text(
              multiple
                  ? 'Add two or more PDFs. They are joined in the order you add them.'
                  : 'Add the PDF you want to ${_tool.name}.',
              style: TextStyle(fontSize: 13, height: 1.45, color: t.textFaint),
            ),
          for (final source in _sources)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  FormatBadge('PDF', size: 34, filled: true),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          source.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: t.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${source.pageCount} page${source.pageCount == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 11.5, color: t.textFaint),
                        ),
                      ],
                    ),
                  ),
                  if (!_busy)
                    IconButton(
                      tooltip: 'Remove',
                      onPressed: () => setState(() {
                        _sources.remove(source);
                        _plan = null;
                        _result = null;
                      }),
                      icon: Icon(Icons.close_rounded, size: 18, color: t.textFaint),
                    ),
                ],
              ),
            ),
          for (final path in _inspecting)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: t.textFaint),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      p.basename(path),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13, color: t.textFaint),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : () => _pick(multiple: multiple),
                  icon: Icon(
                    multiple || _sources.isEmpty
                        ? Icons.add_rounded
                        : Icons.swap_horiz_rounded,
                    size: 18,
                  ),
                  label: Text(
                    multiple
                        ? 'Add PDFs'
                        : (_sources.isEmpty ? 'Choose a PDF' : 'Replace PDF'),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
        ],
      ),
    );
  }

  List<Widget> _options() {
    final t = context.tokens;
    return switch (_tool) {
      PdfTool.merge => const [],
      PdfTool.split => [
          const SectionTitle('How to split'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chips<SplitMode>(
                  values: const [SplitMode.perRange, SplitMode.perPage],
                  current: _splitMode,
                  labelOf: (v) => v == SplitMode.perRange ? 'Page ranges' : 'Every page',
                  onPick: (v) => setState(() {
                    _splitMode = v;
                    _plan = null;
                    _result = null;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 14),
                if (_splitMode == SplitMode.perRange)
                  TextField(
                    controller: _ranges,
                    onChanged: (_) => setState(() {
                      _plan = null;
                      _result = null;
                      _error = null;
                    }),
                    keyboardType: TextInputType.text,
                    decoration: const InputDecoration(
                      hintText: '1-3, 4-6 — one file per range',
                    ),
                  )
                else
                  Text(
                    'One file per page, named after the page number.',
                    style: TextStyle(fontSize: 12.5, color: t.textFaint),
                  ),
              ],
            ),
          ),
        ],
      PdfTool.rotate => [
          const SectionTitle('Rotation'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chips<int>(
                  values: const [3, 2, 1],
                  current: _quarterTurns,
                  labelOf: (v) => switch (v) {
                    3 => '90° left',
                    2 => '180°',
                    _ => '90° right',
                  },
                  onPick: (v) => setState(() {
                    _quarterTurns = v;
                    _plan = null;
                    _result = null;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _rotatePages,
                  onChanged: (_) => setState(() {
                    _plan = null;
                    _result = null;
                    _error = null;
                  }),
                  decoration: const InputDecoration(
                    hintText: 'Pages, e.g. 2, 5-7 — blank rotates all',
                  ),
                ),
              ],
            ),
          ),
        ],
      PdfTool.compress => [
          const SectionTitle('How to compress'),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _chips<CompressMode>(
                  values: const [CompressMode.rebuild, CompressMode.rasterise],
                  current: _compressMode,
                  labelOf: (v) => v == CompressMode.rebuild ? 'Re-save' : 'Rasterise',
                  onPick: (v) => setState(() {
                    _compressMode = v;
                    _plan = null;
                    _result = null;
                    _error = null;
                  }),
                ),
                const SizedBox(height: 12),
                Text(
                  _compressMode == CompressMode.rebuild
                      ? 'Rewrites the file, dropping whatever nothing refers to. Text stays '
                          'selectable and nothing is re-encoded — so a file that was never '
                          'amended may barely change.'
                      : 'Renders every page as a JPEG and rebuilds the document. This is what '
                          'shrinks a scan, and the text layer does not survive it: the result '
                          'is no longer selectable or searchable.',
                  style: TextStyle(fontSize: 12.5, height: 1.45, color: t.textFaint),
                ),
                if (_compressMode == CompressMode.rasterise) ...[
                  const SizedBox(height: 16),
                  _label('Render density', '$_dpi dpi'),
                  const SizedBox(height: 8),
                  _chips<int>(
                    values: const [110, 150, 200, 300],
                    current: _dpi,
                    labelOf: (v) => '$v',
                    onPick: (v) => setState(() {
                      _dpi = v;
                      _plan = null;
                      _result = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  _label('JPEG quality', '$_quality'),
                  Slider(
                    value: _quality.toDouble(),
                    min: 30,
                    max: 100,
                    divisions: 14,
                    onChanged: (v) => setState(() {
                      _quality = v.round();
                      _plan = null;
                      _result = null;
                    }),
                  ),
                ],
              ],
            ),
          ),
        ],
    };
  }

  Widget _runningPanel() {
    final t = context.tokens;
    return Panel(
      child: Column(
        children: [
          PulseProgressListener(
            progress: _progress,
            indeterminate: _indeterminate,
            size: 150,
            label: _tool.name,
          ),
          const SizedBox(height: 14),
          Text(
            _indeterminate
                ? 'Writing one file — pdfium has no progress to report mid-save'
                : 'Writing ${_plan?.outputs.length ?? 0} files',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: t.textFaint),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => _cancel?.cancel(),
              child: const Text('Cancel'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultPanel(PdfToolResult result) {
    final t = context.tokens;
    final plan = _plan;
    final delta = plan != null && plan.outputs.length == 1 ? result.sizeDeltaRatio : null;
    final names = result.outputs.map(p.basename).toList();

    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_rounded, size: 20, color: t.textPrimary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  plan?.tool.label ?? 'PDF written',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${names.first}${names.length > 1 ? ' + ${names.length - 1} more' : ''}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12.5, color: t.textFaint),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              StatPill(
                label: 'Written',
                value: humanBytes(result.outputBytes),
                icon: Icons.save_alt_rounded,
              ),
              const SizedBox(width: 10),
              StatPill(
                label: 'Took',
                value: humanDuration(result.elapsed),
                icon: Icons.timer_outlined,
              ),
              const SizedBox(width: 10),
              StatPill(
                label: delta == null
                    ? 'Pages'
                    : (delta < 0 ? 'Smaller' : 'Larger'),
                value: delta == null
                    ? '${plan?.totalOutputPages ?? 0}'
                    : '${(delta.abs() * 100).toStringAsFixed(0)}%',
                icon: delta == null
                    ? Icons.description_outlined
                    : (delta < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded),
              ),
            ],
          ),
          if (plan != null && plan.isLossy) ...[
            const SizedBox(height: 12),
            Text(
              'Pages were rasterised: the result has no text layer, so nothing in it '
              'is selectable or searchable.',
              style: TextStyle(fontSize: 12, height: 1.4, color: t.textFaint),
            ),
          ],
          if (delta != null && delta >= 0 && plan?.tool == PdfTool.compress) ...[
            const SizedBox(height: 12),
            Text(
              'This file was already about as small as it gets. Rasterising it is the '
              'option that really shrinks a page-image document.',
              style: TextStyle(fontSize: 12, height: 1.4, color: t.textFaint),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(result.outputs.first),
                  icon: const Icon(Icons.open_in_new_rounded, size: 18),
                  label: const Text('Open'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _share(result.outputs),
                  icon: const Icon(Icons.ios_share_rounded, size: 18),
                  label: const Text('Share'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/files'),
                  icon: const Icon(Icons.folder_open_rounded, size: 18),
                  label: const Text('Files'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool get _canRun {
    if (_busy || _sources.isEmpty || _inspecting.isNotEmpty) return false;
    if (_tool == PdfTool.merge) return _sources.length >= 2;
    return true;
  }

  String get _runLabel => switch (_tool) {
        PdfTool.merge => _sources.length >= 2
            ? 'Merge ${_sources.length} PDFs'
            : 'Add at least two PDFs',
        PdfTool.split => _splitMode == SplitMode.perPage
            ? 'Split into ${_sources.isEmpty ? 'pages' : '${_sources.first.pageCount} files'}'
            : 'Split by range',
        PdfTool.rotate => 'Rotate',
        PdfTool.compress => _compressMode == CompressMode.rasterise
            ? 'Rasterise at $_dpi dpi'
            : 'Re-save smaller',
      };

  Widget _label(String title, String value) {
    final t = context.tokens;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        Text(
          value,
          style: TextStyle(fontSize: 13, color: t.textFaint, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _chips<T>({
    required List<T> values,
    required T current,
    required String Function(T) labelOf,
    required ValueChanged<T> onPick,
  }) {
    final t = context.tokens;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final v in values)
          InkWell(
            onTap: _busy ? null : () => onPick(v),
            borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: v == current ? t.accent : Colors.transparent,
                border: Border.all(color: v == current ? t.accent : t.border),
                borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
              ),
              child: Text(
                labelOf(v),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: v == current ? t.onAccent : t.textPrimary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
