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
import '../../core/data/settings_store.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/brand.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/pulse.dart';
import '../../core/widgets/starfield.dart';
import '../../engine/converters/converter.dart';
import '../../engine/engine.dart';
import '../../engine/format.dart';
import '../../engine/job.dart';
import '../../engine/registry.dart';
import 'options_sheet.dart';
import 'target_picker.dart';

/// Everything the convert screen needs to start. Passed through GoRouter's
/// `extra` so the route stays a plain path.
class ConvertArgs {
  const ConvertArgs({required this.paths, this.target, this.displayNames});
  final List<String> paths;
  final FileFormat? target;
  final List<String>? displayNames;
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
    _source = FormatRegistry.byExt(p.extension(_sourcePath));
    _target = widget.args?.target;

    final quality = context.read<SettingsStore>().imageQuality;
    _options = _options.copyWith(quality: quality);

    if (_target != null) {
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
                  : 'OneKit does not recognise "${p.extension(_sourcePath)}" yet.',
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
        PageHeader(
          title: 'Convert to',
          subtitle: '${targets.length} target formats available',
          onBack: () => context.go('/'),
        ),
        _sourceCard(source),
        Expanded(
          child: TargetPicker(
            source: source,
            targets: targets,
            selected: _target,
            onSelected: (f) => setState(() => _target = f),
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
                    _target == null ? 'Pick a format' : 'Convert to ${_target!.upper}',
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
            FormatBadge(source.ext, size: 46, filled: true),
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

  Future<void> _openOptions() async {
    final target = _target;
    final source = _source;
    if (target == null || source == null) return;
    final updated = await showModalBottomSheet<ConvertOptions>(
      context: context,
      isScrollControlled: true,
      builder: (_) => OptionsSheet(source: source, target: target, options: _options),
    );
    if (updated != null && mounted) setState(() => _options = updated);
  }

  // ------------------------------------------------------------- running

  Widget _running() {
    final job = _job!;
    final t = context.tokens;
    return Column(
      children: [
        PageHeader(title: 'Converting', subtitle: job.pair?.shortLabel),
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
          subtitle: job.pair?.shortLabel,
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
              const OneKitBanner(),
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
                  child: Text(ok ? 'Convert again' : 'Try another format'),
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
        ],
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
