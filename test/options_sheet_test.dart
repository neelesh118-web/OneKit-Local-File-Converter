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

  /// Opens [sheet] as a modal, picks [chip], then the "Auto" chip in that same
  /// row, applies, and returns what the sheet handed back.
  ///
  /// Scoped to the row on purpose: wherever a sheet shows both controls of a
  /// family it has two "Auto" chips, and the one that clears the setting is the
  /// one sharing a row with the value that was just chosen. [alsoPick] is chosen
  /// first, in another row, and is expected to survive.
  Future<ConvertOptions> pickThenAuto(
    WidgetTester tester,
    Widget sheet,
    String chip, {
    String? alsoPick,
  }) async {
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
                    builder: (_) => sheet,
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

    if (alsoPick != null) {
      await tester.tap(find.text(alsoPick));
      await tester.pump();
    }
    await tester.tap(find.text(chip));
    await tester.pump();
    await tester.tap(
      find.descendant(
        of: find.ancestor(of: find.text(chip), matching: find.byType(Wrap)),
        matching: find.text('Auto'),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Apply'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(applied, isNotNull, reason: 'Apply has to hand the settings back');
    return applied!;
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

  group('returning a control to Auto', () {
    // "Auto" is a chip like any other, and the value behind it is null — so
    // picking it has to unset the field. A copyWith that reads `value ?? this`
    // cannot express that, and the chip then does nothing at all once anything
    // else in its row has been chosen.
    Widget audioSheet() => OptionsSheet(
          source: fmt('wav'),
          target: fmt('mp3'),
          options: const ConvertOptions(),
        );
    Widget videoSheet() => OptionsSheet(
          source: fmt('mp4'),
          target: fmt('mkv'),
          options: const ConvertOptions(),
        );

    testWidgets('bitrate', (tester) async {
      final applied = await pickThenAuto(tester, audioSheet(), '128');
      expect(applied.audioBitrateKbps, isNull, reason: 'Auto means unset, not 128');
    });

    testWidgets('sample rate', (tester) async {
      final applied = await pickThenAuto(tester, audioSheet(), '48k');
      expect(applied.sampleRate, isNull, reason: 'Auto is a choice, and it is not 48k');
    });

    testWidgets('video quality', (tester) async {
      final applied = await pickThenAuto(tester, videoSheet(), 'Small');
      expect(applied.videoCrf, isNull, reason: 'the CRF is not 28 once Auto is picked');
    });

    testWidgets('frame rate', (tester) async {
      final applied = await pickThenAuto(tester, videoSheet(), '60');
      expect(applied.fps, isNull, reason: 'the frame rate is not 60 once Auto is picked');
    });

    testWidgets('clearing one control leaves its neighbour alone', (tester) async {
      final applied = await pickThenAuto(tester, audioSheet(), '128', alsoPick: '48k');
      expect(applied.audioBitrateKbps, isNull);
      expect(applied.sampleRate, 48000, reason: 'a cleared bitrate is not a cleared sample rate');
    });
  });

  group('ConvertOptions.copyWith', () {
    // The sheet's controls all go through this, so its two rules are worth
    // pinning down where they can be read at a glance: an argument left out
    // keeps the field, and an explicit null clears it.
    const full = ConvertOptions(
      quality: 70,
      width: 1600,
      height: 900,
      audioBitrateKbps: 192,
      sampleRate: 44100,
      videoCrf: 23,
      fps: 30,
      stripMetadata: true,
      pdfPageRange: '1-3',
      pdfDpi: 300,
      maxEdge: 2400,
    );

    test('carries over every field it was not given', () {
      final changed = full.copyWith(quality: 50);
      expect(changed.quality, 50);
      expect(changed.width, 1600);
      expect(changed.height, 900);
      expect(changed.audioBitrateKbps, 192);
      expect(changed.sampleRate, 44100);
      expect(changed.videoCrf, 23);
      expect(changed.fps, 30);
      expect(changed.stripMetadata, isTrue);
      expect(changed.pdfPageRange, '1-3');
      expect(changed.pdfDpi, 300);
      expect(changed.maxEdge, 2400);
    });

    test('clears the fields it is given an explicit null for', () {
      final cleared = full.copyWith(
        width: null,
        height: null,
        audioBitrateKbps: null,
        sampleRate: null,
        videoCrf: null,
        fps: null,
        pdfPageRange: null,
        maxEdge: null,
      );
      expect(cleared.width, isNull);
      expect(cleared.height, isNull);
      expect(cleared.audioBitrateKbps, isNull);
      expect(cleared.sampleRate, isNull);
      expect(cleared.videoCrf, isNull);
      expect(cleared.fps, isNull);
      expect(cleared.pdfPageRange, isNull);
      expect(cleared.maxEdge, isNull);
      expect(cleared.quality, 70, reason: 'a field that was not mentioned is untouched');
      expect(cleared.stripMetadata, isTrue);
      expect(cleared.pdfDpi, 300);
    });
  });
}
