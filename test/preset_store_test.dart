import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/data/preset_store.dart';
import 'package:onekit_converter/engine/job.dart';
import 'package:onekit_converter/engine/registry.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A preset is a promise to run something later, against a file the user has
/// not picked yet. These tests are about the two ways it can be wrong: losing
/// the recipe somewhere between saving and running it, and being offered for a
/// file it cannot actually be run on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('model', () {
    test('keeps every setting through a round trip', () {
      const preset = ConversionPreset(
        id: 'p1',
        name: 'Web photos',
        targetExt: 'webp',
        options: ConvertOptions(
          quality: 68,
          width: 1600,
          audioBitrateKbps: 128,
          sampleRate: 44100,
          videoCrf: 28,
          fps: 30,
          stripMetadata: true,
          pdfPageRange: '1-5',
          pdfDpi: 300,
        ),
      );

      final back = ConversionPreset.tryFromJson(
        jsonDecode(jsonEncode(preset.toJson())),
      );

      expect(back, isNotNull);
      expect(back!.name, 'Web photos');
      expect(back.targetExt, 'webp');
      expect(back.options.quality, 68);
      expect(back.options.width, 1600);
      expect(back.options.height, isNull);
      expect(back.options.audioBitrateKbps, 128);
      expect(back.options.sampleRate, 44100);
      expect(back.options.videoCrf, 28);
      expect(back.options.fps, 30);
      expect(back.options.stripMetadata, isTrue);
      expect(back.options.pdfPageRange, '1-5');
      expect(back.options.pdfDpi, 300);
    });

    test('a preset that keeps the format stores no target', () {
      // Optimize is the absence of a target, not a self-pair: the catalogue has
      // no "JPG to JPG", so a preset must not invent one.
      const preset = ConversionPreset(id: 'p2', name: 'Shrink');
      final json = preset.toJson();
      expect(json.containsKey('to'), isFalse);
      expect(preset.isOptimize, isTrue);
      expect(preset.summary, 'Keep the format');
    });

    test('a summary reads as the recipe, in the report\'s own words', () {
      const plain = ConversionPreset(id: 'p3', name: 'To JPG', targetExt: 'jpg');
      const tuned = ConversionPreset(
        id: 'p4',
        name: 'Small JPG',
        targetExt: 'jpg',
        options: ConvertOptions(quality: 62, stripMetadata: true),
      );

      expect(plain.summary, 'JPG', reason: 'nothing was changed, so nothing is listed');
      expect(tuned.summary, 'JPG · quality 62, strip metadata');
    });

    test('unusable stored data costs one preset, not the list', () {
      expect(ConversionPreset.tryFromJson(null), isNull);
      expect(ConversionPreset.tryFromJson('nonsense'), isNull);
      expect(ConversionPreset.tryFromJson({'name': 'no id'}), isNull);
      expect(ConversionPreset.tryFromJson({'id': 'x'}), isNull);
      expect(ConversionPreset.tryFromJson({'id': 'x', 'name': '   '}), isNull);
      // A preset with no options at all is legitimate.
      final bare = ConversionPreset.tryFromJson({'id': 'x', 'name': 'Bare'});
      expect(bare, isNotNull);
      expect(bare!.options.quality, const ConvertOptions().quality);
    });

    test('applicability is asked of the engine, not assumed', () {
      final flac = FormatRegistry.byExt('flac')!;
      final jpg = FormatRegistry.byExt('jpg')!;
      final csv = FormatRegistry.byExt('csv')!;

      const toJpg = ConversionPreset(id: 'a', name: 'To JPG', targetExt: 'jpg');
      const shrink = ConversionPreset(id: 'b', name: 'Shrink');

      expect(toJpg.appliesTo(csv), isFalse, reason: 'CSV cannot become a JPG here');
      expect(toJpg.appliesTo(jpg), isTrue);
      expect(shrink.appliesTo(jpg), isTrue, reason: 'a JPG can be re-encoded');
      expect(shrink.appliesTo(flac), isFalse, reason: 'FLAC cannot get smaller');
    });
  });

  group('store', () {
    test('saves, lists and reloads from the preferences file', () async {
      final store = await PresetStore.load();
      expect(store.isEmpty, isTrue);

      await store.save(
        name: 'Web photos',
        targetExt: 'webp',
        options: const ConvertOptions(quality: 68, stripMetadata: true),
      );
      await store.save(
        name: 'Shrink anything',
        options: const ConvertOptions(quality: 55),
      );

      // A second instance stands in for the next launch: what is written has to
      // be what comes back.
      final reloaded = await PresetStore.load();
      expect(reloaded.presets.length, 2);
      expect(reloaded.presets.first.name, 'Web photos');
      expect(reloaded.presets.first.targetExt, 'webp');
      expect(reloaded.presets.first.options.quality, 68);
      expect(reloaded.presets.last.isOptimize, isTrue);
      expect(reloaded.presets.last.options.quality, 55);
    });

    test('saving the same name again replaces the recipe in place', () async {
      final store = await PresetStore.load();
      await store.save(name: 'Photos', targetExt: 'jpg', options: const ConvertOptions(quality: 90));
      await store.save(name: 'Video', options: const ConvertOptions(quality: 60));
      await store.save(
        name: 'photos',
        targetExt: 'webp',
        options: const ConvertOptions(quality: 70),
      );

      expect(store.presets.length, 2, reason: 'a correction is not a second chip');
      expect(store.presets.first.name, 'photos');
      expect(store.presets.first.targetExt, 'webp');
      expect(store.presets.first.options.quality, 70);
      // And it keeps its place rather than jumping to the end.
      expect(store.presets.last.name, 'Video');
    });

    test('presets saved back to back are still separate presets', () async {
      // Ids cannot come from a timestamp alone: the clock's resolution can be a
      // millisecond, so two presets saved in one tick would share an id — and
      // removing one would take the other with it.
      final store = await PresetStore.load();
      for (var i = 0; i < 5; i++) {
        await store.save(name: 'P$i', targetExt: 'jpg', options: const ConvertOptions());
      }

      expect(store.presets.map((p) => p.id).toSet().length, 5);
      expect(store.presets.map((p) => p.name).toSet().length, 5);

      await store.remove(store.presets.first.id);
      expect([for (final p in store.presets) p.name], ['P1', 'P2', 'P3', 'P4']);
    });

    test('saving returns what was actually stored', () async {
      final store = await PresetStore.load();
      final first = await store.save(name: 'A', targetExt: 'png', options: const ConvertOptions());
      final again = await store.save(name: 'A', targetExt: 'jpg', options: const ConvertOptions());

      expect(first.name, 'A');
      expect(again.targetExt, 'jpg');
      expect(store.presets.length, 1);
    });

    test('rename and remove stick', () async {
      final store = await PresetStore.load();
      await store.save(name: 'A', targetExt: 'png', options: const ConvertOptions());
      final id = store.presets.single.id;

      await store.rename(id, '  Renamed  ');
      expect(store.presets.single.name, 'Renamed');
      await store.rename(id, '   ');
      expect(store.presets.single.name, 'Renamed', reason: 'a blank name is not a name');

      await store.remove(id);
      expect(store.isEmpty, isTrue);
      expect((await PresetStore.load()).isEmpty, isTrue);
    });

    test('forSource offers only the presets that can run', () async {
      final store = await PresetStore.load();
      await store.save(name: 'To JPG', targetExt: 'jpg', options: const ConvertOptions());
      await store.save(name: 'Shrink', options: const ConvertOptions(quality: 50));

      final forJpg = store.forSource(FormatRegistry.byExt('jpg')!);
      expect([for (final p in forJpg) p.name], ['To JPG', 'Shrink']);

      final forFlac = store.forSource(FormatRegistry.byExt('flac')!);
      expect([for (final p in forFlac) p.name], ['To JPG'],
          reason: 'FLAC cannot be shrunk, but it can be converted');
    });

    test('a corrupt entry does not take the good ones with it', () async {
      SharedPreferences.setMockInitialValues({
        'conversion_presets': [
          '{"id":"ok","name":"Good","to":"jpg","options":{"quality":80}}',
          'not json at all',
          '{"id":"","name":"Nameless"}',
        ],
      });

      final store = await PresetStore.load();
      expect([for (final p in store.presets) p.name], ['Good']);
      expect(store.presets.single.options.quality, 80);
    });
  });
}
