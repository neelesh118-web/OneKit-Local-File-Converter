import 'dart:async';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../format.dart';
import '../job.dart';
import 'converter.dart';

/// The workhorse. FFmpeg covers audio, video, and the long tail of image
/// formats the pure-Dart decoder cannot touch (AVIF, HEIC, JP2, QOI, ...).
///
/// Progress is real: ffprobe gives the source duration up front, and ffmpeg's
/// statistics callback reports how many milliseconds of output exist so far.
/// Where there is no timeline (a single still image), the job runs
/// indeterminate rather than faking a percentage.
class FfmpegConverter extends FileConverter {
  const FfmpegConverter();

  @override
  String get name => 'FFmpeg';

  static const _timelineFamilies = {Family.audio, Family.video};

  @override
  bool supports(FileFormat from, FileFormat to) {
    const handled = {Family.audio, Family.video, Family.image};
    return handled.contains(from.family) && handled.contains(to.family);
  }

  @override
  Future<void> convert(ConvertRequest r) async {
    r.cancel.throwIfCancelled();

    final hasTimeline = _timelineFamilies.contains(r.from.family);
    Duration? duration;
    if (hasTimeline) {
      duration = await _probeDuration(r.inputPath);
    }

    // Without a duration there is nothing honest to base a percentage on.
    final totalMs = duration?.inMilliseconds ?? 0;
    final canReportPercent = totalMs > 0;
    r.onProgress(0, indeterminate: !canReportPercent);

    final args = _buildArgs(r);

    final completer = Completer<void>();
    var sessionId = 0;
    final logTail = <String>[];

    final session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (session) async {
        final code = await session.getReturnCode();
        if (ReturnCode.isSuccess(code)) {
          r.onProgress(1.0, indeterminate: false);
          completer.complete();
        } else if (ReturnCode.isCancel(code) || r.cancel.isCancelled) {
          completer.completeError(ConversionException('Cancelled'));
        } else {
          completer.completeError(
            ConversionException(
              'FFmpeg could not convert ${r.from.upper} to ${r.to.upper}.',
              detail: logTail.join('\n'),
            ),
          );
        }
      },
      (log) {
        // Keep only the tail; ffmpeg logs are long and we just want the reason.
        logTail.add(log.getMessage().trimRight());
        if (logTail.length > 40) logTail.removeAt(0);
      },
      (stats) {
        if (!canReportPercent) return;
        final done = stats.getTime();
        if (done <= 0) return;
        final value = done / totalMs;
        r.onProgress(value.clamp(0.0, 0.999), indeterminate: false);
      },
    );

    sessionId = session.getSessionId() ?? 0;
    r.cancel.onCancel(() {
      if (sessionId != 0) FFmpegKit.cancel(sessionId);
    });
    if (r.cancel.isCancelled && sessionId != 0) {
      await FFmpegKit.cancel(sessionId);
    }

    return completer.future;
  }

  static Future<Duration?> _probeDuration(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final raw = session.getMediaInformation()?.getDuration();
      if (raw == null) return null;
      final seconds = double.tryParse(raw);
      if (seconds == null || seconds <= 0) return null;
      return Duration(milliseconds: (seconds * 1000).round());
    } catch (_) {
      return null;
    }
  }

  /// Builds the argument vector. Arguments are passed as a list, never as a
  /// joined string, so paths containing spaces or quotes cannot break out.
  static List<String> _buildArgs(ConvertRequest r) {
    final o = r.options;
    final args = <String>['-hide_banner', '-nostdin', '-y'];

    // A still image feeding a video target has to be looped into a timeline.
    final stillToVideo = r.from.family == Family.image && r.to.family == Family.video;
    if (stillToVideo) {
      args.addAll(['-loop', '1', '-t', '3']);
    }

    args.addAll(['-i', r.inputPath]);

    if (r.to.family == Family.audio) {
      // Drop video streams so cover art cannot derail an audio-only muxer.
      args.addAll(['-vn', '-map', '0:a:0?']);
      final br = o.audioBitrateKbps;
      if (br != null && _lossyAudio.contains(r.to.ext)) {
        args.addAll(['-b:a', '${br}k']);
      }
      if (o.sampleRate != null) args.addAll(['-ar', '${o.sampleRate}']);
      final codec = _audioCodec[r.to.ext];
      if (codec != null) args.addAll(['-c:a', codec]);
    } else if (r.to.family == Family.video) {
      final vcodec = _videoCodec[r.to.ext];
      if (vcodec != null) args.addAll(['-c:v', vcodec]);
      if (o.videoCrf != null && _crfCodecs.contains(vcodec)) {
        args.addAll(['-crf', '${o.videoCrf}']);
      }
      if (o.fps != null) args.addAll(['-r', '${o.fps}']);
      if (stillToVideo) {
        args.addAll(['-pix_fmt', 'yuv420p']);
      }
      // Even dimensions are required by most H.264/H.265 profiles.
      args.addAll(['-vf', _scaleFilter(o, forceEven: true)]);
    } else if (r.to.family == Family.image) {
      if (r.from.family == Family.video) {
        if (r.to.ext == 'gif' || r.to.ext == 'apng' || r.to.ext == 'webp') {
          // Animated targets keep the motion; everything else takes one frame.
          args.addAll(['-vf', '${_scaleFilter(o)},fps=${o.fps ?? 12}']);
          if (r.to.ext == 'gif') args.addAll(['-loop', '0']);
        } else {
          args.addAll(['-frames:v', '1', '-vf', _scaleFilter(o)]);
        }
      } else {
        args.addAll(['-vf', _scaleFilter(o)]);
      }
      args.addAll(_imageQualityArgs(r.to, o.quality));
    }

    if (o.stripMetadata) args.addAll(['-map_metadata', '-1']);

    final forced = _forcedFormat[r.to.ext];
    if (forced != null) args.addAll(['-f', forced]);

    args.add(r.outputPath);
    return args;
  }

  static String _scaleFilter(ConvertOptions o, {bool forceEven = false}) {
    final w = o.width;
    final h = o.height;
    if (w == null && h == null) {
      return forceEven ? 'scale=trunc(iw/2)*2:trunc(ih/2)*2' : 'scale=iw:ih';
    }
    // -1/-2 lets ffmpeg preserve the aspect ratio for the omitted dimension.
    final auto = forceEven ? '-2' : '-1';
    return 'scale=${w ?? auto}:${h ?? auto}';
  }

  /// Maps a 1-100 quality slider onto whatever scale each encoder wants.
  static List<String> _imageQualityArgs(FileFormat to, int quality) {
    final q = quality.clamp(1, 100);
    switch (to.ext) {
      case 'jpg':
      case 'jpeg':
        // mjpeg -q:v runs 2 (best) to 31 (worst).
        return ['-q:v', '${(2 + (100 - q) * 29 / 99).round()}'];
      case 'webp':
        return ['-quality', '$q', '-compression_level', '6'];
      case 'avif':
        // libaom CRF: 0 (best) to 63 (worst).
        return ['-crf', '${((100 - q) * 63 / 99).round()}', '-b:v', '0', '-cpu-used', '6'];
      case 'jp2':
      case 'j2k':
        return ['-q:v', '${(2 + (100 - q) * 29 / 99).round()}'];
      default:
        return const [];
    }
  }

  static const _lossyAudio = {'mp3', 'aac', 'm4a', 'ogg', 'oga', 'opus', 'ac3', 'eac3', 'mp2', 'amr', 'adts', 'sbc', 'gsm'};

  static const _audioCodec = {
    'mp3': 'libmp3lame',
    'aac': 'aac',
    'm4a': 'aac',
    'adts': 'aac',
    'ogg': 'libvorbis',
    'oga': 'libvorbis',
    'opus': 'libopus',
    'flac': 'flac',
    'wav': 'pcm_s16le',
    'w64': 'pcm_s16le',
    'aiff': 'pcm_s16be',
    'aif': 'pcm_s16be',
    'alac': 'alac',
    'ac3': 'ac3',
    'eac3': 'eac3',
    'mp2': 'mp2',
    'amr': 'libopencore_amrnb',
    'au': 'pcm_s16be',
    'caf': 'pcm_s16le',
    'dts': 'dca',
    'tta': 'tta',
    'wv': 'wavpack',
    'voc': 'pcm_u8',
    'gsm': 'libgsm',
    'sbc': 'sbc',
    '8svx': 'pcm_s8',
    'mka': 'libvorbis',
  };

  static const _videoCodec = {
    'mp4': 'libx264',
    'm4v': 'libx264',
    'mov': 'libx264',
    'mkv': 'libx264',
    'ts': 'libx264',
    'f4v': 'libx264',
    'flv': 'libx264',
    'h264': 'libx264',
    'hevc': 'libx265',
    'webm': 'libvpx-vp9',
    'ivf': 'libvpx-vp9',
    'ogv': 'libtheora',
    'avi': 'mpeg4',
    'asf': 'msmpeg4v3',
    'mpg': 'mpeg2video',
    'mpeg': 'mpeg2video',
    '3gp': 'libx264',
    '3g2': 'libx264',
    'dv': 'dvvideo',
    'mxf': 'mpeg2video',
    'y4m': 'rawvideo',
  };

  static const _crfCodecs = {'libx264', 'libx265', 'libvpx-vp9'};

  /// Extensions ffmpeg cannot infer a muxer from on its own.
  static const _forcedFormat = {
    'adts': 'adts',
    'h264': 'h264',
    'hevc': 'hevc',
    'zlib': 'data',
    'farbfeld': 'image2',
    'phm': 'image2',
    'vbn': 'image2',
    'ras': 'image2',
    'apng': 'apng',
  };
}
