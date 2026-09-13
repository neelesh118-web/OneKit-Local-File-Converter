/// AdMob unit identifiers.
///
/// Kept in one file so the production IDs can be swapped without touching any
/// widget. In debug builds Google's public test units are used instead, which
/// is what keeps the real account clear of invalid-traffic strikes during
/// development.
library;

import 'package:flutter/foundation.dart';

class AdIds {
  AdIds._();

  /// Declared in AndroidManifest.xml as com.google.android.gms.ads.APPLICATION_ID.
  static const androidAppId = 'ca-app-pub-2489505475567649~2600183490';

  static const _testBanner = 'ca-app-pub-3940256099942544/6300978111';
  static const _testInterstitial = 'ca-app-pub-3940256099942544/1033173712';
  static const _testNative = 'ca-app-pub-3940256099942544/2247696110';
  static const _testRewarded = 'ca-app-pub-3940256099942544/5224354917';
  static const _testAppOpen = 'ca-app-pub-3940256099942544/9257395921';

  static const _banner = 'ca-app-pub-2489505475567649/7225824219';
  static const _interstitial = 'ca-app-pub-2489505475567649/5936793275';
  static const _native = 'ca-app-pub-2489505475567649/1095530132';
  static const _rewarded = 'ca-app-pub-2489505475567649/6329394147';
  static const _appOpen = 'ca-app-pub-2489505475567649/9684466592';

  static String get banner => kDebugMode ? _testBanner : _banner;
  static String get interstitial => kDebugMode ? _testInterstitial : _interstitial;
  static String get native => kDebugMode ? _testNative : _native;
  static String get rewarded => kDebugMode ? _testRewarded : _rewarded;
  static String get appOpen => kDebugMode ? _testAppOpen : _appOpen;
}
