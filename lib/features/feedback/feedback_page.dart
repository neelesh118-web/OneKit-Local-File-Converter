import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';

import '../../core/data/history_store.dart';
import '../../core/diagnostics/diagnostics.dart';
import '../../core/diagnostics/report_file.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/common.dart';
import '../../core/widgets/starfield.dart';

/// What a tester sends when something did not work.
///
/// Closed testing produces reports that have to be read by someone else, so the
/// screen is built around one rule: the report is visible, in full, before it
/// goes anywhere. There is no analytics behind it and no upload — the written
/// text is shown, copied or handed to whatever app the user picks from the
/// share sheet, and that is the entire mechanism.
///
/// It opens from the failed result card with [failure] filled in, and from
/// Settings with nothing but history to draw on. Either way the report is
/// assembled from the same function, so neither entry point can send something
/// the other would not.
/// How the report was opened.
class FeedbackArgs {
  const FeedbackArgs({this.failure, this.symptoms = const {}});

  /// The failure the user was looking at when they tapped "Send a report". It
  /// is attached whatever history says, because it is the one they mean.
  final FailureRecord? failure;

  /// Facts only the calling screen knows — which conversion was on it, with
  /// which options. Triage reads these first.
  final Map<String, String> symptoms;
}

class FeedbackPage extends StatefulWidget {
  const FeedbackPage({super.key, this.args});

  final FeedbackArgs? args;

  @override
  State<FeedbackPage> createState() => _FeedbackPageState();
}

class _FeedbackPageState extends State<FeedbackPage> {
  /// How many older failures a report may carry. Enough to show a pattern,
  /// few enough that a report stays readable.
  static const int _historyFailures = 4;

  final _message = TextEditingController();
  EnvironmentInfo? _environment;
  List<FailureRecord> _recent = const [];

  /// Set when the history could not be read at all, so the report says that
  /// rather than claiming there were no failures.
  bool _historyUnreadable = false;
  bool _includeRecent = true;
  bool _sending = false;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Needs MediaQuery, so it cannot happen in initState. Once is enough.
    if (_started) return;
    _started = true;
    _load();
  }

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final view = View.of(context);
    final size = view.physicalSize / view.devicePixelRatio;
    final environment = await EnvironmentInfo.collect(
      extra: {
        'Screen': '${size.width.round()} x ${size.height.round()} dp '
            '@ ${view.devicePixelRatio.toStringAsFixed(2)}x',
        'Text size': '${MediaQuery.textScalerOf(context).scale(1).toStringAsFixed(2)}x',
      },
    );

    List<FailureRecord> recent;
    try {
      final entries = await HistoryStore.instance.failures(limit: _historyFailures + 1);
      recent = [for (final entry in entries) FailureRecord.fromEntry(entry)];
    } catch (_) {
      // The one thing this screen must never do is refuse to produce a report.
      // Whatever could not be read is stated in the report instead.
      _historyUnreadable = true;
      recent = [];
    }
    final live = _live;
    if (live != null) {
      // The live job is the same failure as the row history just took, so the
      // duplicate goes: the job knows its engine output, and reporting the same
      // failure twice only makes the list look worse than it is.
      recent.removeWhere((r) => r.name == live.name && r.pair == live.pair);
      recent.insert(0, live);
    }

    if (!mounted) return;
    setState(() {
      _environment = environment;
      _recent = recent;
    });
  }

  /// The failures this report would carry right now.
  List<FailureRecord> get _failures {
    if (_recent.isEmpty) return const [];
    final live = _live;
    if (live != null) {
      // The one on screen is always included; the toggle is about the others.
      final rest = _recent.skip(1).take(_historyFailures);
      return [live, if (_includeRecent) ...rest];
    }
    return _includeRecent ? _recent.take(_historyFailures).toList() : const [];
  }

  /// The failure being reported right now, if the screen was opened from one.
  FailureRecord? get _live => widget.args?.failure;

  Map<String, String> get _symptoms => widget.args?.symptoms ?? const {};

  String get _report {
    final environment = _environment;
    if (environment == null) return '';
    return buildFailureReport(
      environment: environment,
      failures: _failures,
      message: _message.text,
      symptoms: _symptoms,
      failuresNote: _historyUnreadable
          ? '(the failure list could not be read on this device)'
          : null,
    );
  }

  String get _subject {
    final failures = _failures;
    final name = failures.isEmpty ? null : failures.first.pair;
    return name == null
        ? '$productName failure report'
        : '$productName failure report — $name';
  }

  Future<void> _share() async {
    final text = _report;
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    final file = await writeReport(text);
    if (!mounted) return;
    setState(() => _sending = false);

    if (file == null) {
      // Nowhere to write it is not a reason to withhold the report: text goes
      // into the share sheet instead, and the user is told which happened.
      _note('Sharing as text — the report could not be saved to a file.');
      await SharePlus.instance.share(ShareParams(text: text, subject: _subject));
      return;
    }
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path)],
        subject: _subject,
        text: 'Failure report attached (${p.basename(file.path)}).',
      ),
    );
  }

  Future<void> _copy() async {
    final text = _report;
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    _note('Report copied to the clipboard.');
  }

  void _note(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final t = context.tokens;
    return Scaffold(
      backgroundColor: t.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const Starfield(density: 0.7, speed: 0.6),
          SafeArea(
            child: Column(
              children: [
                PageHeader(title: 'Send a report', onBack: () => context.pop()),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.fromLTRB(
                      20,
                      0,
                      20,
                      MediaQuery.viewPaddingOf(context).bottom + 24,
                    ),
                    children: [
                      const SizedBox(height: 8),
                      _messageBox(t),
                      if (_symptoms.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _symptomsPanel(t),
                      ],
                      const SizedBox(height: 12),
                      if (_recent.isNotEmpty) _attachmentChoice(t),
                      const SizedBox(height: 12),
                      _preview(t),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _environment == null || _sending ? null : _share,
                        icon: const Icon(Icons.ios_share_rounded, size: 18),
                        label: Text(_sending ? 'Preparing…' : 'Share report'),
                      ),
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed: _environment == null ? null : _copy,
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy report'),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'The app has no analytics and never uploads anything: this report '
                        'leaves the phone only when you pick somewhere to send it. Sharing '
                        'it by email reaches the developer at $developerContact.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, height: 1.4, color: t.textFaint),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _messageBox(AppTokens t) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What went wrong?', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _message,
              maxLines: 4,
              minLines: 3,
              onChanged: (_) => setState(() {}),
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                hintText: 'What you tapped, what you expected, and what happened '
                    'instead. Steps help more than anything else here.',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      );

  Widget _symptomsPanel(AppTokens t) => Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Where it happened', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final entry in _symptoms.entries)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 118,
                      child: Text(
                        entry.key,
                        style: TextStyle(fontSize: 12.5, color: t.textFaint),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        entry.value,
                        style: TextStyle(fontSize: 13, color: t.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );

  Widget _attachmentChoice(AppTokens t) => Panel(
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Attach recent failures',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _recent.length == 1
                        ? 'One failed conversion, with the engine\'s own error output.'
                        : 'The ${_recent.take(_historyFailures).length} most recent '
                            'failed conversions, with the engine\'s own error output.',
                    style: TextStyle(fontSize: 12.5, color: t.textFaint, height: 1.35),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Switch(
              value: _includeRecent,
              onChanged: (v) => setState(() => _includeRecent = v),
            ),
          ],
        ),
      );

  Widget _preview(AppTokens t) {
    final report = _report;
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.visibility_outlined, size: 17, color: t.textFaint),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Attached to the report',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'This is the whole report, exactly as it will be sent. Nothing is '
            'added when you send it.',
            style: TextStyle(fontSize: 12, height: 1.35, color: t.textFaint),
          ),
          const SizedBox(height: 10),
          if (report.isEmpty)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 12),
                Text(
                  'Reading device details…',
                  style: TextStyle(fontSize: 13, color: t.textSecondary),
                ),
              ],
            )
          else
            Container(
              constraints: const BoxConstraints(maxHeight: 260),
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: t.surfaceRaised,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: t.border),
              ),
              child: SingleChildScrollView(
                child: SelectableText(
                  report,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.45,
                    color: t.textSecondary,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
