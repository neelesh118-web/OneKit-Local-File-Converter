import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';

import 'package:archive/archive.dart';
import 'package:html/parser.dart' as html_parser;
import 'package:markdown/markdown.dart' as md;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:xml/xml.dart';

import '../format.dart';
import '../job.dart';
import 'converter.dart';
import 'data_converter.dart';

/// A document reduced to a flat list of blocks. HTML is the pivot on the way
/// in; this structure is the pivot on the way out, so every reader only has to
/// produce blocks and every writer only has to consume them.
class DocBlock {
  const DocBlock(this.type, this.text, {this.level = 0, this.rows});

  /// One of: h, p, li, code, quote, hr, table.
  final String type;
  final String text;
  final int level;
  final List<List<String>>? rows;
}

/// Text-document conversion: Markdown, HTML, plain text, RTF, reStructuredText,
/// DOCX and ODT in; the same set plus PDF, LaTeX and data formats out.
class DocumentConverter extends FileConverter {
  const DocumentConverter();

  @override
  String get name => 'Document';

  static const _readable = {'md', 'markdown', 'html', 'htm', 'txt', 'rtf', 'rst', 'docx', 'odt'};

  /// Whether the block reader understands [ext]. PDF is deliberately excluded:
  /// only pdfium can read it, so [PdfConverter] owns that route.
  static bool canRead(String ext) => _readable.contains(ext);

  @override
  bool supports(FileFormat from, FileFormat to) {
    if (from.family != Family.document) return false;
    if (!canRead(from.ext)) return false;
    return to.family == Family.document || to.family == Family.data;
  }

  @override
  Future<void> convert(ConvertRequest r) async {
    r.onProgress(0.1, indeterminate: false);
    final blocks = await readBlocks(r.inputPath, r.from.ext);
    r.cancel.throwIfCancelled();
    r.onProgress(0.5, indeterminate: false);

    if (r.to.family == Family.data) {
      // Documents become a row per block, which is what makes DOCX -> CSV
      // and MD -> JSON meaningful rather than a dump of one giant string.
      final rows = [
        for (final b in blocks)
          {'type': b.type, 'level': b.level, 'text': b.text},
      ];
      await File(r.outputPath).writeAsString(DataConverter.serialize(rows, r.to.ext), flush: true);
      r.onProgress(1.0, indeterminate: false);
      return;
    }

    if (r.to.ext == 'pdf') {
      final bytes = await buildPdf(blocks, title: r.from.upper);
      await File(r.outputPath).writeAsBytes(bytes, flush: true);
      r.onProgress(1.0, indeterminate: false);
      return;
    }

    await File(r.outputPath).writeAsString(writeBlocks(blocks, r.to.ext), flush: true);
    r.onProgress(1.0, indeterminate: false);
  }

  // ------------------------------------------------------------------ read

  static Future<List<DocBlock>> readBlocks(String path, String ext) async {
    switch (ext) {
      case 'md':
      case 'markdown':
        return _fromHtml(md.markdownToHtml(
          await File(path).readAsString(),
          extensionSet: md.ExtensionSet.gitHubWeb,
        ));
      case 'html':
      case 'htm':
        return _fromHtml(await File(path).readAsString());
      case 'txt':
        return _fromPlain(await File(path).readAsString());
      case 'rst':
        return _fromRst(await File(path).readAsString());
      case 'rtf':
        return _fromPlain(_stripRtf(await File(path).readAsString()));
      case 'docx':
        return _fromOfficeXml(await File(path).readAsBytes(), 'word/document.xml', 'w');
      case 'odt':
        return _fromOfficeXml(await File(path).readAsBytes(), 'content.xml', 'text');
      default:
        throw ConversionException('This app cannot read ${ext.toUpperCase()} documents.');
    }
  }

  /// Exposed so the eBook reader can reuse the HTML pivot for EPUB chapters.
  static List<DocBlock> readHtmlBlocks(String source) => _fromHtml(source);

  static List<DocBlock> _fromHtml(String source) {
    final doc = html_parser.parse(source);
    final out = <DocBlock>[];

    void walk(dynamic node) {
      for (final el in node.children) {
        final tag = el.localName as String;
        switch (tag) {
          case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
            out.add(DocBlock('h', el.text.trim(), level: int.parse(tag.substring(1))));
          case 'p':
            final t = el.text.trim();
            if (t.isNotEmpty) out.add(DocBlock('p', t));
          case 'li':
            out.add(DocBlock('li', el.text.trim()));
          case 'pre':
            out.add(DocBlock('code', el.text));
          case 'blockquote':
            out.add(DocBlock('quote', el.text.trim()));
          case 'hr':
            out.add(const DocBlock('hr', ''));
          case 'table':
            final rows = <List<String>>[];
            for (final tr in el.querySelectorAll('tr')) {
              rows.add([for (final c in tr.children) c.text.trim()]);
            }
            if (rows.isNotEmpty) out.add(DocBlock('table', '', rows: rows));
          case 'br' || 'script' || 'style':
            break;
          default:
            walk(el);
        }
      }
    }

    walk(doc.body ?? doc.documentElement!);
    if (out.isEmpty) {
      final t = doc.body?.text.trim() ?? '';
      if (t.isNotEmpty) return _fromPlain(t);
    }
    return out;
  }

  static List<DocBlock> _fromPlain(String text) {
    return [
      for (final para in text.replaceAll('\r\n', '\n').split(RegExp(r'\n\s*\n')))
        if (para.trim().isNotEmpty) DocBlock('p', para.trim()),
    ];
  }

  /// A practical reStructuredText subset: over/underlined titles and bullets.
  static List<DocBlock> _fromRst(String text) {
    final lines = const LineSplitter().convert(text);
    final out = <DocBlock>[];
    final buffer = <String>[];

    void flush() {
      if (buffer.isEmpty) return;
      out.add(DocBlock('p', buffer.join(' ').trim()));
      buffer.clear();
    }

    const markers = '=-~^"\'`#*+';
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final next = i + 1 < lines.length ? lines[i + 1] : '';
      final isUnderline = next.isNotEmpty &&
          markers.contains(next[0]) &&
          next.trim().split('').toSet().length == 1 &&
          next.trim().length >= line.trim().length &&
          line.trim().isNotEmpty;
      if (isUnderline) {
        flush();
        out.add(DocBlock('h', line.trim(), level: markers.indexOf(next[0]) < 2 ? 1 : 2));
        i++;
        continue;
      }
      final t = line.trim();
      if (t.isEmpty) {
        flush();
      } else if (t.startsWith('- ') || t.startsWith('* ')) {
        flush();
        out.add(DocBlock('li', t.substring(2).trim()));
      } else {
        buffer.add(t);
      }
    }
    flush();
    return out;
  }

  /// Pulls paragraph text out of the XML inside a DOCX or ODT zip container.
  static List<DocBlock> _fromOfficeXml(List<int> bytes, String entry, String ns) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final file = archive.files.where((f) => f.name == entry).firstOrNull;
    if (file == null) {
      throw ConversionException('This file is not a readable ${entry == 'content.xml' ? 'ODT' : 'DOCX'} document.');
    }
    final doc = XmlDocument.parse(utf8.decode(file.content as List<int>));
    final out = <DocBlock>[];

    for (final p in doc.findAllElements('p', namespace: '*')) {
      if (p.name.prefix != ns && ns == 'w') continue;
      final text = p.descendantElements
          .where((e) => e.name.local == 't')
          .map((e) => e.innerText)
          .join()
          .trim();
      if (text.isEmpty) continue;

      // Heading styles carry their level in the style name (Heading1 / H2).
      final style = p.descendantElements
              .where((e) => e.name.local == 'pStyle')
              .map((e) => e.getAttribute('val', namespace: '*') ?? '')
              .firstOrNull ??
          p.getAttribute('style-name', namespace: '*') ??
          '';
      final m = RegExp(r'(?:heading|h)[ _-]?(\d)', caseSensitive: false).firstMatch(style);
      if (m != null) {
        out.add(DocBlock('h', text, level: int.parse(m.group(1)!)));
      } else if (RegExp(r'list', caseSensitive: false).hasMatch(style)) {
        out.add(DocBlock('li', text));
      } else {
        out.add(DocBlock('p', text));
      }
    }

    if (out.isEmpty) throw ConversionException('No readable text was found in this document.');
    return out;
  }

  /// Strips RTF control words. Good enough for text extraction, and it never
  /// pretends to preserve formatting.
  static String _stripRtf(String rtf) {
    var s = rtf;
    s = s.replaceAll(RegExp(r'\\\*\\[a-z]+(-?\d+)?[ ]?(\{[^}]*\})?'), '');
    s = s.replaceAllMapped(RegExp(r"\\'([0-9a-fA-F]{2})"), (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)));
    s = s.replaceAll(RegExp(r'\\par[d]?\b'), '\n\n');
    s = s.replaceAll(RegExp(r'\\line\b'), '\n');
    s = s.replaceAll(RegExp(r'\\tab\b'), '\t');
    s = s.replaceAll(RegExp(r'\\[a-zA-Z]+-?\d*[ ]?'), '');
    s = s.replaceAll(RegExp(r'[{}]'), '');
    return s.trim();
  }

  // ----------------------------------------------------------------- write

  static String writeBlocks(List<DocBlock> blocks, String ext) {
    switch (ext) {
      case 'md':
      case 'markdown':
        return _toMarkdown(blocks);
      case 'html':
      case 'htm':
        return _toHtml(blocks);
      case 'txt':
        return _toPlain(blocks);
      case 'rst':
        return _toRst(blocks);
      case 'rtf':
        return _toRtf(blocks);
      case 'tex':
        return _toTex(blocks);
      default:
        throw ConversionException('This app cannot write ${ext.toUpperCase()} documents.');
    }
  }

  static String _toMarkdown(List<DocBlock> b) {
    final out = StringBuffer();
    for (final x in b) {
      switch (x.type) {
        case 'h':
          out.writeln('${'#' * x.level.clamp(1, 6)} ${x.text}\n');
        case 'li':
          out.writeln('- ${x.text}');
        case 'code':
          out.writeln('```\n${x.text.trimRight()}\n```\n');
        case 'quote':
          out.writeln('> ${x.text.replaceAll('\n', '\n> ')}\n');
        case 'hr':
          out.writeln('---\n');
        case 'table':
          final rows = x.rows!;
          out.writeln('| ${rows.first.join(' | ')} |');
          out.writeln('|${' --- |' * rows.first.length}');
          for (final r in rows.skip(1)) {
            out.writeln('| ${r.join(' | ')} |');
          }
          out.writeln();
        default:
          out.writeln('${x.text}\n');
      }
    }
    return out.toString();
  }

  static String _toHtml(List<DocBlock> b) {
    final body = StringBuffer();
    var inList = false;
    void closeList() {
      if (inList) {
        body.writeln('</ul>');
        inList = false;
      }
    }

    for (final x in b) {
      if (x.type != 'li') closeList();
      switch (x.type) {
        case 'h':
          final l = x.level.clamp(1, 6);
          body.writeln('<h$l>${_esc(x.text)}</h$l>');
        case 'li':
          if (!inList) {
            body.writeln('<ul>');
            inList = true;
          }
          body.writeln('  <li>${_esc(x.text)}</li>');
        case 'code':
          body.writeln('<pre><code>${_esc(x.text)}</code></pre>');
        case 'quote':
          body.writeln('<blockquote>${_esc(x.text)}</blockquote>');
        case 'hr':
          body.writeln('<hr>');
        case 'table':
          body.writeln('<table>');
          for (final r in x.rows!) {
            body.writeln('  <tr>${r.map((c) => '<td>${_esc(c)}</td>').join()}</tr>');
          }
          body.writeln('</table>');
        default:
          body.writeln('<p>${_esc(x.text)}</p>');
      }
    }
    closeList();

    return '''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Converted with Local File Converter</title>
<style>
  body { font-family: -apple-system, "Segoe UI", Roboto, sans-serif; line-height: 1.6; max-width: 46rem; margin: 2rem auto; padding: 0 1.25rem; }
  pre { background: #f4f4f5; padding: 1rem; overflow-x: auto; border-radius: 8px; }
  blockquote { border-left: 3px solid #ccc; margin: 0; padding-left: 1rem; color: #555; }
  table { border-collapse: collapse; width: 100%; }
  td, th { border: 1px solid #ddd; padding: .5rem; text-align: left; }
</style>
</head>
<body>
${body.toString().trimRight()}
</body>
</html>
''';
  }

  static String _toPlain(List<DocBlock> b) {
    final out = StringBuffer();
    for (final x in b) {
      switch (x.type) {
        case 'h':
          out.writeln('${x.text.toUpperCase()}\n');
        case 'li':
          out.writeln('  * ${x.text}');
        case 'hr':
          out.writeln('${'-' * 40}\n');
        case 'table':
          for (final r in x.rows!) {
            out.writeln(r.join('\t'));
          }
          out.writeln();
        default:
          out.writeln('${x.text}\n');
      }
    }
    return out.toString();
  }

  static String _toRst(List<DocBlock> b) {
    final out = StringBuffer();
    for (final x in b) {
      switch (x.type) {
        case 'h':
          final marker = x.level <= 1 ? '=' : (x.level == 2 ? '-' : '~');
          out.writeln(x.text);
          out.writeln(marker * x.text.length);
          out.writeln();
        case 'li':
          out.writeln('- ${x.text}');
        case 'code':
          out.writeln('::\n');
          for (final l in const LineSplitter().convert(x.text)) {
            out.writeln('    $l');
          }
          out.writeln();
        case 'quote':
          out.writeln('    ${x.text}\n');
        case 'hr':
          out.writeln('----\n');
        default:
          out.writeln('${x.text}\n');
      }
    }
    return out.toString();
  }

  static String _toRtf(List<DocBlock> b) {
    String esc(String s) => s
        .replaceAll('\\', r'\\')
        .replaceAll('{', r'\{')
        .replaceAll('}', r'\}')
        .replaceAllMapped(RegExp(r'[^\x00-\x7F]'), (m) => r'\u' '${m.group(0)!.codeUnitAt(0)}?');

    final out = StringBuffer(r'{\rtf1\ansi\deff0{\fonttbl{\f0 Helvetica;}}');
    for (final x in b) {
      switch (x.type) {
        case 'h':
          final size = (34 - x.level * 4).clamp(20, 34);
          out.write('\\pard\\sa180\\b\\fs$size ${esc(x.text)}\\b0\\fs22\\par\n');
        case 'li':
          out.write('\\pard\\fi-360\\li720\\sa80 \\bullet\\tab ${esc(x.text)}\\par\n');
        case 'hr':
          out.write('\\pard\\brdrb\\brdrs\\brdrw10\\par\n');
        default:
          out.write('\\pard\\sa180\\fs22 ${esc(x.text)}\\par\n');
      }
    }
    out.write('}');
    return out.toString();
  }

  static String _toTex(List<DocBlock> b) {
    String esc(String s) => s.replaceAllMapped(
          RegExp(r'[&%$#_{}~^\\]'),
          (m) => switch (m.group(0)!) {
            '\\' => r'\textbackslash{}',
            '~' => r'\textasciitilde{}',
            '^' => r'\textasciicircum{}',
            final c => '\\$c',
          },
        );

    final out = StringBuffer()
      ..writeln(r'\documentclass[11pt]{article}')
      ..writeln(r'\usepackage[utf8]{inputenc}')
      ..writeln(r'\usepackage[margin=1in]{geometry}')
      ..writeln(r'\begin{document}')
      ..writeln();

    var inList = false;
    void closeList() {
      if (inList) {
        out.writeln(r'\end{itemize}');
        inList = false;
      }
    }

    for (final x in b) {
      if (x.type != 'li') closeList();
      switch (x.type) {
        case 'h':
          final cmd = switch (x.level) { 1 => 'section', 2 => 'subsection', _ => 'subsubsection' };
          out.writeln('\\$cmd{${esc(x.text)}}');
        case 'li':
          if (!inList) {
            out.writeln(r'\begin{itemize}');
            inList = true;
          }
          out.writeln('  \\item ${esc(x.text)}');
        case 'code':
          out.writeln('\\begin{verbatim}\n${x.text.trimRight()}\n\\end{verbatim}');
        case 'quote':
          out.writeln('\\begin{quote}\n${esc(x.text)}\n\\end{quote}');
        case 'hr':
          out.writeln(r'\hrulefill');
        default:
          out.writeln('${esc(x.text)}\n');
      }
    }
    closeList();
    out.writeln(r'\end{document}');
    return out.toString();
  }

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  // ------------------------------------------------------------------- pdf
  /// Lays blocks out onto A4 pages. `pw.MultiPage` handles the pagination, so
  /// long documents flow rather than being clipped to one page.
  /// Cached theme so the font is loaded once, not on every conversion.
  static pw.ThemeData? _pdfTheme;
  static bool _pdfThemeLoaded = false;

  static Future<pw.ThemeData> _getPdfTheme() async {
    if (_pdfThemeLoaded) return _pdfTheme!;
    _pdfThemeLoaded = true;
    try {
      final regular = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Regular.ttf'));
      final bold = pw.Font.ttf(await rootBundle.load('assets/fonts/NotoSans-Bold.ttf'));
      _pdfTheme = pw.ThemeData.withFont(base: regular, bold: bold);
    } catch (_) {
      // In unit tests or when assets are unavailable, fall back to the
      // default built-in PDF fonts. Non-Latin text won't render, but the
      // conversion still works -- same behaviour as before the font was
      // bundled.
      _pdfTheme = pw.ThemeData.withFont(base: pw.Font.helvetica());
    }
    return _pdfTheme!;
  }


  static Future<List<int>> buildPdf(List<DocBlock> blocks, {String? title}) async {
    final theme = await _getPdfTheme();
    final doc = pw.Document(
      title: title == null ? 'Local File Converter' : 'Converted from $title',
      theme: theme,
    );

    final widgets = <pw.Widget>[];
    for (final x in blocks) {
      switch (x.type) {
        case 'h':
          widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(top: 14, bottom: 6),
            child: pw.Text(
              x.text,
              style: pw.TextStyle(
                fontSize: (24 - x.level * 2.5).clamp(12, 24).toDouble(),
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ));
        case 'li':
          widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(left: 14, bottom: 4),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text("\u2022  ", style: const pw.TextStyle(fontSize: 11)),
                pw.Expanded(child: pw.Text(x.text, style: const pw.TextStyle(fontSize: 11))),
              ],
            ),
          ));
        case 'code':
          widgets.add(pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.symmetric(vertical: 6),
            padding: const pw.EdgeInsets.all(8),
            decoration: const pw.BoxDecoration(color: PdfColors.grey200),
            child: pw.Text(x.text, style: const pw.TextStyle(fontSize: 9.5)),
          ));
        case 'quote':
          widgets.add(pw.Container(
            margin: const pw.EdgeInsets.symmetric(vertical: 6),
            padding: const pw.EdgeInsets.only(left: 10),
            decoration: const pw.BoxDecoration(
              border: pw.Border(left: pw.BorderSide(color: PdfColors.grey500, width: 2)),
            ),
            child: pw.Text(x.text, style: const pw.TextStyle(fontSize: 11, color: PdfColors.grey700)),
          ));
        case 'hr':
          widgets.add(pw.Divider(height: 18, color: PdfColors.grey400));
        case 'table':
          widgets.add(pw.TableHelper.fromTextArray(
            data: x.rows!,
            cellStyle: const pw.TextStyle(fontSize: 9.5),
            headerStyle: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
          ));
        default:
          widgets.add(pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: pw.Text(x.text, style: const pw.TextStyle(fontSize: 11, lineSpacing: 2)),
          ));
      }
    }

    doc.addPage(pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(48, 48, 48, 56),
      build: (_) => widgets.isEmpty ? [pw.Text('(empty document)')] : widgets,
    ));

    return doc.save();
  }
}
