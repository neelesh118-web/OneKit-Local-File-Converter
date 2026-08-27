import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:csv/csv.dart';
import 'package:xml/xml.dart';
import 'package:yaml/yaml.dart';

import '../format.dart';
import '../job.dart';
import 'converter.dart';

/// Structured-data conversion (JSON / CSV / TSV / XML / YAML / INI / ...).
///
/// Every format is parsed into one canonical shape — either a list of rows
/// (tabular) or a free-form tree — and then serialised out. That keeps the
/// matrix an N-in / M-out problem instead of N x M bespoke converters.
class DataConverter extends FileConverter {
  const DataConverter();

  @override
  String get name => 'Structured Data';

  @override
  bool supports(FileFormat from, FileFormat to) =>
      from.family == Family.data && to.family == Family.data;

  @override
  Future<void> convert(ConvertRequest r) async {
    r.onProgress(0.1, indeterminate: false);
    final text = await File(r.inputPath).readAsString();
    r.cancel.throwIfCancelled();
    r.onProgress(0.4, indeterminate: false);

    // Locals only, never the request itself: an isolate message cannot carry
    // the progress callback or the CancelToken under AOT.
    final fromExt = r.from.ext;
    final toExt = r.to.ext;
    // A large CSV or JSON is pure CPU; parsing it inline froze the interface.
    final out = await Isolate.run(() => transcode(text, fromExt, toExt));

    r.cancel.throwIfCancelled();
    await File(r.outputPath).writeAsString(out, flush: true);
    r.onProgress(1.0, indeterminate: false);
  }

  /// Parse and re-serialise in one step, so a worker isolate only has to be
  /// handed two strings.
  static String transcode(String text, String fromExt, String toExt) =>
      serialize(parse(text, fromExt), toExt);

  // ------------------------------------------------------------------ parse

  /// Returns either `List<Map<String, dynamic>>` (tabular) or a JSON-like tree.
  static dynamic parse(String text, String ext) {
    switch (ext) {
      case 'json':
        return _decodeJson(text);
      case 'ndjson':
      case 'jsonl':
        return text
            .split('\n')
            .map((l) => l.trim())
            .where((l) => l.isNotEmpty)
            .map<dynamic>(_decodeJson)
            .toList();
      case 'csv':
        return _rowsToMaps(const CsvToListConverter(shouldParseNumbers: true, eol: '\n')
            .convert(text.replaceAll('\r\n', '\n')));
      case 'tsv':
        return _rowsToMaps(const CsvToListConverter(
          fieldDelimiter: '\t',
          shouldParseNumbers: true,
          eol: '\n',
        ).convert(text.replaceAll('\r\n', '\n')));
      case 'xml':
        return _xmlToValue(XmlDocument.parse(text).rootElement);
      case 'yaml':
      case 'yml':
        return _yamlToValue(loadYaml(text));
      case 'ini':
        return _parseIni(text);
      case 'properties':
        return _parseProperties(text);
      case 'toml':
        return _parseToml(text);
      default:
        throw ConversionException('OneKit cannot read ${ext.toUpperCase()} as data.');
    }
  }

  static dynamic _decodeJson(String text) {
    try {
      return jsonDecode(text);
    } on FormatException catch (e) {
      throw ConversionException('This file is not valid JSON.', detail: e.message);
    }
  }

  /// CSV/TSV arrive as a header row plus value rows.
  static List<Map<String, dynamic>> _rowsToMaps(List<List<dynamic>> rows) {
    if (rows.isEmpty) return const [];
    final header = rows.first.map((c) => c.toString()).toList();
    return [
      for (final row in rows.skip(1))
        {
          for (var i = 0; i < header.length; i++)
            header[i]: i < row.length ? row[i] : null,
        },
    ];
  }

  static dynamic _xmlToValue(XmlElement el) {
    final children = el.childElements.toList();
    if (children.isEmpty) {
      final t = el.innerText.trim();
      if (el.attributes.isEmpty) return t;
      return {
        for (final a in el.attributes) '@${a.name.local}': a.value,
        if (t.isNotEmpty) '#text': t,
      };
    }
    // Repeated sibling names collapse into a list, which is what makes
    // <rows><row/><row/></rows> round-trip to CSV correctly.
    final map = <String, dynamic>{
      for (final a in el.attributes) '@${a.name.local}': a.value,
    };
    for (final c in children) {
      final key = c.name.local;
      final v = _xmlToValue(c);
      if (map.containsKey(key)) {
        final existing = map[key];
        map[key] = existing is List ? [...existing, v] : [existing, v];
      } else {
        map[key] = v;
      }
    }
    if (map.length == 1) {
      final only = map.values.first;
      if (only is List) return only;
    }
    return map;
  }

  static dynamic _yamlToValue(dynamic node) {
    if (node is YamlMap) {
      return {for (final e in node.entries) e.key.toString(): _yamlToValue(e.value)};
    }
    if (node is YamlList) return node.map(_yamlToValue).toList();
    return node;
  }

  static Map<String, dynamic> _parseIni(String text) {
    final out = <String, dynamic>{};
    var section = '';
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith(';') || line.startsWith('#')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        section = line.substring(1, line.length - 1).trim();
        out.putIfAbsent(section, () => <String, dynamic>{});
        continue;
      }
      final i = line.indexOf('=');
      if (i < 0) continue;
      final k = line.substring(0, i).trim();
      final v = _coerce(line.substring(i + 1).trim());
      if (section.isEmpty) {
        out[k] = v;
      } else {
        (out[section] as Map<String, dynamic>)[k] = v;
      }
    }
    return out;
  }

  static Map<String, dynamic> _parseProperties(String text) {
    final out = <String, dynamic>{};
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#') || line.startsWith('!')) continue;
      final i = line.indexOf(RegExp(r'[=:]'));
      if (i < 0) continue;
      out[line.substring(0, i).trim()] = _coerce(line.substring(i + 1).trim());
    }
    return out;
  }

  /// A pragmatic TOML subset: tables, key/value pairs, inline arrays.
  static Map<String, dynamic> _parseToml(String text) {
    final out = <String, dynamic>{};
    Map<String, dynamic> table = out;
    for (final raw in const LineSplitter().convert(text)) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      if (line.startsWith('[') && line.endsWith(']')) {
        final path = line.substring(1, line.length - 1).replaceAll('[', '').replaceAll(']', '').split('.');
        table = out;
        for (final part in path) {
          table = (table.putIfAbsent(part.trim(), () => <String, dynamic>{}) as Map<String, dynamic>);
        }
        continue;
      }
      final i = line.indexOf('=');
      if (i < 0) continue;
      final k = line.substring(0, i).trim().replaceAll('"', '');
      final rawV = line.substring(i + 1).trim();
      if (rawV.startsWith('[') && rawV.endsWith(']')) {
        table[k] = rawV
            .substring(1, rawV.length - 1)
            .split(',')
            .map((e) => _coerce(e.trim()))
            .where((e) => e != '')
            .toList();
      } else {
        table[k] = _coerce(rawV);
      }
    }
    return out;
  }

  static dynamic _coerce(String v) {
    var s = v;
    if ((s.startsWith('"') && s.endsWith('"') && s.length >= 2) ||
        (s.startsWith("'") && s.endsWith("'") && s.length >= 2)) {
      return s.substring(1, s.length - 1);
    }
    if (s == 'true') return true;
    if (s == 'false') return false;
    if (s == 'null' || s == '~') return null;
    final n = num.tryParse(s);
    return n ?? s;
  }

  // -------------------------------------------------------------- serialize

  static String serialize(dynamic value, String ext) {
    switch (ext) {
      case 'json':
        return const JsonEncoder.withIndent('  ').convert(value);
      case 'ndjson':
      case 'jsonl':
        final rows = _asRows(value);
        return '${rows.map(jsonEncode).join('\n')}\n';
      case 'csv':
        return _toDelimited(value, ',');
      case 'tsv':
        return _toDelimited(value, '\t');
      case 'xml':
        return _toXml(value);
      case 'yaml':
      case 'yml':
        return _toYaml(value, 0);
      case 'ini':
        return _toIni(value);
      case 'properties':
        return _toProperties(value, '');
      case 'toml':
        return _toToml(value);
      case 'sql':
        return _toSql(value);
      default:
        throw ConversionException('OneKit cannot write ${ext.toUpperCase()} as data.');
    }
  }

  /// Coerces any parsed value into a row list so tabular targets always work.
  static List<Map<String, dynamic>> _asRows(dynamic value) {
    if (value is List) {
      return [
        for (final e in value)
          if (e is Map) e.map((k, v) => MapEntry(k.toString(), v)) else {'value': e},
      ];
    }
    if (value is Map) {
      // A map of maps (common for INI/TOML) becomes one row per section.
      final entries = value.entries.toList();
      if (entries.isNotEmpty && entries.every((e) => e.value is Map)) {
        return [
          for (final e in entries)
            {'key': e.key.toString(), ...(e.value as Map).map((k, v) => MapEntry(k.toString(), v))},
        ];
      }
      return [value.map((k, v) => MapEntry(k.toString(), v))];
    }
    return [
      {'value': value}
    ];
  }

  static String _toDelimited(dynamic value, String delimiter) {
    final rows = _asRows(value);
    if (rows.isEmpty) return '';
    // Union of all keys, in first-seen order, so ragged records still line up.
    final header = <String>[];
    for (final r in rows) {
      for (final k in r.keys) {
        if (!header.contains(k)) header.add(k);
      }
    }
    final table = <List<dynamic>>[
      header,
      for (final r in rows) [for (final h in header) _flat(r[h])],
    ];
    return ListToCsvConverter(fieldDelimiter: delimiter, eol: '\n').convert(table);
  }

  /// Nested values cannot live in a cell, so they are inlined as JSON.
  static dynamic _flat(dynamic v) => (v is Map || v is List) ? jsonEncode(v) : v;

  static String _toXml(dynamic value) {
    final b = XmlBuilder();
    b.processing('xml', 'version="1.0" encoding="UTF-8"');
    b.element('root', nest: () => _xmlNode(b, value));
    return b.buildDocument().toXmlString(pretty: true, indent: '  ');
  }

  static void _xmlNode(XmlBuilder b, dynamic value) {
    if (value is Map) {
      for (final e in value.entries) {
        final key = _safeXmlName(e.key.toString());
        if (e.value is List) {
          for (final item in e.value as List) {
            b.element(key, nest: () => _xmlNode(b, item));
          }
        } else {
          b.element(key, nest: () => _xmlNode(b, e.value));
        }
      }
    } else if (value is List) {
      for (final item in value) {
        b.element('item', nest: () => _xmlNode(b, item));
      }
    } else if (value != null) {
      b.text(value.toString());
    }
  }

  static String _safeXmlName(String raw) {
    var s = raw.replaceAll(RegExp(r'[^A-Za-z0-9_.\-]'), '_');
    if (s.isEmpty || RegExp(r'^[^A-Za-z_]').hasMatch(s)) s = '_$s';
    return s;
  }

  static String _toYaml(dynamic value, int indent) {
    final pad = '  ' * indent;
    if (value is Map) {
      if (value.isEmpty) return '$pad{}\n';
      final b = StringBuffer();
      for (final e in value.entries) {
        final v = e.value;
        if (v is Map || v is List) {
          b.write('$pad${e.key}:\n${_toYaml(v, indent + 1)}');
        } else {
          b.write('$pad${e.key}: ${_yamlScalar(v)}\n');
        }
      }
      return b.toString();
    }
    if (value is List) {
      if (value.isEmpty) return '$pad[]\n';
      final b = StringBuffer();
      for (final v in value) {
        if (v is Map || v is List) {
          // Splice the child block in under the dash.
          final block = _toYaml(v, indent + 1);
          final lines = block.split('\n')..removeWhere((l) => l.isEmpty);
          b.write('$pad- ${lines.first.trimLeft()}\n');
          for (final l in lines.skip(1)) {
            b.write('$l\n');
          }
        } else {
          b.write('$pad- ${_yamlScalar(v)}\n');
        }
      }
      return b.toString();
    }
    return '$pad${_yamlScalar(value)}\n';
  }

  static String _yamlScalar(dynamic v) {
    if (v == null) return 'null';
    if (v is num || v is bool) return '$v';
    final s = v.toString();
    if (s.isEmpty || RegExp(r'[:#\-{}\[\]&*!|>%@`"' "'" r']').hasMatch(s) || s.trim() != s) {
      return jsonEncode(s);
    }
    return s;
  }

  static String _toIni(dynamic value) {
    final b = StringBuffer();
    final map = value is Map ? value : {'data': value};
    final scalars = map.entries.where((e) => e.value is! Map);
    for (final e in scalars) {
      b.writeln('${e.key}=${_flat(e.value)}');
    }
    for (final e in map.entries.where((e) => e.value is Map)) {
      b.writeln();
      b.writeln('[${e.key}]');
      for (final s in (e.value as Map).entries) {
        b.writeln('${s.key}=${_flat(s.value)}');
      }
    }
    return b.toString();
  }

  static String _toProperties(dynamic value, String prefix) {
    final b = StringBuffer();
    void walk(dynamic v, String path) {
      if (v is Map) {
        for (final e in v.entries) {
          walk(e.value, path.isEmpty ? '${e.key}' : '$path.${e.key}');
        }
      } else if (v is List) {
        for (var i = 0; i < v.length; i++) {
          walk(v[i], '$path.$i');
        }
      } else {
        b.writeln('$path=${v ?? ''}');
      }
    }

    walk(value, prefix);
    return b.toString();
  }

  static String _toToml(dynamic value) {
    final b = StringBuffer();
    final map = value is Map ? value : {'data': value};
    for (final e in map.entries.where((e) => e.value is! Map)) {
      b.writeln('${e.key} = ${_tomlScalar(e.value)}');
    }
    for (final e in map.entries.where((e) => e.value is Map)) {
      b.writeln();
      b.writeln('[${e.key}]');
      for (final s in (e.value as Map).entries) {
        b.writeln('${s.key} = ${_tomlScalar(s.value)}');
      }
    }
    return b.toString();
  }

  static String _tomlScalar(dynamic v) {
    if (v is num || v is bool) return '$v';
    if (v is List) return '[${v.map(_tomlScalar).join(', ')}]';
    return jsonEncode(v?.toString() ?? '');
  }

  static String _toSql(dynamic value) {
    final rows = _asRows(value);
    if (rows.isEmpty) return '-- no rows\n';
    final header = <String>[];
    for (final r in rows) {
      for (final k in r.keys) {
        if (!header.contains(k)) header.add(k);
      }
    }
    final table = 'converted_data';
    final b = StringBuffer()
      ..writeln('CREATE TABLE IF NOT EXISTS $table (')
      ..writeln(header.map((h) => '  "${_sqlIdent(h)}" TEXT').join(',\n'))
      ..writeln(');')
      ..writeln();
    for (final r in rows) {
      final values = header.map((h) => _sqlValue(r[h])).join(', ');
      b.writeln('INSERT INTO $table ("${header.map(_sqlIdent).join('", "')}") VALUES ($values);');
    }
    return b.toString();
  }

  static String _sqlIdent(String s) => s.replaceAll('"', '');

  static String _sqlValue(dynamic v) {
    if (v == null) return 'NULL';
    if (v is num || v is bool) return '$v';
    final s = _flat(v).toString().replaceAll("'", "''");
    return "'$s'";
  }
}
