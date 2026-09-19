import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/data/history_store.dart';
import 'package:onekit_converter/core/diagnostics/diagnostics.dart';
import 'package:onekit_converter/engine/job.dart';

/// The report is the one artifact a closed tester sends, so these tests are
/// about what it does and does not contain: the engine's own words for a
/// failure, the build the tester is actually running, and none of the folders
/// their files live in.
void main() {
  // The binding is needed to reach a method channel at all; with no handler
  // registered behind it, `onekit/diagnostics` behaves exactly as it does on a
  // device that has no such channel — which is the case worth pinning, because
  // a report that cannot be produced is worse than a short one.
  TestWidgetsFlutterBinding.ensureInitialized();

  group('environment', () {
    test('reports the Dart half when the platform channel is absent', () async {
      final environment = await EnvironmentInfo.collect();

      expect(environment.fields['Build mode'], 'debug');
      expect(environment.fields['Engine'], isNotEmpty);
      // Nothing the platform would have answered for is invented.
      expect(environment.fields['Package'], EnvironmentInfo.unknown);
      expect(environment.fields.containsKey('Device'), isFalse);

      // And an unknown never reaches the report as a row.
      expect(environment.lines.any((l) => l.contains(EnvironmentInfo.unknown)), isFalse);
      expect(environment.lines.any((l) => l.startsWith('Build mode: ')), isTrue);
    });

    test('reads a device the platform describes in full', () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('onekit/diagnostics'),
        (call) async => <String, Object?>{
          'packageName': 'com.onekit.converter',
          'versionName': '1.0.0',
          'versionCode': 2,
          'installer': 'com.android.vending',
          'manufacturer': 'Google',
          'model': 'Pixel 7',
          'device': 'panther',
          'androidRelease': '14',
          'sdkInt': 34,
          'securityPatch': '2026-08-05',
          'buildType': 'userdebug',
          'abis': 'arm64-v8a, armeabi-v7a',
          'nativeAbi': 'arm64',
          'emulator': true,
          'debuggable': true,
          'totalRamMb': 7787,
          'lowRam': true,
          'freeStorageMb': 21504,
          'totalStorageMb': 120832,
        },
      );
      addTearDown(
        () => messenger.setMockMethodCallHandler(
          const MethodChannel('onekit/diagnostics'),
          null,
        ),
      );

      final environment = await EnvironmentInfo.collect();

      expect(environment.fields['App version'], '1.0.0 (build 2)');
      expect(environment.fields['Device'], 'Google Pixel 7 (panther)');
      expect(environment.fields['Android'], '14 (API 34) patch 2026-08-05 (userdebug build)');
      expect(environment.fields['CPU'],
          'arm64-v8a, armeabi-v7a · build runs arm64 · ${Platform.numberOfProcessors} cores');
      expect(environment.fields['RAM'], '7.6 GB (low-RAM device)');
      expect(environment.fields['Storage'], '21.0 GB free of 118.0 GB');
      expect(environment.fields['Emulator'], 'yes');
      expect(environment.fields['Debuggable'], 'yes');
    });

    test('keeps the extras a screen adds', () async {
      final environment = await EnvironmentInfo.collect(
        extra: {'Screen': '411 x 866 dp @ 2.63x'},
      );
      expect(environment.fields['Screen'], '411 x 866 dp @ 2.63x');
    });
  });

  group('report', () {
    final environment = EnvironmentInfo({
      'App version': '1.0.0 (build 2)',
      'Package': 'com.onekit.converter',
      'Device': 'Google Pixel 7 (panther)',
    });

    test('leads with the tester\'s own words and names the build', () {
      final report = buildFailureReport(
        environment: environment,
        message: 'The merge button did nothing.',
        at: DateTime(2026, 9, 19, 14, 3),
        symptoms: {'Conversion': 'HEIC → JPG'},
      );

      expect(report, contains('What the tester reported'));
      expect(report, contains('The merge button did nothing.'));
      expect(report, contains('Conversion: HEIC → JPG'));
      expect(report, contains('App version: 1.0.0 (build 2)'));
      expect(report, contains('Device: Google Pixel 7 (panther)'));
      expect(report, contains('2026-09-19 14:03'));
    });

    test('says so when the tester typed nothing', () {
      final report = buildFailureReport(environment: environment);
      expect(report, contains('(nothing typed — see the failures below)'));
      expect(report, contains('(none recorded)'));
    });

    test('carries the engine output for each failure', () {
      final report = buildFailureReport(
        environment: environment,
        failures: [
          FailureRecord(
            pair: 'HEIC → JPG',
            name: 'IMG_0123.heic',
            at: DateTime(2026, 9, 19, 13, 58),
            error: 'This HEIC file could not be decoded.',
            detail: 'heif: Unsupported feature\nConversion failed!',
            sourceBytes: 4_404_019,
            elapsedMs: 1340,
          ),
        ],
      );

      expect(report, contains('1. HEIC → JPG — IMG_0123.heic — 2026-09-19 13:58'));
      expect(report, contains('Failed: This HEIC file could not be decoded.'));
      expect(report, contains('Source 4.2 MB, output 0 B, after 1.3 s'));
      expect(report, contains('heif: Unsupported feature'));
      expect(report, contains('Conversion failed!'));
    });

    test('clips a log that would bury the report, keeping the end', () {
      final long = '${'noise\n' * 400}the actual reason';
      final report = buildFailureReport(
        environment: environment,
        failures: [
          FailureRecord(
            pair: 'MOV → MP4',
            name: 'clip.mov',
            at: DateTime(2026, 9, 19),
            detail: long,
          ),
        ],
      );

      expect(report, contains('the actual reason'));
      expect(report, contains('earlier output cut'));
      // Some of the log survives, and not all of it does.
      final kept = 'noise'.allMatches(report).length;
      expect(kept, greaterThan(0));
      expect(kept, lessThan(400));
    });

    test('a multi-line failure stays on one summary line', () {
      final report = buildFailureReport(
        environment: environment,
        failures: [
          FailureRecord(
            pair: 'PNG → PDF',
            name: 'page.png',
            at: DateTime(2026, 9, 19),
            error: 'Could not read the file.\nIt may be corrupt.',
          ),
        ],
      );
      expect(report, contains('Failed: Could not read the file. It may be corrupt.'));
    });
  });

  group('paths', () {
    test('trims folders off an engine log, keeping the name and the message', () {
      final redacted = redactPaths(
        'Opening /storage/emulated/0/Download/My Holiday/beach 2.jpg: OK\n'
        'Error opening /data/user/0/com.onekit.converter/cache/lfc_work/in.heic: '
        'No such file or directory',
      );

      expect(redacted, isNot(contains('My Holiday')));
      expect(redacted, isNot(contains('emulated')));
      expect(redacted, contains('beach 2.jpg'));
      expect(redacted, contains('No such file or directory'));
      expect(
        redacted,
        'Opening …/beach 2.jpg: OK\n'
        'Error opening …/in.heic: No such file or directory',
      );
    });

    test('leaves text that only looks like a path alone', () {
      // A version string, a MIME type and an FFmpeg marker are not paths, and
      // rewriting them would make a log harder to read, not safer.
      const line = 'ffmpeg version 6.0 Copyright (c) 2000-2023\n'
          'image/heic, yuvj420p, 90k tbn';
      expect(redactPaths(line), line);
    });

    test('keeps a path with no name at all as it was', () {
      expect(redactPaths('mounted at /data/'), 'mounted at /data/');
    });
  });

  group('history', () {
    test('a failure becomes a record with its engine output', () {
      final record = FailureRecord.fromEntry(
        HistoryEntry(
          id: 1,
          name: 'holiday.heic',
          fromExt: 'heic',
          toExt: 'jpg',
          status: 'failed',
          createdAt: DateTime(2026, 9, 19, 12),
          error: 'This HEIC file could not be decoded.',
          errorDetail: 'heif: Unsupported feature',
          sourceBytes: 2_097_152,
        ),
      );

      expect(record.pair, 'HEIC → JPG');
      expect(record.name, 'holiday.heic');
      expect(record.detail, 'heif: Unsupported feature');
      expect(record.lines(1).join('\n'), contains('heif: Unsupported feature'));
    });

    test('an optimize and a PDF tool run are named for what they did', () {
      // Neither is a pair, so neither may be reported as "JPG → JPG" or
      // "PDF → PDF": the first would look like a mistake and the second like a
      // conversion that never happened.
      final optimized = FailureRecord.fromEntry(
        HistoryEntry(
          id: 2,
          name: 'IMG.jpg',
          fromExt: 'jpg',
          toExt: 'jpg',
          status: 'failed',
          createdAt: DateTime(2026, 9, 19),
        ),
      );
      final tool = FailureRecord.fromEntry(
        HistoryEntry(
          id: 3,
          name: 'report.pdf',
          fromExt: 'pdf',
          toExt: 'pdf',
          status: 'failed',
          createdAt: DateTime(2026, 9, 19),
          tool: 'merge',
        ),
      );

      expect(optimized.pair, 'JPG optimized');
      expect(tool.pair, 'PDF merged');
    });
  });

  group('options', () {
    test('a default job says defaults rather than listing every field', () {
      expect(const ConvertOptions().describe(), 'defaults');
    });

    test('names the choices that were actually made', () {      expect(
        const ConvertOptions(
          quality: 62,
          width: 1280,
          videoCrf: 28,
          stripMetadata: true,
          pdfPageRange: '2-10',
        ).describe(),
        'quality 62, resize 1280xauto, CRF 28, strip metadata, pages 2-10',
      );
    });
  });
}
