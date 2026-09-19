import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/data/settings_store.dart';
import 'package:onekit_converter/core/theme/app_theme.dart';
import 'package:onekit_converter/features/batch/batch_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The batch screen with a mixed queue in it. What matters is that the screen
/// tells the truth about a queue that spans formats: which files are ready,
/// which are skipped, and that one shared quality is offered for all of them.
///
/// Files are written with the synchronous API on purpose. A `testWidgets` body
/// runs in a fake-async zone where the real event loop is not drained, so any
/// awaited file I/O in the test itself simply never completes.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late SettingsStore settings;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('onekit_batch_test');
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsStore.load();
  });

  tearDown(() {
    BatchPage.seed(const []);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  /// One optimizable file and three this build cannot shrink: lossless audio, a
  /// format with no encoder here, and a type the app does not know. None of
  /// them is a native image, so nothing tries to decode a thumbnail out of the
  /// placeholder bytes.
  List<String> seedQueue() {
    final paths = [
      for (final name in ['song.mp3', 'take.flac', 'photo.heic', 'blob.xyz'])
        '${dir.path}/$name',
    ];
    for (final path in paths) {
      File(path).writeAsBytesSync(List<int>.filled(2048, 7));
    }
    BatchPage.seed(paths);
    return paths;
  }

  Future<void> pumpBatch(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 4200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsStore>.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: const Scaffold(body: BatchPage()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('offers both modes, and starts in convert', (tester) async {
    seedQueue();
    await pumpBatch(tester);

    // Section titles are upper-cased by the widget, so the finder matches the
    // rendered text.
    expect(find.text('WHAT SHOULD THIS BATCH DO?'), findsOneWidget);
    expect(find.text('Convert to one'), findsOneWidget);
    expect(find.text('Optimize each'), findsOneWidget);
    // Four formats this mixed have no shared target at all, which is the
    // situation Optimize exists for — the point here is only that the convert
    // side is the one being shown.
    expect(find.text('NO SHARED TARGET FORMAT'), findsOneWidget);
    // The optimize explainer is not there until it is asked for.
    expect(find.text('Each file keeps its format'), findsNothing);
    // Nothing is marked skipped before a target exists: the run is simply not
    // configured yet.
    expect(find.textContaining('Skipped'), findsNothing);
    expect(find.text('Pick a format'), findsOneWidget);
  });

  testWidgets('optimize counts what it can do and says what it cannot', (tester) async {
    seedQueue();
    await pumpBatch(tester);

    await tester.tap(find.text('Optimize each'));
    await tester.pump();

    expect(find.text('Each file keeps its format'), findsOneWidget);
    // Three of the four files are unpromisable, and the screen says so before
    // the run rather than failing them one at a time.
    expect(find.textContaining('1 file ready · MP3'), findsOneWidget);
    expect(find.textContaining('3 files will be skipped'), findsOneWidget);

    // Per row too: a specific file has to be accounted for, not just a count.
    expect(find.textContaining('Keep MP3'), findsOneWidget);
    expect(find.textContaining('cannot re-encode FLAC'), findsOneWidget);
    expect(find.textContaining('cannot re-encode HEIC'), findsOneWidget);
    expect(find.text('Unsupported file type'), findsOneWidget);

    // And the button counts the same one file, not the queue.
    expect(find.text('Optimize 1 file'), findsOneWidget);
  });

  testWidgets('the options button opens one sheet for the whole queue', (tester) async {
    // Audio and video: two formats with two different sets of controls.
    final paths = [
      for (final name in ['song.mp3', 'clip.mp4']) '${dir.path}/$name',
    ];
    for (final path in paths) {
      File(path).writeAsBytesSync(List<int>.filled(2048, 7));
    }
    BatchPage.seed(paths);
    await pumpBatch(tester);

    await tester.tap(find.text('Optimize each'));
    await tester.pump();
    expect(find.textContaining('2 files ready'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.tune_rounded));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Optimize options'), findsOneWidget);
    expect(find.textContaining('re-encoded into its own format'), findsOneWidget);
    expect(find.text('Bitrate'), findsOneWidget, reason: 'the MP3 brought this');
    expect(find.text('Video quality'), findsOneWidget, reason: 'the MP4 brought this');
    // There is no target format to render pages into, so those controls would
    // be meaningless here.
    expect(find.text('Pages'), findsNothing);
  });

  testWidgets('switching back to convert does not carry optimize over', (tester) async {
    seedQueue();
    await pumpBatch(tester);

    await tester.tap(find.text('Optimize each'));
    await tester.pump();
    await tester.tap(find.text('Convert to one'));
    await tester.pump();

    expect(find.text('Each file keeps its format'), findsNothing);
    expect(find.text('Optimize 1 file'), findsNothing);
    // The queue outlives the mode, and the convert side goes back to waiting
    // for a target.
    expect(find.textContaining('4 files queued'), findsOneWidget);
    expect(find.text('Pick a format'), findsOneWidget);
  });
}
