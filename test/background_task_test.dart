import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/background/background_task.dart';
import 'package:onekit_converter/engine/pdf/pdf_plan.dart';
import 'package:xml/xml.dart';

/// A conversion is the app's own long work, and Android will kill a backgrounded
/// process in the middle of it. What a tester reports when that happens is "it
/// just stopped", so what is worth pinning here is that the notification says
/// something true from the start of a run to the end of it — and that nothing
/// about a conversion depends on it existing.
///
/// The foreground service itself, and the notification it actually shows, are
/// Android's business: `integration_test/`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('onekit/background');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late DateTime now;

  setUp(() async {
    calls = [];
    now = DateTime(2026, 1, 1);
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    // The controller is a singleton, so put the clock where each test wants it
    // and leave it as if no run were in progress.
    BackgroundTask.instance.clock = () => now;
    await BackgroundTask.instance.end();
    calls.clear();
  });

  group('what a run tells the platform', () {
    test('it started, how far along it is, and how it ended', () async {
      await BackgroundTask.instance.begin('Converting holiday.mp4');

      expect(calls.single.method, 'begin');
      expect(calls.single.arguments, {
        'title': 'Converting holiday.mp4',
        'text': 'Starting…',
      });

      calls.clear();
      BackgroundTask.instance.report(0.42);
      await pumpEventQueue();
      expect(calls.single.method, 'report');
      expect(calls.single.arguments, {
        'title': 'Converting holiday.mp4',
        'text': '42%',
        'fraction': 0.42,
      });

      calls.clear();
      await BackgroundTask.instance.end(notice: 'holiday.mp4 converted · 12% smaller');
      expect(calls.single.method, 'end');
      expect(calls.single.arguments, {'notice': 'holiday.mp4 converted · 12% smaller'});
    });

    test('a backend that cannot measure itself spins instead of guessing', () async {
      // pdfium imports and saves a document in one call each, so a number here
      // would be one nobody measured.
      await BackgroundTask.instance.begin('Merging PDFs');
      calls.clear();

      BackgroundTask.instance.report(0.0, indeterminate: true);
      await pumpEventQueue();

      expect(calls.single.arguments['fraction'], isNull);
      expect(calls.single.arguments['text'], 'Working…');
    });

    test('a fraction outside 0-1 is clamped rather than passed on', () async {
      await BackgroundTask.instance.begin('Converting a.png');
      calls.clear();

      BackgroundTask.instance.report(1.4);
      await pumpEventQueue();

      expect(calls.single.arguments['fraction'], 1.0);
      expect(calls.single.arguments['text'], '100%');
    });

    test('ending without a notice leaves nothing behind', () async {
      // A run the user cancelled themselves does not need a notification to say
      // so: they were there.
      await BackgroundTask.instance.begin('Converting a.png');
      calls.clear();

      await BackgroundTask.instance.end();

      final args = calls.single.arguments;
      expect(calls.single.method, 'end');
      expect(args is Map ? args.containsKey('notice') : false, isFalse);
    });
  });

  group('the throttle', () {
    test('sends the first tick, then no more than one per 750 ms', () async {
      await BackgroundTask.instance.begin('Converting a.psd');
      calls.clear();

      BackgroundTask.instance.report(0.10);
      await pumpEventQueue();
      expect(calls, hasLength(1), reason: 'the first tick is always worth sending');

      now = now.add(const Duration(milliseconds: 200));
      BackgroundTask.instance.report(0.11);
      BackgroundTask.instance.report(0.12);
      await pumpEventQueue();
      expect(calls, hasLength(1), reason: 'still inside the gap');

      now = now.add(const Duration(milliseconds: 800));
      BackgroundTask.instance.report(0.13);
      await pumpEventQueue();
      expect(calls, hasLength(2));
      expect(calls.last.arguments['text'], '13%');
    });

    test('the last tick always goes out, gap or no gap', () async {
      await BackgroundTask.instance.begin('Converting a.mp4');
      BackgroundTask.instance.report(0.97);
      await pumpEventQueue();
      calls.clear();

      // Right on top of the previous one: a notification left reading 97% and
      // then replaced by "converted" looks like the number lied.
      now = now.add(const Duration(milliseconds: 10));
      BackgroundTask.instance.report(1.0);
      await pumpEventQueue();

      expect(calls, hasLength(1));
      expect(calls.single.arguments['text'], '100%');
    });

    test('a tick after the run has ended is dropped', () async {
      await BackgroundTask.instance.begin('Converting a.mp4');
      await BackgroundTask.instance.end(notice: 'a.mp4 converted');
      calls.clear();

      // The engine's last callback can land after the run is wrapped up.
      BackgroundTask.instance.report(0.9);
      await pumpEventQueue();

      expect(calls, isEmpty, reason: 'there is no run left to report on');
    });
  });

  test('none of it is required for a conversion to work', () async {
    // No channel behind the call is the desktop and test-suite case, and a user
    // who declined the notification permission is close enough to it. An
    // unhandled error here would fail this test.
    messenger.setMockMethodCallHandler(channel, null);

    await BackgroundTask.instance.begin('Converting a.png');
    BackgroundTask.instance.report(0.5);
    await BackgroundTask.instance.end(notice: 'a.png converted');
    await pumpEventQueue();

    expect(BackgroundTask.instance.running, isFalse);
  });

  group('the wording a tester reads', () {
    test('every PDF tool can say what it is doing while it is doing it', () {
      for (final tool in PdfTool.values) {
        expect(tool.working, isNotEmpty);
        expect(
          tool.working,
          isNot(tool.label),
          reason: 'the label is past tense; this one is on screen mid-run',
        );
      }
    });
  });

  group('AndroidManifest background declarations', () {
    late XmlDocument manifest;

    String? attr(XmlElement element, String name) {
      for (final attribute in element.attributes) {
        if (attribute.name.local.split(':').last == name) return attribute.value;
      }
      return null;
    }

    String localName(XmlElement element) => element.name.local.split(':').last;

    setUpAll(() {
      manifest = XmlDocument.parse(
        File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
      );
    });

    test('the service is private, and typed for the work it does', () {
      final service = manifest
          .findAllElements('service')
          .where((e) => localName(e) == 'service')
          .firstWhere(
            (e) => (attr(e, 'name') ?? '').endsWith('ConversionService'),
            orElse: () => throw StateError('ConversionService is not declared'),
          );

      // Nothing outside the app has any business starting or binding it.
      expect(attr(service, 'exported'), 'false');
      // Android 14 refuses to start a foreground service that does not name its
      // type, and dataSync is the one that covers writing converted files.
      expect(attr(service, 'foregroundServiceType'), 'dataSync');
    });

    test('the permissions a foreground service needs are declared', () {
      final declared = {
        for (final element in manifest.findAllElements('uses-permission'))
          attr(element, 'name') ?? '',
      };

      expect(
        declared,
        containsAll(<String>[
          'android.permission.FOREGROUND_SERVICE',
          'android.permission.FOREGROUND_SERVICE_DATA_SYNC',
          'android.permission.POST_NOTIFICATIONS',
        ]),
      );
    });
  });
}
