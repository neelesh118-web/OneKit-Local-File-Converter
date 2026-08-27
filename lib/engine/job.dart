import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'format.dart';
import 'registry.dart';

enum JobStatus { queued, running, done, failed, cancelled }

/// Options a user can tune before converting. Only the fields relevant to the
/// chosen target are surfaced in the UI.
class ConvertOptions {
  const ConvertOptions({
    this.quality = 90,
    this.width,
    this.height,
    this.audioBitrateKbps,
    this.sampleRate,
    this.videoCrf,
    this.fps,
    this.stripMetadata = false,
    this.pdfPageRange,
    this.pdfDpi = 150,
    this.maxEdge,
  });

  /// Encoder quality 1-100 for lossy image targets.
  final int quality;

  /// Optional resize. Null keeps the source dimension; setting one and leaving
  /// the other null preserves the aspect ratio.
  final int? width;
  final int? height;

  final int? audioBitrateKbps;
  final int? sampleRate;

  /// x264/x265 constant rate factor. Lower is better quality, larger files.
  final int? videoCrf;
  final int? fps;

  final bool stripMetadata;

  /// 1-based inclusive page range for PDF sources, e.g. "1-5". Null = all.
  final String? pdfPageRange;
  final int pdfDpi;

  /// A ceiling on the longest edge, never an upscale. Used internally where an
  /// unbounded bitmap would be a memory problem — embedding a photo in a PDF,
  /// or rendering a preview thumbnail.
  final int? maxEdge;

  ConvertOptions copyWith({
    int? quality,
    int? width,
    int? height,
    int? audioBitrateKbps,
    int? sampleRate,
    int? videoCrf,
    int? fps,
    bool? stripMetadata,
    String? pdfPageRange,
    int? pdfDpi,
    int? maxEdge,
  }) {
    return ConvertOptions(
      quality: quality ?? this.quality,
      width: width ?? this.width,
      height: height ?? this.height,
      audioBitrateKbps: audioBitrateKbps ?? this.audioBitrateKbps,
      sampleRate: sampleRate ?? this.sampleRate,
      videoCrf: videoCrf ?? this.videoCrf,
      fps: fps ?? this.fps,
      stripMetadata: stripMetadata ?? this.stripMetadata,
      pdfPageRange: pdfPageRange ?? this.pdfPageRange,
      pdfDpi: pdfDpi ?? this.pdfDpi,
      maxEdge: maxEdge ?? this.maxEdge,
    );
  }
}

/// One file being converted into one target format.
class ConversionJob {
  ConversionJob({
    required this.id,
    required this.sourcePath,
    required this.target,
    this.options = const ConvertOptions(),
    FileFormat? source,
    this.displayName,
  }) : source = source ?? FormatRegistry.byExt(p.extension(sourcePath));

  final String id;
  final String sourcePath;
  final FileFormat? source;
  final FileFormat target;
  final ConvertOptions options;

  /// Overrides the on-disk name in the UI (SAF picks can have opaque names).
  final String? displayName;

  JobStatus status = JobStatus.queued;

  /// 0.0 - 1.0, reported by the engine. Never synthesised from a timer.
  ///
  /// Exposed as a [ValueNotifier] so the progress dial can rebuild on its own
  /// without the surrounding page rebuilding with it — a conversion emits
  /// these many times a second.
  final ValueNotifier<double> progressNotifier = ValueNotifier<double>(0);

  double get progress => progressNotifier.value;
  set progress(double v) => progressNotifier.value = v;

  /// Set while the engine genuinely cannot report a percentage.
  bool indeterminate = false;

  /// Releases the progress listenable. Safe to call more than once.
  void dispose() => progressNotifier.dispose();

  String? outputPath;

  /// Additional files produced alongside [outputPath] — a multi-page PDF
  /// rendered to images is the main case.
  List<String> extraOutputs = const [];

  String? error;

  /// The underlying engine's reason (an FFmpeg log tail, a decoder message).
  /// Shown behind a disclosure on the failure card, never as the headline.
  String? errorDetail;

  Duration elapsed = Duration.zero;
  int outputBytes = 0;

  String get name => displayName ?? p.basename(sourcePath);
  String get baseName => p.basenameWithoutExtension(name);

  int get sourceBytes {
    try {
      return File(sourcePath).lengthSync();
    } on FileSystemException {
      return 0;
    }
  }

  ConversionPair? get pair => source == null ? null : ConversionPair(source!, target);

  bool get isTerminal =>
      status == JobStatus.done || status == JobStatus.failed || status == JobStatus.cancelled;

  /// Negative means the output got smaller, which is the common case.
  double? get sizeDeltaRatio {
    final src = sourceBytes;
    if (src <= 0 || outputBytes <= 0) return null;
    return (outputBytes - src) / src;
  }
}

/// Thrown by converters when a conversion cannot be completed. The message is
/// written for the user, not for a log file.
class ConversionException implements Exception {
  ConversionException(this.message, {this.detail});
  final String message;
  final String? detail;

  @override
  String toString() => message;
}

String humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = bytes / 1024;
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(size >= 100 || i == 0 ? 0 : 1)} ${units[i]}';
}

String humanDuration(Duration d) {
  if (d.inMilliseconds < 1000) return '${d.inMilliseconds} ms';
  if (d.inSeconds < 60) return '${(d.inMilliseconds / 1000).toStringAsFixed(1)} s';
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m}m ${s}s';
}
