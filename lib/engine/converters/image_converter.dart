import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../format.dart';
import '../job.dart';
import 'converter.dart';

/// Pure-Dart image conversion for the formats the `image` package fully
/// supports. It skips the native round-trip entirely, which makes the common
/// PNG/JPG/WEBP/HEIC-adjacent conversions noticeably faster than shelling out.
///
/// Anything outside these sets falls through to [FfmpegConverter].
class DartImageConverter extends FileConverter {
  const DartImageConverter();

  @override
  String get name => 'Dart Image';

  /// Formats the bundled decoder handles.
  ///
  /// PNM/PPM/PGM/PBM and EXR are deliberately absent: the decoder accepts only
  /// a narrow subset of each and failed on real FFmpeg-written files during
  /// device testing, so those route to FFmpeg instead.
  static const decodable = {'png', 'jpg', 'jpeg', 'bmp', 'gif', 'ico', 'cur', 'tga', 'tiff', 'tif', 'webp', 'psd'};

  /// Formats the bundled encoder handles.
  static const encodable = {'png', 'jpg', 'jpeg', 'bmp', 'gif', 'ico', 'cur', 'tga', 'tiff', 'tif'};

  @override
  bool supports(FileFormat from, FileFormat to) =>
      from.family == Family.image &&
      to.family == Family.image &&
      decodable.contains(from.ext) &&
      encodable.contains(to.ext);

  @override
  Future<void> convert(ConvertRequest r) async {
    r.cancel.throwIfCancelled();
    r.onProgress(0.05, indeterminate: false);

    final bytes = await File(r.inputPath).readAsBytes();
    r.cancel.throwIfCancelled();
    r.onProgress(0.2, indeterminate: false);

    // Copy every value the worker needs into locals first. Capturing `r`
    // directly would drag its callbacks and CancelToken into the isolate
    // message; the JIT tolerates that, but AOT rejects it and the conversion
    // fails only in release builds.
    final fromExt = r.from.ext;
    final toExt = r.to.ext;
    final quality = r.options.quality;
    final width = r.options.width;
    final height = r.options.height;

    // Decode + re-encode on a worker isolate; large images would otherwise
    // block the UI thread for hundreds of milliseconds.
    final out = await Isolate.run(
      () => _transcode(bytes, fromExt, toExt, quality, width, height),
    );

    r.cancel.throwIfCancelled();
    r.onProgress(0.9, indeterminate: false);
    await File(r.outputPath).writeAsBytes(out, flush: true);
    r.onProgress(1.0, indeterminate: false);
  }
}

/// Runs on a worker isolate — must not touch anything from the UI thread.
Uint8List _transcode(
  Uint8List bytes,
  String fromExt,
  String toExt,
  int quality,
  int? width,
  int? height,
) {
  final decoded = img.decodeNamedImage('input.$fromExt', bytes);
  if (decoded == null) {
    throw ConversionException('This ${fromExt.toUpperCase()} file could not be read. It may be corrupt or use an unsupported variant.');
  }

  var image = decoded;
  if (width != null || height != null) {
    image = img.copyResize(
      image,
      width: width,
      height: height,
      maintainAspect: width == null || height == null,
      interpolation: img.Interpolation.cubic,
    );
  }

  switch (toExt) {
    case 'jpg':
    case 'jpeg':
      // JPEG has no alpha channel; compositing onto white avoids black halos.
      return img.encodeJpg(_flatten(image), quality: quality.clamp(1, 100));
    case 'png':
      // Map the quality slider onto zlib levels rather than ignoring it.
      return img.encodePng(image, level: ((100 - quality) * 9 / 99).round().clamp(0, 9));
    case 'bmp':
      return img.encodeBmp(image);
    case 'gif':
      return img.encodeGif(image);
    case 'ico':
      return img.encodeIco(image);
    case 'cur':
      return img.encodeCur(image);
    case 'tga':
      return img.encodeTga(image);
    case 'tiff':
    case 'tif':
      return img.encodeTiff(image);
    default:
      throw ConversionException('OneKit cannot write ${toExt.toUpperCase()} with this engine.');
  }
}

img.Image _flatten(img.Image src) {
  if (!src.hasAlpha) return src;
  final canvas = img.Image(width: src.width, height: src.height, numChannels: 3);
  img.fill(canvas, color: img.ColorRgb8(255, 255, 255));
  return img.compositeImage(canvas, src);
}
