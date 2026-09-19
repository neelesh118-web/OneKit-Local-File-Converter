import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/theme/app_theme.dart';
import 'package:onekit_converter/engine/format.dart';
import 'package:onekit_converter/engine/job.dart';
import 'package:onekit_converter/engine/registry.dart';
import 'package:onekit_converter/features/convert/options_sheet.dart';

/// The options sheet is shared by a single conversion, where it is scoped to
/// one target, and by a batch Optimize, where the queue spans formats and each
/// file is re-encoded into its own. The second case has to offer a control when
/// *any* queued file understands it, and it must not start offering controls
/// for work that is not happening — a PDF page range in a queue with no PDF in
/// it is a setting that silently does nothing.
void main() {
  FileFormat fmt(String ext) => FormatRegistry.byExt('.$ext')!;

  Future<void> pump(WidgetTester tester, Widget sheet) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: SingleChildScrollView(child: sheet)),
      ),
    );
    await tester.pump();
  }

  group('batch sheet', () {
    testWidgets('covers every format in the queue', (tester) async {
      await pump(
        tester,
        OptionsSheet.batch(
          formats: [fmt('jpg'), fmt('mp4'), fmt('mp3')],
          options: const ConvertOptions(),
        ),
      );

      expect(find.text('Optimize options'), findsOneWidget);
      expect(find.text('Quality'), findsOneWidget, reason: 'the JPG brought this');
      expect(find.text('Resize'), findsOneWidget, reason: 'the JPG brought this');
      expect(find.text('Video quality'), findsOneWidget, reason: 'the MP4 brought this');
      expect(find.text('Bitrate'), findsOneWidget, reason: 'the MP3 brought this');
      expect(find.text('Remove metadata'), findsOneWidget);
      expect(find.text('Apply'), findsOneWidget);

      // Nothing in this queue is a PDF, so nothing offers to render pages.
      expect(find.text('Pages'), findsNothing);
      expect(find.text('Render density'), findsNothing);
    });

    testWidgets('an audio-only queue offers no image or video controls', (tester) async {
      await pump(
        tester,
        OptionsSheet.batch(formats: [fmt('mp3')], options: const ConvertOptions()),
      );

      expect(find.text('Bitrate'), findsOneWidget);
      expect(find.text('Quality'), findsNothing);
      expect(find.text('Video quality'), findsNothing);
      expect(find.text('Resize'), findsNothing);
      expect(find.text('Remove metadata'), findsOneWidget);
    });

    testWidgets('one setting is returned for the whole queue', (tester) async {
      // A tall window: the sheet is anchored to the bottom, and Apply has to be
      // on screen for a tap to reach it.
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      ConvertOptions? applied;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    applied = await showModalBottomSheet<ConvertOptions>(
                      context: context,
                      builder: (_) => OptionsSheet.batch(
                        formats: [fmt('jpg'), fmt('mp4')],
                        options: const ConvertOptions(),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The CRF chip, which is the same control the single-conversion sheet
      // uses: the batch does not get a second, subtly different set.
      await tester.tap(find.text('Small'));
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(applied, isNotNull);
      expect(applied!.videoCrf, 28);
      expect(applied!.quality, const ConvertOptions().quality);
    });
  });

  group('saving a preset', () {
    testWidgets('offers to save, then confirms what it saved', (tester) async {
      ConvertOptions? captured;
      await pump(
        tester,
        OptionsSheet(
          source: fmt('png'),
          target: fmt('jpg'),
          options: const ConvertOptions(quality: 80, width: 1200),
          onSavePreset: (options) async {
            captured = options;
            return 'Web photos';
          },
        ),
      );

      await tester.tap(find.text('Save as a preset'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(captured, isNotNull, reason: 'the sheet hands its settings over, it does not store them');
      expect(captured!.quality, 80);
      expect(captured!.width, 1200);
      expect(find.textContaining('Saved as "Web photos"'), findsOneWidget);
      // The offer gives way to the confirmation rather than inviting a second
      // save of the same thing.
      expect(find.text('Save as a preset'), findsNothing);
    });

    testWidgets('a backed-out save leaves the sheet as it was', (tester) async {
      await pump(
        tester,
        OptionsSheet(
          source: fmt('png'),
          target: fmt('jpg'),
          options: const ConvertOptions(),
          onSavePreset: (options) async => null,
        ),
      );

      await tester.tap(find.text('Save as a preset'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.textContaining('Saved as'), findsNothing);
      expect(find.text('Save as a preset'), findsOneWidget);
    });

    testWidgets('no save offer unless the screen can store one', (tester) async {
      await pump(
        tester,
        OptionsSheet(source: fmt('png'), target: fmt('jpg'), options: const ConvertOptions()),
      );
      expect(find.text('Save as a preset'), findsNothing);
    });

    testWidgets('a cleared resize box means no resize, not the last number', (tester) async {
      // Apply and Save both hand over the same object, so this covers what a
      // preset would store as well as what a conversion would run.
      ConvertOptions? applied;
      tester.view.physicalSize = const Size(1200, 2600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () async {
                    applied = await showModalBottomSheet<ConvertOptions>(
                      context: context,
                      builder: (_) => OptionsSheet(
                        source: fmt('png'),
                        target: fmt('jpg'),
                        options: const ConvertOptions(width: 1200, height: 900),
                      ),
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // The width box is the sheet's first number field, and it starts filled
      // from the options it was opened with.
      final width = find.byType(TextField).first;
      expect(tester.widget<TextField>(width).controller!.text, '1200');
      await tester.enterText(width, '');
      await tester.pump();
      await tester.tap(find.text('Apply'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(applied, isNotNull);
      expect(applied!.width, isNull, reason: 'an empty box is not a width');
      expect(applied!.height, 900, reason: 'the untouchhed side is kept');
    });
  });

  group('single target sheet', () {
    testWidgets('is still scoped to its own target', (tester) async {
      await pump(
        tester,
        OptionsSheet(
          source: fmt('png'),
          target: fmt('mp3'),
          options: const ConvertOptions(),
        ),
      );

      expect(find.text('MP3 options'), findsOneWidget);
      expect(find.text('Bitrate'), findsOneWidget);
      expect(find.text('Quality'), findsNothing);
      expect(find.text('Resize'), findsNothing);
    });

    testWidgets('still shows a PDF source its page range', (tester) async {
      await pump(
        tester,
        OptionsSheet(
          source: fmt('pdf'),
          target: fmt('png'),
          options: const ConvertOptions(),
        ),
      );

      expect(find.text('PNG options'), findsOneWidget);
      expect(find.text('Pages'), findsOneWidget);
      expect(find.text('Render density'), findsOneWidget);
    });
  });
}
