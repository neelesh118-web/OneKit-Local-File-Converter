import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/data/preset_store.dart';
import 'package:onekit_converter/core/data/settings_store.dart';
import 'package:onekit_converter/core/theme/app_theme.dart';
import 'package:onekit_converter/engine/job.dart';
import 'package:onekit_converter/features/presets/presets_page.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The screen where a preset can be renamed or thrown away. Everything it does
/// has to survive a relaunch, so the store is the thing being driven here — the
/// page is just its surface.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PresetStore presets;
  late SettingsStore settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    presets = await PresetStore.load();
    // The starfield behind the page reads the user's preferences.
    settings = await SettingsStore.load();
  });

  /// Lets a route finish opening or closing.
  ///
  /// Not `pumpAndSettle`: the starfield behind the page animates forever, so
  /// settling never happens. A few frames is enough for a menu or a dialog to
  /// come and go, and asserting the route is gone is what makes the rest of a
  /// test trustworthy — a still-open route puts the page under it offstage,
  /// where every finder silently fails.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> pumpPage(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<PresetStore>.value(value: presets),
          ChangeNotifierProvider<SettingsStore>.value(value: settings),
        ],
        child: MaterialApp(theme: AppTheme.dark(), home: const PresetsPage()),
      ),
    );
    await tester.pump();
  }

  testWidgets('says how presets are made when there are none', (tester) async {
    await pumpPage(tester);

    expect(find.text('No presets yet'), findsOneWidget);
    expect(find.textContaining('Save as a preset'), findsOneWidget);
    expect(find.text('Pick a file to start'), findsOneWidget);
  });

  testWidgets('lists each recipe with what it will actually do', (tester) async {
    await presets.save(
      name: 'Web photos',
      targetExt: 'webp',
      options: const ConvertOptions(quality: 68, width: 1600, stripMetadata: true),
    );
    await presets.save(name: 'Smaller, same format', options: const ConvertOptions(quality: 50));

    await pumpPage(tester);

    expect(find.text('Web photos'), findsOneWidget);
    expect(find.text('WEBP · quality 68, resize 1600xauto, strip metadata'), findsOneWidget);
    expect(find.text('Smaller, same format'), findsOneWidget);
    expect(find.text('Keep the format · quality 50'), findsOneWidget);
  });

  testWidgets('offers both actions on every preset', (tester) async {
    await presets.save(name: 'Web photos', targetExt: 'webp', options: const ConvertOptions());
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Preset actions'));
    await settle(tester);

    expect(find.text('Rename'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('deletes a preset, and it stays deleted', (tester) async {
    await presets.save(name: 'Web photos', targetExt: 'webp', options: const ConvertOptions());
    await presets.save(name: 'Keep', targetExt: 'jpg', options: const ConvertOptions());
    await pumpPage(tester);

    // Through the store, which is what the row's menu calls and what the page
    // follows. Tapping a popup item is covered by the rename test above.
    await presets.remove(presets.presets.first.id);
    await settle(tester);

    expect(find.text('Presets'), findsOneWidget, reason: 'the page is on screen, not under a route');
    expect(find.text('Web photos'), findsNothing);
    expect(find.text('Keep'), findsOneWidget);
    expect((await PresetStore.load()).presets.single.name, 'Keep');
  });

  testWidgets('renames a preset without touching its recipe', (tester) async {
    await presets.save(
      name: 'Old name',
      targetExt: 'webp',
      options: const ConvertOptions(quality: 68),
    );
    await pumpPage(tester);

    await tester.tap(find.byTooltip('Preset actions'));
    await settle(tester);
    await tester.tap(find.text('Rename'));
    await settle(tester);

    // The dialog opens on the current name, so renaming is an edit rather than
    // a retype.
    expect(find.text('Rename preset'), findsOneWidget);
    expect(find.text('Rename'), findsNothing, reason: 'the menu gave way to the dialog');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'Old name');
    await tester.enterText(find.byType(TextField), 'Holiday photos');
    await tester.pump();
    await tester.tap(find.text('Save'));
    await settle(tester);
    expect(find.text('Rename preset'), findsNothing, reason: 'the dialog closed');

    final stored = (await PresetStore.load()).presets.single;
    expect(stored.name, 'Holiday photos');
    expect(stored.targetExt, 'webp');
    expect(stored.options.quality, 68);
    expect(find.text('Holiday photos'), findsOneWidget);
  });
}
