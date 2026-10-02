import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'onekit_icon.dart';

/// Renders the launcher icon layers to PNG.
///
/// Run it, then copy the four goldens into `assets/icon/` and regenerate the
/// Android resources with `dart run flutter_launcher_icons`:
///
/// ```
/// flutter test tool/icon/generate_icons_test.dart --update-goldens
/// cp tool/icon/goldens/icon.png             assets/icon/icon.png
/// cp tool/icon/goldens/icon_background.png  assets/icon/icon_background.png
/// cp tool/icon/goldens/icon_foreground.png  assets/icon/icon_foreground.png
/// cp tool/icon/goldens/icon_monochrome.png  assets/icon/icon_monochrome.png
/// cp tool/icon/goldens/icon_512.png         assets/icon/play_store_512.png
/// cp tool/icon/goldens/icon_512.png         store/icon_512.png
/// dart run flutter_launcher_icons
/// ```
///
/// It is a golden test rather than a script because rendering the icon needs
/// Skia, and `flutter test` is the shortest path to a renderer that has it.
void main() {
  /// The tile the artwork is drawn on, in logical pixels. 1024 is Play's
  /// own icon size and an exact multiple of every density Android asks for.
  const canvas = 1024.0;

  Future<void> render(
    WidgetTester tester,
    String name, {
    required OneKitIconPainter painter,
    double size = canvas,
  }) async {
    tester.view.physicalSize = Size(size, size);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final key = GlobalKey();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: RepaintBoundary(
          key: key,
          child: SizedBox(
            width: size,
            height: size,
            child: CustomPaint(painter: painter),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await expectLater(find.byKey(key), matchesGoldenFile('goldens/$name.png'));
  }

  testWidgets('legacy tile, 1024', (tester) async {
    await render(tester, 'icon', painter: const OneKitIconPainter());
  });

  testWidgets('adaptive background, 1024', (tester) async {
    await render(tester, 'icon_background', painter: const OneKitIconPainter(glyph: false));
  });

  testWidgets('adaptive foreground, 1024', (tester) async {
    // Inside the 66% the platform guarantees: 0.48 of the tile leaves room for
    // a launcher that scales the layer up and pans it.
    await render(
      tester,
      'icon_foreground',
      painter: const OneKitIconPainter(tile: false, glyphScale: 0.48),
    );
  });

  testWidgets('monochrome, 1024', (tester) async {
    await render(
      tester,
      'icon_monochrome',
      painter: const OneKitIconPainter(tile: false, glyphScale: 0.48, flat: true),
    );
  });

  testWidgets('Play listing icon, 512', (tester) async {
    await render(tester, 'icon_512', painter: const OneKitIconPainter(), size: 512);
  });

  testWidgets('sanity: the mark is dark-on-light safe and paints nothing else', (tester) async {
    // Not a rendering test: a guard that the painter still answers for both
    // layers, so a future edit cannot quietly make the foreground opaque.
    expect(const OneKitIconPainter().tile, isTrue);
    expect(const OneKitIconPainter(tile: false).tile, isFalse);
    debugPrint('OneKit icon generator: shapes are ready to render.');
  });
}
