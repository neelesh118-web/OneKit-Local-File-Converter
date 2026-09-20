import 'package:path/path.dart' as p;

import '../job.dart';
import 'page_range.dart';

/// What a PDF toolbox run does to its inputs.
enum PdfTool {
  merge,
  split,
  rotate,
  compress;

  /// Shown on the History row and in the result card.
  String get label => switch (this) {
        PdfTool.merge => 'PDF merged',
        PdfTool.split => 'PDF split',
        PdfTool.rotate => 'PDF rotated',
        PdfTool.compress => 'PDF compressed',
      };

  /// What the tool is doing while it runs, for the progress notification. The
  /// label above is past tense because it describes a finished job; this one is
  /// on screen while there is still something to wait for.
  String get working => switch (this) {
        PdfTool.merge => 'Merging PDFs',
        PdfTool.split => 'Splitting a PDF',
        PdfTool.rotate => 'Rotating PDF pages',
        PdfTool.compress => 'Compressing a PDF',
      };
}

/// How a split divides a document.
enum SplitMode {
  /// One output file per comma-separated part of the range spec.
  perRange,

  /// One output file per page.
  perPage,
}

/// How a compress run saves the document.
enum CompressMode {
  /// A plain re-save: pdfium rewrites the file, renumbering objects and
  /// dropping whatever nothing references. Lossless — text stays text — and it
  /// is what actually helps a PDF that has been saved and amended repeatedly.
  rebuild,

  /// Render every page and rebuild the document from those images. The big
  /// win for scans, and a real loss: the text stops being selectable.
  rasterise;

  bool get isLossy => this == CompressMode.rasterise;
}

/// An input document and its page count. The count comes from the engine
/// (pdfium), never from this layer, which is what keeps planning testable
/// without a device.
class PdfSource {
  const PdfSource({required this.path, required this.pageCount});

  final String path;
  final int pageCount;

  String get stem => p.basenameWithoutExtension(path);
  String get name => p.basename(path);
}

/// One page of the output, pointing at the input it came from.
class PdfPageRef {
  const PdfPageRef({
    required this.source,
    required this.page,
    this.quarterTurns = 0,
  });

  /// Index into [PdfPlan.sources].
  final int source;

  /// 1-based page number within that source.
  final int page;

  /// Clockwise quarter turns to apply to this page, 0-3.
  final int quarterTurns;
}

/// One PDF the run will write.
class PdfPlanOutput {
  const PdfPlanOutput({required this.fileName, required this.pages});

  /// File name including '.pdf'. The engine still sanitises it and reserves a
  /// unique path, so a name that collides becomes "name (1).pdf".
  final String fileName;
  final List<PdfPageRef> pages;

  int get pageCount => pages.length;
}

/// Everything a run needs, worked out before any file is touched.
///
/// Planning is separated from execution on purpose: deciding which pages go
/// where is pure logic that can be tested on the host, and the executor that
/// follows it is a thin loop over pdfium calls that cannot.
class PdfPlan {
  const PdfPlan({
    required this.tool,
    required this.sources,
    required this.outputs,
    this.compressMode = CompressMode.rebuild,
    this.dpi = 150,
    this.quality = 80,
  });

  final PdfTool tool;
  final List<PdfSource> sources;
  final List<PdfPlanOutput> outputs;
  final CompressMode compressMode;
  final int dpi;
  final int quality;

  int get totalOutputPages =>
      outputs.fold(0, (sum, output) => sum + output.pageCount);

  /// True when the result cannot contain selectable text.
  bool get isLossy => tool == PdfTool.compress && compressMode.isLossy;

  /// One line for the result card: "3 files, 12 pages" / "1 file, 4 pages".
  String get summary =>
      '${outputs.length} file${outputs.length == 1 ? '' : 's'}, '
      '$totalOutputPages page${totalOutputPages == 1 ? '' : 's'}';
}

/// Works out what a toolbox run will produce, and refuses the requests that
/// cannot be honoured with a message written for the user.
///
/// Nothing here opens a file. The page counts arrive as [PdfSource]s, so every
/// rule below — range clamping, output naming, ordering — is host-testable.
class PdfPlanner {
  PdfPlanner._();


  /// Several documents into one, in the order they were given.
  static PdfPlan merge(List<PdfSource> sources) {
    if (sources.length < 2) {
      throw ConversionException(
        'Merging needs at least two PDFs. Add another file, or use Split, Rotate '
        'or Compress for a single one.',
      );
    }
    final pages = <PdfPageRef>[];
    for (var i = 0; i < sources.length; i++) {
      for (var page = 1; page <= sources[i].pageCount; page++) {
        pages.add(PdfPageRef(source: i, page: page));
      }
    }
    return PdfPlan(
      tool: PdfTool.merge,
      sources: sources,
      outputs: [
        PdfPlanOutput(
          fileName: '${sources.first.stem}_merged.pdf',
          pages: pages,
        ),
      ],
    );
  }

  /// One document into several: either one file per part of [ranges], or one
  /// file per page.
  static PdfPlan split(
    PdfSource source, {
    required SplitMode mode,
    String? ranges,
  }) {
    final outputs = <PdfPlanOutput>[];

    if (mode == SplitMode.perPage) {
      for (var page = 1; page <= source.pageCount; page++) {
        outputs.add(
          PdfPlanOutput(
            fileName: '${source.stem}_p$page.pdf',
            pages: [PdfPageRef(source: 0, page: page)],
          ),
        );
      }
    } else {
      final groups = parsePageGroups(ranges, source.pageCount)
          .where((group) => group.isNotEmpty)
          .toList();
      if (groups.isEmpty) {
        throw ConversionException(
          'None of those pages exist in this PDF. It has '
          '${source.pageCount} page${source.pageCount == 1 ? '' : 's'}.',
        );
      }
      for (final group in groups) {
        outputs.add(
          PdfPlanOutput(
            fileName: '${source.stem}_p${group.label}.pdf',
            pages: [
              for (final page in group.pages) PdfPageRef(source: 0, page: page),
            ],
          ),
        );
      }
    }

    if (outputs.length > maxOutputs) {
      throw ConversionException(
        'That would write ${outputs.length} files. Split into page ranges '
        'instead, or fewer pages at a time.',
      );
    }
    return PdfPlan(tool: PdfTool.split, sources: [source], outputs: outputs);
  }

  /// A ceiling on how many files one run may write. Splitting a 900-page scan
  /// page by page would bury the output folder — and the Files tab — under
  /// files nobody asked to see individually.
  static const maxOutputs = 150;

  /// Rotates the selected pages of one document, leaving the rest alone.
  ///
  /// [quarterTurns] is relative and clockwise: 1 is 90° right, 3 is 90° left.
  /// A blank [pages] spec rotates every page.
  static PdfPlan rotate(
    PdfSource source, {
    required int quarterTurns,
    String? pages,
  }) {
    final turns = quarterTurns % 4;
    if (turns == 0) {
      throw ConversionException('Pick a rotation first.');
    }
    final selected = parsePageRange(pages, source.pageCount).toSet();
    if (selected.isEmpty) {
      throw ConversionException(
        'None of those pages exist in this PDF. It has '
        '${source.pageCount} page${source.pageCount == 1 ? '' : 's'}.',
      );
    }

    return PdfPlan(
      tool: PdfTool.rotate,
      sources: [source],
      outputs: [
        PdfPlanOutput(
          fileName: '${source.stem}_rotated.pdf',
          pages: [
            for (var page = 1; page <= source.pageCount; page++)
              PdfPageRef(
                source: 0,
                page: page,
                quarterTurns: selected.contains(page) ? turns : 0,
              ),
          ],
        ),
      ],
    );
  }

  /// One document, saved smaller — losslessly, or as page images.
  static PdfPlan compress(
    PdfSource source, {
    CompressMode mode = CompressMode.rebuild,
    int dpi = 150,
    int quality = 80,
  }) {
    if (mode == CompressMode.rasterise && (dpi < 36 || dpi > 600)) {
      throw ConversionException('Choose a render density between 36 and 600 dpi.');
    }
    return PdfPlan(
      tool: PdfTool.compress,
      sources: [source],
      outputs: [
        PdfPlanOutput(
          fileName: '${source.stem}_compressed.pdf',
          pages: [
            for (var page = 1; page <= source.pageCount; page++)
              PdfPageRef(source: 0, page: page),
          ],
        ),
      ],
      compressMode: mode,
      dpi: dpi,
      quality: quality.clamp(1, 100),
    );
  }
}
