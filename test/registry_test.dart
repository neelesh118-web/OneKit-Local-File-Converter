import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/engine/engine.dart';
import 'package:onekit_converter/engine/format.dart';
import 'package:onekit_converter/engine/registry.dart';

void main() {
  test('registry advertises 5000+ conversion pairs', () {
    expect(FormatRegistry.pairCount, greaterThanOrEqualTo(5000));
  });

  test('no pair reads an unreadable or writes an unwritable format', () {
    for (final p in FormatRegistry.pairs) {
      expect(p.from.read, isTrue, reason: 'source ${p.from.ext} not readable');
      expect(p.to.write, isTrue, reason: 'target ${p.to.ext} not writable');
      expect(p.from.ext == p.to.ext, isFalse);
    }
  });

  test('extension lookup handles dots, case and aliases', () {
    expect(FormatRegistry.byExt('.PNG')?.ext, 'png');
    expect(FormatRegistry.byExt('jpeg')?.family, Family.image);
    expect(FormatRegistry.byExt('tar.gz')?.ext, 'tgz');
    expect(FormatRegistry.byExt('nope'), isNull);
  });

  test('SVG is not advertised, because nothing can rasterise it', () {
    expect(FormatRegistry.byExt('svg'), isNull);
    expect(FormatRegistry.pairs.any((p) => p.id.contains('svg')), isFalse);
  });

  test('pair composition adds up and matches the matrix', () {
    final total = FormatRegistry.pairCount;
    final same = FormatRegistry.sameFamilyPairCount;
    final cross = FormatRegistry.crossFamilyPairTotal;

    expect(same + cross, total);
    expect(FormatRegistry.crossFamilyPairCounts.values.fold(0, (a, b) => a + b), cross);

    // Recompute independently and compare.
    var sameRecount = 0;
    final crossRecount = <Family, int>{};
    for (final p in FormatRegistry.pairs) {
      if (p.isCrossFamily) {
        crossRecount.update(p.to.family, (n) => n + 1, ifAbsent: () => 1);
      } else {
        sameRecount++;
      }
    }
    expect(same, sameRecount);
    expect(FormatRegistry.crossFamilyPairCounts, crossRecount);
  });

  // ------------------------------------------------------------------ optimize
  //
  // Optimize re-encodes a file into its own format. It is a capability of the
  // converters, not a catalogue entry: a self-pair is not a conversion, and
  // the matrix above asserts that none of them appear here.

  group('optimize', () {
    FileFormat fmt(String ext) => FormatRegistry.byExt(ext)!;

    test('is offered for the media formats people actually compress', () {
      for (final ext in [
        'jpg', 'jpeg', 'png', 'webp', 'avif', 'tiff', 'gif', 'bmp',
        'mp4', 'mkv', 'mov', 'webm', 'avi', 'ts',
        'mp3', 'm4a', 'aac', 'ogg', 'opus', 'ac3',
      ]) {
        expect(ConversionEngine.instance.canOptimize(fmt(ext)), isTrue, reason: ext);
      }
    });

    test('is refused where a re-encode cannot deliver a smaller file', () {
      const refused = {
        // Lossless audio: re-encoding it cannot shrink it.
        'wav': 'lossless',
        'flac': 'lossless',
        'alac': 'lossless',
        'aiff': 'lossless',
        'tta': 'lossless',
        'wv': 'lossless',
        // Raw elementary streams and mandated broadcast geometry.
        'h264': 'raw stream',
        'hevc': 'raw stream',
        'y4m': 'raw stream',
        'ivf': 'raw stream',
        'dv': 'fixed geometry',
        'mxf': 'fixed geometry',
        // No encoder in this build, so there is nothing to re-encode with.
        'heic': 'write-only',
        'heif': 'write-only',
        'wma': 'write-only',
        'dds': 'write-only',
        'psd': 'write-only',
        'farbfeld': 'write-only',
        // Handled by other converters, none of which claims to re-encode.
        'pdf': 'other converter',
        'docx': 'other converter',
        'json': 'other converter',
        'csv': 'other converter',
        'zip': 'other converter',
        'srt': 'other converter',
        'epub': 'other converter',
      };
      refused.forEach((ext, why) {
        expect(ConversionEngine.instance.canOptimize(fmt(ext)), isFalse,
            reason: '$ext ($why)');
      });
    });

    test('never appears in the catalogue or the target picker', () {
      for (final f in FormatRegistry.all) {
        expect(FormatRegistry.targetsFor(f).any((t) => t.ext == f.ext), isFalse,
            reason: '${f.ext} lists itself as a conversion target');
      }
      expect(FormatRegistry.pairs.any((p) => p.from.ext == p.to.ext), isFalse);
    });

    test('only claims formats that can both be decoded and encoded', () {
      for (final f in FormatRegistry.all) {
        if (!ConversionEngine.instance.canOptimize(f)) continue;
        expect(f.read, isTrue, reason: '${f.ext} cannot be decoded');
        expect(f.write, isTrue, reason: '${f.ext} cannot be encoded');
      }
    });
  });

  test('headline pairs are present', () {
    final ids = FormatRegistry.pairs.map((p) => p.id).toSet();
    for (final id in [
      'png>jpg',
      'heic>jpg',
      'mp4>mp3',
      'webp>png',
      'pdf>png',
      'jpg>pdf',
      'csv>json',
      'zip>tar',
      'srt>vtt',
      'mkv>mp4',
      'epub>txt',
      'mov>gif',
      'pdf>epub',
      'md>epub',
      'docx>csv',
    ]) {
      expect(ids, contains(id), reason: id);
    }
  });
}
