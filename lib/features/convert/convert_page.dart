import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/ads/ads.dart';
import '../../core/data/history_store.dart';
import '../../core/data/preset_store.dart';
import '../../core/data/settings_store.dart';
import '../../core/diagnostics/diagnostics.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/file_preview.dart';
import '../../core/widgets/pulse.dart';
import '../../core/widgets/starfield.dart';
import '../../engine/converters/converter.dart';
import '../../engine/engine.dart';
import '../../engine/format.dart';
import '../../engine/job.dart';
import '../../engine/registry.dart';
import '../feedback/feedback_page.dart';
import '../presets/preset_chip.dart';
import 'options_sheet.dart';
import 'target_picker.dart';

/// Everything the convert screen needs to start. Passed through GoRouter's
/// `extra` so the route stays a plain path.
class ConvertArgs {
  const ConvertArgs({
    required this.paths,
    this.target,
    this.displayNames,
    this.optimize = false,
    this.options,
    this.presetName,
  });
  final List<String> paths;
  final FileFormat? target;
  final List<String>? displayNames;

  /// Settings that came with a saved recipe. Null means the screen's own
  /// defaults, which is what every other entry point uses.
  final ConvertOptions? options;

  /// The name of the preset that was applied, when one was. A named recipe is
  /// a decision the user already made, so the screen runs it rather than
  /// asking them to confirm it again.
  final String? presetName;

  /// Opens the screen on the Optimize path: keep the file's own format and only
  /// re-encode it smaller. Ignored for formats no engine can re-encode, which
  /// falls back to the normal target picker with an explanation.
  final bool optimize;
}

enum _Phase { chooseTarget, running, finished }

/// The single-file conversion screen: pick a target, watch a real percentage,
/// then open or share the result.
class ConvertPage extends StatefulWidget {
  const ConvertPage({super.key, this.args});
  final ConvertArgs? args;

  @override
  State<ConvertPage> createState() => _ConvertPageState();
}

class _ConvertPageState extends State<ConvertPage> {
  late final String _sourcePath;
  FileFormat? _source;
  FileFormat? _target;
  ConvertOptions _options = const ConvertOptions();

  /// True while Optimize is selected: the target is the source's own format and
  /// the job re-encodes rather than converts.
  bool _optimize = false;

  _Phase _phase = _Phase.chooseTarget;
  ConversionJob? _job;
  CancelToken? _cancel;

  /// Mirrors the running job's indeterminate flag. Unlike progress, this
  /// changes at most a couple of times per job, so a rebuild is fine.
  bool _indeterminate = false;

  @override
  void initState() {
    super.initState();
    final paths = widget.args?.paths ?? const <String>[];
    _sourcePath = paths.isEmpty ? '' : paths.first;
    final source = FormatRegistry.byExt(p.extension(_sourcePath));
    _source = source;

    // Optimize is only offered when an engine can really re-encode the format,
    // so the shortcut cannot land the user on a button that cannot work.
    final wantsOptimize = widget.args?.optimize ?? false;
    _optimize =
        wantsOptimize && source != null && ConversionEngine.instance.canOptimize(source);
    final requested = widget.args?.target;
    _target = _optimize ? source : requested;

    // A recipe that cannot be run on this file — a preset saved for videos,
    // applied to a spreadsheet — falls back to the picker with the reason said
    // out loud, the same way an impossible Optimize does. Starting a job the
    // engine will refuse would spend the user's tap on a failure.
    final offTarget = !_optimize &&
        requested != null &&
        (source == null || !ConversionEngine.instance.canConvert(source, requested));
    if (offTarget) _target = null;

    // A recipe that arrived with the file replaces the screen's defaults
    // outright — that is what makes a preset a preset rather than a suggestion.
    final presetOptions = widget.args?.options;
    if (presetOptions != null) {
      _options = presetOptions;
    } else {
      final quality = context.read<SettingsStore>().imageQuality;
      _options = _options.copyWith(quality: quality);
    }

    if (wantsOptimize && !_optimize) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              source == null
                  ? 'This app does not recognise that file type yet.'
                  : '${source.upper} cannot be re-encoded smaller. Pick a format to convert it to instead.',
            ),
          ),
        );
      });
    } else if (offTarget) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              widget.args?.presetName == null
                  ? 'That format is not available for this file. Pick one instead.'
                  : 'The preset "${widget.args!.presetName}" does not fit this file. Pick a format instead.',
            ),
          ),
        );
      });
    } else if (widget.args?.presetName != null || (_target != null && !_optimize)) {
      // A saved preset is a recipe the user already decided on, so applying it
      // runs it — including an optimize preset, whose quality they chose when
      // they saved it. A bare target from a shortcut does the same. Optimize on
      // its own deliberately waits: its quality has to be visible
      // before the file is re-encoded at it.
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  @override
  void dispose() {
    _cancel?.cancel();
    super.dispose();
  }

  Future<void> _start() async {
    final source = _source;
    final target = _target;
    if (source == null || target == null) return;

    final cancel = CancelToken();
    final job = ConversionJob(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      sourcePath: _sourcePath,
      source: source,
      target: target,
      options: _options,
      displayName: widget.args?.displayNames?.firstOrNull,
      optimize: _optimize,
    );

    setState(() {
      _cancel = cancel;
      _job = job;
      _phase = _Phase.running;
    });

    await ConversionEngine.instance.run(
      job,
      cancel: cancel,
      // No setState here: the dial listens to job.progressNotifier directly,
      // so a tick repaints ~200px instead of rebuilding the whole screen.
      // Only the indeterminate flag needs a rebuild, and it changes once.
      onUpdate: () {
        if (mounted && _indeterminate != job.indeterminate) {
          setState(() => _indeterminate = job.indeterminate);
        }
      },
      outputDirectory: context.mounted ? context.read<SettingsStore>().outputDir : null,
    );

    if (!mounted) return;
    await HistoryStore.instance.record(job);
    if (job.status == JobStatus.done && mounted) {
      await context.read<SettingsStore>().bumpConversionCount();
      HapticFeedback.mediumImpact();
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.finished);
    if (job.status == JobStatus.done && mounted) {
      await AdManager.instance.onBatchComplete(context);
    }
  }

  void _cancelJob() {
    _cancel?.cancel();
    HapticFeedback.lightImpact();
  }

  void _reset() {
    setState(() {
      _phase = _Phase.chooseTarget;
      _job = null;
      _cancel = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;

    return PopScope(
      canPop: _phase != _Phase.running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmCancel();
      },
      child: Scaffold(
        backgroundColor: t.background,
        body: Stack(
          fit: StackFit.expand,
          children: [
            Starfield(
              density: 1.1,
              // The field visibly accelerates while a conversion runs.
              speed: _phase == _Phase.running ? 2.6 : 1.0,
            ),
            SafeArea(child: _body()),
          ],
        ),
      ),
    );
  }

  Widget _body() => switch (_phase) {
        _Phase.chooseTarget => _chooseTarget(),
        _Phase.running => _running(),
        _Phase.finished => _finished(),
      };

  // -------------------------------------------------------------- choose

  Widget _chooseTarget() {
    final t = context.tokens;
    final source = _source;

    if (_sourcePath.isEmpty || source == null) {
      return Column(
        children: [
          PageHeader(title: 'Convert', onBack: () => context.go('/')),
          Expanded(
            child: EmptyState(
              icon: Icons.help_outline_rounded,
              title: 'Unsupported file',
              message: _sourcePath.isEmpty
                  ? 'No file was selected.'
                  : 'This app does not recognise "${p.extension(_sourcePath)}" yet.',
              action: FilledButton(onPressed: () => context.go('/'), child: const Text('Back to Convert')),
            ),
          ),
        ],
      );
    }

    final targets = FormatRegistry.targetsFor(source)
        .where((f) => ConversionEngine.instance.canConvert(source, f))
        .toList();

    return Column(
      children: [
        const AppBanner(),
        PageHeader(
          title: _optimize ? 'Optimize' : 'Convert to',
          subtitle: _optimize
              ? 'Keep ${source.upper} — shrink the file instead'
              : '${targets.length} target formats available',
          onBack: () => context.go('/'),
        ),
        _sourceCard(source),
        if (_applicablePresets.isNotEmpty) ...[
          SectionTitle(
            'One-tap presets',
            trailing: TextButton(
              onPressed: () => context.push('/presets'),
              child: const Text('Manage'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final preset in _applicablePresets)
                  PresetChip(preset: preset, onTap: () => _applyPreset(preset)),
              ],
            ),
          ),
        ],
        // Optimize sits above the grid rather than in it: it is not a target
        // format, and the catalogue never pretends that it is.
        if (ConversionEngine.instance.canOptimize(source))
          _OptimizeTile(
            source: source,
            selected: _optimize,
            caption: _optimizeCaption(source),
            onTap: () => setState(() {
              _optimize = true;
              _target = source;
            }),
          ),
        Expanded(
          child: TargetPicker(
            source: source,
            targets: targets,
            // No chip should look selected while Optimize is the choice.
            selected: _optimize ? null : _target,
            onSelected: (f) => setState(() {
              _optimize = false;
              _target = f;
            }),
          ),
        ),
        Container(
          padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.viewPaddingOf(context).bottom + 14),
          decoration: BoxDecoration(
            color: t.background.withValues(alpha: 0.95),
            border: Border(top: BorderSide(color: t.border)),
          ),
          child: Row(
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
                  onPressed: _target == null ? null : _start,
                  child: Text(
                    _target == null
                        ? 'Pick a format'
                        : _optimize
                            ? 'Shrink ${_target!.upper}'
                            : 'Convert to ${_target!.upper}',
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _sourceCard(FileFormat source) {
    final t = context.tokens;
    final size = File(_sourcePath).existsSync() ? File(_sourcePath).lengthSync() : 0;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Panel(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Shows the actual file, not just its extension.
            FilePreview(path: _sourcePath, format: source, size: 46, filled: true),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.args?.displayNames?.firstOrNull ?? p.basename(_sourcePath),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${source.name} · ${humanBytes(size)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12.5, color: t.textFaint),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// What optimizing this format will actually do, in one line. Formats whose
  /// re-encode cannot shrink anything on its own say what can.
  String _optimizeCaption(FileFormat source) {
    final o = _options;
    if (source.family == Family.image) {
      if (!source.lossy) return 'Resize, or remove metadata, to make it smaller';
      return 'Re-encode at ${o.quality}% quality';
    }
    if (source.family == Family.audio) {
      final br = o.audioBitrateKbps;
      return br == null ? 'Re-encode at a lower bitrate' : 'Re-encode at $br kbps';
    }
    if (source.family == Family.video) {
      final crf = o.videoCrf;
      return crf == null ? 'Re-encode at a smaller size' : 'Re-encode at CRF $crf';
    }
    return 'Re-encode at a smaller size';
  }

  Future<void> _openOptions() async {
    final target = _target;
    final source = _source;
    if (target == null || source == null) return;
    final updated = await showModalBottomSheet<ConvertOptions>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OptionsSheet(
        source: source,
        target: target,
        options: _options,
        onSavePreset: _savePreset,
      ),
    );
    if (updated != null && mounted) setState(() => _options = updated);
  }

  // -------------------------------------------------------------- presets

  /// Presets that can actually run on the file on screen. One saved for videos
  /// is not offered for a photo, rather than being offered and then failing.
  List<ConversionPreset> get _applicablePresets {
    final source = _source;
    if (source == null) return const [];
    return context.watch<PresetStore>().forSource(source);
  }

  /// Runs a saved recipe on the file on screen.
  ///
  /// One tap is the promise a preset makes: the target and the settings are set
  /// from the recipe and the job starts. Nothing is destroyed by getting it
  /// wrong — the output is a new file and the original is untouched.
  void _applyPreset(ConversionPreset preset) {
    final source = _source;
    if (source == null) return;
    final target = preset.isOptimize ? source : preset.target;
    if (target == null) return;
    setState(() {
      _optimize = preset.isOptimize;
      _target = target;
      _options = preset.options;
    });
    _start();
  }

  /// Keeps the settings the options sheet is holding, under a name.
  Future<String?> _savePreset(ConvertOptions options) async {
    final store = context.read<PresetStore>();
    final source = _source;
    final target = _target;
    final name = await askPresetName(
      context,
      suggested: _suggestedPresetName(source, target, options),
      existing: [for (final p in store.presets) p.name],
    );
    if (name == null) return null;
    final saved = await store.save(
      name: name,
      // Optimize presets store no target: they keep whatever format the next
      // file happens to be, which is the whole point of saving one.
      targetExt: _optimize ? null : target?.ext,
      options: options,
    );
    return saved.name;
  }

  /// A first guess at a name, since most people keep it: what the recipe is.
  String _suggestedPresetName(FileFormat? source, FileFormat? target, ConvertOptions options) {
    if (_optimize || target == null) {
      return source == null ? 'Shrink a file' : 'Shrink ${source.upper}';
    }
    final from = source == null ? '' : '${source.upper} to ';
    final settings = options.describe();
    return settings == 'defaults' ? '$from${target.upper}' : '$from${target.upper} (${options.quality}%)';
  }

  // ------------------------------------------------------------- running

  Widget _running() {
    final job = _job!;
    final t = context.tokens;
    return Column(
      children: [
        PageHeader(title: _optimize ? 'Optimizing' : 'Converting', subtitle: job.headline),
        const Spacer(),
        PulseProgressListener(
          progress: job.progressNotifier,
          indeterminate: _indeterminate,
          size: 240,
          label: job.name,
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FormatBadge(job.source?.ext ?? '?', size: 44),
            const Padding(padding: EdgeInsets.symmetric(horizontal: 14), child: ConvertArrow()),
            FormatBadge(job.target.ext, size: 44, filled: true),
          ],
        ),
        const SizedBox(height: 14),
        Text(
          _indeterminate
              ? 'Working — this format has no timeline to measure'
              : 'Everything happens on this device',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: t.textFaint),
        ),
        const Spacer(),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewPaddingOf(context).bottom + 20),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton(onPressed: _cancelJob, child: const Text('Cancel')),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmCancel() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop converting?'),
        content: const Text('The conversion in progress will be discarded.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep going')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Stop')),
        ],
      ),
    );
    if (leave == true) {
      _cancelJob();
      if (mounted) context.go('/');
    }
  }

  // ------------------------------------------------------------ finished

  Widget _finished() {
    final job = _job!;
    final t = context.tokens;
    final ok = job.status == JobStatus.done;

    return Column(
      children: [
        PageHeader(
          title: ok ? 'Done' : (job.status == JobStatus.cancelled ? 'Cancelled' : 'Failed'),
          subtitle: job.headline,
          onBack: () => context.go('/'),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
            children: [
              Center(
                child: PulseHalo(
                  size: 168,
                  active: ok,
                  child: Container(
                    width: 92,
                    height: 92,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ok ? t.accent : Colors.transparent,
                      border: Border.all(color: ok ? t.accent : t.border, width: 1.6),
                    ),
                    child: Icon(
                      ok ? Icons.check_rounded : Icons.priority_high_rounded,
                      size: 42,
                      color: ok ? t.onAccent : t.textFaint,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              if (ok) ..._successBody(job) else _failureBody(job),
              const SizedBox(height: 20),
              const AppBanner(),
              const SizedBox(height: 8),
              const SupportCard(compact: true),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewPaddingOf(context).bottom + 14),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: ok ? _reset : _reset,
                  child: Text(
                    ok ? (_optimize ? 'Optimize again' : 'Convert again') : 'Try another format',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: ok ? () => _open(job) : () => context.go('/'),
                  child: Text(ok ? 'Open' : 'Back'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  List<Widget> _successBody(ConversionJob job) {
    final t = context.tokens;
    final delta = job.sizeDeltaRatio;
    return [
      // The converted file itself, so an exotic output is still viewable even
      // with no app installed that understands it.
      if (job.outputPath != null) ...[
        FilePreview(path: job.outputPath!, format: job.target, expanded: true),
        const SizedBox(height: 12),
      ],
      Panel(
        child: Column(
          children: [
            Text(
              p.basename(job.outputPath ?? ''),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                StatPill(label: 'Output size', value: humanBytes(job.outputBytes), icon: Icons.save_alt_rounded),
                const SizedBox(width: 10),
                StatPill(label: 'Took', value: humanDuration(job.elapsed), icon: Icons.timer_outlined),
                const SizedBox(width: 10),
                StatPill(
                  label: delta == null ? 'Change' : (delta < 0 ? 'Smaller' : 'Larger'),
                  value: delta == null ? '—' : '${(delta.abs() * 100).toStringAsFixed(0)}%',
                  icon: delta != null && delta < 0 ? Icons.trending_down_rounded : Icons.trending_up_rounded,
                ),
              ],
            ),
            // Re-encoding can legitimately land larger than the original — a
            // file that was already well compressed, encoded again at high
            // quality. Saying so, with a way out, beats a silent disappointment.
            if (job.optimize && delta != null && delta > 0) ...[
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline_rounded, size: 16, color: t.textFaint),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This came out larger. Lower the quality, or add a resize, and try again.',
                      style: TextStyle(fontSize: 12.5, height: 1.4, color: t.textFaint),
                    ),
                  ),
                ],
              ),
            ],
            if (job.extraOutputs.isNotEmpty) ...[
              const SizedBox(height: 14),
              Text(
                '+ ${job.extraOutputs.length} more file${job.extraOutputs.length == 1 ? '' : 's'} saved alongside it',
                style: TextStyle(fontSize: 12.5, color: t.textFaint),
              ),
            ],
          ],
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _share(job),
              icon: const Icon(Icons.ios_share_rounded, size: 19),
              label: const Text('Share'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => context.go('/files'),
              icon: const Icon(Icons.folder_open_rounded, size: 19),
              label: const Text('Files'),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _failureBody(ConversionJob job) {
    final t = context.tokens;
    final detail = job.errorDetail;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            job.error ?? 'The conversion did not complete.',
            style: TextStyle(fontSize: 14.5, height: 1.5, color: t.textPrimary),
          ),
          const SizedBox(height: 10),
          Text(
            'Nothing was uploaded and your original file is untouched.',
            style: TextStyle(fontSize: 12.5, color: t.textFaint),
          ),
          if (detail != null && detail.trim().isNotEmpty) _EngineOutput(detail: detail),
          const SizedBox(height: 14),
          OutlinedButton.icon(
            onPressed: () => _reportFailure(job),
            icon: const Icon(Icons.bug_report_outlined, size: 18),
            label: const Text('Send a report'),
          ),
          const SizedBox(height: 8),
          Text(
            'Attaches this device, this build and the engine output above. Nothing '
            'is sent until you pick where it goes.',
            style: TextStyle(fontSize: 12, height: 1.35, color: t.textFaint),
          ),
        ],
      ),
    );
  }

  /// Opens the report screen on the job that just failed, so the engine's own
  /// account of it travels with the report rather than being retyped.
  void _reportFailure(ConversionJob job) {
    context.push(
      '/feedback',
      extra: FeedbackArgs(
        failure: FailureRecord(
          pair: job.headline,
          name: job.name,
          at: DateTime.now(),
          error: job.error,
          detail: job.errorDetail,
          sourceBytes: job.sourceBytes,
          outputBytes: job.outputBytes,
          elapsedMs: job.elapsed.inMilliseconds,
        ),
        symptoms: {
          'Conversion': job.headline,
          'Source': '${job.name} (${humanBytes(job.sourceBytes)})',
          'Options': job.options.describe(),
          'Engine': job.optimize ? 'optimize' : 'convert',
        },
      ),
    );
  }

  Future<void> _open(ConversionJob job) async {
    final path = job.outputPath;
    if (path == null) return;
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('No app on this device can open ${job.target.upper} files.')),
      );
    }
  }

  Future<void> _share(ConversionJob job) async {
    final path = job.outputPath;
    if (path == null) return;
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(path), ...job.extraOutputs.map(XFile.new)],
        subject: p.basename(path),
      ),
    );
  }
}

/// The Optimize entry: keep the file's own format and re-encode it smaller.
///
/// It is offered only when the engine really has a converter for it, and it is
/// kept visually separate from the target grid, because it is not a target
/// format — nothing in the registry converts JPG to JPG, and nothing here
/// pretends otherwise.
class _OptimizeTile extends StatelessWidget {
  const _OptimizeTile({
    required this.source,
    required this.selected,
    required this.caption,
    required this.onTap,
  });

  final FileFormat source;
  final bool selected;
  final String caption;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Optimize, keep ${source.upper}',
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: selected ? t.accent : t.surface.withValues(alpha: 0.6),
              border: Border.all(
                color: selected ? t.accent : t.border,
                width: selected ? 1.6 : 1,
              ),
              borderRadius: BorderRadius.circular(AppTheme.radiusSmall + 2),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.compress_rounded,
                  size: 20,
                  color: selected ? t.onAccent : t.textSecondary,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Optimize — keep ${source.upper}',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: selected ? t.onAccent : t.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        caption,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: selected ? t.onAccent.withValues(alpha: 0.75) : t.textFaint,
                        ),
                      ),
                    ],
                  ),
                ),
                if (selected) Icon(Icons.check_rounded, size: 17, color: t.onAccent),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The engine's own account of a failure, one tap away.
///
/// It is the most useful thing in a report and the least readable thing on a
/// screen, so it is folded away by default — but it is not hidden. Someone
/// deciding whether to send a report should be able to read exactly what goes
/// with it, and the failure card is where they are already looking.
class _EngineOutput extends StatefulWidget {
  const _EngineOutput({required this.detail});

  final String detail;

  @override
  State<_EngineOutput> createState() => _EngineOutputState();
}

class _EngineOutputState extends State<_EngineOutput> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        TextButton.icon(
          onPressed: () => setState(() => _open = !_open),
          style: TextButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size(0, 32),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: t.textSecondary,
          ),
          icon: Icon(
            _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
            size: 18,
          ),
          label: Text(_open ? 'Hide engine output' : 'Show engine output'),
        ),
        if (_open)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: t.surfaceRaised,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: t.border),
            ),
            child: SelectableText(
              widget.detail.trim(),
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                height: 1.4,
                color: t.textSecondary,
              ),
            ),
          ),
      ],
    );
  }
}
