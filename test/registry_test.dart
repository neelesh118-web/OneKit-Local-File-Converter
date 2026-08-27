import 'package:flutter_test/flutter_test.dart';
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
