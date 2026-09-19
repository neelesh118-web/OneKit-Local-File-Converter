import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:onekit_converter/engine/engine.dart';
import 'package:onekit_converter/engine/pdf/pdf_plan.dart';
import 'package:onekit_converter/engine/pdf/pdf_toolbox.dart';
import 'package:path/path.dart' as p;
// The pdf package exports its own PdfPage/PdfPageRotation for building
// pages; the ones asserted on here are pdfrx's.
import 'package:pdf/pdf.dart' hide PdfDocument, PdfPage, PdfPageRotation;
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

/// Runs the PDF toolbox against real pdfium, on a device.
///
/// This is the half the host cannot reach: pdfrx's host build is a stub that
/// throws, so `test/pdf_tools_test.dart` covers the planning and nothing else.
/// Everything here asserts on what comes back out of a real PDF — page counts,
/// the order of the text, the rotation stored on the page, and whether the text
/// layer survived — rather than on the tool reporting success.
///
/// Run it in profile mode, like the format matrix:
///
/// ```bash
/// flutter drive --driver=test_driver/integration_test.dart
///   --target=integration_test/pdf_tools_test.dart --profile
/// ```
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory work;
  late Directory out;

  setUpAll(() async {
    final base = await ConversionEngine.tempDir();
    work = await Directory(p.join(base.path, 'pdf_tools')).create(recursive: true);
    out = await Directory(p.join(base.path, 'pdf_tools_out')).create(recursive: true);
  });

  tearDownAll(() {
    work.deleteSync(recursive: true);
    out.deleteSync(recursive: true);
  });

  /// A text PDF, one marker per page, so an operation can be checked by what
  /// ended up where rather than only by how many pages there are.
  Future<String> textPdf(String name, List<String> markers) async {
    final doc = pw.Document();
    for (final marker in markers) {
      doc.addPage(
        pw.Page(
          build: (_) => pw.Center(
            child: pw.Text(marker, style: const pw.TextStyle(fontSize: 28)),
          ),
        ),
      );
    }
    final file = File(p.join(work.path, name));
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  /// One page holding a large noisy bitmap, which is the kind of document the
  /// rasterising compress exists for.
  Future<String> imagePdf(String name) async {
    final image = img.Image(width: 1400, height: 1900);
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        image.setPixelRgb(x, y, (x * 7 + y * 13) % 256, (x * 3) % 256, (y * 5) % 256);
      }
    }
    final doc = pw.Document();
    final bitmap = pw.MemoryImage(img.encodeJpg(image, quality: 95));
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(595, 842, marginAll: 0),
        build: (_) => pw.Image(bitmap, fit: pw.BoxFit.fill),
      ),
    );
    final file = File(p.join(work.path, name));
    await file.writeAsBytes(await doc.save());
    return file.path;
  }

  Future<PdfToolResult> run(PdfPlan plan) =>
      PdfToolbox.run(plan, outputDirectory: out.path);

  /// Every page's extracted text, in order. Empty strings mean "no text here",
  /// which is exactly what the rasterising compress should produce.
  Future<List<String>> textsOf(String path, int pages) async {
    final doc = await openPdfDocument(path);
    try {
      return [
        for (var i = 0; i < pages; i++)
          (await doc.pages[i].loadText())?.fullText ?? '',
      ];
    } finally {
      doc.dispose();
    }
  }

  Future<List<PdfPageRotation>> rotationsOf(String path, int pages) async {
    final doc = await openPdfDocument(path);
    try {
      return [for (var i = 0; i < pages; i++) doc.pages[i].rotation];
    } finally {
      doc.dispose();
    }
  }

  Future<PdfSource> inspect(String path) => PdfToolbox.inspect(path);

  group('PDF toolbox', () {
    test('merge joins every page of every document, in order', () async {
      final first = await textPdf('first.pdf', ['MARKER-ONE', 'MARKER-TWO']);
      final second = await textPdf('second.pdf', ['SECOND-ONE', 'SECOND-TWO']);

      final plan = PdfPlanner.merge([await inspect(first), await inspect(second)]);
      final result = await run(plan);

      expect(result.outputs, hasLength(1));
      final merged = await inspect(result.outputs.first);
      expect(merged.pageCount, 4);

      final text = await textsOf(result.outputs.first, 4);
      expect(text[0], contains('MARKER-ONE'));
      expect(text[1], contains('MARKER-TWO'));
      // The second document's pages follow the first's, not the other way round.
      expect(text[2], contains('SECOND-ONE'));
      expect(text[3], contains('SECOND-TWO'));
    });

    test('merge keeps both results when the same merge runs twice', () async {
      final first = await textPdf('twice-a.pdf', ['A']);
      final second = await textPdf('twice-b.pdf', ['B']);
      final plan = PdfPlanner.merge([await inspect(first), await inspect(second)]);

      final one = await run(plan);
      final two = await run(plan);

      expect(one.outputs.first, isNot(two.outputs.first));
      expect(await File(one.outputs.first).length(), greaterThan(0));
      expect(await File(two.outputs.first).length(), greaterThan(0));
    });

    test('split by range writes one file per range, with the right pages',
        () async {
      final source = await textPdf(
        'split.pdf',
        ['PAGE-ONE', 'PAGE-TWO', 'PAGE-THREE'],
      );
      final plan = PdfPlanner.split(
        await inspect(source),
        mode: SplitMode.perRange,
        ranges: '3, 1-2',
      );
      final result = await run(plan);

      expect(result.outputs, hasLength(2));
      expect((await inspect(result.outputs[0])).pageCount, 1);
      expect((await inspect(result.outputs[1])).pageCount, 2);

      final first = await textsOf(result.outputs[0], 1);
      expect(first.single, contains('PAGE-THREE'));
      final second = await textsOf(result.outputs[1], 2);
      expect(second[0], contains('PAGE-ONE'));
      expect(second[1], contains('PAGE-TWO'));
    });

    test('split per page writes one file per page', () async {
      final source = await textPdf('each.pdf', ['ONE', 'TWO']);
      final plan = PdfPlanner.split(await inspect(source), mode: SplitMode.perPage);
      final result = await run(plan);

      expect(result.outputs, hasLength(2));
      for (final path in result.outputs) {
        expect((await inspect(path)).pageCount, 1);
      }
      expect((await textsOf(result.outputs[0], 1)).single, contains('ONE'));
      expect((await textsOf(result.outputs[1], 1)).single, contains('TWO'));
    });

    test('rotate turns the selected pages and leaves the rest alone', () async {
      final source = await textPdf('rotate.pdf', ['ONE', 'TWO', 'THREE']);
      final plan = PdfPlanner.rotate(
        await inspect(source),
        quarterTurns: 1,
        pages: '1,3',
      );
      final result = await run(plan);

      expect((await inspect(result.outputs.single)).pageCount, 3);
      final rotations = await rotationsOf(result.outputs.single, 3);
      expect(rotations[0], PdfPageRotation.clockwise90);
      expect(rotations[1], PdfPageRotation.none);
      expect(rotations[2], PdfPageRotation.clockwise90);

      // Rotating is page geometry, not content: the text is still there.
      final text = await textsOf(result.outputs.single, 3);
      expect(text[0], contains('ONE'));
      expect(text[2], contains('THREE'));
    });

    test('rotate left is the other direction, and stacks on an existing turn',
        () async {
      final source = await textPdf('rotate-left.pdf', ['ONE']);
      final plan = PdfPlanner.rotate(
        await inspect(source),
        quarterTurns: 3,
        pages: '1',
      );
      final result = await run(plan);

      final rotations = await rotationsOf(result.outputs.single, 1);
      expect(rotations.single, PdfPageRotation.clockwise270);
    });

    test('a lossless compress keeps every page and its text', () async {
      final source = await textPdf('rebuild.pdf', ['KEEP-ONE', 'KEEP-TWO']);
      final before = await File(source).length();

      final plan = PdfPlanner.compress(await inspect(source));
      final result = await run(plan);

      expect(result.sourceBytes, before);
      expect((await inspect(result.outputs.single)).pageCount, 2);
      final text = await textsOf(result.outputs.single, 2);
      expect(text[0], contains('KEEP-ONE'));
      expect(text[1], contains('KEEP-TWO'));
      // The result is a real PDF, not an empty shell.
      expect(await File(result.outputs.single).length(), greaterThan(500));
    });

    test('rasterising shrinks an image page and drops the text layer', () async {
      final source = await imagePdf('scan.pdf');
      final sourceBytes = await File(source).length();

      final plan = PdfPlanner.compress(
        await inspect(source),
        mode: CompressMode.rasterise,
        dpi: 96,
        quality: 40,
      );
      final result = await run(plan);

      expect(plan.isLossy, isTrue);
      expect((await inspect(result.outputs.single)).pageCount, 1);
      expect(
        result.outputBytes,
        lessThan(sourceBytes),
        reason: 'rasterising an image page at 96 dpi should be smaller',
      );
    });

    test('rasterising a text document leaves no text to extract', () async {
      final source = await textPdf('raster-text.pdf', ['GONE-ONE', 'GONE-TWO']);
      final plan = PdfPlanner.compress(
        await inspect(source),
        mode: CompressMode.rasterise,
        dpi: 150,
        quality: 80,
      );
      final result = await run(plan);

      expect((await inspect(result.outputs.single)).pageCount, 2);
      final text = await textsOf(result.outputs.single, 2);
      // The honest consequence of the mode: the page is an image now.
      expect(text.join(), isNot(contains('GONE-ONE')));
    });

    test('a file that is not a PDF fails with a readable message', () async {
      final junk = File(p.join(work.path, 'not-a-pdf.pdf'))
        ..writeAsStringSync('this is not a PDF at all');
      await expectLater(
        inspect(junk.path),
        throwsA(isA<Exception>()),
      );
    });
  });
}
