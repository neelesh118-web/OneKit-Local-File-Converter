import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/data/settings_store.dart';
import 'package:onekit_converter/core/diagnostics/diagnostics.dart';
import 'package:onekit_converter/core/theme/app_theme.dart';
import 'package:onekit_converter/features/feedback/feedback_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// What the Kotlin side of `onekit/diagnostics` actually returns, so the Dart
/// half of the report is tested against the payload it really gets rather than
/// against one invented here. Field names are the contract between the two.
const _androidPayload = <String, Object?>{
  'packageName': 'com.onekit.converter',
  'versionName': '1.0.0',
  'versionCode': 2,
  'installer': 'com.android.vending',
  'manufacturer': 'Google',
  'brand': 'google',
  'model': 'Pixel 7',
  'device': 'panther',
  'androidRelease': '14',
  'sdkInt': 34,
  'securityPatch': '2026-08-05',
  'abis': 'arm64-v8a, armeabi-v7a',
  'nativeAbi': 'arm64',
  'buildType': 'user',
  'emulator': false,
  'debuggable': false,
  'totalRamMb': 7787,
  'lowRam': false,
  'freeStorageMb': 21504,
  'totalStorageMb': 120832,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late SettingsStore settings;

  setUp(() async {
    messenger.setMockMethodCallHandler(
      const MethodChannel('onekit/diagnostics'),
      (call) async => call.method == 'environment' ? _androidPayload : null,
    );
    // The starfield behind the page reads the user's preferences, exactly as it
    // does under the real app.
    SharedPreferences.setMockInitialValues({});
    settings = await SettingsStore.load();
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(const MethodChannel('onekit/diagnostics'), null);
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    FeedbackArgs? args,
    // A tall window by default so the whole page is built: the preview and both
    // buttons sit below the fold on a phone, and these tests are about their
    // contents.
    Size size = const Size(1200, 4000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsStore>.value(
        value: settings,
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: FeedbackPage(args: args),
        ),
      ),
    );
    // One frame for the environment future, one for the rebuild it triggers.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('reads the device payload into the report', (tester) async {
    await pumpPage(tester);

    final report = tester.widget<SelectableText>(find.byType(SelectableText)).data!;

    expect(report, contains('App version: 1.0.0 (build 2)'));
    expect(report, contains('Package: com.onekit.converter'));
    expect(report, contains('Installed from: com.android.vending'));
    expect(report, contains('Device: Google Pixel 7 (panther)'));
    expect(report, contains('Android: 14 (API 34) patch 2026-08-05'));
    expect(report, contains('CPU: arm64-v8a, armeabi-v7a · build runs arm64 · '));
    expect(report, contains('RAM: 7.6 GB'));
    expect(report, contains('Storage: 21.0 GB free of 118.0 GB'));
    expect(report, contains('Screen: 1200 x 4000 dp @ 1.00x'));
    expect(report, contains('Text size: 1.00x'));

    // Nothing the device did not say is invented.
    expect(report, isNot(contains('Emulator')));
    expect(report, isNot(contains(EnvironmentInfo.unknown)));

    // The history cannot be read in a host test, and the report admits it
    // instead of claiming there were no failures.
    expect(report, contains('could not be read'));
  });

  testWidgets('shows what the tester typed, and copies it', (tester) async {
    await pumpPage(tester);

    await tester.enterText(find.byType(TextField), 'Merge froze on page 40.');
    await tester.pump();

    final preview = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(preview, contains('Merge froze on page 40.'));

    // The clipboard gets the same string the preview showed, so "Copy report"
    // can never hand over something the user did not read.
    String? copied;
    messenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    await tester.tap(find.text('Copy report'));
    await tester.pump();
    expect(copied, preview);
  });

  testWidgets('a live failure leads the report, with its engine output', (tester) async {
    await pumpPage(
      tester,
      args: FeedbackArgs(
        failure: FailureRecord(
          pair: 'HEIC → JPG',
          name: 'IMG_0123.heic',
          at: DateTime(2026, 9, 19, 13, 58),
          error: 'This HEIC file could not be decoded.',
          detail: 'heif: Unsupported feature',
          sourceBytes: 4_404_019,
        ),
        symptoms: {'Conversion': 'HEIC → JPG', 'Options': 'quality 90'},
      ),
    );

    final report = tester.widget<SelectableText>(find.byType(SelectableText)).data!;
    expect(report, contains('Where it happened'));
    expect(report, contains('Conversion: HEIC → JPG'));
    expect(report, contains('1. HEIC → JPG — IMG_0123.heic — 2026-09-19 13:58'));
    expect(report, contains('heif: Unsupported feature'));
  });

  testWidgets('lays out on a phone-sized screen', (tester) async {
    // 411 x 866 dp at 3x, which is where the page actually ships. A capped,
    // scrollable preview is what keeps the buttons reachable under a report that
    // runs for a page and a half.
    await pumpPage(
      tester,
      size: const Size(1233, 2598),
      args: FeedbackArgs(
        failure: FailureRecord(
          pair: 'MOV → MP4',
          name: 'clip.mov',
          at: DateTime(2026, 9, 19),
          error: 'This video could not be read.',
          detail: 'noise\n' * 120,
        ),
        symptoms: {'Conversion': 'MOV → MP4'},
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Send a report'), findsOneWidget);
  });
}
