import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> pumpBatch(
    WidgetTester tester, {
    Size size = const Size(1200, 4200),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = textScale;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

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

  /// A whole folder, taken through Android's own picker. What matters here is
  /// that the screen answers every way the pick can come back: files queued and
  /// named after the folder, a folder with nothing convertible in it, and a user
  /// who backed out. The picker and the copy themselves are device behaviour.
  group('taking a whole folder', () {
    const folderChannel = MethodChannel('onekit/folder');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

    /// What Dart sent with the pick, so the extension filter can be checked.
    Map<Object?, Object?>? asked;

    /// Three files in a folder on disk, as the platform's copies would be.
    List<Map<String, Object?>> folderFiles() {
      final out = <Map<String, Object?>>[];
      for (final name in ['track.mp3', 'clip.mp4', 'rows.csv']) {
        final path = '${dir.path}/$name';
        File(path).writeAsBytesSync(List<int>.filled(2048, 7));
        out.add({'path': path, 'name': name});
      }
      return out;
    }

    void answerWith(Map<String, Object?> payload) {
      asked = null;
      messenger.setMockMethodCallHandler(folderChannel, (call) async {
        asked = (call.arguments as Map?)?.cast<Object?, Object?>();
        return payload;
      });
    }

    tearDown(() => messenger.setMockMethodCallHandler(folderChannel, null));

    testWidgets('every file inside lands in the queue, named after the folder',
        (tester) async {
      answerWith({
        'folder': 'Camera',
        'root': '${dir.path}/copies',
        'files': folderFiles(),
        'skipped': 2,
      });

      await pumpBatch(tester);
      await tester.tap(find.text('Folder'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('3 files queued'), findsOneWidget);
      // The row says where each file came from, so a folder of forty is still
      // readable as one pick rather than forty. Anchored at the start so the
      // message above is not counted as a row.
      expect(find.textContaining(RegExp(r'^from Camera · ')), findsNWidgets(3));
      // And what was left behind is said out loud rather than quietly dropped.
      expect(find.textContaining('Added 3 files from Camera'), findsWidgets);
      expect(find.textContaining('2 skipped'), findsWidgets);

      // The platform filters by extension, so the pick has to carry what this
      // build can read or files are skipped for no reason the user can see.
      expect(
        (asked!['extensions'] as List).cast<String>(),
        containsAll(<String>['mp3', 'mp4', 'csv']),
      );
    });

    testWidgets('a folder with nothing convertible in it says so', (tester) async {
      answerWith({
        'folder': 'Notes',
        'root': '${dir.path}/copies',
        'files': <Object?>[],
        'skipped': 6,
      });

      await pumpBatch(tester);
      await tester.tap(find.text('Folder'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Nothing in that folder can be converted.'), findsOneWidget);
      expect(find.text('Nothing queued'), findsOneWidget);
    });

    testWidgets('an empty folder is told apart from one nothing can be read from',
        (tester) async {
      answerWith({
        'folder': 'Empty',
        'root': '${dir.path}/copies',
        'files': <Object?>[],
        'skipped': 0,
      });

      await pumpBatch(tester);
      await tester.tap(find.text('Folder'));
      await tester.pump();
      await tester.pump();

      expect(find.text('That folder is empty.'), findsOneWidget);
    });

    testWidgets('backing out of the picker changes nothing and says nothing',
        (tester) async {
      answerWith({'files': <Object?>[], 'skipped': 0, 'cancelled': true});

      await pumpBatch(tester);
      await tester.tap(find.text('Folder'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Nothing queued'), findsOneWidget);
      expect(find.byType(SnackBar), findsNothing);
    });

    testWidgets('three ways in still fit a narrow phone with large text', (tester) async {
      // The source row is three buttons wide, which is the layout most likely to
      // tear on the devices this app is actually for. A RenderFlex overflow
      // fails the test on its own, so pumping is the assertion.
      await pumpBatch(tester, size: const Size(360, 760), textScale: 1.5);

      expect(tester.takeException(), isNull);
      // Below the fold at this size, which is a scroll rather than a fault, so
      // the labels are looked up without the offstage filter.
      for (final label in ['Files', 'Folder', 'ZIP']) {
        expect(find.text(label, skipOffstage: false), findsOneWidget,
            reason: '$label is not on the screen at all');
      }
    });

    testWidgets('a folder that cannot be read is a refusal, not an empty queue',
        (tester) async {
      answerWith({'problem': 'unreadable'});

      await pumpBatch(tester);
      await tester.tap(find.text('Folder'));
      await tester.pump();
      await tester.pump();

      expect(find.textContaining('could not be read'), findsOneWidget);
    });
  });
}
