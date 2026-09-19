import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/data/preset_store.dart';
import 'package:onekit_converter/core/data/settings_store.dart';
import 'package:onekit_converter/core/theme/app_theme.dart';
import 'package:onekit_converter/engine/job.dart';
import 'package:onekit_converter/engine/registry.dart';
import 'package:onekit_converter/features/convert/convert_page.dart';
import 'package:onekit_converter/features/presets/preset_chip.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The promise a preset makes is one tap, so the thing worth testing is that a
/// tap really runs the recipe: the right target, the saved settings, and no
/// second confirmation. The job's own I/O never completes in a test, which is
/// fine — the screen is checked where it is unambiguous, in the running state.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;
  late String csvPath;
  late SettingsStore settings;
  late PresetStore presets;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('onekit_preset_test');
    // A data-format source: its preview is text, and the file is never decoded
    // into anything the test would have to fake.
    csvPath = '${dir.path}/table.csv';
    File(csvPath).writeAsStringSync('a,b\n1,2\n');

    SharedPreferences.setMockInitialValues({});
    settings = await SettingsStore.load();
    presets = await PresetStore.load();
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  Future<void> pumpConvert(WidgetTester tester, {ConvertArgs? args}) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsStore>.value(value: settings),
          ChangeNotifierProvider<PresetStore>.value(value: presets),
        ],
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: ConvertPage(args: args ?? ConvertArgs(paths: [csvPath])),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('offers only the presets this file can actually run', (tester) async {
    await presets.save(
      name: 'To JSON',
      targetExt: 'json',
      options: const ConvertOptions(),
    );
    await presets.save(
      name: 'Video for chat',
      targetExt: 'mp4',
      options: const ConvertOptions(videoCrf: 32),
    );
    await presets.save(
      name: 'Shrink the file',
      options: const ConvertOptions(quality: 50),
    );

    await pumpConvert(tester);

    expect(find.text('ONE-TAP PRESETS'), findsOneWidget);
    expect(find.text('To JSON'), findsOneWidget);
    // CSV cannot become an MP4, and it cannot be re-encoded into itself, so
    // neither recipe belongs on this screen.
    expect(find.text('Video for chat'), findsNothing);
    expect(find.text('Shrink the file'), findsNothing);
  });

  testWidgets('one tap sets the target and starts the job', (tester) async {
    await presets.save(
      name: 'To JSON',
      targetExt: 'json',
      options: const ConvertOptions(),
    );
    await pumpConvert(tester);

    expect(find.text('Convert to'), findsOneWidget, reason: 'nothing has started yet');

    await tester.tap(find.text('To JSON'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Converting'), findsOneWidget);
    expect(find.text('CSV → JSON'), findsOneWidget);
  });

  testWidgets('an optimize preset keeps the file\'s own format', (tester) async {
    final jpgPath = '${dir.path}/photo.jpg';
    File(jpgPath).writeAsBytesSync(List<int>.filled(64, 7));
    await presets.save(
      name: 'Shrink anything',
      options: const ConvertOptions(quality: 47),
    );
    await pumpConvert(tester, args: ConvertArgs(paths: [jpgPath]));

    // Its settings are visible before the tap, which is the point of showing a
    // preset's summary rather than only its name.
    expect(find.textContaining('quality 47'), findsOneWidget);

    await tester.tap(find.text('Shrink anything'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('Optimizing'), findsOneWidget);
    expect(find.text('JPG · re-encoded in place'), findsOneWidget);
  });

  testWidgets('a preset applied on Home runs as soon as the screen opens', (tester) async {
    // This is the route Home pushes when a preset chip is tapped there: it
    // carries the recipe, and arriving with one means running it.
    await pumpConvert(
      tester,
      args: ConvertArgs(
        paths: [csvPath],
        target: FormatRegistry.byExt('json'),
        options: const ConvertOptions(),
        presetName: 'To JSON',
      ),
    );

    expect(find.text('Converting'), findsOneWidget);
    expect(find.text('CSV → JSON'), findsOneWidget);
    // And the picker it would otherwise have waited on is gone.
    expect(find.text('ONE-TAP PRESETS'), findsNothing);
  });

  testWidgets('a preset that cannot run on this file falls back, and says so', (tester) async {
    // The recipe is for videos; the file is a spreadsheet. Starting it would
    // spend the tap on a failure the engine was always going to report.
    await pumpConvert(
      tester,
      args: ConvertArgs(
        paths: [csvPath],
        target: FormatRegistry.byExt('avif'),
        options: const ConvertOptions(),
        presetName: 'Video for chat',
      ),
    );

    expect(find.text('Convert to'), findsOneWidget, reason: 'it waits for a target');
    expect(
      find.textContaining('"Video for chat" does not fit this file'),
      findsOneWidget,
    );
  });

  testWidgets('the presets that do fit are still there to tap', (tester) async {
    await presets.save(name: 'To JSON', targetExt: 'json', options: const ConvertOptions());
    await pumpConvert(
      tester,
      args: ConvertArgs(
        paths: [csvPath],
        target: FormatRegistry.byExt('avif'),
        presetName: 'Nonsense',
      ),
    );

    expect(find.byType(PresetChip), findsOneWidget);
    expect(find.text('To JSON'), findsOneWidget);
  });
}
