import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
// The pdf package exports its own PdfPage/PdfPageRotation for building pages;
// the ones that matter here are pdfrx's, which wrap a real pdfium page.
import 'package:pdf/pdf.dart' hide PdfDocument, PdfPage, PdfPageRotation;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

import '../converters/converter.dart';
import '../engine.dart';
import '../job.dart';
import 'pdf_plan.dart';

/// What a toolbox run produced.
class PdfToolResult {
  const PdfToolResult({
    required this.outputs,
    required this.sourceBytes,
    required this.outputBytes,
    required this.elapsed,
  });

  /// Written files, in plan order. The first is the primary result.
  final List<String> outputs;
  final int sourceBytes;
  final int outputBytes;
  final Duration elapsed;

  /// Negative means the result is smaller, which is the point of compress.
  double? get sizeDeltaRatio {
    if (sourceBytes <= 0 || outputBytes <= 0) return null;
    return (outputBytes - sourceBytes) / sourceBytes;
  }
}

/// Runs the PDF toolbox on the engine the app already bundles.
///
/// Every operation is pdfium work through pdfrx: pages are imported from the
/// source documents, rotated, deleted, and written back out. Nothing is
/// re-encoded and nothing is rasterised, so a merge, split or rotate keeps the
/// original text, fonts and vectors exactly as they were. The one operation
/// that does change content — the rasterising compress — says so where it is
/// offered.
class PdfToolbox {
  PdfToolbox._();

  /// Reads a document's page count. pdfium parses the page tree for this, not
  /// the page contents, so it is cheap even for a large file.
  static Future<PdfSource> inspect(String path) async {
    final doc = await openPdfDocument(path);
    try {
      return PdfSource(path: path, pageCount: doc.pages.length);
    } finally {
      doc.dispose();
    }
  }

  /// Runs [plan], writing its outputs into [outputDirectory].
  ///
  /// Progress is reported per output file, not per page: pdfium's import and
  /// save are single calls with no progress channel, and a finer-grained number
  /// would be exactly the invented percentage this app refuses to show anywhere
  /// else.
  static Future<PdfToolResult> run(
    PdfPlan plan, {
    required String outputDirectory,
    CancelToken? cancel,
    void Function(double value)? onProgress,
  }) async {
    if (plan.outputs.isEmpty) {
      throw ConversionException('Nothing was selected to write.');
    }

    final started = DateTime.now();
    var sourceBytes = 0;
    for (final source in plan.sources) {
      sourceBytes += await _lengthOf(source.path);
    }

    final dir = Directory(outputDirectory);
    await dir.create(recursive: true);

    final written = <String>[];
    switch (plan.tool) {
      case PdfTool.merge:
        await _merge(plan, dir.path, written, cancel, onProgress);
      case PdfTool.split:
      case PdfTool.rotate:
        await _editPerOutput(plan, dir.path, written, cancel, onProgress);
      case PdfTool.compress:
        await _compress(plan, dir.path, written, cancel, onProgress);
    }

    cancel?.throwIfCancelled();

    var outputBytes = 0;
    for (final path in written) {
      outputBytes += await _lengthOf(path);
    }
    onProgress?.call(1.0);

    return PdfToolResult(
      outputs: written,
      sourceBytes: sourceBytes,
      outputBytes: outputBytes,
      elapsed: DateTime.now().difference(started),
    );
  }

  // ------------------------------------------------------------------ merge

  /// Merging is the only operation that needs a brand new document, because its
  /// pages come from several files.
  static Future<void> _merge(
    PdfPlan plan,
    String dir,
    List<String> written,
    CancelToken? cancel,
    void Function(double value)? onProgress,
  ) async {
    final docs = <PdfDocument>[];
    try {
      for (final source in plan.sources) {
        cancel?.throwIfCancelled();
        docs.add(await openPdfDocument(source.path));
      }

      final output = plan.outputs.first;
      final dest = await PdfDocument.createNew(sourceName: output.fileName);
      try {
        // Every page is foreign here, so pdfium imports it when the destination
        // is encoded — which is why the sources must stay open until then.
        dest.pages = [
          for (final ref in output.pages)
            _rotated(docs[ref.source].pages[ref.page - 1], ref.quarterTurns),
        ];
        final path = await _reserve(dir, output.fileName);
        await File(path).writeAsBytes(await dest.encodePdf(), flush: true);
        written.add(path);
        onProgress?.call(1.0);
      } finally {
        dest.dispose();
      }
    } finally {
      for (final doc in docs) {
        doc.dispose();
      }
    }
  }

  // --------------------------------------------------------- split, rotate

  /// Split and rotate both edit a document's page list and write the result
  /// back out. Each output gets its own copy of the source, because pdfium
  /// arranges pages in place: a second arrangement on the same document would
  /// be computing its page moves against the first one's leftovers.
  static Future<void> _editPerOutput(
    PdfPlan plan,
    String dir,
    List<String> written,
    CancelToken? cancel,
    void Function(double value)? onProgress,
  ) async {
    for (var i = 0; i < plan.outputs.length; i++) {
      cancel?.throwIfCancelled();
      final output = plan.outputs[i];

      final doc = await openPdfDocument(plan.sources.first.path);
      try {
        // The right-hand side is read in full before the assignment, so the
        // page objects are the document's own, unmutated ones.
        doc.pages = [
          for (final ref in output.pages)
            _rotated(doc.pages[ref.page - 1], ref.quarterTurns),
        ];
        final path = await _reserve(dir, output.fileName);
        await File(path).writeAsBytes(await doc.encodePdf(), flush: true);
        written.add(path);
      } finally {
        doc.dispose();
      }
      onProgress?.call((i + 1) / plan.outputs.length);
    }
  }

  // --------------------------------------------------------------- compress

  static Future<void> _compress(
    PdfPlan plan,
    String dir,
    List<String> written,
    CancelToken? cancel,
    void Function(double value)? onProgress,
  ) async {
    final doc = await openPdfDocument(plan.sources.first.path);
    try {
      if (plan.compressMode == CompressMode.rasterise) {
        await _rasterise(plan, doc, dir, written, cancel, onProgress);
        return;
      }

      // The lossless path is a plain re-save. pdfium rewrites the file,
      // renumbering objects and dropping whatever nothing refers to, while
      // leaving every page exactly as it found it — including the document's
      // bookmarks, page labels and metadata.
      final path = await _reserve(dir, plan.outputs.first.fileName);
      await File(path).writeAsBytes(await doc.encodePdf(), flush: true);
      written.add(path);
      onProgress?.call(1.0);
    } finally {
      doc.dispose();
    }
  }

  /// Renders every page and rebuilds the document from those images.
  ///
  /// This is the compress that actually shrinks a scanned PDF, and it is lossy
  /// in the way the user is told about: there is no longer any text in the
  /// result, so nothing is selectable or searchable.
  static Future<void> _rasterise(
    PdfPlan plan,
    PdfDocument doc,
    String dir,
    List<String> written,
    CancelToken? cancel,
    void Function(double value)? onProgress,
  ) async {
    final target = pw.Document(title: plan.sources.first.stem);
    final scale = plan.dpi / 72;
    final pageCount = plan.outputs.first.pageCount;

    for (var i = 0; i < pageCount; i++) {
      cancel?.throwIfCancelled();
      final page = doc.pages[i];
      // The page keeps its own size in points, so the document's geometry
      // survives even though its contents become a bitmap.
      final widthPt = page.width;
      final heightPt = page.height;

      final rendered = await page.render(
        fullWidth: widthPt * scale,
        fullHeight: heightPt * scale,
        // Opaque white, or transparent regions would come out black in a JPEG.
        backgroundColor: 0xFFFFFFFF,
      );
      if (rendered == null) {
        throw ConversionException('Page ${i + 1} could not be rendered.');
      }

      final Uint8List jpeg;
      try {
        // pdfrx always hands back BGRA8888.
        final frame = img.Image.fromBytes(
          width: rendered.width,
          height: rendered.height,
          bytes: Uint8List.fromList(rendered.pixels).buffer,
          numChannels: 4,
          order: img.ChannelOrder.bgra,
        );
        jpeg = img.encodeJpg(frame, quality: plan.quality);
      } finally {
        rendered.dispose();
      }

      // dart_pdf embeds JPEG bytes as they are, so the only lossy step is the
      // render itself.
      final image = pw.MemoryImage(jpeg);
      target.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(widthPt, heightPt, marginAll: 0),
          build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
        ),
      );
      onProgress?.call((i + 1) / pageCount * 0.9);
    }

    cancel?.throwIfCancelled();
    final path = await _reserve(dir, plan.outputs.first.fileName);
    await File(path).writeAsBytes(await target.save(), flush: true);
    written.add(path);
    onProgress?.call(1.0);
  }

  // ------------------------------------------------------------------ misc

  /// Turns a plan's relative quarter turns into the absolute rotation pdfium
  /// wants, leaving a page with no rotation change untouched.
  static PdfPage _rotated(PdfPage page, int quarterTurns) {
    final turns = quarterTurns % 4;
    if (turns == 0) return page;
    return page.rotatedTo(PdfPageRotation.values[(page.rotation.index + turns) % 4]);
  }

  static Future<String> _reserve(String dir, String fileName) {
    return ConversionEngine.reserveUniquePath(
      dir,
      p.basenameWithoutExtension(fileName),
      p.extension(fileName).replaceFirst('.', ''),
    );
  }

  static Future<int> _lengthOf(String path) async {
    try {
      return await File(path).length();
    } on FileSystemException {
      return 0;
    }
  }
}

/// Opens a PDF through the bundled pdfium, with the failure a user should see
/// when it cannot be opened.
///
/// Shared by the PDF converter and the toolbox, so a corrupt or password
/// protected file gets the same explanation wherever it is met.
Future<PdfDocument> openPdfDocument(String path) async {
  try {
    // pdfrx 2.x requires an explicit init before the first document is opened;
    // it is idempotent and cheap on later calls.
    await pdfrxFlutterInitialize();
    return await PdfDocument.openFile(path);
  } catch (e) {
    throw ConversionException(
      'This PDF could not be opened. It may be corrupt or password protected.',
      detail: '$e',
    );
  }
}
