import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../theme/app_theme.dart';
import 'ad_ids.dart';

/// Ad policy, deliberately restrained.
///
/// One anchored banner on the main surfaces, and an interstitial only after
/// every [_interstitialEveryNConversions]th conversion with a hard cooldown.
/// Nothing interrupts a conversion in progress, and nothing is shown on the
/// splash. If an ad fails to load the space collapses rather than reserving a
/// grey box.
class AdManager extends ChangeNotifier {
  AdManager._();
  static final AdManager instance = AdManager._();

  static const _interstitialEveryNConversions = 3;
  static const _interstitialCooldown = Duration(minutes: 2);

  bool _initialised = false;
  bool _adsRemoved = false;
  int _conversionsSinceAd = 0;
  DateTime? _lastInterstitial;

  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;

  bool get enabled => _initialised && !_adsRemoved;

  /// Set when the user supports the app; suppresses every ad surface.
  bool get adsRemoved => _adsRemoved;
  set adsRemoved(bool v) {
    _adsRemoved = v;
    if (v) {
      _interstitial?.dispose();
      _interstitial = null;
    }
    notifyListeners();
  }

  Future<void> initialize() async {
    if (_initialised) return;
    debugPrint('[AdManager] Initializing AdMob...');
    try {
      await MobileAds.instance.initialize();
      _initialised = true;
      debugPrint('[AdManager] AdMob initialized successfully');
      _preloadInterstitial();
      notifyListeners();
    } catch (e) {
      // The app is fully usable without ads; never let this block startup.
      debugPrint('[AdManager] AdMob init failed: $e');
    }
  }

  void _preloadInterstitial() {
    if (!enabled || _interstitial != null || _loadingInterstitial) return;
    _loadingInterstitial = true;
    InterstitialAd.load(
      adUnitId: AdIds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingInterstitial = false;
          _interstitial = ad;
        },
        onAdFailedToLoad: (err) {
          _loadingInterstitial = false;
          _interstitial = null;
        },
      ),
    );
  }

  /// Called once per finished batch, not once per file: converting 40 images
  /// should not mean 13 interstitials.
  Future<void> onBatchComplete(BuildContext context) async {
    if (!enabled) return;
    _conversionsSinceAd++;
    if (_conversionsSinceAd < _interstitialEveryNConversions) {
      _preloadInterstitial();
      return;
    }
    final last = _lastInterstitial;
    if (last != null && DateTime.now().difference(last) < _interstitialCooldown) return;

    final ad = _interstitial;
    if (ad == null) {
      _preloadInterstitial();
      return;
    }

    _interstitial = null;
    _conversionsSinceAd = 0;
    _lastInterstitial = DateTime.now();

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, _) {
        ad.dispose();
        _preloadInterstitial();
      },
    );
    await ad.show();
  }

  @override
  void dispose() {
    _interstitial?.dispose();
    super.dispose();
  }
}

/// An anchored adaptive banner that occupies no space until it has actually
/// loaded, so the layout never shows an empty reserved slot.
class AppBanner extends StatefulWidget {
  const AppBanner({super.key, this.padded = true});

  final bool padded;

  @override
  State<AppBanner> createState() => _AppBannerState();
}

class _AppBannerState extends State<AppBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    // Listen for AdManager initialization to reload when ads become available.
    AdManager.instance.addListener(_onAdManagerChanged);
  }

  @override
  void dispose() {
    AdManager.instance.removeListener(_onAdManagerChanged);
    _ad?.dispose();
    super.dispose();
  }

  void _onAdManagerChanged() {
    if (AdManager.instance.enabled && !_loaded && _ad == null) {
      _load();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    _load();
  }

  Future<void> _load() async {
    if (!AdManager.instance.enabled) {
      debugPrint('[AdBanner] AdManager not enabled');
      return;
    }
    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted) {
      debugPrint('[AdBanner] AdSize null or unmounted');
      return;
    }

    debugPrint('[AdBanner] Loading banner: ${AdIds.banner}');
    final ad = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          debugPrint('[AdBanner] Ad loaded successfully');
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[AdBanner] Ad failed to load: ${error.message}');
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    final t = context.tokens;
    return Container(
      alignment: Alignment.center,
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      margin: widget.padded ? const EdgeInsets.symmetric(vertical: 8) : EdgeInsets.zero,
      decoration: BoxDecoration(
        border: Border.all(color: t.border),
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: AdWidget(ad: ad),
    );
  }
}
