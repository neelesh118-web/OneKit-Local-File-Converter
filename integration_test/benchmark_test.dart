import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'package:ffmpeg_kit_flutter_new/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new/return_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:onekit_converter/engine/converters/converter.dart';
import 'package:onekit_converter/engine/converters/ffmpeg_converter.dart';
import 'package:onekit_converter/engine/converters/image_converter.dart';
import 'package:onekit_converter/engine/engine.dart';
import 'package:onekit_converter/engine/job.dart';
import 'package:onekit_converter/engine/registry.dart';
import 'package:path/path.dart' as p;

/// Wall-clock benchmarks for the conversions users actually run, at sizes users
/// actually have. The format matrix proves correctness on tiny fixtures; this
/// proves speed on realistic ones.
///
/// Run in profile mode — debug timings are meaningless:
///   flutter drive --driver=test_driver/integration_test.dart \
///     --target=integration_test/benchmark_test.dart --profile
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  late Directory work;
  final results = <_Result>[];

  setUpAll(() async {
    work = await Directory(p.join((await ConversionEngine.tempDir()).path, 'bench'))
        .create(recursive: true);
  });

  tearDownAll(() {
    _report(results);
    work.deleteSync(recursive: true);
  });

  /// Times [body], recording it under [label]. [note] carries extra context
  /// such as the output size.
  Future<Duration> time(String label, Future<String?> Function() body) async {
    final sw = Stopwatch()..start();
    final out = await body();
    sw.stop();
    var bytes = 0;
    if (out != null && File(out).existsSync()) bytes = File(out).lengthSync();
    results.add(_Result(label, sw.elapsed, bytes, ok: out != null));
    return sw.elapsed;
  }

  /// Runs a job through the full engine, exactly as the app does.
  Future<String?> viaEngine(String input, String toExt, {ConvertOptions? options}) async {
    final job = ConversionJob(
      id: 'bench',
      sourcePath: input,
      target: FormatRegistry.byExt(toExt)!,
      options: options ?? const ConvertOptions(quality: 90),
    );
    await ConversionEngine.instance.run(job, cancel: CancelToken(), outputDirectory: work.path);
    return job.status == JobStatus.done ? job.outputPath : null;
  }

  /// Runs one specific converter, bypassing engine routing. This is how the
  /// Dart-vs-FFmpeg question gets a straight answer.
  Future<String?> viaConverter(FileConverter c, String input, String toExt) async {
    final out = p.join(work.path, 'direct_${DateTime.now().microsecondsSinceEpoch}.$toExt');
    try {
      await c.convert(ConvertRequest(
        inputPath: input,
        outputPath: out,
        from: FormatRegistry.byExt(p.extension(input))!,
        to: FormatRegistry.byExt(toExt)!,
        options: const ConvertOptions(quality: 90),
        cancel: CancelToken(),
        extraOutputs: [],
        onProgress: (_, {bool indeterminate = false}) {},
      ));
      return File(out).existsSync() ? out : null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------- fixtures

  late String photo; // 12 MP PNG
  late String mp3; // 3 minute audio
  late String video; // 30 second 1080p H.264 in MP4
  late String mkv; // same H.264 stream, in Matroska -> the remux candidate
  late String zip; // ~50 MB archive
  late String pdf; // 100 page document

  test('build realistic fixtures', () async {
    // Mandelbrot rather than testsrc: the test pattern is flat colour blocks
    // that compress to almost nothing, which would make this measure zip
    // speed instead of image decoding. This is ~12 MP of real detail.
    photo = p.join(work.path, 'photo.png');
    await _ffmpeg(['-f', 'lavfi', '-i', 'mandelbrot=size=4000x3000', '-frames:v', '1', photo]);

    mp3 = p.join(work.path, 'audio.mp3');
    await _ffmpeg([
      '-f', 'lavfi', '-i', 'sine=frequency=440:duration=180',
      '-c:a', 'libmp3lame', '-b:a', '192k', mp3,
    ]);

    // 10 seconds of 720p. Long enough that a re-encode is clearly slower than
    // a remux, short enough that the suite finishes on a phone.
    video = p.join(work.path, 'clip.mp4');
    await _ffmpeg([
      '-f', 'lavfi', '-i', 'testsrc=size=1280x720:rate=30:duration=10',
      '-f', 'lavfi', '-i', 'sine=frequency=440:duration=10',
      '-c:v', 'libx264', '-preset', 'veryfast', '-pix_fmt', 'yuv420p',
      '-c:a', 'aac', '-shortest', video,
    ]);

    // Same encoded streams, different container. Converting this back to MP4
    // is pure remux work — the case the engine currently re-encodes.
    mkv = p.join(work.path, 'clip.mkv');
    await _ffmpeg(['-i', video, '-c', 'copy', mkv]);

    // A real TAR of semi-compressible entries. Pure random data would make the
    // archive benchmark measure I/O only; pure zeroes would measure nothing.
    final rnd = math.Random(7);
    final archive = Archive();
    for (var i = 0; i < 25; i++) {
      final chunk = Uint8List.fromList(
        List<int>.generate(2 << 20, (j) => (j % 251) ^ rnd.nextInt(16)),
      );
      archive.addFile(ArchiveFile.bytes('entry_$i.bin', chunk));
    }
    zip = p.join(work.path, 'bundle.tar');
    await File(zip).writeAsBytes(TarEncoder().encode(archive), flush: true);

    pdf = p.join(work.path, 'doc.pdf');
    final md = File(p.join(work.path, 'doc.md'));
    final b = StringBuffer();
    for (var i = 1; i <= 100; i++) {
      b.writeln('# Chapter $i\n');
      for (var j = 0; j < 12; j++) {
        b.writeln('Paragraph $j of chapter $i. ${'Lorem ipsum dolor sit amet. ' * 6}\n');
      }
    }
    await md.writeAsString(b.toString());
    final built = await viaEngine(md.path, 'pdf');
    pdf = built ?? '';

    for (final f in [photo, mp3, video, mkv, zip]) {
      expect(File(f).existsSync(), isTrue, reason: 'fixture missing: $f');
    }
    expect(pdf, isNotEmpty, reason: 'could not build the PDF fixture');

    // ignore: avoid_print
    print('fixtures: photo ${_mb(photo)}, mp3 ${_mb(mp3)}, mp4 ${_mb(video)}, '
        'mkv ${_mb(mkv)}, tar ${_mb(zip)}, pdf ${_mb(pdf)}');
  }, timeout: const Timeout(Duration(minutes: 10)));

  // -------------------------------------------------------------- images

  test('image: Dart vs FFmpeg head to head', () async {
    // The whole reason this file exists. Same 12 MP source, same target, two
    // engines, one number each.
    await time('12MP PNG>JPG  [Dart]', () => viaConverter(const DartImageConverter(), photo, 'jpg'));
    await time('12MP PNG>JPG  [FFmpeg]', () => viaConverter(const FfmpegConverter(), photo, 'jpg'));
    await time('12MP PNG>WEBP [FFmpeg]', () => viaConverter(const FfmpegConverter(), photo, 'webp'));
    await time('12MP PNG>PNG  [Dart]', () => viaConverter(const DartImageConverter(), photo, 'bmp'));
    await time('12MP PNG>BMP  [FFmpeg]', () => viaConverter(const FfmpegConverter(), photo, 'bmp'));
  }, timeout: const Timeout(Duration(minutes: 10)));

  test('image: through the engine as shipped', () async {
    await time('engine PNG>JPG', () => viaEngine(photo, 'jpg'));
    await time('engine PNG>PDF', () => viaEngine(photo, 'pdf'));
  }, timeout: const Timeout(Duration(minutes: 10)));

  // --------------------------------------------------------------- audio

  test('audio', () async {
    await time('3min MP3>WAV', () => viaEngine(mp3, 'wav'));
    await time('3min MP3>M4A', () => viaEngine(mp3, 'm4a'));
    await time('3min MP3>FLAC', () => viaEngine(mp3, 'flac'));
  }, timeout: const Timeout(Duration(minutes: 10)));

  // --------------------------------------------------------------- video

  test('video: the remux opportunity', () async {
    // Both of these hold an H.264 video stream and AAC audio already. A remux
    // should be near-instant; today both fully re-encode.
    await time('10s MKV>MP4 (remuxable)', () => viaEngine(mkv, 'mp4'));
    await time('10s MP4>MKV (remuxable)', () => viaEngine(video, 'mkv'));
    await time('10s MP4>AVI (real encode)', () => viaEngine(video, 'avi'));
    await time('10s MP4>MP3 (audio only)', () => viaEngine(video, 'mp3'));
  }, timeout: const Timeout(Duration(minutes: 20)));

  // ----------------------------------------------------- archive and pdf

  test('archive and document', () async {
    await time('50MB TAR>ZIP', () => viaEngine(zip, 'zip'));
    await time('100pg PDF>TXT', () => viaEngine(pdf, 'txt'));
    await time('100pg PDF>PNG', () => viaEngine(pdf, 'png', options: const ConvertOptions(pdfDpi: 72)));
  }, timeout: const Timeout(Duration(minutes: 20)));

  // ---------------------------------------------------------- batch cost

  test('batch: 40 photos, serial as shipped', () async {
    // Approximates the common "convert my camera roll" case, at a size where
    // per-job fixed overhead is visible against the actual work.
    final small = p.join(work.path, 'small.png');
    await _ffmpeg(['-f', 'lavfi', '-i', 'testsrc=size=1200x900', '-frames:v', '1', small]);

    final sw = Stopwatch()..start();
    for (var i = 0; i < 20; i++) {
      await viaEngine(small, 'jpg');
    }
    sw.stop();
    results.add(_Result('20x 1MP PNG>JPG serial', sw.elapsed, 0, ok: true));
  }, timeout: const Timeout(Duration(minutes: 20)));
}

class _Result {
  _Result(this.label, this.elapsed, this.bytes, {required this.ok});
  final String label;
  final Duration elapsed;
  final int bytes;
  final bool ok;
}

String _mb(String path) {
  final b = File(path).existsSync() ? File(path).lengthSync() : 0;
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

void _report(List<_Result> rows) {
  // ignore: avoid_print
  print('\n=== OneKit benchmark ===');
  for (final r in rows) {
    final ms = r.elapsed.inMilliseconds;
    final time = ms >= 1000 ? '${(ms / 1000).toStringAsFixed(2)} s' : '$ms ms';
    final size = r.bytes > 0 ? ' -> ${(r.bytes / 1024).toStringAsFixed(0)} KB' : '';
    // ignore: avoid_print
    print('${r.ok ? ' ' : '!'} ${r.label.padRight(28)} ${time.padLeft(9)}$size');
  }
}

Future<void> _ffmpeg(List<String> args) async {
  final session = await FFmpegKit.executeWithArguments(['-hide_banner', '-y', ...args]);
  final code = await session.getReturnCode();
  if (!ReturnCode.isSuccess(code)) {
    final logs = await session.getAllLogsAsString() ?? '';
    final tail = const LineSplitter().convert(logs).reversed.take(6).toList().reversed;
    fail('fixture generation failed:\n${tail.join('\n')}');
  }
}
