import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:onekit_converter/core/data/history_store.dart';
import 'package:onekit_converter/core/diagnostics/diagnostics.dart';
import 'package:onekit_converter/core/diagnostics/report_file.dart';
import 'package:onekit_converter/engine/job.dart';
import 'package:onekit_converter/engine/registry.dart';

/// The device half of a failure report, which no host test can reach: the
/// `onekit/diagnostics` channel is backed by Kotlin, the report is written into
/// the app's own storage, and the engine's reason for a failure now survives in
/// the history database.
///
/// Run on a real phone — this project builds ARM only:
///
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/diagnostics_test.dart --profile
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the device answers with a build worth reporting', (tester) async {
    final environment = await EnvironmentInfo.collect(extra: {'Screen': 'test'});

    // Android answers for all of these without a permission. If the channel is
    // not attached, every one of them comes back absent and a tester's report
    // is a page of nothing — so this is the test that matters.
    expect(
      environment.fields['Package'],
      'com.onekit.converter',
      reason: 'the channel did not answer: is DiagnosticsChannel attached?',
    );
    expect(environment.fields['App version'], isNot(EnvironmentInfo.unknown));
    expect(environment.fields['App version'], contains('build'));
    expect(environment.fields['Android'], contains('API'));
    expect(environment.fields['CPU'], contains('cores'));
    expect(environment.fields['Locale'], isNotEmpty);
    expect(environment.fields['Storage'], contains('free'));
    expect(environment.fields['RAM'], isNotEmpty);
    expect(environment.fields['Emulator'], isNot(EnvironmentInfo.unknown));
  });

  testWidgets('a report is written where the app can clean it up', (tester) async {
    final environment = await EnvironmentInfo.collect();
    final report = buildFailureReport(
      environment: environment,
      message: 'Written by the device test.',
      failures: [
        FailureRecord(
          pair: 'HEIC → JPG',
          name: 'device-test.heic',
          at: DateTime.now(),
          error: 'This HEIC file could not be decoded.',
          detail: 'Error opening /storage/emulated/0/Download/My Folder/x.heic: '
              'No such file or directory',
          sourceBytes: 4096,
        ),
      ],
    );

    final file = await writeReport(report);
    expect(file, isNotNull, reason: 'the report could not be written');
    addTearDown(() async {
      if (await file!.exists()) await file.delete();
    });

    final onDisk = await file!.readAsString();
    expect(onDisk, contains('Written by the device test.'));
    expect(onDisk, contains('device-test.heic'));
    // The folders an engine log names are trimmed before the report is shown,
    // let alone written.
    expect(onDisk, isNot(contains('My Folder')));
    expect(onDisk, isNot(contains('emulated')));
    // And it lands under the working directory Settings already clears.
    expect(file.path, contains('lfc_work'));
  });

  testWidgets('a failure can be reported after the app has been restarted', (tester) async {
    // The engine's reason only ever lived on the job in memory before this, so a
    // tester who reported the failure the next morning had nothing to send.
    final job = ConversionJob(
      id: 'device-test-${DateTime.now().microsecondsSinceEpoch}',
      sourcePath: '/nope/device-test.heic',
      target: FormatRegistry.byExt('jpg')!,
    )
      ..status = JobStatus.failed
      ..error = 'This HEIC file could not be decoded.'
      ..errorDetail = 'heif: Unsupported feature';
    await HistoryStore.instance.record(job);

    final failures = await HistoryStore.instance.failures(limit: 5);
    final mine = failures.firstWhere((entry) => entry.name == 'device-test.heic');
    addTearDown(() => HistoryStore.instance.delete(mine.id));

    expect(mine.errorDetail, 'heif: Unsupported feature');
    expect(mine.succeeded, isFalse);
    // And it reaches the report intact, named for the pair it was.
    final record = FailureRecord.fromEntry(mine);
    expect(record.pair, 'HEIC → JPG');
    expect(record.lines(1).join('\n'), contains('heif: Unsupported feature'));
  });
}
