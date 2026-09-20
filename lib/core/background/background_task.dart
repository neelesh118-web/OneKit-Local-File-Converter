import 'dart:async';

import 'package:flutter/services.dart';

/// Keeps a run alive while the app is off screen, and tells the user about it.
///
/// A conversion is the app's own work and it is slow: a long video, a forty-file
/// batch, a hundred-page PDF render. Android is free to kill a backgrounded
/// process, and what a tester sees when it does is "it just stopped" — they
/// switched to another app and the run died with the screen. A foreground
/// service is the platform's answer: the process is kept, and the price is a
/// notification that says what it is being kept for.
///
/// So the notification is the point rather than a side effect, and it says
/// something true at every moment: what is running, how far along it is, and —
/// once it is over — what came out, so someone who switched apps learns the job
/// finished without going back to look.
///
/// Nothing here is required for a conversion to work. On a platform with no such
/// channel everything is a quiet no-op, which is what keeps a notification from
/// ever being load-bearing.
class BackgroundTask {
  BackgroundTask._();

  static final BackgroundTask instance = BackgroundTask._();

  static const _methods = MethodChannel('onekit/background');

  /// The engine reports progress far faster than anyone can read it — an FFmpeg
  /// session emits statistics many times a second, and the engine already
  /// coalesces them to about twenty a second for the dial. Sending each of those
  /// to the notification would be abusive to the platform and would flicker
  /// through numbers no one sees, so only a tick this far from the last one goes
  /// out.
  static const _minGap = Duration(milliseconds: 750);

  /// What is running, or null when nothing is. Reports for a run that has
  /// finished are dropped rather than posted under a stale title.
  String? _title;

  DateTime? _lastSent;

  /// Overridable so the throttling can be tested without waiting on a real
  /// clock.
  DateTime Function() clock = DateTime.now;

  bool get running => _title != null;

  /// Starts the foreground notification for a run, and the service behind it.
  ///
  /// The title is what the notification says it is doing — "Converting
  /// holiday.mp4", "Converting 12 files" — and it stays for the whole run.
  Future<void> begin(String title, {String text = 'Starting…'}) async {
    _title = title;
    _lastSent = null;
    await _send('begin', {'title': title, 'text': text});
  }

  /// Reports progress toward the end of the run.
  ///
  /// [indeterminate] is for a backend that genuinely cannot measure itself —
  /// pdfium imports and saves a document in one call each — so the notification
  /// shows a spinner rather than a number nobody measured.
  void report(double fraction, {bool indeterminate = false}) {
    final title = _title;
    if (title == null) return;

    final value = fraction.clamp(0.0, 1.0);
    final now = clock();
    // The last tick of a run is always sent: a notification left at 97% that
    // then jumps to "converted" reads as if something went wrong.
    final finishing = !indeterminate && value >= 1.0;
    final last = _lastSent;
    if (!finishing && last != null && now.difference(last) < _minGap) return;
    _lastSent = now;

    unawaited(_send('report', {
      'title': title,
      'text': indeterminate ? 'Working…' : '${(value * 100).round()}%',
      'fraction': indeterminate ? null : value,
    }));
  }

  /// Ends the run, and leaves [notice] behind as a notification of its own.
  ///
  /// For a run that finished while the app was off screen, that notice is the
  /// only way the user finds out it is done, which is why the caller is expected
  /// to pass one for anything that succeeded or failed and to pass nothing for a
  /// run the user cancelled themselves.
  Future<void> end({String? notice}) async {
    _title = null;
    _lastSent = null;
    await _send('end', {if (notice != null) 'notice': notice});
  }

  Future<void> _send(String method, [Map<String, Object?>? args]) async {
    try {
      await _methods.invokeMethod<void>(method, args);
    } on MissingPluginException {
      // No such channel: a desktop build, or this test suite. A conversion that
      // cannot put up a notification still converts.
    } on PlatformException {
      // The platform refused — most likely the notification permission was
      // declined, or the service was not allowed to start from where it was
      // asked. Silence is the right answer; the run continues either way.
    }
  }
}
