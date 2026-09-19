import 'dart:io';

import 'package:path/path.dart' as p;

import '../../engine/engine.dart';

/// Writes a report into the app's scratch space so it can be sent as a real
/// attachment rather than as a wall of text pasted into a message.
///
/// It lives under the same `lfc_work` directory as everything else the app
/// creates, so Settings' "Clear working files" is also what deletes reports —
/// nobody has to be told that there is a second place to clean up. Returns null
/// when there is nowhere to write, which the caller reports honestly instead of
/// pretending a report was sent.
Future<File?> writeReport(String text, {DateTime? at, int keep = 5}) async {
  try {
    final root = await ConversionEngine.tempDir();
    final dir = Directory(p.join(root.path, 'reports'));
    await dir.create(recursive: true);

    final when = (at ?? DateTime.now()).toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    final name = 'onekit-report-${when.year}${two(when.month)}${two(when.day)}'
        '-${two(when.hour)}${two(when.minute)}${two(when.second)}.txt';
    final file = File(p.join(dir.path, name));
    await file.writeAsString(text, flush: true);

    await _prune(dir, keep: keep);
    return file;
  } catch (_) {
    return null;
  }
}

/// Keeps the report folder from becoming a pile. Reports are only ever read
/// once, on the way into a message, so old ones have no value to anyone.
Future<void> _prune(Directory dir, {required int keep}) async {
  final files = await dir
      .list()
      .where((e) => e is File && p.extension(e.path) == '.txt')
      .cast<File>()
      .toList();
  if (files.length <= keep) return;
  files.sort((a, b) => a.path.compareTo(b.path));
  for (final file in files.take(files.length - keep)) {
    try {
      await file.delete();
    } catch (_) {
      // A report that cannot be tidied is not worth failing the write over.
    }
  }
}
