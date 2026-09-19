import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../engine/engine.dart';
import '../../engine/format.dart';
import '../../engine/job.dart';
import '../../engine/registry.dart';

/// A saved recipe: what a file should become, and the settings that go with it.
///
/// Deliberately not tied to a file. A preset answers "what do I always do with
/// photos?", so it can be run against whatever the user picks next — which is
/// why [targetExt] is a format *extension* rather than anything built from the
/// source. Null means Optimize: re-encode the file into its own format. There
/// is no representation for "JPG to JPG" here, for the same reason the
/// catalogue has no self-pairs — keeping every file's format is its own thing,
/// not a conversion.
@immutable
class ConversionPreset {
  const ConversionPreset({
    required this.id,
    required this.name,
    this.targetExt,
    this.options = const ConvertOptions(),
  });

  final String id;
  final String name;

  /// Null when this preset optimizes rather than converts.
  final String? targetExt;
  final ConvertOptions options;

  bool get isOptimize => targetExt == null;

  /// The format this preset converts into, or null when it keeps the source's.
  FileFormat? get target => targetExt == null ? null : FormatRegistry.byExt(targetExt!);

  /// The recipe in one line, in the same words a failure report uses for the
  /// same settings — one vocabulary for one thing.
  String get summary {
    final head = isOptimize
        ? 'Keep the format'
        : (target?.upper ?? targetExt!.toUpperCase());
    final settings = options.describe();
    return settings == 'defaults' ? head : '$head · $settings';
  }

  /// Whether this recipe can actually be run against [source].
  ///
  /// Asked of the engine rather than assumed, exactly as the conversion matrix
  /// and the batch queue ask it: a preset that cannot run is kept out of the
  /// chips instead of being offered and then failing.
  bool appliesTo(FileFormat source) {
    if (isOptimize) return ConversionEngine.instance.canOptimize(source);
    final to = target;
    return to != null && ConversionEngine.instance.canConvert(source, to);
  }

  ConversionPreset copyWith({String? name}) => ConversionPreset(
        id: id,
        name: name ?? this.name,
        targetExt: targetExt,
        options: options,
      );

  /// Only what was changed is written down, so the stored file stays readable
  /// and an option added in a later version simply defaults for an old preset.
  Map<String, Object?> toJson() {
    const base = ConvertOptions();
    return {
      'id': id,
      'name': name,
      if (targetExt != null) 'to': targetExt,
      'options': {
        if (options.quality != base.quality) 'quality': options.quality,
        if (options.width != null) 'width': options.width,
        if (options.height != null) 'height': options.height,
        if (options.audioBitrateKbps != null) 'audio': options.audioBitrateKbps,
        if (options.sampleRate != null) 'rate': options.sampleRate,
        if (options.videoCrf != null) 'crf': options.videoCrf,
        if (options.fps != null) 'fps': options.fps,
        if (options.stripMetadata) 'strip': true,
        if (options.pdfPageRange != null) 'pages': options.pdfPageRange,
        if (options.pdfDpi != base.pdfDpi) 'dpi': options.pdfDpi,
      },
    };
  }

  /// Reads one back, or null when the stored entry is not usable. Corrupt or
  /// half-written data costs the user that one preset, never the whole list and
  /// never a crash on launch.
  static ConversionPreset? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = raw['name'];
    if (id is! String || id.isEmpty || name is! String || name.trim().isEmpty) {
      return null;
    }
    final to = raw['to'];
    final options = raw['options'];
    return ConversionPreset(
      id: id,
      name: name,
      targetExt: to is String && to.isNotEmpty ? to : null,
      options: _optionsFrom(options is Map ? options : const {}),
    );
  }

  static ConvertOptions _optionsFrom(Map<Object?, Object?> m) {
    int? int_(String key) => m[key] is int ? m[key] as int : int.tryParse('${m[key]}');
    const base = ConvertOptions();
    return ConvertOptions(
      quality: int_('quality') ?? base.quality,
      width: int_('width'),
      height: int_('height'),
      audioBitrateKbps: int_('audio'),
      sampleRate: int_('rate'),
      videoCrf: int_('crf'),
      fps: int_('fps'),
      stripMetadata: m['strip'] == true,
      pdfPageRange: m['pages'] is String ? m['pages'] as String : null,
      pdfDpi: int_('dpi') ?? base.pdfDpi,
    );
  }
}

/// The user's saved recipes, in the order they were saved.
///
/// Stored as JSON in the same preferences file as the rest of the app's
/// settings, which is the right size for a handful of presets and needs no
/// schema of its own.
class PresetStore extends ChangeNotifier {
  PresetStore._(this._prefs, this._presets);

  static const _key = 'conversion_presets';

  /// Bumped for every preset made in this run. A timestamp alone is not enough
  /// to tell two apart: the clock's resolution on a phone can be a millisecond,
  /// so two presets saved in the same tick would share an id — and deleting one
  /// would delete both.
  static int _sequence = 0;

  final SharedPreferences _prefs;
  List<ConversionPreset> _presets;

  static Future<PresetStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return PresetStore._(prefs, _decode(prefs.getStringList(_key)));
  }

  static List<ConversionPreset> _decode(List<String>? raw) {
    if (raw == null) return [];
    final out = <ConversionPreset>[];
    for (final entry in raw) {
      try {
        final preset = ConversionPreset.tryFromJson(jsonDecode(entry));
        if (preset != null) out.add(preset);
      } catch (_) {
        // One unreadable entry is not worth losing the others over.
      }
    }
    return out;
  }

  List<ConversionPreset> get presets => List.unmodifiable(_presets);
  bool get isEmpty => _presets.isEmpty;

  /// Presets that can actually be run against [source], in saved order.
  List<ConversionPreset> forSource(FileFormat source) =>
      [for (final p in _presets) if (p.appliesTo(source)) p];

  ConversionPreset? byId(String id) =>
      _presets.where((p) => p.id == id).firstOrNull;

  /// Adds a preset, replacing any preset with the same name.
  ///
  /// Replacing rather than duplicating: saving the same recipe twice is a
  /// correction, and silently ending up with two identical chips would be a
  /// worse outcome than an overwrite the user can see.
  Future<ConversionPreset> save({
    required String name,
    required ConvertOptions options,
    String? targetExt,
  }) async {
    final trimmed = name.trim();
    final preset = ConversionPreset(
      id: _newId(),
      name: trimmed,
      targetExt: targetExt,
      options: options,
    );
    final at = _presets.indexWhere(
      (p) => p.name.toLowerCase() == trimmed.toLowerCase(),
    );
    if (at >= 0) {
      // Keep its place in the list: a preset the user has reached for a hundred
      // times should not move to the end because they changed its quality.
      _presets[at] = ConversionPreset(
        id: _presets[at].id,
        name: trimmed,
        targetExt: targetExt,
        options: options,
      );
    } else {
      _presets = [..._presets, preset];
    }
    await _persist();
    return _presets.firstWhere(
      (p) => p.name.toLowerCase() == trimmed.toLowerCase(),
      orElse: () => preset,
    );
  }

  Future<void> rename(String id, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final at = _presets.indexWhere((p) => p.id == id);
    if (at < 0) return;
    _presets[at] = _presets[at].copyWith(name: trimmed);
    await _persist();
  }

  Future<void> remove(String id) async {
    final before = _presets.length;
    _presets = [for (final p in _presets) if (p.id != id) p];
    if (_presets.length == before) return;
    await _persist();
  }

  /// An id no other preset in the list has, whatever the clock says.
  String _newId() {
    while (true) {
      final id = 'p${DateTime.now().microsecondsSinceEpoch}_${_sequence++}';
      if (_presets.every((p) => p.id != id)) return id;
    }
  }

  Future<void> _persist() async {
    await _prefs.setStringList(
      _key,
      [for (final p in _presets) jsonEncode(p.toJson())],
    );
    notifyListeners();
  }
}
