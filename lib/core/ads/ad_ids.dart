/// AdMob unit identifiers.
///
/// Kept in one file so the production IDs can be swapped without touching any
/// widget. In debug builds Google's public test units are used instead, which
/// is what keeps the real account clear of invalid-traffic strikes during
/// development — a test unit is a unit Google expects to be clicked, so a
/// mis-tap during development costs nothing.
library;

import 'package:flutter/foundation.dart';

/// The formats this app asks AdMob for.
///
/// One unit per format rather than one per placement. A converter shows the
/// same banner on seven screens, and splitting that into seven units would
/// produce seven near-identical rows in the console and no decision anyone
/// could act on; a single unit per format still tells us which *format* earns,
/// which is the question worth asking. A placement that ever needs to be
/// switched off on its own is the moment to split, and not before.
enum AdFormat { banner, interstitial, native, rewarded, appOpen }

class AdIds {
  AdIds._();

  /// The account every number below belongs to, and the one the store listing
  /// and the privacy policy name.
  static const account = 'ca-app-pub-2489505475567649';

  /// Google's own sample account. Its units always fill, which is why they are
  /// what a debug build requests: they make the ad plumbing visible without
  /// putting a request on the real account.
  static const demoAccount = 'ca-app-pub-3940256099942544';

  /// Declared in AndroidManifest.xml as
  /// `com.google.android.gms.ads.APPLICATION_ID`. Unlike the units this cannot
  /// be chosen at runtime — the SDK reads it from the manifest before any Dart
  /// code runs — so a build with the wrong one is a build with no ads at all.
  static const androidAppId = '$account~2600183490';

  static const _production = <AdFormat, String>{
    AdFormat.banner: '$account/7225824219',
    AdFormat.interstitial: '$account/5936793275',
    AdFormat.native: '$account/1095530132',
    AdFormat.rewarded: '$account/6329394147',
    AdFormat.appOpen: '$account/9684466592',
  };

  static const _demo = <AdFormat, String>{
    AdFormat.banner: '$demoAccount/6300978111',
    AdFormat.interstitial: '$demoAccount/1033173712',
    AdFormat.native: '$demoAccount/2247696110',
    AdFormat.rewarded: '$demoAccount/5224354917',
    AdFormat.appOpen: '$demoAccount/9257395921',
  };

  /// The unit to request for [format] in this build.
  ///
  /// `kDebugMode` is a compile-time constant, so a release build folds this to
  /// the production map and the demo units are not in the binary at all — which
  /// is checked, not assumed: `tool/release_check.dart` greps the built AAB for
  /// the sample account and expects to find nothing.
  static String unit(AdFormat format) => (kDebugMode ? _demo : _production)[format]!;

  static String get banner => unit(AdFormat.banner);
  static String get interstitial => unit(AdFormat.interstitial);
  static String get native => unit(AdFormat.native);
  static String get rewarded => unit(AdFormat.rewarded);
  static String get appOpen => unit(AdFormat.appOpen);

  /// Both tables, for the tests that hold them to their accounts and to the
  /// manifest. Nothing at runtime reads these.
  @visibleForTesting
  static Map<AdFormat, String> get productionUnits => _production;

  @visibleForTesting
  static Map<AdFormat, String> get demoUnits => _demo;
}
