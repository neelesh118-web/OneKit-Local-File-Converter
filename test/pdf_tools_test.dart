import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/engine/job.dart';
import 'package:onekit_converter/engine/pdf/page_range.dart';
import 'package:onekit_converter/engine/pdf/pdf_plan.dart';

/// The PDF toolbox works out what it will write before it touches a file, and
/// that planning is pure logic: no pdfium, no file access. This is where the
/// merge order, the split naming, the range clamping and the rotations are
/// pinned down, on the host, for a feature whose execution can only be run on a
/// device.
void main() {
  PdfSource source(String name, int pageCount) =>
      PdfSource(path: '/tmp/$name', pageCount: pageCount);

  /// The page numbers of an output, as "source/page" strings, so the shape of a
  /// plan is readable in a failure message.
  List<String> refs(PdfPlanOutput output) =>
      [for (final ref in output.pages) '${ref.source}/${ref.page}'];

  group('page range parsing', () {
    test('a blank spec means every page', () {
      expect(parsePageRange(null, 3), [1, 2, 3]);
      expect(parsePageRange('   ', 3), [1, 2, 3]);
      expect(parsePageGroups('', 3).single.pages, [1, 2, 3]);
    });

    test('handles singletons, ranges and open-ended ranges', () {
      expect(parsePageRange('2', 5), [2]);
      expect(parsePageRange('2-4', 5), [2, 3, 4]);
      expect(parsePageRange('-2', 5), [1, 2]);
      expect(parsePageRange('4-', 5), [4, 5]);
      expect(parsePageRange('-', 2), [1, 2]);
      expect(parsePageRange('1-3,7,10-', 12), [1, 2, 3, 7, 10, 11, 12]);
    });

    test('sorts and collapses duplicates', () {
      expect(parsePageRange('3,1,3,1-2', 5), [1, 2, 3]);
    });

    test('clamps to the document instead of inventing pages', () {
      expect(parsePageRange('2-99', 3), [2, 3]);
      expect(parsePageRange('99-100', 3), isEmpty);
      expect(parsePageRange('0', 3), isEmpty);
      expect(parsePageRange('abc', 3), isEmpty);
      expect(parsePageGroups('99-100', 3).single.isEmpty, isTrue);
    });

    test('keeps the groups the user wrote, in order', () {
      final groups = parsePageGroups('3, 1-2', 5);
      expect(groups, hasLength(2));
      expect(groups[0].pages, [3]);
      expect(groups[0].label, '3');
      expect(groups[1].pages, [1, 2]);
      expect(groups[1].label, '1-2');
    });

    test('an empty document selects nothing', () {
      expect(parsePageRange(null, 0), isEmpty);
      expect(parsePageGroups('1-3', 0), isEmpty);
    });
  });

  group('merge planning', () {
    test('joins every page of every source, in the order given', () {
      final plan = PdfPlanner.merge([source('a.pdf', 2), source('b.pdf', 3)]);

      expect(plan.tool, PdfTool.merge);
      expect(plan.outputs, hasLength(1));
      expect(plan.outputs.single.fileName, 'a_merged.pdf');
      expect(refs(plan.outputs.single), ['0/1', '0/2', '1/1', '1/2', '1/3']);
      expect(plan.totalOutputPages, 5);
      expect(plan.summary, '1 file, 5 pages');
    });

    test('refuses a single document with a message that says what to do', () {
      expect(
        () => PdfPlanner.merge([source('a.pdf', 2)]),
        throwsA(
          isA<ConversionException>().having(
            (e) => e.message,
            'message',
            contains('at least two'),
          ),
        ),
      );
    });
  });

  group('split planning', () {
    test('one file per range, named after the range', () {
      final plan = PdfPlanner.split(
        source('report.pdf', 6),
        mode: SplitMode.perRange,
        ranges: '1-2, 4, 6-',
      );

      expect(plan.outputs.map((o) => o.fileName).toList(), [
        'report_p1-2.pdf',
        'report_p4.pdf',
        'report_p6.pdf',
      ]);
      expect(refs(plan.outputs.first), ['0/1', '0/2']);
      expect(refs(plan.outputs.last), ['0/6']);
      expect(plan.summary, '3 files, 4 pages');
    });

    test('one file per page when that is what was asked for', () {
      final plan = PdfPlanner.split(source('scan.pdf', 3), mode: SplitMode.perPage);

      expect(plan.outputs.map((o) => o.fileName).toList(), [
        'scan_p1.pdf',
        'scan_p2.pdf',
        'scan_p3.pdf',
      ]);
      expect(plan.outputs.every((o) => o.pageCount == 1), isTrue);
    });

    test('clamps a range that runs past the end', () {
      final plan = PdfPlanner.split(
        source('short.pdf', 3),
        mode: SplitMode.perRange,
        ranges: '1-99',
      );

      expect(plan.outputs.single.fileName, 'short_p1-3.pdf');
      expect(plan.totalOutputPages, 3);
    });

    test('refuses a range that matches nothing', () {
      expect(
        () => PdfPlanner.split(
          source('short.pdf', 3),
          mode: SplitMode.perRange,
          ranges: '40-50',
        ),
        throwsA(
          isA<ConversionException>().having(
            (e) => e.message,
            'message',
            contains('3 pages'),
          ),
        ),
      );
    });

    test('refuses to bury the output folder in files', () {
      expect(
        () => PdfPlanner.split(source('huge.pdf', 400), mode: SplitMode.perPage),
        throwsA(
          isA<ConversionException>().having(
            (e) => e.message,
            'message',
            contains('400 files'),
          ),
        ),
      );
      // Right up to the ceiling is fine.
      expect(
        PdfPlanner.split(source('ok.pdf', PdfPlanner.maxOutputs), mode: SplitMode.perPage)
            .outputs
            .length,
        PdfPlanner.maxOutputs,
      );
    });
  });

  group('rotate planning', () {
    test('keeps every page and rotates only the ones selected', () {
      final plan = PdfPlanner.rotate(
        source('doc.pdf', 3),
        quarterTurns: 1,
        pages: '2',
      );

      expect(plan.outputs.single.fileName, 'doc_rotated.pdf');
      expect(refs(plan.outputs.single), ['0/1', '0/2', '0/3']);
      expect(plan.outputs.single.pages.map((p) => p.quarterTurns).toList(), [0, 1, 0]);
    });

    test('a blank spec rotates the whole document, either way', () {
      final left = PdfPlanner.rotate(source('doc.pdf', 2), quarterTurns: 3);
      expect(left.outputs.single.pages.map((p) => p.quarterTurns).toList(), [3, 3]);

      final half = PdfPlanner.rotate(source('doc.pdf', 2), quarterTurns: 2, pages: '1');
      expect(half.outputs.single.pages.map((p) => p.quarterTurns).toList(), [2, 0]);
    });

    test('refuses a no-op rotation and a page that does not exist', () {
      expect(
        () => PdfPlanner.rotate(source('doc.pdf', 2), quarterTurns: 0),
        throwsA(isA<ConversionException>()),
      );
      expect(
        () => PdfPlanner.rotate(source('doc.pdf', 2), quarterTurns: 1, pages: '9'),
        throwsA(
          isA<ConversionException>().having(
            (e) => e.message,
            'message',
            contains('2 pages'),
          ),
        ),
      );
    });
  });

  group('compress planning', () {
    test('a re-save keeps every page and promises nothing lossy', () {
      final plan = PdfPlanner.compress(source('book.pdf', 4));

      expect(plan.outputs.single.fileName, 'book_compressed.pdf');
      expect(plan.totalOutputPages, 4);
      expect(plan.compressMode, CompressMode.rebuild);
      expect(plan.isLossy, isFalse);
    });

    test('rasterising carries its density and quality, and says it is lossy', () {
      final plan = PdfPlanner.compress(
        source('scan.pdf', 2),
        mode: CompressMode.rasterise,
        dpi: 200,
        quality: 65,
      );

      expect(plan.isLossy, isTrue);
      expect(plan.dpi, 200);
      expect(plan.quality, 65);
      expect(CompressMode.rasterise.isLossy, isTrue);
      expect(CompressMode.rebuild.isLossy, isFalse);
    });

    test('clamps quality and refuses a density pdfium would not render', () {
      expect(
        PdfPlanner.compress(
          source('scan.pdf', 1),
          mode: CompressMode.rasterise,
          quality: 500,
        ).quality,
        100,
      );
      expect(
        () => PdfPlanner.compress(
          source('scan.pdf', 1),
          mode: CompressMode.rasterise,
          dpi: 2000,
        ),
        throwsA(isA<ConversionException>()),
      );
    });
  });

  test('every tool labels itself for the history row', () {
    expect(PdfTool.merge.label, 'PDF merged');
    expect(PdfTool.split.label, 'PDF split');
    expect(PdfTool.rotate.label, 'PDF rotated');
    expect(PdfTool.compress.label, 'PDF compressed');
  });
}
