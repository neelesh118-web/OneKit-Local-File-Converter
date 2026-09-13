import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../format.dart';
import '../job.dart';
import 'converter.dart';

/// The face payload every route pivots through: the sfnt flavor word and the
/// raw bytes of each table, keyed by tag.
typedef _SfntFace = ({int flavor, Map<String, Uint8List> tables});

/// Font container work, entirely in Dart.
///
/// Like the subtitle converter, this pivots through a parsed face: every
/// operation is a repack of the sfnt table structure — the same bytes in,
/// rearranged on the way out — so fonts that come out render identically to
/// the ones that went in:
///
/// - TTC → TTF/OTF: extract the first face out of a TrueType Collection.
/// - TTF/OTF → TTC: wrap a single face into a one-entry collection.
/// - WOFF → TTF/OTF/TTC: inflate each zlib-compressed table (WOFF 1.0).
/// - TTF/OTF → WOFF: deflate each table and rebuild the 44-byte header.
///
/// What this deliberately does not claim is TTF <-> OTF: they differ in glyph
/// outline format (quadratic 'glyf' versus cubic 'CFF '), and translating
/// between the two is font compiling, which no bundled engine can do. The
/// registry's `fontToFontExcluded` keeps those pairs out of the catalogue.
/// Writing a face under the wrong extension is refused at run time too: the
/// flavor is checked against the requested target before any bytes are built.
class FontConverter extends FileConverter {
  const FontConverter();

  @override
  String get name => 'Font';

  /// Bare sfnt faces.
  static const _faces = {'ttf', 'otf'};

  @override
  bool supports(FileFormat from, FileFormat to) {
    if (from.family != Family.font || to.family != Family.font) return false;
    // TTF <-> OTF is outline translation, not repacking.
    if (_faces.contains(from.ext) && _faces.contains(to.ext)) return false;
    return true;
  }

  @override
  Future<void> convert(ConvertRequest r) async {
    r.onProgress(0.05, indeterminate: false);
    final bytes = await File(r.inputPath).readAsBytes();
    r.cancel.throwIfCancelled();

    // Copy the values the worker needs into locals: capturing the request
    // would drag its callbacks and CancelToken into the isolate message, which
    // the JIT tolerates and AOT rejects.
    final fromExt = r.from.ext;
    final toExt = r.to.ext;

    r.onProgress(0.3, indeterminate: false);
    final out = await Isolate.run(() => _repack(bytes, fromExt, toExt));

    r.cancel.throwIfCancelled();
    r.onProgress(0.9, indeterminate: false);
    await File(r.outputPath).writeAsBytes(out, flush: true);
    r.onProgress(1.0, indeterminate: false);
  }

  /// Runs on a worker isolate — must touch nothing from the UI thread.
  static List<int> _repack(Uint8List bytes, String fromExt, String toExt) {
    final face = switch (fromExt) {
      'woff' => _parseWoff(bytes),
      'ttc' => _readCollectionFace(bytes, 0),
      'ttf' || 'otf' => _readSfnt(bytes),
      _ => throw ConversionException('This app cannot read ${fromExt.toUpperCase()} fonts.'),
    };

    return switch (toExt) {
      'woff' => _packWoff(face),
      'ttc' => _wrapCollection(face),
      'ttf' || 'otf' => _writeSfnt(face, toExt),
      _ => throw ConversionException('This app cannot write ${toExt.toUpperCase()} fonts.'),
    };
  }

  // ------------------------------------------------------------------ sfnt

  /// 'OTTO' — a CFF-flavoured OpenType face.
  static const _otto = 0x4F54544F;
  static const _ttcTag = 0x74746366; // 'ttcf'

  /// Parses a bare sfnt face. If the bytes turn out to be a collection or a
  /// WOFF file with the wrong extension, it is parsed as what it is rather
  /// than failing confusingly later.
  static _SfntFace _readSfnt(Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    if (bytes.length < 12) throw ConversionException(_shortMessage());
    final flavor = d.getUint32(0);
    if (flavor == _ttcTag) return _readCollectionFace(bytes, 0);
    if (flavor == _woffTag) return _parseWoff(bytes);
    final numTables = d.getUint16(4);
    return (flavor: flavor, tables: _readTableDirectory(d, 12, numTables, bytes.length));
  }

  /// Reads the table directory that starts at [dirOffset] and slices each
  /// table out. Bounds-checked so a corrupt font fails with a clear message.
  static Map<String, Uint8List> _readTableDirectory(
    ByteData d,
    int dirOffset,
    int numTables,
    int fileLength,
  ) {
    if (dirOffset + 16 * numTables > fileLength) {
      throw ConversionException(_corruptMessage());
    }
    final tables = <String, Uint8List>{};
    for (var i = 0; i < numTables; i++) {
      final rec = dirOffset + 16 * i;
      final offset = d.getUint32(rec + 8);
      final length = d.getUint32(rec + 12);
      if (offset + length > fileLength) {
        throw ConversionException(_corruptMessage());
      }
      tables[_tag(d, rec)] = Uint8List.sublistView(bytesOf(d), offset, offset + length);
    }
    if (tables.isEmpty) throw ConversionException(_corruptMessage());
    return tables;
  }

  /// The bytes a [ByteData] view was built over. sublistView always spans the
  /// whole source here, so this is the start of the file.
  static Uint8List bytesOf(ByteData d) =>
      d.buffer.asUint8List(d.offsetInBytes, d.lengthInBytes);

  /// Serialises a face as a bare sfnt: 12-byte header, table directory sorted
  /// by tag, then each table padded to a 4-byte boundary, checksums included.
  ///
  /// [toExt] is checked against the flavor so a CFF face is never labelled
  /// .ttf, nor a glyf face .otf — a file with the wrong outlines inside is
  /// worse than an honest refusal.
  static Uint8List _writeSfnt(_SfntFace face, String toExt) {
    _checkFlavor(face.flavor, toExt);
    return _writeSfntBody(face);
  }
  static String _tag(ByteData d, int at) => String.fromCharCodes([
        d.getUint8(at),
        d.getUint8(at + 1),
        d.getUint8(at + 2),
        d.getUint8(at + 3),
      ]);

  static void _writeTag(ByteData d, int at, String tag) {
    for (var i = 0; i < 4; i++) {
      d.setUint8(at + i, i < tag.length ? tag.codeUnitAt(i) : 0x20);
    }
  }

  static ({int range, int selector}) _searchRange(int numTables) {
    var selector = 0;
    while ((1 << (selector + 1)) <= numTables) {
      selector++;
    }
    return (range: 16 * (1 << selector), selector: selector);
  }

  /// Checksum over the table's big-endian words; a trailing partial word is
  /// zero-padded rather than wrapped around.
  static int _tableChecksum(Uint8List data) {
    var sum = 0;
    final d = ByteData.sublistView(data);
    final words = data.length ~/ 4;
    for (var i = 0; i < words; i++) {
      sum += d.getUint32(i * 4);
    }
    final tail = data.length & 3;
    if (tail != 0) {
      var last = 0;
      for (var i = 0; i < tail; i++) {
        last |= data[words * 4 + i] << (24 - 8 * i);
      }
      sum += last;
    }
    return sum & 0xFFFFFFFF;
  }

  // ------------------------------------------------------------------- ttc

  /// Extracts face [index] from a TrueType Collection.
  static _SfntFace _readCollectionFace(Uint8List bytes, int index) {
    final d = ByteData.sublistView(bytes);
    if (bytes.length < 12 || d.getUint32(0) != _ttcTag) {
      throw ConversionException(_corruptMessage());
    }
    final count = d.getUint32(8);
    if (index >= count) throw ConversionException(_corruptMessage());
    final faceOffset = d.getUint32(12 + 4 * index);
    if (faceOffset + 12 > bytes.length) throw ConversionException(_corruptMessage());

    final flavor = d.getUint32(faceOffset);
    final numTables = d.getUint16(faceOffset + 4);
    final tables = _readTableDirectory(d, faceOffset + 12, numTables, bytes.length);
    return (flavor: flavor, tables: tables);
  }

  /// Wraps a face into a one-entry collection. A TTC header carries no
  /// checksums of its own — the faces inside keep theirs — so the face body
  /// is a complete, valid sfnt that any renderer can also read directly.
  /// Its table offsets point into the whole collection file, as the format
  /// requires.
  static Uint8List _wrapCollection(_SfntFace face) {
    // 'ttcf', version, count, one offset — 16 bytes, already 4-aligned.
    const headerSize = 16;
    final body = _writeSfntBody(face, baseOffset: headerSize);

    final out = Uint8List(headerSize + body.length - headerSize);
    final d = ByteData.sublistView(out);
    d.setUint32(0, _ttcTag);
    d.setUint32(4, 0x00010000); // collection version 1.0
    d.setUint32(8, 1); // one face
    d.setUint32(12, headerSize); // the face starts right after
    out.setAll(headerSize, Uint8List.sublistView(body, headerSize));
    return out;
  }

  /// Builds the sfnt body. [baseOffset] shifts every table offset: a bare
  /// face is self-relative (0), but a face embedded in a collection uses
  /// offsets measured from the start of the whole TTC file.
  static Uint8List _writeSfntBody(_SfntFace face, {int baseOffset = 0}) {
    final tags = face.tables.keys.toList()..sort();
    final numTables = tags.length;

    final dirSize = 12 + 16 * numTables;
    var bodySize = 0;
    for (final t in tags) {
      bodySize += (face.tables[t]!.length + 3) & ~3;
    }
    final out = Uint8List(baseOffset + dirSize + bodySize);
    final d = ByteData.sublistView(out);

    d.setUint32(baseOffset + 0, face.flavor);
    d.setUint16(baseOffset + 4, numTables);
    final entry = _searchRange(numTables);
    d.setUint16(baseOffset + 6, entry.range);
    d.setUint16(baseOffset + 8, entry.selector);
    d.setUint16(baseOffset + 10, 16 * numTables - entry.range);

    var offset = baseOffset + dirSize;
    for (var i = 0; i < numTables; i++) {
      final tag = tags[i];
      final data = face.tables[tag]!;
      final rec = baseOffset + 12 + 16 * i;
      _writeTag(d, rec, tag);
      d.setUint32(rec + 4, _tableChecksum(data));
      d.setUint32(rec + 8, offset);
      d.setUint32(rec + 12, data.length);
      out.setAll(offset, data);
      offset += (data.length + 3) & ~3;
    }
    return out;
  }

  // ------------------------------------------------------------------ woff

  static const _woffTag = 0x774F4646; // 'wOFF'

  /// Inflates a WOFF 1.0 file back into a face. The spec is honoured
  /// strictly: overlapping or out-of-range blocks are rejected, and a table
  /// whose compressed size is not smaller than its original size is stored
  /// raw, exactly as the encoder is required to have written it.
  static _SfntFace _parseWoff(Uint8List bytes) {
    final d = ByteData.sublistView(bytes);
    if (bytes.length < 44 || d.getUint32(0) != _woffTag) {
      throw ConversionException(_corruptMessage());
    }
    final flavor = d.getUint32(4);
    final numTables = d.getUint16(12);
    final totalSfntSize = d.getUint32(16);
    if (totalSfntSize < 12 + 16 * numTables) throw ConversionException(_corruptMessage());

    final tables = <String, Uint8List>{};
    final decoder = ZLibDecoder();
    for (var i = 0; i < numTables; i++) {
      final rec = 44 + 20 * i;
      if (rec + 20 > bytes.length) throw ConversionException(_corruptMessage());
      final tableOffset = d.getUint32(rec + 4);
      final compLength = d.getUint32(rec + 8);
      final origLength = d.getUint32(rec + 12);
      if (tableOffset + compLength > bytes.length) {
        throw ConversionException(_corruptMessage());
      }

      final Uint8List data;
      if (compLength < origLength) {
        try {
          data = Uint8List.fromList(
            decoder.decodeBytes(Uint8List.sublistView(bytes, tableOffset, tableOffset + compLength)),
          );
        } catch (_) {
          throw ConversionException('This WOFF font could not be decompressed.');
        }
        if (data.length != origLength) throw ConversionException(_corruptMessage());
      } else {
        data = Uint8List.sublistView(bytes, tableOffset, tableOffset + origLength);
      }
      tables[_tag(d, rec)] = data;
    }
    if (tables.isEmpty) throw ConversionException(_corruptMessage());
    return (flavor: flavor, tables: tables);
  }

  /// Packs a face into WOFF 1.0: each table is deflated and only kept that
  /// way when it is actually smaller. No metadata or private block is
  /// carried across, so those header fields stay zero.
  static Uint8List _packWoff(_SfntFace face) {
    final tags = face.tables.keys.toList()..sort();
    final numTables = tags.length;
    final dirSize = 12 + 16 * numTables;

    final encoder = ZLibEncoder();
    final stored = <String, Uint8List>{};
    var totalSfntSize = dirSize;
    for (final t in tags) {
      final data = face.tables[t]!;
      final packed = Uint8List.fromList(encoder.encode(data));
      stored[t] = packed.length < data.length ? packed : data;
      totalSfntSize += (data.length + 3) & ~3;
    }

    // Layout pass: every table offset must be a multiple of four, so padding
    // goes between tables (never after the last one — data beyond the final
    // block makes the file invalid).
    final offsets = <String, int>{};
    var offset = 44 + 20 * numTables;
    for (var i = 0; i < numTables; i++) {
      final tag = tags[i];
      offsets[tag] = (offset + 3) & ~3;
      offset = offsets[tag]! + stored[tag]!.length;
    }

    final out = Uint8List(offset);
    final d = ByteData.sublistView(out);
    d.setUint32(0, _woffTag);
    d.setUint32(4, face.flavor);
    d.setUint32(8, out.length); // total WOFF length
    d.setUint16(12, numTables);
    d.setUint16(14, 0); // reserved
    d.setUint32(16, totalSfntSize);
    d.setUint16(20, 1); // majorVersion
    d.setUint16(22, 0); // minorVersion

    for (var i = 0; i < numTables; i++) {
      final tag = tags[i];
      final data = stored[tag]!;
      final original = face.tables[tag]!;
      final rec = 44 + 20 * i;
      _writeTag(d, rec, tag);
      d.setUint32(rec + 4, offsets[tag]!);
      d.setUint32(rec + 8, data.length);
      d.setUint32(rec + 12, original.length);
      d.setUint32(rec + 16, _tableChecksum(original));
      out.setAll(offsets[tag]!, data);
    }
    return out;
  }

  // -------------------------------------------------------------- guards

  /// The requested extension must not claim an outline format the face does
  /// not carry — 'OTTO' is CFF, anything else here is TrueType glyf.
  static void _checkFlavor(int flavor, String toExt) {
    final isCff = flavor == _otto;
    final wantsCff = toExt == 'otf';
    if (isCff != wantsCff) {
      throw ConversionException(
        'This font contains ${isCff ? 'CFF' : 'TrueType'} outlines, so it cannot be '
        'written as ${toExt.toUpperCase()}. Convert it to ${isCff ? 'OTF' : 'TTF'} instead.',
      );
    }
  }

  // ------------------------------------------------------------- messages

  static String _shortMessage() =>
      'This font file is too small to hold any font data. It may be corrupt or incomplete.';

  static String _corruptMessage() =>
      'This font could not be opened. It may be corrupt, or use an unsupported structure.';
}
