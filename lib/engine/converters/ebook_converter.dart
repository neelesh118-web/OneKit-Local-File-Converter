import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../format.dart';
import '../job.dart';
import 'converter.dart';
import 'converter_util.dart';
import 'document_converter.dart';

/// eBooks in and out. EPUB is read by following the OPF spine so chapters come
/// out in reading order, and written as a minimal but valid EPUB 3 container.
class EbookConverter extends FileConverter {
  const EbookConverter();

  @override
  String get name => 'eBook';

  @override
  bool supports(FileFormat from, FileFormat to) {
    if (from.family == Family.ebook) {
      return to.family == Family.ebook || to.family == Family.document;
    }
    // Only document formats the block reader actually understands; PDF is
    // handled by PdfConverter, which sits ahead of this one.
    return to.family == Family.ebook &&
        from.family == Family.document &&
        DocumentConverter.canRead(from.ext);
  }

  /// Builds an eBook from already-extracted blocks. Used by [PdfConverter],
  /// which owns PDF text extraction.
  static List<int> build(List<DocBlock> blocks, String ext, String title) {
    if (ext != 'epub') {
      throw ConversionException('OneKit cannot write ${ext.toUpperCase()} eBooks.');
    }
    return _buildEpub(blocks, title);
  }

  @override
  Future<void> convert(ConvertRequest r) async {
    r.onProgress(0.1, indeterminate: false);

    final blocks = r.from.family == Family.ebook
        ? await _read(r.inputPath, r.from.ext)
        : await DocumentConverter.readBlocks(r.inputPath, r.from.ext);
    r.cancel.throwIfCancelled();
    r.onProgress(0.55, indeterminate: false);

    if (r.to.ext == 'epub') {
      final title = p.basenameWithoutExtension(r.inputPath);
      // Zipping a whole book is CPU-bound; keep it off the UI isolate.
      final bytes = await Isolate.run(() => _buildEpub(blocks, title));
      await File(r.outputPath).writeAsBytes(bytes, flush: true);
    } else if (r.to.ext == 'pdf') {
      await File(r.outputPath).writeAsBytes(await DocumentConverter.buildPdf(blocks), flush: true);
    } else {
      await File(r.outputPath).writeAsString(
        DocumentConverter.writeBlocks(blocks, r.to.ext),
        flush: true,
      );
    }
    r.onProgress(1.0, indeterminate: false);
  }

  // ------------------------------------------------------------------ read

  static Future<List<DocBlock>> _read(String path, String ext) async {
    final bytes = await File(path).readAsBytes();
    return switch (ext) {
      'epub' => _readEpub(bytes),
      'fb2' => _readFb2(utf8.decode(bytes, allowMalformed: true)),
      _ => throw ConversionException('OneKit cannot read ${ext.toUpperCase()} eBooks.'),
    };
  }

  static List<DocBlock> _readEpub(List<int> bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (e) {
      throw ConversionException('This EPUB could not be opened.', detail: '$e');
    }

    ArchiveFile? find(String name) =>
        archive.files.where((f) => f.name.toLowerCase() == name.toLowerCase()).firstOrNull;

    String textOf(ArchiveFile f) => utf8.decode(f.content as List<int>, allowMalformed: true);

    // container.xml points at the OPF, which holds the spine reading order.
    final container = find('META-INF/container.xml');
    var opfPath = '';
    if (container != null) {
      final rootFile = XmlDocument.parse(textOf(container))
          .findAllElements('rootfile', namespace: '*')
          .firstOrNull;
      opfPath = rootFile?.getAttribute('full-path') ?? '';
    }
    if (opfPath.isEmpty) {
      opfPath = archive.files
              .where((f) => f.name.toLowerCase().endsWith('.opf'))
              .map((f) => f.name)
              .firstOrNull ??
          '';
    }

    final order = <String>[];
    if (opfPath.isNotEmpty) {
      final opf = find(opfPath);
      if (opf != null) {
        final doc = XmlDocument.parse(textOf(opf));
        final base = p.url.dirname(opfPath);
        final hrefById = <String, String>{
          for (final item in doc.findAllElements('item', namespace: '*'))
            if (item.getAttribute('id') != null && item.getAttribute('href') != null)
              item.getAttribute('id')!: item.getAttribute('href')!,
        };
        for (final ref in doc.findAllElements('itemref', namespace: '*')) {
          final href = hrefById[ref.getAttribute('idref') ?? ''];
          if (href == null) continue;
          order.add(base == '.' || base.isEmpty ? href : p.url.normalize('$base/$href'));
        }
      }
    }

    // Fall back to every XHTML file in archive order if the spine is unusable.
    final targets = order.isNotEmpty
        ? order
        : archive.files
            .where((f) => RegExp(r'\.x?html?$', caseSensitive: false).hasMatch(f.name))
            .map((f) => f.name)
            .toList();

    final blocks = <DocBlock>[];
    for (final name in targets) {
      final file = find(name) ?? find(Uri.decodeFull(name));
      if (file == null || !file.isFile) continue;
      blocks.addAll(DocumentConverter.readHtmlBlocks(textOf(file)));
    }

    if (blocks.isEmpty) throw ConversionException('No readable chapters were found in this EPUB.');
    return blocks;
  }

  static List<DocBlock> _readFb2(String xml) {
    final doc = XmlDocument.parse(xml);
    final blocks = <DocBlock>[];

    for (final body in doc.findAllElements('body', namespace: '*')) {
      for (final section in body.descendantElements.where((e) => e.name.local == 'section')) {
        final title = section.childElements.where((e) => e.name.local == 'title').firstOrNull;
        if (title != null) {
          final t = title.innerText.trim();
          if (t.isNotEmpty) blocks.add(DocBlock('h', t, level: 2));
        }
        for (final el in section.childElements) {
          switch (el.name.local) {
            case 'p':
              final t = el.innerText.trim();
              if (t.isNotEmpty) blocks.add(DocBlock('p', t));
            case 'subtitle':
              blocks.add(DocBlock('h', el.innerText.trim(), level: 3));
            case 'empty-line':
              break;
          }
        }
      }
    }

    if (blocks.isEmpty) throw ConversionException('No readable text was found in this FB2 file.');
    return blocks;
  }

  // ----------------------------------------------------------------- write

  /// Builds a minimal, spec-valid EPUB 3: mimetype first and stored, then the
  /// container, package document and a single XHTML chapter.
  static List<int> _buildEpub(List<DocBlock> blocks, String title) {
    final id = 'urn:uuid:${_stableUuid(title)}';
    final safeTitle = _esc(title);
    final chapter = DocumentConverter.writeBlocks(blocks, 'html');

    const containerXml = '''<?xml version="1.0" encoding="UTF-8"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>
''';

    final opf = '''<?xml version="1.0" encoding="UTF-8"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="bookid">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:identifier id="bookid">$id</dc:identifier>
    <dc:title>$safeTitle</dc:title>
    <dc:language>en</dc:language>
    <meta property="dcterms:modified">${DateTime.now().toUtc().toIso8601String().split('.').first}Z</meta>
  </metadata>
  <manifest>
    <item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>
    <item id="chapter" href="chapter.xhtml" media-type="application/xhtml+xml"/>
  </manifest>
  <spine>
    <itemref idref="chapter"/>
  </spine>
</package>
''';

    final nav = '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops">
<head><title>$safeTitle</title></head>
<body>
  <nav epub:type="toc" id="toc"><h1>Contents</h1>
    <ol><li><a href="chapter.xhtml">$safeTitle</a></li></ol>
  </nav>
</body>
</html>
''';

    final archive = Archive();
    void add(String name, String content, {bool store = false}) {
      final f = ArchiveFile.string(name, content);
      // The EPUB spec requires the mimetype entry to be stored, not deflated.
      if (store) f.compression = CompressionType.none;
      archive.addFile(f);
    }

    // The mimetype entry must be first and uncompressed.
    add('mimetype', 'application/epub+zip', store: true);
    add('META-INF/container.xml', containerXml);
    add('OEBPS/content.opf', opf);
    add('OEBPS/nav.xhtml', nav);
    add('OEBPS/chapter.xhtml', _toXhtml(chapter, safeTitle));

    return ZipEncoder().encode(archive);
  }

  /// EPUB requires well-formed XHTML, so void elements have to be self-closed.
  static String _toXhtml(String html, String title) {
    var body = html;
    final start = body.indexOf('<body>');
    final end = body.lastIndexOf('</body>');
    if (start >= 0 && end > start) body = body.substring(start + 6, end);
    body = body
        .replaceAll(RegExp(r'<(br|hr|img)([^>]*?)/?>', caseSensitive: false), r'<$1$2 />')
        .replaceAll('&nbsp;', '&#160;');
    return '''<?xml version="1.0" encoding="UTF-8"?>
<html xmlns="http://www.w3.org/1999/xhtml">
<head><title>$title</title><meta charset="utf-8"/></head>
<body>
$body
</body>
</html>
''';
  }

  static String _esc(String s) =>
      s.replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// A deterministic identifier so converting the same book twice produces the
  /// same EPUB id rather than a new one each run.
  static String _stableUuid(String seed) => stableUuidFrom(seed);
}
