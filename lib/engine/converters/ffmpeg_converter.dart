import 'dart:async';
import 'dart:io' show Platform;

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';

import '../format.dart';
import '../job.dart';
import 'converter.dart';

/// What a single ffprobe pass tells us about an input file.
///
/// The duration drives the honest progress percentage. The codec names decide
/// whether the streams can be copied into the target container rather than
/// re-encoded — the difference between a second and several minutes.
class _Probe {
  const _Probe({this.duration, this.videoCodec, this.audioCodec});

  final Duration? duration;
  final String? videoCodec;
  final String? audioCodec;
}

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
    final probe = hasTimeline ? await _probe(r.inputPath) : const _Probe();

    // Try the phone's own video encoder first. It is dramatically faster and
    // far kinder to the battery, but support varies by chipset and some
    // devices reject inputs they claim to handle — so a failure silently
    // re-runs the job in software rather than surfacing an error.
    if (_hardwareCandidate(r, probe)) {
      try {
        await _execute(r, _buildArgs(r, probe, true), probe);
        return;
      } on ConversionException {
        if (r.cancel.isCancelled) rethrow;
        _hardwareBroken.add(r.to.ext);
      }
    }

    await _execute(r, _buildArgs(r, probe), probe);
  }

  /// Targets whose hardware encoder has already failed once this session.
  /// Retrying it for every file in a batch would waste the whole batch.
  static final Set<String> _hardwareBroken = <String>{};

  static bool _hardwareCandidate(ConvertRequest r, _Probe probe) {
    if (!Platform.isAndroid) return false;
    if (r.to.family != Family.video) return false;
    if (_hardwareBroken.contains(r.to.ext)) return false;
    if (!_mediacodecEncoder.containsKey(_videoCodec[r.to.ext])) return false;
    // A remux does not encode at all, so there is nothing to accelerate.
    return !_willCopyVideo(r, probe);
  }

  /// FFmpeg encoders backed by Android's MediaCodec hardware.
  static const _mediacodecEncoder = {
    'libx264': 'h264_mediacodec',
    'libx265': 'hevc_mediacodec',
  };

  Future<void> _execute(ConvertRequest r, List<String> args, _Probe probe) async {

    // Without a duration there is nothing honest to base a percentage on.
    final totalMs = probe.duration?.inMilliseconds ?? 0;
    final canReportPercent = totalMs > 0;
    r.onProgress(0, indeterminate: !canReportPercent);

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

  /// What ffprobe tells us about the input. The duration drives the progress
  /// percentage; the codec names decide whether the streams can simply be
  /// copied into the new container instead of re-encoded.
  static Future<_Probe> _probe(String path) async {
    try {
      final session = await FFprobeKit.getMediaInformation(path);
      final info = session.getMediaInformation();
      if (info == null) return const _Probe();

      Duration? duration;
      final raw = info.getDuration();
      final seconds = raw == null ? null : double.tryParse(raw);
      if (seconds != null && seconds > 0) {
        duration = Duration(milliseconds: (seconds * 1000).round());
      }

      String? video;
      String? audio;
      for (final stream in info.getStreams()) {
        final type = stream.getType();
        final codec = stream.getCodec();
        if (codec == null) continue;
        if (type == 'video' && video == null) {
          // Cover art is stored as a video stream; it is not the movie.
          if (!_coverArtCodecs.contains(codec)) video = codec;
        } else if (type == 'audio' && audio == null) {
          audio = codec;
        }
      }
      return _Probe(duration: duration, videoCodec: video, audioCodec: audio);
    } catch (_) {
      return const _Probe();
    }
  }

  /// Still-image codecs that show up as a video stream on audio files.
  static const _coverArtCodecs = {'mjpeg', 'png', 'bmp', 'gif'};

  /// Codecs each container can carry without re-encoding. Only the mappings
  /// worth taking are listed — an unlisted target simply re-encodes as before.
  static const _containerVideoCodecs = <String, Set<String>>{
    'mp4': {'h264', 'hevc', 'mpeg4', 'av1'},
    'm4v': {'h264', 'hevc', 'mpeg4'},
    'mov': {'h264', 'hevc', 'mpeg4', 'prores'},
    '3gp': {'h264', 'mpeg4'},
    '3g2': {'h264', 'mpeg4'},
    'mkv': {'h264', 'hevc', 'mpeg4', 'av1', 'vp8', 'vp9', 'theora', 'mpeg2video'},
    'webm': {'vp8', 'vp9', 'av1'},
    'ts': {'h264', 'hevc', 'mpeg2video'},
    'flv': {'h264', 'flv1'},
    'f4v': {'h264'},
    'avi': {'mpeg4', 'h264', 'mjpeg'},
    'asf': {'msmpeg4v3', 'wmv2'},
    'mpg': {'mpeg1video', 'mpeg2video'},
    'mpeg': {'mpeg1video', 'mpeg2video'},
    'ogv': {'theora'},
  };

  static const _containerAudioCodecs = <String, Set<String>>{
    'mp4': {'aac', 'mp3', 'alac', 'ac3'},
    'm4v': {'aac', 'mp3'},
    'm4a': {'aac', 'alac'},
    'mov': {'aac', 'mp3', 'alac', 'pcm_s16le'},
    '3gp': {'aac', 'amr_nb'},
    '3g2': {'aac', 'amr_nb'},
    'mkv': {'aac', 'mp3', 'flac', 'opus', 'vorbis', 'ac3', 'eac3', 'dts', 'pcm_s16le'},
    'mka': {'aac', 'mp3', 'flac', 'opus', 'vorbis', 'ac3'},
    'webm': {'opus', 'vorbis'},
    'ts': {'aac', 'mp3', 'ac3'},
    'flv': {'aac', 'mp3'},
    'f4v': {'aac'},
    'avi': {'mp3', 'ac3', 'pcm_s16le'},
    'mp3': {'mp3'},
    'flac': {'flac'},
    'ogg': {'vorbis', 'opus'},
    'oga': {'vorbis', 'opus', 'flac'},
    'opus': {'opus'},
    'wav': {'pcm_s16le', 'pcm_s24le'},
    'aac': {'aac'},
    'adts': {'aac'},
    'ac3': {'ac3'},
    'wv': {'wavpack'},
  };

  /// Whether the already-encoded streams can be dropped straight into the new
  /// container. Copying is both instant and lossless, so it is always the
  /// better answer when it is available.
  static bool _canCopyVideo(String? codec, FileFormat to) =>
      codec != null && (_containerVideoCodecs[to.ext]?.contains(codec) ?? false);

  static bool _canCopyAudio(String? codec, FileFormat to) =>
      codec != null && (_containerAudioCodecs[to.ext]?.contains(codec) ?? false);

  /// Builds the argument vector. Arguments are passed as a list, never as a
  /// joined string, so paths containing spaces or quotes cannot break out.
  /// Whether the video stream will be copied rather than re-encoded.
  static bool _willCopyVideo(ConvertRequest r, _Probe probe) {
    final o = r.options;
    final wantsReencode = o.width != null ||
        o.height != null ||
        o.videoCrf != null ||
        o.fps != null ||
        _fixedGeometry.contains(r.to.ext);
    return !wantsReencode && _canCopyVideo(probe.videoCodec, r.to);
  }

  static List<String> _buildArgs(
    ConvertRequest r, [
    _Probe probe = const _Probe(),
    bool hardware = false,
  ]) {
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

      // If the encoded audio already suits the target container, copy it: an
      // instant, bit-exact extraction rather than a lossy re-encode. Only when
      // the user has not asked for a different bitrate or sample rate, since
      // honouring those requires actually re-encoding.
      final untouched = o.audioBitrateKbps == null && o.sampleRate == null;
      if (untouched && _canCopyAudio(probe.audioCodec, r.to)) {
        args.addAll(['-c:a', 'copy']);
        if (o.stripMetadata) args.addAll(['-map_metadata', '-1']);
        final forcedAudio = _forcedFormat[r.to.ext];
        if (forcedAudio != null) args.addAll(['-f', forcedAudio]);
        args.add(r.outputPath);
        return args;
      }

      final br = o.audioBitrateKbps;
      if (br != null && _lossyAudio.contains(r.to.ext)) {
        args.addAll(['-b:a', '${br}k']);
      }

      // Some codecs accept only one rate and channel count. Narrow-band speech
      // codecs are the main case: AMR-NB and GSM are 8 kHz mono, full stop.
      final fixed = _fixedAudioLayout[r.to.ext];
      if (fixed != null) {
        args.addAll(['-ar', '${fixed.rate}', '-ac', '${fixed.channels}']);
      } else if (o.sampleRate != null) {
        args.addAll(['-ar', '${o.sampleRate}']);
      }

      final codec = _audioCodec[r.to.ext];
      if (codec != null) args.addAll(['-c:a', codec]);
      // FFmpeg refuses its own experimental encoders without this.
      if (_experimentalCodecs.contains(codec)) args.addAll(['-strict', '-2']);
    } else if (r.to.family == Family.video) {
      // The big win: a container change between two formats that already hold
      // the same codec is a remux, not a transcode. MKV->MP4 with H.264 inside
      // goes from minutes to about a second, and loses nothing.
      final wantsReencode = o.width != null ||
          o.height != null ||
          o.videoCrf != null ||
          o.fps != null ||
          _fixedGeometry.contains(r.to.ext);
      final copyVideo = _willCopyVideo(r, probe);
      final copyAudio = !wantsReencode && _canCopyAudio(probe.audioCodec, r.to);

      if (copyVideo) {
        args.addAll(['-c:v', 'copy']);
        // The audio may still need converting even when the video can be
        // copied — a WebM's Opus track cannot go into an MP4, for instance.
        if (copyAudio) {
          args.addAll(['-c:a', 'copy']);
        } else {
          args.addAll(['-c:a', _remuxAudioCodec[r.to.ext] ?? 'aac']);
        }
        if (_mp4Family.contains(r.to.ext)) args.addAll(['-movflags', '+faststart']);
        if (o.stripMetadata) args.addAll(['-map_metadata', '-1']);
        final forcedRemux = _forcedFormat[r.to.ext];
        if (forcedRemux != null) args.addAll(['-f', forcedRemux]);
        args.add(r.outputPath);
        return args;
      }

      final soft = _videoCodec[r.to.ext];
      final vcodec = hardware ? (_mediacodecEncoder[soft] ?? soft) : soft;
      if (vcodec != null) args.addAll(['-c:v', vcodec]);
      if (copyAudio) args.addAll(['-c:a', 'copy']);
      if (o.videoCrf != null && _crfCodecs.contains(vcodec)) {
        args.addAll(['-crf', '${o.videoCrf}']);
      }
      if (o.fps != null) args.addAll(['-r', '${o.fps}']);
      if (stillToVideo) {
        args.addAll(['-pix_fmt', 'yuv420p']);
      }
      // The 3GPP containers only accept baseline H.264 with AAC audio.
      if (r.to.ext == '3gp' || r.to.ext == '3g2') {
        args.addAll([
          '-profile:v', 'baseline', '-level', '3.0',
          '-pix_fmt', 'yuv420p',
          '-c:a', 'aac', '-ar', '44100', '-ac', '2',
        ]);
      } else if (_needsAacAudio.contains(r.to.ext)) {
        // MP4-family muxers reject Vorbis/Opus, which is what a WebM source
        // would otherwise carry straight through.
        args.addAll(['-c:a', 'aac']);
      }
      // DV and MXF are broadcast formats with fixed geometry: DV is 720x576
      // at 25 fps, and MXF wants 4:2:0 MPEG-2 with 48 kHz audio. Resizing is
      // not optional here — it is what the format is.
      if (r.to.ext == 'dv') {
        args.addAll([
          '-s', '720x576', '-r', '25', '-pix_fmt', 'yuv420p',
          '-ar', '48000', '-ac', '2',
        ]);
      } else if (r.to.ext == 'mxf') {
        args.addAll([
          '-pix_fmt', 'yuv420p', '-r', '25',
          '-c:a', 'pcm_s16le', '-ar', '48000', '-ac', '2',
        ]);
      } else {
        // Even dimensions are required by most H.264/H.265 profiles.
        args.addAll(['-vf', _scaleFilter(o, forceEven: true)]);
      }
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
      // PNM is a family (PBM/PGM/PPM), so the concrete encoder has to be named.
      final imageCodec = _imageCodec[r.to.ext];
      if (imageCodec != null) args.addAll(['-c:v', imageCodec]);
      final pixFmt = _imagePixFmt[r.to.ext];
      if (pixFmt != null) args.addAll(['-pix_fmt', pixFmt]);
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

  /// Codecs that accept exactly one sample rate / channel layout.
  static const _fixedAudioLayout = <String, ({int rate, int channels})>{
    'amr': (rate: 8000, channels: 1),
    'gsm': (rate: 8000, channels: 1),
    '8svx': (rate: 8000, channels: 1),
  };

  /// Encoders FFmpeg marks experimental; they need -strict -2 to run at all.
  static const _experimentalCodecs = {'dca', 'opus'};

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

  /// Containers that must carry AAC audio regardless of what came in.
  static const _needsAacAudio = {'mp4', 'm4v', 'mov', 'f4v', 'flv', 'ts'};

  /// MP4-family containers, which benefit from a relocated moov atom so the
  /// file starts playing before it has finished downloading.
  static const _mp4Family = {'mp4', 'm4v', 'mov', '3gp', '3g2', 'f4v'};

  /// Targets with a mandated frame size or rate, so a copy is never valid.
  static const _fixedGeometry = {'dv', 'mxf', '3gp', '3g2'};

  /// When the video is copied but the audio cannot be, this is what the audio
  /// becomes — the codec each container is happiest carrying.
  static const _remuxAudioCodec = {
    'mkv': 'aac',
    'webm': 'libopus',
    'ogv': 'libvorbis',
    'avi': 'libmp3lame',
    'asf': 'libmp3lame',
    'mpg': 'mp2',
    'mpeg': 'mp2',
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
    // VP8, not VP9: the bundled build writes VP9 that its own decoder then
    // rejects, which broke every webm/ivf round trip on device.
    'webm': 'libvpx',
    'ivf': 'libvpx',
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

  static const _crfCodecs = {'libx264', 'libx265', 'libvpx-vp9', 'libvpx'};

  /// Image encoders that accept only one pixel format.
  static const _imagePixFmt = {
    'vbn': 'rgba',
    'wbmp': 'monob',
    'xbm': 'monob',
  };

  /// Image targets whose muxer cannot pick an encoder from the extension.
  static const _imageCodec = {
    'pnm': 'ppm',
    'vbn': 'vbn',
    'ras': 'sunrast',
    'phm': 'phm',
  };

  /// Extensions FFmpeg cannot infer a muxer from on its own.
  static const _forcedFormat = {
    // ALAC is a codec, not a container: it has to be muxed into MP4/iTunes.
    'alac': 'ipod',
    'adts': 'adts',
    'h264': 'h264',
    'hevc': 'hevc',
    'zlib': 'data',
    'pnm': 'image2',
    'phm': 'image2',
    'ras': 'image2',
    'apng': 'apng',
  };
}
