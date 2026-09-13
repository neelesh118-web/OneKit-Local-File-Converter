import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../format.dart';
import '../job.dart';
import 'converter.dart';
import 'data_converter.dart';
import 'document_converter.dart';

/// One timed caption.
class Cue {
  const Cue(this.start, this.end, this.text);
  final Duration start;
  final Duration end;
  final String text;
}

/// Subtitle conversion. Every format is parsed into [Cue]s and written back
/// out, so all ten formats interconvert without bespoke pairings.
class SubtitleConverter extends FileConverter {
  const SubtitleConverter();

  @override
  String get name => 'Subtitle';

  @override
  bool supports(FileFormat from, FileFormat to) =>
      from.family == Family.subtitle &&
      (to.family == Family.subtitle || to.family == Family.data || to.family == Family.document);

  @override
  Future<void> convert(ConvertRequest r) async {
    r.onProgress(0.15, indeterminate: false);
    final text = await File(r.inputPath).readAsString();
    final cues = parse(text, r.from.ext);
    r.cancel.throwIfCancelled();

    if (cues.isEmpty) {
      throw ConversionException('No subtitle cues were found in this file.');
    }
    r.onProgress(0.6, indeterminate: false);

    final String out;
    if (r.to.family == Family.data) {
      out = DataConverter.serialize([
        for (final c in cues)
          {
            'start': _srtTime(c.start),
            'end': _srtTime(c.end),
            'startMs': c.start.inMilliseconds,
            'endMs': c.end.inMilliseconds,
            'text': c.text,
          },
      ], r.to.ext);
    } else if (r.to.family == Family.document) {
      final blocks = [for (final c in cues) DocBlock('p', c.text)];
      if (r.to.ext == 'pdf') {
        await File(r.outputPath).writeAsBytes(await DocumentConverter.buildPdf(blocks), flush: true);
        r.onProgress(1.0, indeterminate: false);
        return;
      }
      out = DocumentConverter.writeBlocks(blocks, r.to.ext);
    } else {
      out = write(cues, r.to.ext);
    }

    await File(r.outputPath).writeAsString(out, flush: true);
    r.onProgress(1.0, indeterminate: false);
  }

  // ------------------------------------------------------------------ read

  static List<Cue> parse(String text, String ext) {
    final s = text.replaceAll('\r\n', '\n').replaceAll('﻿', '');
    return switch (ext) {
      'srt' => _parseSrt(s),
      'vtt' => _parseVtt(s),
      'ass' || 'ssa' => _parseAss(s),
      'sbv' => _parseSbv(s),
      'sub' => _parseMicroDvd(s),
      'lrc' => _parseLrc(s),
      'ttml' || 'dfxp' => _parseTtml(s),
      'smi' => _parseSami(s),
      _ => throw ConversionException('This app cannot read ${ext.toUpperCase()} subtitles.'),
    };
  }

  static final _srtTimeRe = RegExp(
      r'(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})\s*-->\s*(\d{1,2}):(\d{2}):(\d{2})[,.](\d{1,3})');

  static List<Cue> _parseSrt(String s) {
    final cues = <Cue>[];
    for (final block in s.split(RegExp(r'\n\s*\n'))) {
      final lines = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;
      final idx = lines.indexWhere((l) => _srtTimeRe.hasMatch(l));
      if (idx < 0) continue;
      final m = _srtTimeRe.firstMatch(lines[idx])!;
      cues.add(Cue(_fromGroups(m, 1), _fromGroups(m, 5), lines.skip(idx + 1).join('\n').trim()));
    }
    return cues;
  }

  static List<Cue> _parseVtt(String s) {
    // WEBVTT headers, NOTE blocks and cue identifiers are all skipped by the
    // same timing-line search used for SRT.
    return _parseSrt(s.replaceFirst(RegExp(r'^WEBVTT.*?(\n\n|\Z)', dotAll: true), ''));
  }

  static Duration _fromGroups(RegExpMatch m, int base) {
    final ms = m.group(base + 3)!.padRight(3, '0');
    return Duration(
      hours: int.parse(m.group(base)!),
      minutes: int.parse(m.group(base + 1)!),
      seconds: int.parse(m.group(base + 2)!),
      milliseconds: int.parse(ms),
    );
  }

  static List<Cue> _parseAss(String s) {
    final cues = <Cue>[];
    var textIndex = 9;
    for (final line in const LineSplitter().convert(s)) {
      if (line.startsWith('Format:') && line.contains('Text')) {
        textIndex = line.substring(7).split(',').map((e) => e.trim()).toList().indexOf('Text');
      }
      if (!line.startsWith('Dialogue:')) continue;
      final parts = line.substring(9).split(',');
      if (parts.length < 3) continue;
      final start = _parseAssTime(parts[1].trim());
      final end = _parseAssTime(parts[2].trim());
      if (start == null || end == null) continue;
      // Everything from the Text column onward is the caption; commas inside it
      // must not be treated as column separators.
      final body = parts.skip(textIndex < 0 ? 9 : textIndex).join(',');
      cues.add(Cue(start, end, _stripAssTags(body)));
    }
    return cues;
  }

  static Duration? _parseAssTime(String t) {
    final m = RegExp(r'(\d+):(\d{2}):(\d{2})[.,](\d{1,3})').firstMatch(t);
    if (m == null) return null;
    return Duration(
      hours: int.parse(m.group(1)!),
      minutes: int.parse(m.group(2)!),
      seconds: int.parse(m.group(3)!),
      milliseconds: int.parse(m.group(4)!.padRight(3, '0')),
    );
  }

  static String _stripAssTags(String s) =>
      s.replaceAll(RegExp(r'\{[^}]*\}'), '').replaceAll(RegExp(r'\\[Nnh]'), '\n').trim();

  static List<Cue> _parseSbv(String s) {
    final cues = <Cue>[];
    final re = RegExp(r'(\d+):(\d{2}):(\d{2})\.(\d{3}),(\d+):(\d{2}):(\d{2})\.(\d{3})');
    for (final block in s.split(RegExp(r'\n\s*\n'))) {
      final lines = block.split('\n').where((l) => l.trim().isNotEmpty).toList();
      if (lines.isEmpty) continue;
      final m = re.firstMatch(lines.first);
      if (m == null) continue;
      cues.add(Cue(_fromGroups(m, 1), _fromGroups(m, 5), lines.skip(1).join('\n').trim()));
    }
    return cues;
  }

  /// MicroDVD stores frame numbers. Without the source video we assume 23.976,
  /// the most common case, and the timing note is surfaced in the UI.
  static List<Cue> _parseMicroDvd(String s, {double fps = 23.976}) {
    final cues = <Cue>[];
    final re = RegExp(r'^\{(\d+)\}\{(\d+)\}(.*)$');
    for (final line in const LineSplitter().convert(s)) {
      final m = re.firstMatch(line.trim());
      if (m == null) continue;
      // MicroDVD files may open with a {1}{1}<fps> header. It is metadata, not
      // a caption, so it must not come back as a cue on the round trip.
      if (m.group(1) == '1' && m.group(2) == '1' && double.tryParse(m.group(3)!.trim()) != null) {
        continue;
      }
      Duration at(String frame) =>
          Duration(milliseconds: (int.parse(frame) / fps * 1000).round());
      cues.add(Cue(
        at(m.group(1)!),
        at(m.group(2)!),
        m.group(3)!.replaceAll('|', '\n').replaceAll(RegExp(r'\{[^}]*\}'), '').trim(),
      ));
    }
    return cues;
  }

  /// LRC has no end times; each line runs until the next one starts.
  static List<Cue> _parseLrc(String s) {
    final entries = <(Duration, String)>[];
    final re = RegExp(r'\[(\d{1,2}):(\d{2})(?:[.:](\d{1,3}))?\]');
    for (final line in const LineSplitter().convert(s)) {
      final matches = re.allMatches(line).toList();
      if (matches.isEmpty) continue;
      final text = line.substring(matches.last.end).trim();
      for (final m in matches) {
        entries.add((
          Duration(
            minutes: int.parse(m.group(1)!),
            seconds: int.parse(m.group(2)!),
            milliseconds: int.parse((m.group(3) ?? '0').padRight(3, '0')),
          ),
          text,
        ));
      }
    }
    entries.sort((a, b) => a.$1.compareTo(b.$1));
    return [
      for (var i = 0; i < entries.length; i++)
        if (entries[i].$2.isNotEmpty)
          Cue(
            entries[i].$1,
            i + 1 < entries.length ? entries[i + 1].$1 : entries[i].$1 + const Duration(seconds: 4),
            entries[i].$2,
          ),
    ];
  }

  static List<Cue> _parseTtml(String s) {
    final doc = XmlDocument.parse(s);
    final cues = <Cue>[];
    for (final p in doc.findAllElements('p', namespace: '*')) {
      final begin = _parseClock(p.getAttribute('begin') ?? '');
      final end = _parseClock(p.getAttribute('end') ?? '');
      if (begin == null) continue;
      final text = p.innerXml
          .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
          .replaceAll(RegExp(r'<[^>]+>'), '')
          .trim();
      cues.add(Cue(begin, end ?? begin + const Duration(seconds: 3), _unescape(text)));
    }
    return cues;
  }

  static Duration? _parseClock(String v) {
    if (v.isEmpty) return null;
    final clock = RegExp(r'^(\d+):(\d{2}):(\d{2})(?:[.:](\d+))?$').firstMatch(v);
    if (clock != null) {
      return Duration(
        hours: int.parse(clock.group(1)!),
        minutes: int.parse(clock.group(2)!),
        seconds: int.parse(clock.group(3)!),
        milliseconds: int.parse((clock.group(4) ?? '0').padRight(3, '0').substring(0, 3)),
      );
    }
    // Offset form: 12.5s / 400ms / 3m.
    final offset = RegExp(r'^([\d.]+)(h|m|s|ms|f)$').firstMatch(v);
    if (offset != null) {
      final n = double.parse(offset.group(1)!);
      return switch (offset.group(2)!) {
        'h' => Duration(milliseconds: (n * 3600000).round()),
        'm' => Duration(milliseconds: (n * 60000).round()),
        's' => Duration(milliseconds: (n * 1000).round()),
        'ms' => Duration(milliseconds: n.round()),
        _ => Duration(milliseconds: (n / 24 * 1000).round()),
      };
    }
    return null;
  }

  static List<Cue> _parseSami(String s) {
    final cues = <Cue>[];
    final re = RegExp(r'<SYNC\s+Start\s*=\s*"?(\d+)"?[^>]*>(.*?)(?=<SYNC|</BODY)',
        caseSensitive: false, dotAll: true);
    final matches = re.allMatches(s).toList();
    for (var i = 0; i < matches.length; i++) {
      final start = Duration(milliseconds: int.parse(matches[i].group(1)!));
      // Unescape before trimming: SAMI marks the gap after a caption with a
      // &nbsp; block, which only reads as blank once the entity is resolved.
      final text = _unescape(matches[i]
              .group(2)!
              .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
              .replaceAll(RegExp(r'<[^>]+>'), ''))
          .trim();
      if (text.isEmpty) continue;
      // The end time is the next SYNC, which for a written-by-the app file is
      // exactly the blank block that follows this caption.
      final end = i + 1 < matches.length
          ? Duration(milliseconds: int.parse(matches[i + 1].group(1)!))
          : start + const Duration(seconds: 3);
      cues.add(Cue(start, end, text));
    }
    return cues;
  }

  static String _unescape(String s) => s
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');

  // ----------------------------------------------------------------- write

  static String write(List<Cue> cues, String ext) {
    return switch (ext) {
      'srt' => _writeSrt(cues),
      'vtt' => _writeVtt(cues),
      'ass' || 'ssa' => _writeAss(cues, ext == 'ass'),
      'sbv' => _writeSbv(cues),
      'sub' => _writeMicroDvd(cues),
      'lrc' => _writeLrc(cues),
      'ttml' || 'dfxp' => _writeTtml(cues),
      'smi' => _writeSami(cues),
      _ => throw ConversionException('This app cannot write ${ext.toUpperCase()} subtitles.'),
    };
  }

  static String _pad(int n, [int w = 2]) => n.toString().padLeft(w, '0');

  static String _srtTime(Duration d) =>
      '${_pad(d.inHours)}:${_pad(d.inMinutes % 60)}:${_pad(d.inSeconds % 60)},${_pad(d.inMilliseconds % 1000, 3)}';

  static String _vttTime(Duration d) => _srtTime(d).replaceFirst(',', '.');

  static String _writeSrt(List<Cue> cues) {
    final b = StringBuffer();
    for (var i = 0; i < cues.length; i++) {
      b
        ..writeln(i + 1)
        ..writeln('${_srtTime(cues[i].start)} --> ${_srtTime(cues[i].end)}')
        ..writeln(cues[i].text)
        ..writeln();
    }
    return b.toString();
  }

  static String _writeVtt(List<Cue> cues) {
    final b = StringBuffer('WEBVTT\n\n');
    for (final c in cues) {
      b
        ..writeln('${_vttTime(c.start)} --> ${_vttTime(c.end)}')
        ..writeln(c.text)
        ..writeln();
    }
    return b.toString();
  }

  static String _writeAss(List<Cue> cues, bool v4plus) {
    String t(Duration d) =>
        '${d.inHours}:${_pad(d.inMinutes % 60)}:${_pad(d.inSeconds % 60)}.${_pad(d.inMilliseconds % 1000 ~/ 10)}';

    final b = StringBuffer()
      ..writeln('[Script Info]')
      ..writeln('; Converted by Local File Converter')
      ..writeln('ScriptType: ${v4plus ? 'v4.00+' : 'v4.00'}')
      ..writeln('WrapStyle: 0')
      ..writeln('ScaledBorderAndShadow: yes')
      ..writeln()
      ..writeln('[${v4plus ? 'V4+ Styles' : 'V4 Styles'}]');

    if (v4plus) {
      b
        ..writeln('Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding')
        ..writeln('Style: Default,Arial,48,&H00FFFFFF,&H000000FF,&H00000000,&H00000000,0,0,0,0,100,100,0,0,1,2,1,2,10,10,20,1');
    } else {
      b
        ..writeln('Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, TertiaryColour, BackColour, Bold, Italic, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, AlphaLevel, Encoding')
        ..writeln('Style: Default,Arial,48,&HFFFFFF,&H0000FF,&H000000,&H000000,0,0,1,2,1,2,10,10,20,0,1');
    }

    b
      ..writeln()
      ..writeln('[Events]')
      ..writeln('Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text');
    for (final c in cues) {
      b.writeln('Dialogue: 0,${t(c.start)},${t(c.end)},Default,,0,0,0,,${c.text.replaceAll('\n', r'\N')}');
    }
    return b.toString();
  }

  static String _writeSbv(List<Cue> cues) {
    String t(Duration d) =>
        '${d.inHours}:${_pad(d.inMinutes % 60)}:${_pad(d.inSeconds % 60)}.${_pad(d.inMilliseconds % 1000, 3)}';
    final b = StringBuffer();
    for (final c in cues) {
      b
        ..writeln('${t(c.start)},${t(c.end)}')
        ..writeln(c.text)
        ..writeln();
    }
    return b.toString();
  }

  static String _writeMicroDvd(List<Cue> cues, {double fps = 23.976}) {
    final b = StringBuffer('{1}{1}$fps\n');
    for (final c in cues) {
      final s = (c.start.inMilliseconds / 1000 * fps).round();
      final e = (c.end.inMilliseconds / 1000 * fps).round();
      b.writeln('{$s}{$e}${c.text.replaceAll('\n', '|')}');
    }
    return b.toString();
  }

  static String _writeLrc(List<Cue> cues) {
    final b = StringBuffer('[re:LocalFileConverter]\n');
    for (final c in cues) {
      final m = c.start.inMinutes;
      final s = c.start.inSeconds % 60;
      final cs = c.start.inMilliseconds % 1000 ~/ 10;
      b.writeln('[${_pad(m)}:${_pad(s)}.${_pad(cs)}]${c.text.replaceAll('\n', ' ')}');
    }
    return b.toString();
  }

  static String _writeTtml(List<Cue> cues) {
    String t(Duration d) =>
        '${_pad(d.inHours)}:${_pad(d.inMinutes % 60)}:${_pad(d.inSeconds % 60)}.${_pad(d.inMilliseconds % 1000, 3)}';
    final b = StringBuffer()
      ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
      ..writeln('<tt xmlns="http://www.w3.org/ns/ttml" xml:lang="en">')
      ..writeln('  <body>')
      ..writeln('    <div>');
    for (final c in cues) {
      final text = c.text
          .replaceAll('&', '&amp;')
          .replaceAll('<', '&lt;')
          .replaceAll('>', '&gt;')
          .replaceAll('\n', '<br/>');
      b.writeln('      <p begin="${t(c.start)}" end="${t(c.end)}">$text</p>');
    }
    b
      ..writeln('    </div>')
      ..writeln('  </body>')
      ..writeln('</tt>');
    return b.toString();
  }

  static String _writeSami(List<Cue> cues) {
    final b = StringBuffer()
      ..writeln('<SAMI>')
      ..writeln('<HEAD><STYLE TYPE="text/css"><!--')
      ..writeln('P { margin-left: 8pt; margin-right: 8pt; font-family: Arial; text-align: center; }')
      ..writeln('--></STYLE></HEAD>')
      ..writeln('<BODY>');
    for (final c in cues) {
      b
        ..writeln('<SYNC Start=${c.start.inMilliseconds}><P>${c.text.replaceAll('\n', '<br>')}</P></SYNC>')
        ..writeln('<SYNC Start=${c.end.inMilliseconds}><P>&nbsp;</P></SYNC>');
    }
    b
      ..writeln('</BODY>')
      ..writeln('</SAMI>');
    return b.toString();
  }
}
