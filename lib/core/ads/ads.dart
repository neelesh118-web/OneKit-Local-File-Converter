import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../background/background_task.dart';
import '../theme/app_theme.dart';
import 'ad_ids.dart';
import 'ad_policy.dart';
import 'consent.dart';
import 'consent_debug.dart';

/// Everything the app knows about advertising, behind one object.
///
/// The rules live in [AdPolicy] and the consent form in [AdConsent]; this is the
/// part that owns the SDK: it asks for each format once, keeps one of each
/// ready, and decides when one may appear. The shape of the policy is
/// deliberate:
///
/// * a banner on every screen, which is the only format that never interrupts;
/// * an interstitial after every third finished run at most, and never twice
///   within two minutes;
/// * an app-open ad when the app is opened cold — after waiting inside
///   [AdPolicy.appOpenShowWindow] for the ad it asked for — or come back to after minutes
///   away — never in the middle of a run, and never twice in an hour;
/// * a native card in the two long lists, which is the format that pays like a
///   banner but is meant to be looked at;
/// * a rewarded video the user can choose to watch, which buys an hour without
///   any of the above.
///
/// What is deliberately absent is as much a decision: no ad ever covers a
/// conversion that is running, no ad appears on the splash or the first-run
/// onboarding, and nothing here is allowed to fail loudly. Every load is
/// optional, and if an ad does not arrive the space simply is not there.
class AdManager extends ChangeNotifier with WidgetsBindingObserver {
  AdManager._();

  static final AdManager instance = AdManager._();

  /// Where the rewarded hour is remembered. It has to survive a restart: a
  /// reward that only lasts until the app is closed is not worth a video.
  static const _adFreeKey = 'ads_free_until';

  final InterstitialSchedule _interstitialSchedule = InterstitialSchedule();
  final AppOpenSchedule _appOpenSchedule = AppOpenSchedule();

  bool _started = false;
  bool _ready = false;
  bool _removed = false;
  bool _firstRunComplete = true;
  DateTime? _adFreeUntil;
  DateTime? _leftAt;
  Timer? _adFreeTimer;

  InterstitialAd? _interstitial;
  bool _loadingInterstitial = false;
  AppOpenAd? _appOpen;
  /// The app-open request that is in flight, resolved with the ad when it
  /// arrives and with null when the SDK has none — the answer a cold launch
  /// waits for, since at a launch there is never one in hand yet.
  Completer<AppOpenAd?>? _appOpenRequest;
  bool _loadingAppOpen = false;
  RewardedAd? _rewarded;
  bool _loadingRewarded = false;

  /// Whether an ad may be shown right now: the SDK is up, the user has not
  /// bought them out, and no rewarded hour is running.
  bool get enabled => _ready && !_removed && !adFree;

  /// Whether the SDK finished starting (consent settled, `MobileAds.initialize`
  /// returned). Distinct from [enabled], which also accounts for suppression.
  bool get ready => _ready;

  /// The user has removed ads for good. Nothing in the app sets this today —
  /// there is no purchase yet — but every surface already honours it.
  bool get adsRemoved => _removed;
  set adsRemoved(bool value) {
    if (_removed == value) return;
    _removed = value;
    if (value) {
      _interstitial?.dispose();
      _interstitial = null;
    }
    notifyListeners();
  }

  /// True while a rewarded hour is running.
  bool get adFree => isAdFreeUntil(_adFreeUntil, DateTime.now());

  DateTime? get adFreeUntil => _adFreeUntil;

  /// When the hour ends. Null unless [adFree].
  Duration? get adFreeRemaining {
    final until = _adFreeUntil;
    if (until == null) return null;
    final remaining = until.difference(DateTime.now());
    return remaining.isNegative ? null : remaining;
  }

  /// Whether the app has to offer a way back into the consent form, as Google's
  /// policy requires wherever the form was shown at all.
  bool get privacyOptionsRequired => AdConsent.instance.privacyOptionsRequired;

  /// Starts the ad stack: consent first, the SDK second.
  ///
  /// Called from the first frame of the app rather than from `main`, so nothing
  /// about the first paint waits on a network round trip, and so the consent
  /// form — where one is needed — never appears on top of a splash screen that
  /// has not drawn yet.
  ///
  /// [firstRunComplete] is the app's own onboarding flag: a first launch is
  /// where the app has to make its case, and an ad on top of it is a bad trade
  /// for one impression.
  Future<void> start({bool firstRunComplete = true}) async {
    if (_started) return;
    _started = true;
    _firstRunComplete = firstRunComplete;

    // The plugin is Android-only. A desktop build has no ad stack at all, and
    // asking for one would throw instead of answering.
    if (!Platform.isAndroid) return;

    _adFreeUntil = await _loadAdFreeUntil();
    if (adFree) _armAdFreeTimer();

    WidgetsBinding.instance.addObserver(this);

    if (ConsentDebug.resetRequested) await _resetConsent();
    await _settleConsent();
  }

  Future<void> _settleConsent() async {
    final result = await AdConsent.instance.gather(debugSettings: ConsentDebug.settings());
    debugPrint(
      '[AdManager] consent ${result.status.name}: canRequestAds=${result.canRequestAds}'
      '${result.formShown ? ' (form shown)' : ''}${result.error == null ? '' : ' error=${result.error}'}',
    );
    if (!result.canRequestAds) {
      // No ads this launch. Deliberately quiet: the app is complete without
      // them, and a second chance comes on the next resume.
      notifyListeners();
      return;
    }
    await _initialise();
  }

  Future<void> _resetConsent() async {
    try {
      await ConsentInformation.instance.reset();
      debugPrint('[AdManager] consent state cleared by ONEKIT_CONSENT_RESET');
    } catch (e) {
      debugPrint('[AdManager] consent reset failed: $e');
    }
  }

  Future<void> _initialise() async {
    if (_ready) return;
    try {
      await MobileAds.instance.initialize();
    } catch (e) {
      debugPrint('[AdManager] AdMob init failed: $e');
      return;
    }
    _ready = true;
    notifyListeners();
    _preloadInterstitial();
    _preloadAppOpen();
    _preloadRewarded();
  }

  /// The app was opened cold. Shows an app-open ad if one is ready and allowed.
  ///
  /// Called after the first frame, so the call itself never delays startup, and
  /// skipped entirely while a run is on screen: someone returning to a
  /// conversion in progress came back to look at it.
  ///
  /// This is the one moment where the ad cannot already be in hand: the request
  /// goes out when the SDK comes up, which is the same breath as this call. For
  /// as long as this method only looked for a loaded ad it therefore always
  /// found nothing at launch, and the answer it had asked for was spent on the
  /// next return instead — which is what build 5's device pass measured. So a
  /// launch waits here, inside [AdPolicy.appOpenShowWindow] and no longer, for
  /// the answer to the request it has already made, and then re-checks the rules
  /// that can have changed while it waited: an hour bought with a reward, a run
  /// that has started, or a return that showed an app-open ad in the meantime.
  /// Nothing allowed means nothing shown, and the ad stays in hand for the next
  /// return rather than being thrown away.
  Future<void> showAppOpenOnLaunch() async {
    if (!_firstRunComplete) return;
    if (!_appOpenSchedule.launchDue(DateTime.now())) return;

    // The wait is the whole fix: the SDK is fetching this ad right now, and a
    // launch is the only window in which it is worth having.
    if (await _appOpenWithin(AdPolicy.appOpenShowWindow) == null) return;

    // The wait was real, so the rules are re-checked against now rather than
    // against the moment the launch began.
    if (!enabled || !_appOpenSchedule.launchDue(DateTime.now())) return;
    await _showAppOpen();
  }

  /// A conversion, a batch or a PDF job finished.
  ///
  /// The only source of interstitials in the app, which is what keeps them off
  /// every other moment — including the middle of a run, where an ad would
  /// cover the progress the user is waiting on.
  Future<void> onRunFinished() async {
    if (!enabled) return;

    _interstitialSchedule.runFinished();
    final now = DateTime.now();
    if (!_interstitialSchedule.due(now)) {
      _preloadInterstitial();
      return;
    }

    final ad = _interstitial;
    if (ad == null) {
      _preloadInterstitial();
      return;
    }

    _interstitial = null;
    _interstitialSchedule.markedShown(now);
    ad.fullScreenContentCallback = FullScreenContentCallback<InterstitialAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadInterstitial();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[AdManager] interstitial failed to show: ${error.message}');
        ad.dispose();
        _preloadInterstitial();
      },
    );
    try {
      await ad.show();
    } catch (e) {
      debugPrint('[AdManager] interstitial show threw: $e');
      _preloadInterstitial();
    }
  }

  /// Shows a rewarded video and, if it is watched through, buys an hour with no
  /// ads anywhere in the app.
  ///
  /// Returns true when the reward was earned. False covers every other ending —
  /// nothing loaded, nothing to show, the user backed out — and the caller says
  /// so without pretending something was earned.
  Future<bool> showRewardedForAdFree() async {
    if (!enabled) return false;

    final ad = _rewarded;
    if (ad == null) {
      _preloadRewarded();
      return false;
    }
    _rewarded = null;

    var earned = false;
    final finished = Completer<void>();
    void done() {
      if (!finished.isCompleted) finished.complete();
    }

    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadRewarded();
        done();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[AdManager] rewarded failed to show: ${error.message}');
        ad.dispose();
        _preloadRewarded();
        done();
      },
    );

    try {
      await ad.show(onUserEarnedReward: (_, __) => earned = true);
      // The reward callback fires while the video runs; the hour starts when the
      // user is back in the app, so it is not spent watching an end card.
      await finished.future.timeout(const Duration(minutes: 3), onTimeout: () {});
    } catch (e) {
      debugPrint('[AdManager] rewarded show threw: $e');
      _preloadRewarded();
      return false;
    }

    if (!earned) return false;
    await _grantAdFreeHour();
    return true;
  }

  /// Opens the consent form again, for the Settings row.
  Future<bool> showPrivacyOptions() async {
    final shown = await AdConsent.instance.showPrivacyOptions();
    // The answer may have changed, and with it whether ads may load at all.
    final result = await AdConsent.instance.gather(debugSettings: ConsentDebug.settings(), force: true);
    if (result.canRequestAds) {
      await _initialise();
    }
    notifyListeners();
    return shown;
  }

  Future<void> _grantAdFreeHour() async {
    final until = DateTime.now().add(AdPolicy.adFreeAfterReward);
    _adFreeUntil = until;
    await _saveAdFreeUntil(until);
    _armAdFreeTimer();

    // Banners already on screen have to go with it: the reward is a promise
    // about the next hour, and leaving one lit would break it in the first
    // second.
    _interstitial?.dispose();
    _interstitial = null;
    _appOpen?.dispose();
    _appOpen = null;
    _rewarded?.dispose();
    _rewarded = null;

    notifyListeners();
  }

  void _armAdFreeTimer() {
    _adFreeTimer?.cancel();
    final until = _adFreeUntil;
    if (until == null) return;

    final remaining = until.difference(DateTime.now());
    if (remaining <= Duration.zero) {
      _adFreeUntil = null;
      return;
    }
    // Without this the app would stay ad-free until it was restarted, because
    // nothing else was going to ask again.
    _adFreeTimer = Timer(remaining, () {
      _adFreeUntil = null;
      unawaited(_saveAdFreeUntil(null));
      notifyListeners();
      if (enabled) {
        _preloadInterstitial();
        _preloadAppOpen();
        _preloadRewarded();
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _leftAt ??= DateTime.now();
      case AppLifecycleState.resumed:
        final leftAt = _leftAt;
        _leftAt = null;
        unawaited(_onResumed(leftAt == null ? Duration.zero : DateTime.now().difference(leftAt)));
      case AppLifecycleState.inactive:
        break;
    }
  }

  Future<void> _onResumed(Duration away) async {
    // A launch whose consent step never completed — no network, say — gets a
    // second chance here; the consent object itself refuses to ask twice in
    // thirty seconds, so a quick app switch costs nothing.
    if (!_ready) {
      await _settleConsent();
      return;
    }
    if (!_firstRunComplete || !enabled) return;
    if (!_appOpenSchedule.resumeDue(DateTime.now(), away)) return;
    await _showAppOpen();
  }

  /// The app-open ad that is in hand, or the one being fetched right now, waited
  /// for up to [window].
  ///
  /// Returns without consuming anything: the caller decides whether to show it,
  /// and an ad the rules no longer allow stays in hand for the next return.
  Future<AppOpenAd?> _appOpenWithin(Duration window) async {
    final held = _appOpen;
    if (held != null) return held;

    // Nothing can be on its way: the SDK is not up, the user has bought the
    // hour, or ads are removed.
    if (!enabled) return null;

    // The ordinary launch arrives here with the request already in flight: it
    // went out when the SDK came up, moments before this.
    if (_appOpenRequest == null) _preloadAppOpen();
    final request = _appOpenRequest;
    if (request == null || window <= Duration.zero) return null;

    final arrived = await request.future.timeout(window, onTimeout: () => null);
    // It may have been spent while it was on its way — a return that showed one,
    // or a reward that bought the hour out — so only an ad still in hand is
    // handed back.
    return identical(_appOpen, arrived) ? arrived : null;
  }

  Future<void> _showAppOpen() async {
    // Someone who came back to a conversion in progress came back to watch it.
    if (BackgroundTask.instance.running) return;

    final ad = _appOpen;
    if (ad == null) {
      _preloadAppOpen();
      return;
    }

    _appOpen = null;
    _appOpenSchedule.markedShown(DateTime.now());
    ad.fullScreenContentCallback = FullScreenContentCallback<AppOpenAd>(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _preloadAppOpen();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        debugPrint('[AdManager] app open failed to show: ${error.message}');
        ad.dispose();
        _preloadAppOpen();
      },
    );
    try {
      await ad.show();
    } catch (e) {
      debugPrint('[AdManager] app open show threw: $e');
      _preloadAppOpen();
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
        onAdFailedToLoad: (error) {
          _loadingInterstitial = false;
          _interstitial = null;
          debugPrint('[AdManager] interstitial failed to load: ${error.message}');
        },
      ),
    );
  }

  void _preloadAppOpen() {
    if (!enabled || _appOpen != null || _loadingAppOpen) return;
    _loadingAppOpen = true;
    final request = _appOpenRequest = Completer<AppOpenAd?>();
    AppOpenAd.load(
      adUnitId: AdIds.appOpen,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingAppOpen = false;
          _appOpen = ad;
          request.complete(ad);
        },
        onAdFailedToLoad: (error) {
          _loadingAppOpen = false;
          _appOpen = null;
          debugPrint('[AdManager] app open failed to load: ${error.message}');
          request.complete(null);
        },
      ),
    );
  }

  void _preloadRewarded() {
    if (!enabled || _rewarded != null || _loadingRewarded) return;
    _loadingRewarded = true;
    RewardedAd.load(
      adUnitId: AdIds.rewarded,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _loadingRewarded = false;
          _rewarded = ad;
        },
        onAdFailedToLoad: (error) {
          _loadingRewarded = false;
          _rewarded = null;
          debugPrint('[AdManager] rewarded failed to load: ${error.message}');
        },
      ),
    );
  }

  /// Reads the rewarded hour left over from a previous run. A clock that has
  /// moved backwards — a restore, or a user changing the device time — reads as
  /// no suppression rather than as an hour that never ends.
  Future<DateTime?> _loadAdFreeUntil() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final millis = prefs.getInt(_adFreeKey);
      if (millis == null) return null;
      final until = DateTime.fromMillisecondsSinceEpoch(millis);
      if (until.isAfter(DateTime.now().add(AdPolicy.adFreeAfterReward))) {
        await prefs.remove(_adFreeKey);
        return null;
      }
      return until;
    } catch (e) {
      debugPrint('[AdManager] could not read the ad-free hour: $e');
      return null;
    }
  }

  Future<void> _saveAdFreeUntil(DateTime? until) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (until == null) {
        await prefs.remove(_adFreeKey);
      } else {
        await prefs.setInt(_adFreeKey, until.millisecondsSinceEpoch);
      }
    } catch (e) {
      debugPrint('[AdManager] could not store the ad-free hour: $e');
    }
  }

  @override
  void dispose() {
    _adFreeTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _interstitial?.dispose();
    _appOpen?.dispose();
    _rewarded?.dispose();
    super.dispose();
  }
}

/// An anchored adaptive banner that occupies no space until it has loaded, so a
/// screen never shows an empty reserved slot where an ad did not arrive.
///
/// It also watches the manager: ads that come up after the screen was built
/// fill in, and an hour bought with a rewarded video empties it again.
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
    AdManager.instance.addListener(_onManagerChanged);
  }

  @override
  void dispose() {
    AdManager.instance.removeListener(_onManagerChanged);
    _ad?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    unawaited(_load());
  }

  void _onManagerChanged() {
    if (!mounted) return;
    if (AdManager.instance.enabled) {
      if (_ad == null && !_loaded) unawaited(_load());
      return;
    }
    // Suppressed, removed, or not up yet: whatever is on screen goes.
    if (_ad == null && !_loaded) return;
    _ad?.dispose();
    setState(() {
      _ad = null;
      _loaded = false;
    });
  }

  Future<void> _load() async {
    if (!mounted || !AdManager.instance.enabled || _ad != null) return;

    final width = MediaQuery.sizeOf(context).width.truncate();
    final size = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(width);
    if (size == null || !mounted || !AdManager.instance.enabled) return;

    final ad = BannerAd(
      adUnitId: AdIds.banner,
      size: size,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[AppBanner] banner failed to load: ${error.message}');
          ad.dispose();
          if (mounted) {
            setState(() {
              _ad = null;
              _loaded = false;
            });
          }
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

/// The in-feed native ad, used inside the two lists that are long enough to
/// deserve one: History and Files.
///
/// A native ad is the format that is meant to be looked at rather than
/// tolerated — it arrives with a headline, an icon and a call to action that the
/// SDK lays out in the app's own colours, so it sits in a list the way a row
/// does. It collapses to nothing when it does not fill, which is what keeps the
/// list from reserving room for an ad that never came.
class NativeAdCard extends StatefulWidget {
  const NativeAdCard({super.key});

  @override
  State<NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    AdManager.instance.addListener(_onManagerChanged);
  }

  @override
  void dispose() {
    AdManager.instance.removeListener(_onManagerChanged);
    _ad?.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_requested) return;
    _requested = true;
    unawaited(_load());
  }

  void _onManagerChanged() {
    if (!mounted) return;
    if (AdManager.instance.enabled) {
      if (_ad == null && !_loaded) unawaited(_load());
      return;
    }
    if (_ad == null && !_loaded) return;
    _ad?.dispose();
    setState(() {
      _ad = null;
      _loaded = false;
    });
  }

  Future<void> _load() async {
    if (!mounted || !Platform.isAndroid || !AdManager.instance.enabled || _ad != null) return;
    final t = context.tokens;

    final ad = NativeAd(
      adUnitId: AdIds.native,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _loaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('[NativeAdCard] native ad failed to load: ${error.message}');
          ad.dispose();
          if (mounted) setState(() => _ad = null);
        },
      ),
      // The SDK's own template, in the app's colours: primary text in the app's
      // text colour, the call to action on the app's accent. The small layout is
      // a 4:1 strip, which is what keeps it looking like a row in a list rather
      // than a billboard.
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.small,
        mainBackgroundColor: t.surface,
        cornerRadius: AppTheme.radiusSmall,
        callToActionTextStyle: NativeTemplateTextStyle(
          backgroundColor: t.accent,
          textColor: t.onAccent,
          style: NativeTemplateFontStyle.bold,
          size: 13,
        ),
        primaryTextStyle: NativeTemplateTextStyle(
          textColor: t.textPrimary,
          style: NativeTemplateFontStyle.bold,
          size: 14.5,
        ),
        secondaryTextStyle: NativeTemplateTextStyle(textColor: t.textSecondary, size: 12.5),
        tertiaryTextStyle: NativeTemplateTextStyle(textColor: t.textFaint, size: 11),
      ),
    );
    _ad = ad;
    await ad.load();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_loaded || ad == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AspectRatio(aspectRatio: 4, child: AdWidget(ad: ad)),
    );
  }
}
