/// OneKit format registry.
///
/// Every conversion the app advertises is derived from this registry: a format
/// declares which family it belongs to and whether OneKit can decode it, encode
/// it, or both. The pair matrix in [FormatRegistry.pairs] is generated from
/// those capabilities, so the advertised catalogue can never drift from what the
/// engines actually implement.
library;

enum Family { image, audio, video, document, data, archive, ebook, subtitle, font, vector }

extension FamilyInfo on Family {
  String get label => switch (this) {
        Family.image => 'Image',
        Family.audio => 'Audio',
        Family.video => 'Video',
        Family.document => 'Document',
        Family.data => 'Data',
        Family.archive => 'Archive',
        Family.ebook => 'eBook',
        Family.subtitle => 'Subtitle',
        Family.font => 'Font',
        Family.vector => 'Vector',
      };

  String get glyph => switch (this) {
        Family.image => 'IMG',
        Family.audio => 'AUD',
        Family.video => 'VID',
        Family.document => 'DOC',
        Family.data => 'DAT',
        Family.archive => 'ZIP',
        Family.ebook => 'EPB',
        Family.subtitle => 'SUB',
        Family.font => 'FNT',
        Family.vector => 'VEC',
      };
}

/// Which engine handles a format. Used to pick the converter and to explain to
/// the user why a pair is or isn't available.
enum Engine { dartImage, ffmpeg, pdfEngine, dartText, dartArchive, dartEbook, dartFont }

class FileFormat {
  const FileFormat(
    this.ext,
    this.name,
    this.family, {
    this.read = true,
    this.write = true,
    this.engine = Engine.ffmpeg,
    this.aliases = const <String>[],
    this.mime = 'application/octet-stream',
    this.lossy = false,
  });

  /// Canonical lowercase extension without a dot. Doubles as the format id.
  final String ext;
  final String name;
  final Family family;

  /// Whether OneKit can decode / encode this format.
  final bool read;
  final bool write;

  final Engine engine;
  final List<String> aliases;
  final String mime;
  final bool lossy;

  String get id => ext;
  String get upper => ext.toUpperCase();

  @override
  String toString() => upper;
}

/// A single directed conversion, e.g. PNG -> WEBP.
class ConversionPair {
  ConversionPair(this.from, this.to)
      : id = '${from.ext}>${to.ext}',
        searchKey = '${from.ext}>${to.ext} '
            '${from.name.toLowerCase()} ${to.name.toLowerCase()}';

  final FileFormat from;
  final FileFormat to;

  /// Stored, not computed: it is read once per pair during catalogue
  /// generation and again on every search keystroke.
  final String id;

  /// Lowercased haystack matching the whole pair, built once. Searching used
  /// to allocate two lowercase strings per pair per keystroke — roughly
  /// 12,000 throwaway strings for a single character typed.
  final String searchKey;
  String get label => '${from.upper} to ${to.upper}';
  String get shortLabel => '${from.upper} → ${to.upper}';

  /// True when the pair crosses families (MP4 -> MP3, DOCX -> PDF, ...).
  bool get isCrossFamily => from.family != to.family;

  @override
  bool operator ==(Object other) => other is ConversionPair && other.id == id;
  @override
  int get hashCode => id.hashCode;
}
