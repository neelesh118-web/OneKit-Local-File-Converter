/// Page selection for PDF features, parsed in exactly one place.
///
/// The convert screen's "Pages" option, the split tool and the rotate tool all
/// accept the same syntax — "1-3,7,10-" — and it would be a quiet bug for those
/// three to disagree about what it means. So there is one parser, and the PDF
/// toolbox and the PDF converter both go through it.
library;

/// A run of pages as the user wrote it: one comma-separated part of the spec.
///
/// Groups keep their own order and their own identity, which is what lets the
/// split tool turn "1-3,4-6" into two files instead of one. Pages are 1-based
/// and already clamped to the document, so an out-of-range part produces an
/// empty group rather than a nonsense one — the caller can then say which part
/// matched nothing.
class PageGroup {
  const PageGroup(this.pages);

  final List<int> pages;

  bool get isEmpty => pages.isEmpty;
  bool get isNotEmpty => pages.isNotEmpty;
  int get first => pages.first;
  int get last => pages.last;
  int get length => pages.length;

  /// "1-3" for a run, "7" for a single page. Used in output file names.
  String get label => first == last ? '$first' : '$first-$last';
}

/// Parses [spec] against a document of [pageCount] pages.
///
/// An empty or blank spec means every page. Each comma-separated part is "N",
/// "N-M", "N-" or "-M"; anything else is ignored rather than guessed at, and a
/// part that lies entirely outside the document yields an empty group.
List<PageGroup> parsePageGroups(String? spec, int pageCount) {
  if (pageCount <= 0) return const [];
  final text = spec?.trim() ?? '';
  if (text.isEmpty) {
    return [PageGroup([for (var i = 1; i <= pageCount; i++) i])];
  }

  final groups = <PageGroup>[];
  for (final part in text.split(',')) {
    final s = part.trim();
    if (s.isEmpty) continue;

    final range = RegExp(r'^(\d*)\s*-\s*(\d*)$').firstMatch(s);
    if (range != null) {
      // A missing side means "from the start" or "to the end", so "-5" and
      // "5-" both work.
      final start = int.tryParse(range.group(1)!) ?? 1;
      final end = int.tryParse(range.group(2)!) ?? pageCount;
      final pages = <int>[];
      for (var i = start; i <= end && i <= pageCount; i++) {
        if (i >= 1) pages.add(i);
      }
      groups.add(PageGroup(pages));
      continue;
    }

    final n = int.tryParse(s);
    if (n != null && n >= 1 && n <= pageCount) groups.add(PageGroup([n]));
  }
  return groups;
}

/// The flat selection: every page named by [spec], ascending, duplicates
/// collapsed. This is what a single-output operation wants, and it is the
/// behaviour the convert screen's page range has always had.
List<int> parsePageRange(String? spec, int pageCount) {
  final out = <int>{};
  for (final group in parsePageGroups(spec, pageCount)) {
    out.addAll(group.pages);
  }
  return out.toList()..sort();
}
