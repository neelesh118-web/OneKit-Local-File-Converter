import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:pdf/pdf.dart' hide PdfDocument;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../format.dart';
import '../job.dart';
import '../pdf/page_range.dart';
import '../pdf/pdf_toolbox.dart' show openPdfDocument;
import 'converter.dart';
import 'data_converter.dart';
import 'document_converter.dart';
import 'ebook_converter.dart';
import 'ffmpeg_converter.dart';

/// PDF in both directions: images and documents into PDF, and PDF back out to
/// images, text documents or structured data.
class PdfConverter extends FileConverter {
  const PdfConverter();

  @override
  String get name => 'PDF';

  @override
  bool supports(FileFormat from, FileFormat to) {
    if (from.ext == 'pdf') {
      // PDF is claimed here for every text-ish target too, because the generic
      // document reader cannot parse PDF — only pdfium can.
      return to.family == Family.image ||
          to.family == Family.document ||
          to.family == Family.data ||
          to.family == Family.ebook;
    }
    return to.ext == 'pdf' && (from.family == Family.image || from.family == Family.vector);
  }

  @override
  Future<void> convert(ConvertRequest r) async {
    if (r.to.ext == 'pdf') return _imageToPdf(r);
    if (r.to.family == Family.image) return _pdfToImages(r);
    return _pdfToText(r);
  }

  // -------------------------------------------------------------- image ->

  Future<void> _imageToPdf(ConvertRequest r) async {
    r.onProgress(0.15, indeterminate: false);

    // The PDF writer can only embed JPEG and PNG, so anything else is
    // normalised to PNG first.
    final pngPath = await _ensureEmbeddable(r);
    r.cancel.throwIfCancelled();
    r.onProgress(0.5, indeterminate: false);

    final bytes = await File(pngPath).readAsBytes();
    final image = pw.MemoryImage(bytes);

    final doc = pw.Document(title: p.basenameWithoutExtension(r.inputPath));
    doc.addPage(
      pw.Page(
        // The page takes the image's own proportions so nothing is letterboxed.
        pageFormat: PdfPageFormat(
          image.width!.toDouble(),
          image.height!.toDouble(),
          marginAll: 0,
        ),
        build: (_) => pw.Image(image, fit: pw.BoxFit.contain),
      ),
    );

    r.onProgress(0.85, indeterminate: false);
    await File(r.outputPath).writeAsBytes(await doc.save(), flush: true);
    if (pngPath != r.inputPath) {
      await File(pngPath).delete().catchError((_) => File(pngPath));
    }
    r.onProgress(1.0, indeterminate: false);
  }

  /// Largest edge embedded into a PDF page. A 12 MP photo decodes to ~48 MB of
  /// raw pixels inside the PDF writer, which is enough to kill the app on a
  /// mid-range phone; 2400px is still 300 DPI across eight inches.
  static const _maxEmbedEdge = 2400;

  /// Above this, re-encode even a PNG or JPEG so the embedded bitmap stays
  /// bounded. Smaller files are passed through untouched.
  static const _passThroughLimit = 1500 * 1024;

  /// Returns a path to a PNG/JPEG the PDF writer can embed, transcoding first
  /// when the source is something the writer cannot take, or large enough that
  /// embedding it as-is would exhaust memory.
  Future<String> _ensureEmbeddable(ConvertRequest r) async {
    final native = r.from.ext == 'png' || r.from.ext == 'jpg' || r.from.ext == 'jpeg';
    var bytes = 0;
    try {
      bytes = await File(r.inputPath).length();
    } on FileSystemException {
      // Treated as large, which is the safe direction.
    }
    if (native && bytes > 0 && bytes <= _passThroughLimit) return r.inputPath;

    final tmp = p.join(
      Directory.systemTemp.path,
      'lfc_${DateTime.now().microsecondsSinceEpoch}.png',
    );
    const png = FileFormat('png', 'PNG', Family.image);
    await const FfmpegConverter().convert(
      ConvertRequest(
        inputPath: r.inputPath,
        outputPath: tmp,
        from: r.from,
        to: png,
        // The scale is a ceiling, not a resize: images already under the limit
        // come through at their original size.
        options: r.options.copyWith(maxEdge: _maxEmbedEdge),
        onProgress: (_, {bool indeterminate = false}) {},
        cancel: r.cancel,
      ),
    );
    return tmp;
  }

  // -------------------------------------------------------------- pdf ->

  Future<void> _pdfToImages(ConvertRequest r) async {
    final doc = await _open(r.inputPath);
    try {
      final pages = parsePageRange(r.options.pdfPageRange, doc.pages.length);
      if (pages.isEmpty) {
        throw ConversionException('That page range does not match any page in this PDF.');
      }

      final dir = p.dirname(r.outputPath);
      final base = p.basenameWithoutExtension(r.outputPath);
      final ext = r.to.ext;
      // pdfrx renders at 72 dpi natively; scale up for the requested density.
      final scale = (r.options.pdfDpi / 72).clamp(0.5, 8.0);

      for (var i = 0; i < pages.length; i++) {
        r.cancel.throwIfCancelled();
        final page = doc.pages[pages[i] - 1];
        final rendered = await page.render(
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
          // Opaque white so transparent PDF regions do not render black.
          backgroundColor: 0xFFFFFFFF,
        );
        if (rendered == null) {
          throw ConversionException('Page ${pages[i]} could not be rendered.');
        }

        final Uint8List raw;
        try {
          raw = Uint8List.fromList(rendered.pixels);
        } finally {
          rendered.dispose();
        }

        // pdfrx always hands back BGRA8888.
        final frame = img.Image.fromBytes(
          width: rendered.width,
          height: rendered.height,
          bytes: raw.buffer,
          numChannels: 4,
          order: img.ChannelOrder.bgra,
        );

        // Single-page PDFs keep the plain output name; multi-page renders get
        // a page suffix so nothing overwrites anything.
        final outPath = pages.length == 1
            ? r.outputPath
            : p.join(dir, '${base}_p${pages[i]}.$ext');

        await _writeFrame(frame, outPath, ext, r);
        if (outPath != r.outputPath) r.extraOutputs?.add(outPath);
        r.onProgress((i + 1) / pages.length, indeterminate: false);
      }

      // When the range starts past page 1 the primary output has a suffix, so
      // point the job at the first file that was actually written.
      if (pages.length > 1 && !await File(r.outputPath).exists()) {
        final first = p.join(dir, '${base}_p${pages.first}.$ext');
        await File(first).rename(r.outputPath);
        r.extraOutputs?.remove(first);
      }
    } finally {
      doc.dispose();
    }
  }

  /// Writes a rendered frame, using the Dart encoder where it can and falling
  /// back to FFmpeg (via a PNG hand-off) for the exotic targets.
  Future<void> _writeFrame(img.Image frame, String outPath, String ext, ConvertRequest r) async {
    switch (ext) {
      case 'png':
        await File(outPath).writeAsBytes(img.encodePng(frame), flush: true);
      case 'jpg' || 'jpeg':
        await File(outPath).writeAsBytes(
          img.encodeJpg(frame, quality: r.options.quality.clamp(1, 100)),
          flush: true,
        );
      case 'bmp':
        await File(outPath).writeAsBytes(img.encodeBmp(frame), flush: true);
      case 'tiff' || 'tif':
        await File(outPath).writeAsBytes(img.encodeTiff(frame), flush: true);
      case 'tga':
        await File(outPath).writeAsBytes(img.encodeTga(frame), flush: true);
      case 'gif':
        await File(outPath).writeAsBytes(img.encodeGif(frame), flush: true);
      case 'ico':
        await File(outPath).writeAsBytes(img.encodeIco(frame), flush: true);
      default:
        final tmp = '$outPath.tmp.png';
        await File(tmp).writeAsBytes(img.encodePng(frame), flush: true);
        const png = FileFormat('png', 'PNG', Family.image);
        try {
          await const FfmpegConverter().convert(
            ConvertRequest(
              inputPath: tmp,
              outputPath: outPath,
              from: png,
              to: r.to,
              options: r.options,
              onProgress: (_, {bool indeterminate = false}) {},
              cancel: r.cancel,
            ),
          );
        } finally {
          await File(tmp).delete().catchError((_) => File(tmp));
        }
    }
  }

  Future<void> _pdfToText(ConvertRequest r) async {
    final doc = await _open(r.inputPath);
    try {
      final pages = parsePageRange(r.options.pdfPageRange, doc.pages.length);
      final blocks = <DocBlock>[];
      final rows = <Map<String, dynamic>>[];

      for (var i = 0; i < pages.length; i++) {
        r.cancel.throwIfCancelled();
        final text = (await doc.pages[pages[i] - 1].loadText())?.fullText ?? '';
        rows.add({'page': pages[i], 'text': text});
        for (final para in text.split(RegExp(r'\n\s*\n'))) {
          final t = para.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim();
          if (t.isNotEmpty) blocks.add(DocBlock('p', t));
        }
        r.onProgress((i + 1) / pages.length * 0.9, indeterminate: false);
      }

      if (blocks.isEmpty) {
        throw ConversionException(
          'No selectable text was found. This PDF is probably a scan — convert it to an image instead.',
        );
      }

      if (r.to.family == Family.data) {
        await File(r.outputPath).writeAsString(DataConverter.serialize(rows, r.to.ext), flush: true);
      } else if (r.to.family == Family.ebook) {
        await File(r.outputPath).writeAsBytes(
          EbookConverter.build(blocks, r.to.ext, p.basenameWithoutExtension(r.inputPath)),
          flush: true,
        );
      } else {
        await File(r.outputPath).writeAsString(
          DocumentConverter.writeBlocks(blocks, r.to.ext),
          flush: true,
        );
      }
      r.onProgress(1.0, indeterminate: false);
    } finally {
      doc.dispose();
    }
  }

  /// The page range is parsed by the same code the PDF toolbox uses, so "1-3"
  /// cannot mean one thing here and another in Split.
  static Future<PdfDocument> _open(String path) => openPdfDocument(path);
}
