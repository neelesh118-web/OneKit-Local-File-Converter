import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import '../format.dart';
import '../job.dart';
import 'converter.dart';

/// Archive repacking (ZIP <-> TAR <-> TGZ <-> TBZ ...) and single-stream
/// compression (GZ / BZ2 / XZ / ZLIB).
///
/// Container formats are decoded into an in-memory [Archive] and re-encoded, so
/// entry names and directory structure survive the round trip.
class ArchiveConverter extends FileConverter {
  const ArchiveConverter();

  @override
  String get name => 'Archive';

  /// Formats that hold many entries.
  static const containers = {'zip', 'tar', 'tgz', 'tbz', 'txz'};

  /// Formats that wrap exactly one stream.
  static const streams = {'gz', 'bz2', 'xz', 'zlib'};

  @override
  bool supports(FileFormat from, FileFormat to) =>
      from.family == Family.archive && to.family == Family.archive;

  @override
  Future<void> convert(ConvertRequest r) async {
    r.onProgress(0.05, indeterminate: false);
    final bytes = await File(r.inputPath).readAsBytes();
    r.cancel.throwIfCancelled();
    r.onProgress(0.25, indeterminate: false);

    // Copy the values the worker needs into locals: capturing the request
    // would drag its callbacks and CancelToken into the isolate message, which
    // the JIT tolerates and AOT rejects.
    final fromExt = r.from.ext;
    final toExt = r.to.ext;
    final entryName = p.basenameWithoutExtension(r.inputPath);

    r.onProgress(0.35, indeterminate: false);
    // Compression is heavy and entirely CPU-bound. Run it on a worker so a
    // 500 MB ZIP does not freeze the interface for the whole conversion.
    final out = await Isolate.run(() => _repack(bytes, fromExt, toExt, entryName));

    r.cancel.throwIfCancelled();
    r.onProgress(0.9, indeterminate: false);
    await File(r.outputPath).writeAsBytes(out, flush: true);
    r.onProgress(1.0, indeterminate: false);
  }

  /// Runs on a worker isolate — must touch nothing from the UI thread.
  static List<int> _repack(
    Uint8List bytes,
    String fromExt,
    String toExt,
    String entryName,
  ) {
    final fromContainer = containers.contains(fromExt);
    final toContainer = containers.contains(toExt);

    if (fromContainer && toContainer) {
      return _encodeContainer(_decodeContainer(bytes, fromExt), toExt);
    }
    if (!fromContainer && !toContainer) {
      // Stream to stream: decompress then recompress the raw payload.
      return _encodeStream(_decodeStream(bytes, fromExt), toExt);
    }
    if (fromContainer && !toContainer) {
      // Many entries into a single stream: re-pack as TAR first so nothing is
      // lost, then compress that.
      return _encodeStream(TarEncoder().encode(_decodeContainer(bytes, fromExt)), toExt);
    }
    // Single stream into a container: the payload becomes one entry named
    // after the source file with its compression suffix removed.
    final raw = _decodeStream(bytes, fromExt);
    final archive = Archive()..addFile(ArchiveFile(entryName, raw.length, raw));
    return _encodeContainer(archive, toExt);
  }

  static Archive _decodeContainer(Uint8List bytes, String ext) {
    final Archive archive;
    try {
      archive = switch (ext) {
        'zip' => ZipDecoder().decodeBytes(bytes),
        'tar' => TarDecoder().decodeBytes(bytes),
        'tgz' => TarDecoder().decodeBytes(GZipDecoder().decodeBytes(bytes)),
        'tbz' => TarDecoder().decodeBytes(BZip2Decoder().decodeBytes(bytes)),
        'txz' => TarDecoder().decodeBytes(XZDecoder().decodeBytes(bytes)),
        _ => throw ConversionException('OneKit cannot read ${ext.toUpperCase()} archives.'),
      };
    } on ConversionException {
      rethrow;
    } catch (e) {
      throw ConversionException(_corruptMessage(ext), detail: '$e');
    }
    // Some decoders return an empty archive rather than throwing on garbage,
    // which would otherwise surface as a mysteriously empty output file.
    if (archive.files.isEmpty) throw ConversionException(_corruptMessage(ext));
    return archive;
  }

  static String _corruptMessage(String ext) =>
      'This ${ext.toUpperCase()} archive could not be opened. It may be corrupt, '
      'password protected, or use an unsupported compression method.';

  static List<int> _encodeContainer(Archive archive, String ext) {
    switch (ext) {
      case 'zip':
        return ZipEncoder().encode(archive);
      case 'tar':
        return TarEncoder().encode(archive);
      case 'tgz':
        return GZipEncoder().encode(TarEncoder().encode(archive));
      case 'tbz':
        return BZip2Encoder().encode(TarEncoder().encode(archive));
      default:
        throw ConversionException('OneKit cannot write ${ext.toUpperCase()} archives.');
    }
  }

  static List<int> _decodeStream(Uint8List bytes, String ext) {
    try {
      return switch (ext) {
        'gz' => GZipDecoder().decodeBytes(bytes),
        'bz2' => BZip2Decoder().decodeBytes(bytes),
        'xz' => XZDecoder().decodeBytes(bytes),
        'zlib' => const ZLibDecoder().decodeBytes(bytes),
        _ => throw ConversionException('OneKit cannot read ${ext.toUpperCase()} streams.'),
      };
    } on ConversionException {
      rethrow;
    } catch (e) {
      throw ConversionException('This ${ext.toUpperCase()} file could not be decompressed.', detail: '$e');
    }
  }

  static List<int> _encodeStream(List<int> raw, String ext) {
    return switch (ext) {
      'gz' => GZipEncoder().encode(raw),
      'bz2' => BZip2Encoder().encode(raw),
      'zlib' => const ZLibEncoder().encode(raw),
      _ => throw ConversionException('OneKit cannot write ${ext.toUpperCase()} streams.'),
    };
  }

  /// Lists what is inside an archive without extracting it, for the preview
  /// sheet on the batch screen.
  static Future<List<({String name, int size, bool isDir})>> inspect(String path) async {
    final ext = p.extension(path).replaceFirst('.', '').toLowerCase();
    if (!containers.contains(ext)) return const [];
    final archive = _decodeContainer(await File(path).readAsBytes(), ext);
    return [
      for (final f in archive.files) (name: f.name, size: f.size, isDir: !f.isFile),
    ];
  }
}
