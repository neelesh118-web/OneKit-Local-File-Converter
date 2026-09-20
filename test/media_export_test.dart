import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/data/settings_store.dart';
import 'package:onekit_converter/core/media/media_export.dart';
import 'package:onekit_converter/engine/converters/converter.dart';
import 'package:onekit_converter/engine/engine.dart';
import 'package:onekit_converter/engine/format.dart';
import 'package:onekit_converter/engine/job.dart';
import 'package:onekit_converter/engine/registry.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// Copying a finished conversion into the phone's own storage is what makes a
/// result findable at all: the app's private folder is a folder no other app
/// shows, so a conversion that is not copied is one the user has to go hunting
/// for inside OneKit.
///
/// What a host can check is the contract with the Android half — which
/// collection a format belongs in, exactly what crosses the channel, what the
/// app says when no copy happens, and that the engine offers one at all. What
/// only a device can check is that the content resolver writes it:
/// `integration_test/`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('onekit/media_store');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late Directory tmp;

  /// What Dart sent on the last `publish` call, or null when it sent nothing.
  Map<Object?, Object?>? sent;

  /// Stands in for the Android side, answering every call with [payload].
  void answerWith(Object? payload) {
    sent = null;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = (call.arguments as Map?)?.cast<Object?, Object?>();
      return payload;
    });
  }

  setUp(() => tmp = Directory.systemTemp.createTempSync('onekit_export'));
  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    tmp.deleteSync(recursive: true);
  });

  group('the collection a format belongs in', () {
    test('media goes to the collection its own app reads', () {
      expect(MediaExport.collectionFor(Family.image), MediaCollection.images);
      expect(MediaExport.collectionFor(Family.video), MediaCollection.video);
      expect(MediaExport.collectionFor(Family.audio), MediaCollection.audio);
    });

    test('everything a gallery would not show goes to Downloads', () {
      for (final family in const [
        Family.document,
        Family.data,
        Family.archive,
        Family.ebook,
        Family.subtitle,
        Family.font,
        Family.vector,
      ]) {
        expect(
          MediaExport.collectionFor(family),
          MediaCollection.downloads,
          reason: '$family has no app of its own to be listed in',
        );
      }
    });

    test('the names sent match the four the Android side switches on', () {
      // Dart sends `collection.name`, so renaming an enum value without renaming
      // it there would quietly route every format to Downloads.
      expect(
        MediaCollection.values.map((c) => c.name).toList(),
        ['images', 'video', 'audio', 'downloads'],
      );
    });
  });

  group('what crosses the channel', () {
    test('the file to copy, and where it belongs', () async {
      answerWith({'saved': true, 'location': 'Pictures/OneKit'});

      final result = await MediaExport.instance.publish(
        path: '/data/user/0/com.onekit.onekit_converter/files/holiday.png',
        name: 'holiday.png',
        family: Family.image,
        mime: 'image/png',
      );

      expect(sent, {
        'path': '/data/user/0/com.onekit.onekit_converter/files/holiday.png',
        'name': 'holiday.png',
        'mime': 'image/png',
        'collection': 'images',
      });
      expect(result.saved, isTrue);
      expect(result.location, 'Pictures/OneKit');
      expect(result.reason, isNull);
    });

    test('a format with no mime of its own is offered as bytes', () async {
      answerWith({'saved': true, 'location': 'Download/OneKit'});

      await MediaExport.instance.publish(
        path: '/tmp/report.xyz',
        name: 'report.xyz',
        family: Family.data,
      );

      expect(sent!['mime'], 'application/octet-stream');
      expect(sent!['collection'], 'downloads');
    });
  });

  group('when no copy happens', () {
    test('no channel at all is the quiet case, not a failure', () async {
      messenger.setMockMethodCallHandler(channel, null);

      final result = await MediaExport.instance.publish(
        path: '/tmp/a.png',
        name: 'a.png',
        family: Family.image,
      );

      expect(result.saved, isFalse);
      expect(result.reason, MediaExportReason.unsupported);
    });

    test('every reason the platform can send is understood', () async {
      const expected = {
        'unsupported': MediaExportReason.unsupported,
        'unreadable': MediaExportReason.unreadable,
        'refused': MediaExportReason.refused,
        'failed': MediaExportReason.failed,
      };
      for (final entry in expected.entries) {
        answerWith({'saved': false, 'reason': entry.key});
        final result = await MediaExport.instance.publish(
          path: '/tmp/a.png',
          name: 'a.png',
          family: Family.image,
        );
        expect(result.reason, entry.value, reason: 'for "${entry.key}"');
        expect(result.location, isNull);
        expect(result.saved, isFalse);
      }
    });

    test('a reason this build does not know is still not a copy', () {
      final result = MediaExportResult.fromChannel({'saved': false, 'reason': 'kettle'});
      expect(result.saved, isFalse);
      expect(result.reason, MediaExportReason.failed);
    });

    test('a missing or nonsense answer is not a copy either', () {
      for (final payload in <Object?>[null, 'ok', 42, <Object?>[], <String, Object?>{}]) {
        final result = MediaExportResult.fromChannel(payload);
        expect(result.saved, isFalse, reason: 'for $payload');
        expect(result.reason, isNotNull);
      }
    });

    test('a saved answer with no folder still counts as saved', () {
      // Losing the folder name is a cosmetic problem; claiming the copy failed
      // when it did not would send the user looking in the wrong place.
      final result = MediaExportResult.fromChannel({'saved': true});
      expect(result.saved, isTrue);
      expect(result.location, isNotEmpty);
    });

    test('every reason tells the user where the file actually is', () {
      for (final reason in MediaExportReason.values) {
        expect(reason.message, isNotEmpty);
        expect(
          reason.message.toLowerCase(),
          contains('folder'),
          reason: '${reason.name} has to point at the file it is about',
        );
      }
    });
  });

  group('the engine offers a result to the phone', () {
    /// A conversion that needs no device: CSV to JSON runs in Dart.
    Future<ConversionJob> convertCsv({bool publishToGallery = true}) async {
      final input = File(p.join(tmp.path, 'rows.csv'))
        ..writeAsStringSync('name,count\nalpha,1\n');
      final job = ConversionJob(
        id: 'j1',
        sourcePath: input.path,
        target: FormatRegistry.byExt('json')!,
      );
      await ConversionEngine.instance.run(
        job,
        cancel: CancelToken(),
        outputDirectory: tmp.path,
        publishToGallery: publishToGallery,
      );
      return job;
    }

    test('records where the copy landed, without a copy of its own failing it', () async {
      answerWith({'saved': true, 'location': 'Download/OneKit'});

      final job = await convertCsv();

      expect(job.status, JobStatus.done);
      expect(job.publishedTo, 'Download/OneKit');
      expect(job.publishProblem, isNull);
      // The file's own name, not a second name invented for the copy.
      expect(sent!['name'], p.basename(job.outputPath!));
      expect(sent!['collection'], 'downloads', reason: 'a CSV is not media');
    });

    test('a refused copy is a note, never a failed conversion', () async {
      answerWith({'saved': false, 'reason': 'refused'});

      final job = await convertCsv();

      expect(job.status, JobStatus.done, reason: 'the file was written');
      expect(job.outputBytes, greaterThan(0));
      expect(job.publishedTo, isNull);
      expect(job.publishProblem, contains('folder'));
    });

    test('nothing is offered when the caller did not ask for a copy', () async {
      answerWith({'saved': true, 'location': 'Download/OneKit'});

      final job = await convertCsv(publishToGallery: false);

      expect(job.status, JobStatus.done);
      expect(sent, isNull, reason: 'the channel must not be touched at all');
      expect(job.publishedTo, isNull);
      expect(job.publishProblem, isNull, reason: 'not asking is not a problem');
    });
  });

  group('the setting', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('is on by default, because an invisible result is the complaint', () async {
      final settings = await SettingsStore.load();
      expect(settings.saveToGallery, isTrue);

      await settings.setSaveToGallery(false);
      expect(settings.saveToGallery, isFalse);
    });
  });
}
