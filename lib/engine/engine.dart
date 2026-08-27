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
import 'converters/image_converter.dart';
import 'converters/pdf_converter.dart';
import 'converters/subtitle_converter.dart';
import 'format.dart';
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
    SubtitleConverter(),
    DocumentConverter(),
    DataConverter(),
    ArchiveConverter(),
    DartImageConverter(),
    FfmpegConverter(),
  ];

  FileConverter? resolve(FileFormat from, FileFormat to) {
    for (final c in converters) {
      if (c.supports(from, to)) return c;
    }
    return null;
  }

  bool canConvert(FileFormat from, FileFormat to) => resolve(from, to) != null;

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
    job.status = JobStatus.running;
    job.progress = 0;
    job.error = null;
    onUpdate?.call();

    try {
      final from = job.source;
      if (from == null) {
        throw ConversionException(
          'OneKit does not recognise the "${p.extension(job.sourcePath)}" file type.',
        );
      }
      if (!await File(job.sourcePath).exists()) {
        throw ConversionException('The source file is no longer available.');
      }

      final converter = resolve(from, job.target);
      if (converter == null) {
        throw ConversionException('${from.upper} to ${job.target.upper} is not supported.');
      }

      final dir = outputDirectory ?? (await outputDir()).path;
      await Directory(dir).create(recursive: true);
      final outPath = await _uniquePath(dir, job.baseName, job.target.ext);

      final extras = <String>[];
      await converter.convert(ConvertRequest(
        inputPath: job.sourcePath,
        outputPath: outPath,
        from: from,
        to: job.target,
        options: job.options,
        cancel: cancel,
        extraOutputs: extras,
        onProgress: (value, {bool indeterminate = false}) {
          job.indeterminate = indeterminate;
          // Progress must never go backwards; ffmpeg occasionally reports a
          // stale statistic after a seek.
          final clamped = value.clamp(0.0, 1.0);
          if (clamped >= job.progress || indeterminate) job.progress = clamped;
          onUpdate?.call();
        },
      ));

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
      job.error = cancel.isCancelled ? 'Cancelled' : 'Something went wrong converting this file.';
      job.errorDetail = '$e';
    } finally {
      job.elapsed = DateTime.now().difference(started);
      onUpdate?.call();
    }
  }

  /// Where finished files land by default. Kept inside app storage so no
  /// runtime permission is needed; Files can export anywhere from there.
  static Future<Directory> outputDir() async {
    final base = await getApplicationDocumentsDirectory();
    return Directory(p.join(base.path, 'OneKit'));
  }

  static Future<Directory> tempDir() async {
    final base = await getTemporaryDirectory();
    return Directory(p.join(base.path, 'onekit_work'));
  }

  /// Never overwrites: appends (1), (2), ... the way a desktop file manager does.
  static Future<String> _uniquePath(String dir, String base, String ext) async {
    final safe = base.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_').trim();
    final stem = safe.isEmpty ? 'converted' : safe;
    var candidate = p.join(dir, '$stem.$ext');
    var n = 1;
    while (await File(candidate).exists()) {
      candidate = p.join(dir, '$stem ($n).$ext');
      n++;
    }
    return candidate;
  }
}
