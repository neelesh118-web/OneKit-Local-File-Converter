import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/engine/engine.dart';
import 'package:onekit_converter/engine/format.dart';
import 'package:onekit_converter/engine/registry.dart';
import 'package:onekit_converter/features/batch/batch_plan.dart';

/// One queue, two modes. What a file becomes is decided here and nowhere else,
/// which is what lets the screen's counts and the run loop agree.
void main() {
  FileFormat fmt(String ext) => FormatRegistry.byExt('.$ext')!;

  group('converting', () {
    test('every file goes to the shared target', () {
      expect(
        batchTargetFor(source: fmt('heic'), shared: fmt('jpg'), optimize: false)?.ext,
        'jpg',
      );
      expect(
        batchTargetFor(source: fmt('png'), shared: fmt('jpg'), optimize: false)?.ext,
        'jpg',
      );
    });

    test('no target picked yet means nothing runs', () {
      expect(batchTargetFor(source: fmt('png'), shared: null, optimize: false), isNull);
    });

    test('every file the registry can route is routed', () {
      // The other direction of the rule: in convert mode nothing that the
      // catalogue advertises may be quietly dropped from the queue.
      for (final source in FormatRegistry.all) {
        expect(
          batchTargetFor(source: source, shared: fmt('jpg'), optimize: false) != null,
          ConversionEngine.instance.canConvert(source, fmt('jpg')),
          reason: 'the queue and the engine must agree about ${source.ext}',
        );
      }
    });
  });

  group('optimizing', () {
    test('each file becomes itself, whatever the rest of the queue is', () {
      // This is the point of the mode: a mixed queue needs no shared target.
      for (final ext in ['jpg', 'png', 'mp4', 'mp3']) {
        final target = batchTargetFor(source: fmt(ext), shared: null, optimize: true);
        expect(target?.ext, ext, reason: 'expected $ext to be re-encoded into itself');
      }
    });

    test('a shared target is ignored while optimizing', () {
      // The page keeps the user's target while the mode is switched, so it must
      // not leak into an optimize run.
      final target = batchTargetFor(source: fmt('png'), shared: fmt('jpg'), optimize: true);
      expect(target?.ext, 'png');
    });

    test('formats this build cannot re-encode are skipped', () {
      // Lossless audio cannot get smaller by re-encoding, and HEIC has no
      // encoder here at all. Both are queued, neither is promised.
      for (final ext in ['flac', 'wav', 'alac', 'heic']) {
        expect(
          batchTargetFor(source: fmt(ext), shared: null, optimize: true),
          isNull,
          reason: '$ext should be skipped rather than failed',
        );
      }
    });

    test('an unreadable file is skipped in both modes', () {
      expect(batchTargetFor(source: null, shared: null, optimize: true), isNull);
      expect(batchTargetFor(source: null, shared: fmt('jpg'), optimize: false), isNull);
    });

    test('the rule agrees with the engine it asks', () {
      // If this ever disagrees, the queue would promise work the run loop
      // cannot do — the exact drift the shared rule exists to prevent.
      final optimizable = FormatRegistry.all.where(
        (f) => batchTargetFor(source: f, shared: null, optimize: true) != null,
      );
      // A build with nothing optimizable would make this whole mode a lie.
      expect(optimizable.length, greaterThan(20));
      for (final format in optimizable) {
        expect(format.read && format.write, isTrue, reason: '${format.ext} needs both');
      }
      // And the other direction: nothing the engine refuses sneaks through, and
      // nothing it allows is silently skipped by the queue.
      for (final format in FormatRegistry.all) {
        expect(
          batchTargetFor(source: format, shared: null, optimize: true) != null,
          ConversionEngine.instance.canOptimize(format),
          reason: 'the queue and the engine disagree about ${format.ext}',
        );
      }
    });
  });
}
