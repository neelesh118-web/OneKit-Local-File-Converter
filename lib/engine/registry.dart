import 'format.dart';

/// The single source of truth for what the app can convert.
///
/// Formats declare decode/encode capability; [pairs] is generated from those
/// flags plus the cross-family rules below, so the catalogue always matches the
/// engines that are actually wired up.
class FormatRegistry {
  FormatRegistry._();

  // ---------------------------------------------------------------- images
  static const image = <FileFormat>[
    FileFormat('png', 'Portable Network Graphics', Family.image, engine: Engine.dartImage, mime: 'image/png'),
    FileFormat('jpg', 'JPEG Image', Family.image, engine: Engine.dartImage, mime: 'image/jpeg', aliases: ['jpeg', 'jpe'], lossy: true),
    FileFormat('jpeg', 'JPEG Image', Family.image, engine: Engine.dartImage, mime: 'image/jpeg', lossy: true),
    FileFormat('webp', 'WebP Image', Family.image, mime: 'image/webp', lossy: true),
    FileFormat('bmp', 'Bitmap Image', Family.image, engine: Engine.dartImage, mime: 'image/bmp'),
    FileFormat('gif', 'Graphics Interchange Format', Family.image, engine: Engine.dartImage, mime: 'image/gif'),
    FileFormat('tiff', 'Tagged Image File Format', Family.image, engine: Engine.dartImage, mime: 'image/tiff', aliases: ['tif']),
    FileFormat('tif', 'Tagged Image File Format', Family.image, engine: Engine.dartImage, mime: 'image/tiff'),
    FileFormat('ico', 'Windows Icon', Family.image, engine: Engine.dartImage, mime: 'image/x-icon'),
    FileFormat('cur', 'Windows Cursor', Family.image, write: false, mime: 'image/x-icon'),
    FileFormat('tga', 'Truevision Targa', Family.image, engine: Engine.dartImage, mime: 'image/x-tga'),
    FileFormat('pnm', 'Portable Any Map', Family.image, engine: Engine.dartImage, mime: 'image/x-portable-anymap'),
    FileFormat('ppm', 'Portable Pixmap', Family.image, engine: Engine.dartImage, mime: 'image/x-portable-pixmap'),
    FileFormat('pgm', 'Portable Graymap', Family.image, mime: 'image/x-portable-graymap'),
    FileFormat('pbm', 'Portable Bitmap', Family.image, mime: 'image/x-portable-bitmap'),
    FileFormat('pam', 'Portable Arbitrary Map', Family.image, mime: 'image/x-portable-arbitrarymap'),
    FileFormat('pfm', 'Portable Float Map', Family.image, mime: 'image/x-portable-floatmap'),
    FileFormat('avif', 'AV1 Image File Format', Family.image, mime: 'image/avif', lossy: true),
    FileFormat('heic', 'High Efficiency Image', Family.image, write: false, mime: 'image/heic', lossy: true),
    FileFormat('heif', 'High Efficiency Image', Family.image, write: false, mime: 'image/heif', lossy: true),
    FileFormat('jp2', 'JPEG 2000', Family.image, mime: 'image/jp2'),
    FileFormat('j2k', 'JPEG 2000 Codestream', Family.image, mime: 'image/j2k'),
    // JPEG XL is deliberately absent: the bundled FFmpeg has no libjxl, so
    // nothing in the app can read it. Verified by the codec cross-check in
    // integration_test/format_matrix_test.dart.
    FileFormat('exr', 'OpenEXR', Family.image, engine: Engine.dartImage, mime: 'image/x-exr'),
    FileFormat('hdr', 'Radiance HDR', Family.image, mime: 'image/vnd.radiance'),
    FileFormat('dds', 'DirectDraw Surface', Family.image, write: false, mime: 'image/vnd-ms.dds'),
    FileFormat('psd', 'Photoshop Document', Family.image, write: false, engine: Engine.dartImage, mime: 'image/vnd.adobe.photoshop'),
    FileFormat('pcx', 'PC Paintbrush', Family.image, engine: Engine.dartImage, mime: 'image/x-pcx'),
    FileFormat('sgi', 'Silicon Graphics Image', Family.image, mime: 'image/sgi'),
    FileFormat('ras', 'Sun Raster', Family.image, mime: 'image/x-sun-raster'),
    FileFormat('xbm', 'X BitMap', Family.image, mime: 'image/x-xbitmap'),
    FileFormat('xwd', 'X Window Dump', Family.image, mime: 'image/x-xwindowdump'),
    FileFormat('xpm', 'X PixMap', Family.image, write: false, mime: 'image/x-xpixmap'),
    FileFormat('dpx', 'Digital Picture Exchange', Family.image, mime: 'image/x-dpx'),
    FileFormat('qoi', 'Quite OK Image', Family.image, mime: 'image/qoi'),
    FileFormat('apng', 'Animated PNG', Family.image, mime: 'image/apng'),
    FileFormat('wbmp', 'Wireless Bitmap', Family.image, mime: 'image/vnd.wap.wbmp'),
    // Read-only: no farbfeld encoder in the bundled build.
    FileFormat('farbfeld', 'Farbfeld', Family.image, write: false, mime: 'image/farbfeld'),
    FileFormat('phm', 'Portable Half Map', Family.image, mime: 'image/x-portable-halfmap'),
    FileFormat('vbn', 'Vizrt Binary Image', Family.image, mime: 'image/vbn'),
  ];

  // ----------------------------------------------------------------- audio
  static const audio = <FileFormat>[
    FileFormat('mp3', 'MPEG Audio Layer III', Family.audio, mime: 'audio/mpeg', lossy: true),
    FileFormat('wav', 'Waveform Audio', Family.audio, mime: 'audio/wav'),
    FileFormat('flac', 'Free Lossless Audio Codec', Family.audio, mime: 'audio/flac'),
    FileFormat('aac', 'Advanced Audio Coding', Family.audio, mime: 'audio/aac', lossy: true),
    FileFormat('m4a', 'MPEG-4 Audio', Family.audio, mime: 'audio/mp4', lossy: true),
    FileFormat('ogg', 'Ogg Vorbis', Family.audio, mime: 'audio/ogg', lossy: true),
    FileFormat('oga', 'Ogg Audio', Family.audio, mime: 'audio/ogg', lossy: true),
    FileFormat('opus', 'Opus Audio', Family.audio, mime: 'audio/opus', lossy: true),
    FileFormat('wma', 'Windows Media Audio', Family.audio, write: false, mime: 'audio/x-ms-wma', lossy: true),
    FileFormat('ac3', 'Dolby Digital', Family.audio, mime: 'audio/ac3', lossy: true),
    FileFormat('eac3', 'Dolby Digital Plus', Family.audio, mime: 'audio/eac3', lossy: true),
    FileFormat('aiff', 'Audio Interchange File', Family.audio, mime: 'audio/aiff', aliases: ['aif']),
    FileFormat('aif', 'Audio Interchange File', Family.audio, mime: 'audio/aiff'),
    FileFormat('alac', 'Apple Lossless', Family.audio, mime: 'audio/alac'),
    FileFormat('amr', 'Adaptive Multi-Rate', Family.audio, mime: 'audio/amr', lossy: true),
    FileFormat('au', 'Sun Audio', Family.audio, mime: 'audio/basic'),
    FileFormat('caf', 'Core Audio Format', Family.audio, mime: 'audio/x-caf'),
    FileFormat('dts', 'DTS Coherent Acoustics', Family.audio, mime: 'audio/vnd.dts', lossy: true),
    FileFormat('mka', 'Matroska Audio', Family.audio, mime: 'audio/x-matroska'),
    FileFormat('mp2', 'MPEG Audio Layer II', Family.audio, mime: 'audio/mpeg', lossy: true),
    FileFormat('tta', 'True Audio', Family.audio, mime: 'audio/x-tta'),
    FileFormat('voc', 'Creative Voice', Family.audio, mime: 'audio/x-voc'),
    FileFormat('w64', 'Sony Wave64', Family.audio, mime: 'audio/x-w64'),
    FileFormat('wv', 'WavPack', Family.audio, mime: 'audio/x-wavpack'),
    FileFormat('spx', 'Speex', Family.audio, write: false, mime: 'audio/speex', lossy: true),
    // Read-only: the bundled FFmpeg has no libgsm encoder.
    FileFormat('gsm', 'GSM 06.10', Family.audio, write: false, mime: 'audio/gsm', lossy: true),
    FileFormat('sbc', 'Bluetooth SBC', Family.audio, mime: 'audio/sbc', lossy: true),
    FileFormat('ape', 'Monkey Audio', Family.audio, write: false, mime: 'audio/x-ape'),
    FileFormat('mpc', 'Musepack', Family.audio, write: false, mime: 'audio/x-musepack', lossy: true),
    FileFormat('ra', 'RealAudio', Family.audio, write: false, mime: 'audio/x-realaudio', lossy: true),
    FileFormat('shn', 'Shorten', Family.audio, write: false, mime: 'audio/x-shorten'),
    // Read-only: FFmpeg demuxes IFF/8SVX but has no muxer for it.
    FileFormat('8svx', 'Amiga 8SVX', Family.audio, write: false, mime: 'audio/x-8svx'),
    FileFormat('adts', 'ADTS AAC Stream', Family.audio, mime: 'audio/aacp', lossy: true),
  ];

  // ----------------------------------------------------------------- video
  static const video = <FileFormat>[
    FileFormat('mp4', 'MPEG-4 Video', Family.video, mime: 'video/mp4'),
    FileFormat('mkv', 'Matroska Video', Family.video, mime: 'video/x-matroska'),
    FileFormat('avi', 'Audio Video Interleave', Family.video, mime: 'video/x-msvideo'),
    FileFormat('mov', 'QuickTime Movie', Family.video, mime: 'video/quicktime'),
    FileFormat('webm', 'WebM Video', Family.video, mime: 'video/webm'),
    FileFormat('flv', 'Flash Video', Family.video, mime: 'video/x-flv'),
    FileFormat('wmv', 'Windows Media Video', Family.video, write: false, mime: 'video/x-ms-wmv'),
    FileFormat('asf', 'Advanced Systems Format', Family.video, mime: 'video/x-ms-asf'),
    FileFormat('mpg', 'MPEG Video', Family.video, mime: 'video/mpeg', aliases: ['mpeg']),
    FileFormat('mpeg', 'MPEG Video', Family.video, mime: 'video/mpeg'),
    FileFormat('m4v', 'iTunes Video', Family.video, mime: 'video/x-m4v'),
    FileFormat('3gp', '3GPP Multimedia', Family.video, mime: 'video/3gpp'),
    FileFormat('3g2', '3GPP2 Multimedia', Family.video, mime: 'video/3gpp2'),
    FileFormat('ts', 'MPEG Transport Stream', Family.video, mime: 'video/mp2t'),
    FileFormat('m2ts', 'Blu-ray Transport Stream', Family.video, write: false, mime: 'video/mp2t'),
    FileFormat('mts', 'AVCHD Video', Family.video, write: false, mime: 'video/mp2t'),
    FileFormat('vob', 'DVD Video Object', Family.video, write: false, mime: 'video/dvd'),
    FileFormat('ogv', 'Ogg Video', Family.video, mime: 'video/ogg'),
    FileFormat('rm', 'RealMedia', Family.video, write: false, mime: 'application/vnd.rn-realmedia'),
    FileFormat('rmvb', 'RealMedia Variable Bitrate', Family.video, write: false, mime: 'application/vnd.rn-realmedia-vbr'),
    FileFormat('swf', 'Shockwave Flash', Family.video, write: false, mime: 'application/x-shockwave-flash'),
    FileFormat('f4v', 'Flash MP4 Video', Family.video, mime: 'video/x-f4v'),
    FileFormat('dv', 'Digital Video', Family.video, mime: 'video/x-dv'),
    FileFormat('mxf', 'Material Exchange Format', Family.video, mime: 'application/mxf'),
    FileFormat('nut', 'NUT Container', Family.video, mime: 'video/x-nut'),
    FileFormat('y4m', 'YUV4MPEG2', Family.video, mime: 'video/x-yuv4mpeg'),
    FileFormat('ivf', 'Indeo Video Format', Family.video, mime: 'video/x-ivf'),
    FileFormat('h264', 'Raw H.264 Stream', Family.video, mime: 'video/h264'),
    FileFormat('hevc', 'Raw H.265 Stream', Family.video, mime: 'video/hevc', aliases: ['h265']),
  ];

  // -------------------------------------------------------------- document
  static const document = <FileFormat>[
    FileFormat('pdf', 'Portable Document Format', Family.document, engine: Engine.pdfEngine, mime: 'application/pdf'),
    FileFormat('txt', 'Plain Text', Family.document, engine: Engine.dartText, mime: 'text/plain'),
    FileFormat('md', 'Markdown', Family.document, engine: Engine.dartText, mime: 'text/markdown', aliases: ['markdown']),
    FileFormat('html', 'HyperText Markup', Family.document, engine: Engine.dartText, mime: 'text/html', aliases: ['htm']),
    FileFormat('htm', 'HyperText Markup', Family.document, engine: Engine.dartText, mime: 'text/html'),
    FileFormat('rtf', 'Rich Text Format', Family.document, engine: Engine.dartText, mime: 'application/rtf'),
    FileFormat('docx', 'Word Document', Family.document, write: false, engine: Engine.dartText, mime: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'),
    FileFormat('odt', 'OpenDocument Text', Family.document, write: false, engine: Engine.dartText, mime: 'application/vnd.oasis.opendocument.text'),
    FileFormat('tex', 'LaTeX Document', Family.document, read: false, engine: Engine.dartText, mime: 'application/x-tex'),
    FileFormat('rst', 'reStructuredText', Family.document, engine: Engine.dartText, mime: 'text/x-rst'),
  ];

  // ------------------------------------------------------------------ data
  static const data = <FileFormat>[
    FileFormat('json', 'JSON', Family.data, engine: Engine.dartText, mime: 'application/json'),
    FileFormat('csv', 'Comma-Separated Values', Family.data, engine: Engine.dartText, mime: 'text/csv'),
    FileFormat('tsv', 'Tab-Separated Values', Family.data, engine: Engine.dartText, mime: 'text/tab-separated-values'),
    FileFormat('xml', 'XML', Family.data, engine: Engine.dartText, mime: 'application/xml'),
    FileFormat('yaml', 'YAML', Family.data, engine: Engine.dartText, mime: 'application/yaml', aliases: ['yml']),
    FileFormat('yml', 'YAML', Family.data, engine: Engine.dartText, mime: 'application/yaml'),
    FileFormat('ndjson', 'Newline-Delimited JSON', Family.data, engine: Engine.dartText, mime: 'application/x-ndjson', aliases: ['jsonl']),
    FileFormat('jsonl', 'JSON Lines', Family.data, engine: Engine.dartText, mime: 'application/jsonl'),
    FileFormat('ini', 'INI Configuration', Family.data, engine: Engine.dartText, mime: 'text/plain'),
    FileFormat('properties', 'Java Properties', Family.data, engine: Engine.dartText, mime: 'text/x-java-properties'),
    FileFormat('toml', 'TOML', Family.data, engine: Engine.dartText, mime: 'application/toml'),
    FileFormat('sql', 'SQL Insert Script', Family.data, read: false, engine: Engine.dartText, mime: 'application/sql'),
  ];

  // --------------------------------------------------------------- archive
  static const archive = <FileFormat>[
    FileFormat('zip', 'ZIP Archive', Family.archive, engine: Engine.dartArchive, mime: 'application/zip'),
    FileFormat('tar', 'Tape Archive', Family.archive, engine: Engine.dartArchive, mime: 'application/x-tar'),
    FileFormat('gz', 'Gzip', Family.archive, engine: Engine.dartArchive, mime: 'application/gzip'),
    FileFormat('tgz', 'Gzipped Tar', Family.archive, engine: Engine.dartArchive, mime: 'application/gzip', aliases: ['tar.gz']),
    FileFormat('bz2', 'Bzip2', Family.archive, engine: Engine.dartArchive, mime: 'application/x-bzip2'),
    FileFormat('tbz', 'Bzipped Tar', Family.archive, engine: Engine.dartArchive, mime: 'application/x-bzip2', aliases: ['tar.bz2']),
    FileFormat('xz', 'XZ Compressed', Family.archive, write: false, engine: Engine.dartArchive, mime: 'application/x-xz'),
    FileFormat('txz', 'XZ Tar', Family.archive, write: false, engine: Engine.dartArchive, mime: 'application/x-xz', aliases: ['tar.xz']),
    FileFormat('zlib', 'Zlib Stream', Family.archive, engine: Engine.dartArchive, mime: 'application/zlib'),
  ];

  // ----------------------------------------------------------------- ebook
  static const ebook = <FileFormat>[
    FileFormat('epub', 'EPUB eBook', Family.ebook, engine: Engine.dartEbook, mime: 'application/epub+zip'),
    FileFormat('fb2', 'FictionBook 2', Family.ebook, write: false, engine: Engine.dartEbook, mime: 'application/x-fictionbook+xml'),
  ];

  // -------------------------------------------------------------- subtitle
  static const subtitle = <FileFormat>[
    FileFormat('srt', 'SubRip Subtitle', Family.subtitle, engine: Engine.dartText, mime: 'application/x-subrip'),
    FileFormat('vtt', 'WebVTT', Family.subtitle, engine: Engine.dartText, mime: 'text/vtt'),
    FileFormat('ass', 'Advanced SubStation Alpha', Family.subtitle, engine: Engine.dartText, mime: 'text/x-ssa'),
    FileFormat('ssa', 'SubStation Alpha', Family.subtitle, engine: Engine.dartText, mime: 'text/x-ssa'),
    FileFormat('sbv', 'YouTube SubViewer', Family.subtitle, engine: Engine.dartText, mime: 'text/plain'),
    FileFormat('sub', 'MicroDVD Subtitle', Family.subtitle, engine: Engine.dartText, mime: 'text/plain'),
    FileFormat('lrc', 'Lyrics File', Family.subtitle, engine: Engine.dartText, mime: 'text/plain'),
    FileFormat('ttml', 'Timed Text Markup', Family.subtitle, engine: Engine.dartText, mime: 'application/ttml+xml'),
    FileFormat('dfxp', 'Distribution Format Exchange', Family.subtitle, engine: Engine.dartText, mime: 'application/ttaf+xml'),
    FileFormat('smi', 'SAMI Caption', Family.subtitle, engine: Engine.dartText, mime: 'application/smil'),
  ];

  // ------------------------------------------------------------------ font
  //
  // Container work only, by design. TTF and OTF differ in their glyph outline
  // format — quadratic 'glyf' versus cubic 'CFF' — and translating between the
  // two means font compiling, which no bundled engine can do. What pure Dart
  // can do honestly is unpack and repack the sfnt container: extracting the
  // faces inside a TrueType Collection, and WOFF's zlib-compressed tables.
  // TTF <-> OTF is therefore never advertised.
  static const font = <FileFormat>[
    FileFormat('ttf', 'TrueType Font', Family.font, engine: Engine.dartFont, mime: 'font/ttf'),
    FileFormat('otf', 'OpenType Font', Family.font, engine: Engine.dartFont, mime: 'font/otf'),
    FileFormat('ttc', 'TrueType Collection', Family.font, engine: Engine.dartFont, mime: 'font/collection'),
    FileFormat('woff', 'Web Open Font', Family.font, engine: Engine.dartFont, mime: 'font/woff'),
  ];

  // ---------------------------------------------------------------- vector
  //
  // Intentionally empty. Rasterising SVG needs a renderer none of the bundled
  // engines provide (the FFmpeg build has no librsvg, and the Dart decoder has
  // no SVG support), so the app does not claim it.
  static const vector = <FileFormat>[];

  /// Every format the app knows about, deduplicated by extension.
  static final List<FileFormat> all = () {
    final seen = <String>{};
    final out = <FileFormat>[];
    for (final f in [...image, ...audio, ...video, ...document, ...data, ...archive, ...ebook, ...subtitle, ...font, ...vector]) {
      if (seen.add(f.ext)) out.add(f);
    }
    return List<FileFormat>.unmodifiable(out);
  }();

  static final Map<String, FileFormat> _byExtRaw = {for (final f in all) f.ext: f};

  static final Map<String, FileFormat> _byExt = () {
    final m = <String, FileFormat>{};
    for (final f in all) {
      m[f.ext] = f;
    }
    for (final f in all) {
      for (final a in f.aliases) {
        m.putIfAbsent(a, () => f);
      }
    }
    return m;
  }();

  static FileFormat? byExt(String ext) {
    var e = ext.toLowerCase().trim();
    if (e.startsWith('.')) e = e.substring(1);
    if (e.contains('.')) {
      // Compound extensions such as tar.gz resolve before the last-segment fallback.
      final compound = _byExt[e];
      if (compound != null) return compound;
      e = e.split('.').last;
    }
    return _byExt[e];
  }

  /// Formats grouped by family, computed once. `family()` used to re-scan all
  /// 145 formats on every call, and pair generation alone called it ~290 times.
  static final Map<Family, List<FileFormat>> _byFamily = () {
    final m = <Family, List<FileFormat>>{for (final f in Family.values) f: <FileFormat>[]};
    for (final f in all) {
      m[f.family]!.add(f);
    }
    return {
      for (final e in m.entries) e.key: List<FileFormat>.unmodifiable(e.value),
    };
  }();

  static List<FileFormat> family(Family f) => _byFamily[f] ?? const [];

  static final List<FileFormat> readable =
      List.unmodifiable(all.where((f) => f.read));
  static final List<FileFormat> writable =
      List.unmodifiable(all.where((f) => f.write));

  /// Cross-family conversions the app implements, as source family -> target
  /// families. These mirror the converters exactly; anything a converter does
  /// not claim is expressed in [crossFormats] instead, or left out.
  static const Map<Family, List<Family>> crossFamily = {
    // FFmpeg: demux audio out of video, and pull frames or animations out.
    Family.video: [Family.audio, Family.image],
    // FFmpeg: loop a still into a clip.
    Family.image: [Family.video],
    // Document and eBook converters share a block model.
    Family.document: [Family.data, Family.ebook],
    Family.ebook: [Family.document],
    // Subtitles reduce to rows of text either way.
    Family.subtitle: [Family.data, Family.document],
  };

  /// Cross-family routes that apply to one source format rather than a whole
  /// family. Both directions of the PDF bridge live here: every image can
  /// become a PDF page, and a PDF can be rendered back to any image.
  static final Map<String, List<String>> crossFormats = () {
    final imageExts = [
      for (final f in image)
        if (f.write) f.ext,
    ];
    final readableImages = [
      for (final f in image)
        if (f.read) f.ext,
    ];
    return <String, List<String>>{
      'pdf': imageExts,
      for (final ext in readableImages) ext: const ['pdf'],
    };
  }();

  /// Every directed conversion the app offers.
  static final List<ConversionPair> pairs = () {
    final out = <ConversionPair>[];
    final ids = <String>{};

    void add(FileFormat a, FileFormat b) {
      if (!a.read || !b.write) return;
      if (a.ext == b.ext) return;
      final p = ConversionPair(a, b);
      if (ids.add(p.id)) out.add(p);
    }

    for (final src in all) {
      if (!src.read) continue;
      for (final dst in family(src.family)) {
        // Font targets have their own exclusion set: TTF <-> OTF is outline
        // translation, which the engines cannot honestly perform.
        if (fontToFontExcluded.contains('${src.ext}>${dst.ext}')) continue;
        add(src, dst);
      }
      for (final fam in crossFamily[src.family] ?? const <Family>[]) {
        for (final dst in family(fam)) {
          add(src, dst);
        }
      }
      for (final ext in crossFormats[src.ext] ?? const <String>[]) {
        final dst = _byExtRaw[ext];
        if (dst != null) add(src, dst);
      }
    }
    return List<ConversionPair>.unmodifiable(out);
  }();

  /// Pairs the matrix would normally generate but the engines cannot honestly
  /// perform. TTF and OTF differ in glyph outline format — quadratic 'glyf'
  /// versus cubic 'CFF' — so moving between them is font compiling, not
  /// container repacking, and no bundled engine can do it. TTC and WOFF are
  /// deliberately not excluded: they carry either outline format, and the
  /// FontConverter checks the flavor against the requested target at run time.
  static const Set<String> fontToFontExcluded = {'ttf>otf', 'otf>ttf'};

  /// Triggers the lazy static initialisers without blocking the caller.
  /// Call this from a post-frame callback after the splash has drawn so
  /// the heavy pair-matrix computation happens off the first frame.
  static void warmUp() {
    // Touch every lazy static so the Dart VM compiles and caches them.
    // ignore: unnecessary_statements
    pairCount;
    // ignore: unnecessary_statements
    readable;
    // ignore: unnecessary_statements
    writable;
  }

  static int get pairCount => pairs.length;

  /// Pairs whose source and target belong to the same family (PNG -> JPG).
  static final int sameFamilyPairCount = () {
    var n = 0;
    for (final p in pairs) {
      if (!p.isCrossFamily) n++;
    }
    return n;
  }();

  /// Pairs that cross a family boundary (MP4 -> MP3, PDF -> PNG), grouped by
  /// the target family. Derived from [pairs], so it can never drift from what
  /// the engines actually implement.
  static final Map<Family, int> crossFamilyPairCounts = () {
    final m = <Family, int>{};
    for (final p in pairs) {
      if (p.isCrossFamily) m.update(p.to.family, (n) => n + 1, ifAbsent: () => 1);
    }
    return Map<Family, int>.unmodifiable(m);
  }();

  /// Cross-family pairs, i.e. [pairCount] minus [sameFamilyPairCount].
  static int get crossFamilyPairTotal => pairCount - sameFamilyPairCount;

  static final Map<String, List<FileFormat>> _targetCache = {};

  /// Formats [f] can be converted into, for the "convert to..." picker.
  static List<FileFormat> targetsFor(FileFormat f) {
    return _targetCache.putIfAbsent(f.ext, () {
      final seen = <String>{};
      final out = <FileFormat>[];
      for (final p in pairs) {
        if (p.from.ext == f.ext && seen.add(p.to.ext)) out.add(p.to);
      }
      return out;
    });
  }

  static List<ConversionPair> search(String query) {
    final q = query.toLowerCase().trim();
    if (q.isEmpty) return const [];
    final normalized = q.replaceAll(RegExp(r'\s+to\s+|\s*->\s*|\s*→\s*'), '>');
    return pairs
        .where((p) => p.id.contains(normalized) || p.label.toLowerCase().contains(q))
        .take(300)
        .toList();
  }
}
