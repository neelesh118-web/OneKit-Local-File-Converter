import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User preferences, persisted locally. Nothing here ever leaves the device.
class SettingsStore extends ChangeNotifier {
  SettingsStore._(this._prefs);

  static const _kThemeMode = 'theme_mode';
  static const _kStarfield = 'starfield_enabled';
  static const _kImageQuality = 'image_quality';
  static const _kKeepOriginals = 'keep_originals';
  static const _kOutputDir = 'output_dir';
  static const _kSaveToGallery = 'save_to_gallery';
  static const _kOnboarded = 'onboarded';
  static const _kConversionCount = 'conversion_count';
  static const _kRated = 'rated';

  final SharedPreferences _prefs;

  static Future<SettingsStore> load() async {
    return SettingsStore._(await SharedPreferences.getInstance());
  }

  ThemeMode get themeMode => switch (_prefs.getString(_kThemeMode)) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  Future<void> setThemeMode(ThemeMode m) async {
    await _prefs.setString(_kThemeMode, m.name);
    notifyListeners();
  }

  bool get starfieldEnabled => _prefs.getBool(_kStarfield) ?? true;
  Future<void> setStarfieldEnabled(bool v) async {
    await _prefs.setBool(_kStarfield, v);
    notifyListeners();
  }

  /// JPEG/WebP encoder quality, 1-100.
  int get imageQuality => _prefs.getInt(_kImageQuality) ?? 90;
  Future<void> setImageQuality(int v) async {
    await _prefs.setInt(_kImageQuality, v.clamp(1, 100));
    notifyListeners();
  }

  bool get keepOriginals => _prefs.getBool(_kKeepOriginals) ?? true;
  Future<void> setKeepOriginals(bool v) async {
    await _prefs.setBool(_kKeepOriginals, v);
    notifyListeners();
  }

  String? get outputDir => _prefs.getString(_kOutputDir);
  Future<void> setOutputDir(String? v) async {
    if (v == null) {
      await _prefs.remove(_kOutputDir);
    } else {
      await _prefs.setString(_kOutputDir, v);
    }
    notifyListeners();
  }

  /// Whether a finished conversion is also copied into the phone's own Gallery
  /// and Downloads folders.
  ///
  /// On by default. The app's own folder is the only place it may write without
  /// asking for a permission, and it is also a folder no other app shows, so a
  /// converted photo is findable only from inside OneKit — which is not where
  /// anyone looks. Off leaves every result inside the app.
  bool get saveToGallery => _prefs.getBool(_kSaveToGallery) ?? true;
  Future<void> setSaveToGallery(bool v) async {
    await _prefs.setBool(_kSaveToGallery, v);
    notifyListeners();
  }

  bool get onboarded => _prefs.getBool(_kOnboarded) ?? false;
  Future<void> setOnboarded(bool v) async {
    await _prefs.setBool(_kOnboarded, v);
    notifyListeners();
  }

  /// Drives the "enjoying the app?" prompt without nagging on every launch.
  int get conversionCount => _prefs.getInt(_kConversionCount) ?? 0;
  Future<void> bumpConversionCount([int by = 1]) async {
    await _prefs.setInt(_kConversionCount, conversionCount + by);
    notifyListeners();
  }

  bool get rated => _prefs.getBool(_kRated) ?? false;
  Future<void> setRated(bool v) async {
    await _prefs.setBool(_kRated, v);
    notifyListeners();
  }
}
