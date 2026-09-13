import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'converters/archive_converter.dart';
import 'converters/converter.dart';
import 'converters/data_converter.dart';
import 'converters/document_converter.dart';
import 'converters/ebook_converter.dart';
import 'converters/ffmpeg_converter.dart';
import 'converters/font_converter.dart';
import 'converters/pdf_converter.dart';
import 'converters/subtitle_converter.dart';
import 'format.dart' show ConversionPair, Family, FileFormat;
import 'job.dart';

/// Routes a job to the converter that handles it and runs it.
///
/// Order matters: the first converter that claims a pair wins, so the
/// specialised pure-Dart backends sit ahead of the FFmpeg catch-all.
class ConversionEngine {
  ConversionEngine._();
  static final ConversionEngine instance = ConversionEngine._();

  static const List<FileConverter> converters = [
    PdfConverter(),
    EbookConverter(),
    FontConverter(),
    SubtitleConverter(),
    DocumentConverter(),
    DataConverter(),
    ArchiveConverter(),
    // Images go to FFmpeg. A pure-Dart path was tried first on the assumption
    // that avoiding the native round trip would be faster; measured on device
    // it was 9x slower on a 12 MP photo (23.7s vs 2.6s), so it was removed.
    FfmpegConverter(),
  ];

  FileConverter? resolve(FileFormat from, FileFormat to) {
    for (final c in converters) {
      if (c.supports(from, to)) return c;
    }
    return null;
  }

  bool canConvert(FileFormat from, FileFormat to) => resolve(from, to) != null;

  /// Maximum size for Dart-based converters (PDF, documents, archives).
  /// Above this, only FFmpeg-based conversions (audio/video/image) are
  /// allowed because the Dart decoders load entire files into memory.
  static const int _maxDartConverterBytes = 500 * 1024 * 1024; // 500 MB

  /// Formats handled by FFmpeg which streams data and can handle large files.
  static const _ffmpegFamilies = {Family.audio, Family.video, Family.image};

  /// Runs [job] to completion, mutating its status, progress and output fields.
  ///
  /// Returns normally on success and leaves the reason on [job.error] on
  /// failure; it does not rethrow, so a batch never dies on one bad file.
  Future<void> run(
    ConversionJob job, {
    required CancelToken cancel,
    void Function()? onUpdate,
    String? outputDirectory,
  }) async {
    final started = DateTime.now();
    String? reservedOutputPath;
    job.status = JobStatus.running;
    job.progress = 0;
    job.error = null;
    onUpdate?.call();

    try {
      final from = job.source;
      if (from == null) {
        throw ConversionException(
          'This app does not recognise the "${p.extension(job.sourcePath)}" file type.',
        );
      }
      if (!await File(job.sourcePath).exists()) {
        throw ConversionException('The source file is no longer available.');
      }

      // Large-file gate: Dart-based converters load entire files into memory,
      // so files above the limit are restricted to FFmpeg-based conversions
      // which stream data through pipes.
      final sourceSize = await File(job.sourcePath).length();
      if (sourceSize > _maxDartConverterBytes) {
        final converter = resolve(from, job.target);
        if (converter != null && !_ffmpegFamilies.contains(from.family)) {
          throw ConversionException(
            '${from.upper} files over ${humanBytes(_maxDartConverterBytes)} are too large '
            'for this converter. Try an audio, video, or image conversion instead.',
          );
        }
      }

      final converter = resolve(from, job.target);
      if (converter == null) {
        throw ConversionException(
          '${from.upper} to ${job.target.upper} is not supported.',
        );
      }

      final dir = outputDirectory ?? (await outputDir()).path;
      await Directory(dir).create(recursive: true);
      // Reserve the name atomically. A batch may have several workers asking
      // for the same basename at the same time; an exists-then-write check is
      // racy and can make FFmpeg overwrite another result.
      final outPath = await _reserveUniquePath(
        dir,
        job.baseName,
        job.target.ext,
      );
      reservedOutputPath = outPath;

      final extras = <String>[];
      // Converters report as fast as their backend does — ffmpeg's statistics
      // callback can fire far more often than the screen refreshes. Coalesce
      // to ~20 Hz so the UI is never asked to do more work than it can show.
      var lastEmit = DateTime.fromMillisecondsSinceEpoch(0);
      const minGap = Duration(milliseconds: 50);

      await converter.convert(
        ConvertRequest(
          inputPath: job.sourcePath,
          outputPath: outPath,
          from: from,
          to: job.target,
          options: job.options,
          cancel: cancel,
          extraOutputs: extras,
          onProgress: (value, {bool indeterminate = false}) {
            // Progress must never go backwards; ffmpeg occasionally reports a
            // stale statistic after a seek.
            final clamped = value.clamp(0.0, 1.0);
            if (clamped < job.progress && !indeterminate) return;

            final now = DateTime.now();
            final isEdge = clamped >= 1.0 || job.indeterminate != indeterminate;
            if (!isEdge && now.difference(lastEmit) < minGap) return;
            lastEmit = now;

            job.indeterminate = indeterminate;
            job.progress = clamped;
            onUpdate?.call();
          },
        ),
      );

      cancel.throwIfCancelled();

      final outFile = File(outPath);
      if (!await outFile.exists() || await outFile.length() == 0) {
        throw ConversionException(
          'The conversion finished but produced an empty file. This ${from.upper} may use an unsupported variant.',
        );
      }

      job.outputPath = outPath;
      job.outputBytes = await outFile.length();
      job.extraOutputs = extras;
      job.progress = 1.0;
      job.indeterminate = false;
      job.status = JobStatus.done;
    } on ConversionException catch (e) {
      job.status = cancel.isCancelled ? JobStatus.cancelled : JobStatus.failed;
      job.error = cancel.isCancelled ? 'Cancelled' : e.message;
      job.errorDetail = e.detail;
    } catch (e) {
      job.status = cancel.isCancelled ? JobStatus.cancelled : JobStatus.failed;
      job.error = cancel.isCancelled
          ? 'Cancelled'
          : 'Something went wrong converting this file.';
      job.errorDetail = '$e';
    } finally {
      // A cancelled or failed converter may leave a partial output behind.
      // Never expose that file as a valid result, and remove any sidecars a
      // converter created before it failed.
      if (job.status != JobStatus.done) {
        await _deleteIfPresent(reservedOutputPath);
        await _deleteIfPresent(job.outputPath);
        for (final extra in job.extraOutputs) {
          await _deleteIfPresent(extra);
        }
      }
      job.elapsed = DateTime.now().difference(started);
      onUpdate?.call();
    }
  }

  /// Where finished files land by default. Kept inside app storage so no
  /// runtime permission is needed; Files can export anywhere from there.
  static Future<Directory> outputDir() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'LocalFileConverter'));
  }

  static Future<Directory> tempDir() async {
    final base = await getTemporaryDirectory();
    return Directory(p.join(base.path, 'lfc_work'));
  }

  /// Atomically reserves a path so concurrent batch workers cannot collide.
  static Future<String> _reserveUniquePath(
    String dir,
    String base,
    String ext,
  ) async {
    final safe = base.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    final stem = safe.isEmpty ? 'converted' : safe;
    var candidate = p.join(dir, '$stem.$ext');
    var n = 1;
    while (true) {
      try {
        await File(candidate).create(exclusive: true);
        return candidate;
      } on FileSystemException {
        // Only advance to the next suffix when another worker really won the
        // race. Permission, storage, and other I/O failures must not become an
        // infinite filename loop.
        if (!await File(candidate).exists()) rethrow;
        candidate = p.join(dir, '$stem ($n).$ext');
        n++;
      }
    }
  }

  static Future<void> _deleteIfPresent(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } on FileSystemException {
      // Cleanup is best effort; the original conversion error is more useful
      // to the user than a secondary deletion failure.
    }
  }
}
