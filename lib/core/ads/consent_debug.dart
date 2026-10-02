import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Switches for exercising the consent form without being in the EEA.
///
/// The consent form is the one part of the ad stack that cannot be seen from
/// where this app is built: a device in India is never asked, so "the form
/// works" would otherwise be an assumption. The consent SDK's answer is a debug
/// geography, which only applies to devices named in `testIdentifiers` — so
/// both switches go together, and both are read at compile time:
///
/// ```
/// flutter run \
///   --dart-define=ONEKIT_CONSENT_GEOGRAPHY=eea \
///   --dart-define=ONEKIT_CONSENT_TEST_IDS=ABCDEF0123456789
/// ```
///
/// The identifiers are the device's advertising ID, which the phone shows under
/// **Settings → Google → Ads**. A physical device needs one because a debug
/// geography is ignored on a device the SDK cannot recognise; that is Google
/// refusing to let a release build be pushed into a consent state that is not
/// its own.
///
/// `ONEKIT_CONSENT_RESET=true` clears whatever this device answered last, so the
/// form appears again on the next launch.
///
/// All three fold away in release builds: `kReleaseMode` is a compile-time
/// constant, so the branches below are gone before the code is compiled and the
/// strings never reach the binary. `tool/release_check.dart` greps the built
/// bundle for them and expects nothing.
class ConsentDebug {
  ConsentDebug._();

  static const _geography = String.fromEnvironment('ONEKIT_CONSENT_GEOGRAPHY');
  static const _testIdentifiers = String.fromEnvironment('ONEKIT_CONSENT_TEST_IDS');
  static const _reset = bool.fromEnvironment('ONEKIT_CONSENT_RESET');

  /// The debug settings to hand the consent SDK, or null when this build wants
  /// the real answer.
  static ConsentDebugSettings? settings() {
    if (kReleaseMode) return null;

    final identifiers = [
      for (final id in _testIdentifiers.split(','))
        if (id.trim().isNotEmpty) id.trim(),
    ];
    final geography = switch (_geography) {
      'eea' => DebugGeography.debugGeographyEea,
      'us' => DebugGeography.debugGeographyRegulatedUsState,
      'other' => DebugGeography.debugGeographyOther,
      _ => null,
    };

    if (geography == null && identifiers.isEmpty) return null;
    return ConsentDebugSettings(debugGeography: geography, testIdentifiers: identifiers);
  }

  /// Whether the stored answer should be thrown away before the next form is
  /// requested.
  static bool get resetRequested => !kReleaseMode && _reset;
}
