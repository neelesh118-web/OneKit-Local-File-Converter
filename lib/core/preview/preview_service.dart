import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../engine/converters/archive_converter.dart';
import '../../engine/converters/converter.dart';
import '../../engine/engine.dart';
import '../../engine/format.dart';
import '../../engine/job.dart';
import '../../engine/registry.dart';

/// What a file looks like, for screens that want to show it rather than just
/// name it.
sealed class Preview {
  const Preview();
}

/// An image on disk that Flutter can decode directly.
class ImagePreview extends Preview {
  const ImagePreview(this.file);
  final File file;
}

/// The opening of a text-ish file.
class TextPreview extends Preview {
  const TextPreview(this.text, {this.truncated = false});
  final String text;
  final bool truncated;
}

/// What is inside an archive.
class ListingPreview extends Preview {
  const ListingPreview(this.entries, this.total);
  final List<String> entries;
  final int total;
}

/// Nothing can be shown; the caller falls back to a format badge.
class NoPreview extends Preview {
  const NoPreview([this.reason]);
  final String? reason;
}

/// Builds previews for any format OneKit understands.
///
/// The point is that converting a file to QOI or DPX should not mean you can
/// never look at it again. Formats Flutter can decode are shown straight from
/// disk; everything else is rendered to a small cached PNG using the same
/// engines that do the conversions. Nothing here touches the network.
class PreviewService {
  PreviewService._();
  static final PreviewService instance = PreviewService._();

  /// Formats the Flutter image decoder handles without any help.
  static const nativeImage = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};

  /// Text-ish families worth showing as characters.
  static const _textFamilies = {Family.data, Family.subtitle, Family.document};

  static const _thumbSize = 512;
  static const _textBudget = 4000;

  final Map<String, Future<Preview>> _inFlight = {};

  /// Rendering several thumbnails at once would fight the conversion the user
  /// is actually waiting on, so they are produced a couple at a time.
  int _active = 0;
  static const _maxActive = 2;
  final List<Completer<void>> _waiting = [];

  Future<void> _acquire() async {
    if (_active < _maxActive) {
      _active++;
      return;
    }
    final c = Completer<void>();
    _waiting.add(c);
    await c.future;
    _active++;
  }

  void _release() {
    _active--;
    if (_waiting.isNotEmpty) _waiting.removeAt(0).complete();
  }

  /// Preview for [path]. Results are cached per file identity, so scrolling a
  /// list back and forth does not re-render anything.
  Future<Preview> previewOf(String path, {FileFormat? format}) {
    final fmt = format ?? FormatRegistry.byExt(p.extension(path));
    final key = _keyFor(path);
    return _inFlight.putIfAbsent(key, () => _build(path, fmt, key));
  }

  static String _keyFor(String path) {
    final f = File(path);
    var stamp = path;
    try {
      final stat = f.statSync();
      // Include size and mtime so a re-converted file with the same name does
      // not show the previous thumbnail.
      stamp = '$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
    } on FileSystemException {
      // Fall through to the bare path.
    }
    return md5.convert(utf8.encode(stamp)).toString();
  }

  Future<Preview> _build(String path, FileFormat? fmt, String key) async {
    final file = File(path);
    if (!await file.exists()) return const NoPreview('File is gone');
    if (fmt == null) return const NoPreview();

    // Straight from disk — no work at all.
    if (fmt.family == Family.image && nativeImage.contains(fmt.ext)) {
      return ImagePreview(file);
    }

    if (_textFamilies.contains(fmt.family) && fmt.ext != 'pdf') {
      final text = await _readHead(file);
      if (text != null) return text;
    }

    if (fmt.family == Family.archive) {
      return _listing(path);
    }

    // Everything else needs rendering: exotic images, video frames, PDF pages.
    if (fmt.family == Family.image ||
        fmt.family == Family.video ||
        fmt.ext == 'pdf') {
      final thumb = await _renderThumb(path, fmt, key);
      if (thumb != null) return ImagePreview(thumb);
    }

    return const NoPreview();
  }

  Future<TextPreview?> _readHead(File file) async {
    try {
      final raw = await file.openRead(0, _textBudget).transform(utf8.decoder).join();
      final trimmed = raw.trim();
      if (trimmed.isEmpty) return const TextPreview('(empty file)');
      final truncated = await file.length() > _textBudget;
      return TextPreview(trimmed, truncated: truncated);
    } catch (_) {
      // Binary content dressed up with a text extension.
      return null;
    }
  }

  Future<Preview> _listing(String path) async {
    try {
      final entries = await ArchiveConverter.inspect(path);
      if (entries.isEmpty) return const NoPreview();
      return ListingPreview(
        [for (final e in entries.take(40)) e.name],
        entries.length,
      );
    } catch (_) {
      return const NoPreview('Could not read this archive');
    }
  }

  /// Renders a small PNG next to the app's other working files.
  Future<File?> _renderThumb(String path, FileFormat fmt, String key) async {
    final dir = Directory(p.join((await ConversionEngine.tempDir()).path, 'previews'));
    await dir.create(recursive: true);
    final out = File(p.join(dir.path, '$key.png'));
    if (await out.exists() && await out.length() > 0) return out;

    await _acquire();
    try {
      final png = FormatRegistry.byExt('png')!;
      // Ask the engine which backend owns this format rather than assuming
      // FFmpeg — PDF pages can only be rendered by pdfium.
      final converter = ConversionEngine.instance.resolve(fmt, png);
      if (converter == null) return null;

      await converter.convert(ConvertRequest(
        inputPath: path,
        outputPath: out.path,
        from: fmt,
        to: png,
        // Downscale during decode, and take only the first page of a document;
        // a full-size render would cost more than the conversion the user is
        // actually waiting for.
        options: const ConvertOptions(
          maxEdge: _thumbSize,
          pdfPageRange: '1',
          pdfDpi: 72,
        ),
        cancel: CancelToken(),
        extraOutputs: [],
        onProgress: (_, {bool indeterminate = false}) {},
      ));
      if (await out.exists() && await out.length() > 0) return out;
    } catch (_) {
      // A preview is a nicety; never let a failure surface as an error.
    } finally {
      _release();
    }
    return null;
  }

  /// Drops cached thumbnails. Called when the user clears working files.
  Future<void> clear() async {
    _inFlight.clear();
    final dir = Directory(p.join((await ConversionEngine.tempDir()).path, 'previews'));
    if (await dir.exists()) await dir.delete(recursive: true);
  }
}
