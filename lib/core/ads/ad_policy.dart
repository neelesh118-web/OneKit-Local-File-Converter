/// When an ad is allowed to appear.
///
/// The app has one rule above the rest — nothing covers a conversion while it
/// is running — and everything here is the arithmetic behind the others: how
/// many finished runs go by between full-screen ads, how long a break in the
/// app has to be before an app-open ad is welcome, and how long a reward buys
/// peace. The call sites ask these questions; the plugin only ever gets told
/// the answer.
///
/// Deliberately free of widgets and of the ads SDK, so the rules can be tested
/// directly against a clock the test owns, instead of by waiting two minutes
/// for a cooldown to expire.
library;

/// The numbers themselves, in one place, each with the reason it is that size.
class AdPolicy {
  AdPolicy._();

  /// Finished runs — a conversion, a batch, a PDF job — between full-screen
  /// interstitials.
  ///
  /// Three rather than one: a converter is used in bursts, and an interstitial
  /// after every single file would make the app feel like a paywall. Nothing
  /// counts a file inside a batch, so converting forty images is one run here,
  /// not forty.
  static const interstitialEveryNConversions = 3;

  /// The shortest gap between two interstitials, whenever the count is reached.
  static const interstitialCooldown = Duration(minutes: 2);

  /// How long the app has to have been in the background before coming back to
  /// it is "opening the app" rather than switching windows mid-task. Below this
  /// an app-open ad is an interruption, not a greeting.
  static const appOpenBackgroundThreshold = Duration(minutes: 2);

  /// The longest run of app-open ads, launch or resume, that the app will show
  /// inside an hour.
  ///
  /// One an hour is the ceiling on the whole feature: a user who backgrounds the
  /// app six times on a Sunday afternoon meets at most one of these, which is
  /// the difference between a splash screen and a toll booth.
  static const appOpenCooldown = Duration(hours: 1);

  /// How long a cold launch may wait for the app-open ad it has just asked for.
  ///
  /// The request goes out when the SDK comes up, which is the same breath as the
  /// launch, so there is nothing in hand to show yet: this wait is the whole
  /// difference between a launch ad and no launch ad. Five seconds is all of it —
  /// past that the app has stopped being a launch, and an ad on top of a session
  /// that has already started is an interruption rather than a greeting.
  static const appOpenShowWindow = Duration(seconds: 5);

  /// What a finished rewarded video buys: an hour with no ads anywhere in the
  /// app, banners included.
  static const adFreeAfterReward = Duration(hours: 1);
}

/// Whether a reward is still covering [now].
bool isAdFreeUntil(DateTime? until, DateTime now) => until != null && now.isBefore(until);

/// Counts finished runs and answers whether the next one owes a full-screen ad.
///
/// The count is spent when an ad is actually shown, not when it is merely due:
/// an interstitial that had not finished loading, or a run held back by the
/// cooldown, leaves the count where it is, so the very next finished run is
/// offered the ad instead of the count starting again from zero.
class InterstitialSchedule {
  InterstitialSchedule({
    this.everyN = AdPolicy.interstitialEveryNConversions,
    this.cooldown = AdPolicy.interstitialCooldown,
  });

  final int everyN;
  final Duration cooldown;

  int _runs = 0;
  DateTime? _lastShown;

  /// Number of finished runs since the last interstitial was shown.
  int get runs => _runs;

  /// Registers a finished run. A run inside a batch is not counted separately:
  /// the batch is one run, which is what the caller already knows.
  void runFinished() => _runs++;

  /// Whether an interstitial is allowed on top of [now].
  bool due(DateTime now) {
    if (_runs < everyN) return false;
    final last = _lastShown;
    return last == null || now.difference(last) >= cooldown;
  }

  /// Call once the ad is on screen, so the next one waits its turn.
  void markedShown(DateTime now) {
    _runs = 0;
    _lastShown = now;
  }

  /// Forgets the history, for tests that want a clean slate.
  void reset() {
    _runs = 0;
    _lastShown = null;
  }
}

/// The app-open schedule: one launch ad, and one on coming back after a while.
///
/// Both share one cooldown, so a phone call in the middle of a session cannot
/// buy a second one: the question this answers is "has this user seen an
/// app-open ad recently", not "which window did they open".
class AppOpenSchedule {
  AppOpenSchedule({
    this.minimumBackground = AdPolicy.appOpenBackgroundThreshold,
    this.cooldown = AdPolicy.appOpenCooldown,
  });

  final Duration minimumBackground;
  final Duration cooldown;

  DateTime? _lastShown;

  bool _due(DateTime now) {
    final last = _lastShown;
    return last == null || now.difference(last) >= cooldown;
  }

  /// A cold start landed: is an app-open ad allowed on top of it?
  bool launchDue(DateTime now) => _due(now);

  /// The app was away for [away] and is back: is an app-open ad allowed?
  bool resumeDue(DateTime now, Duration away) => away >= minimumBackground && _due(now);

  /// Call when one is actually shown — not when one merely loads, or an ad that
  /// failed to fill would spend the hour it never used.
  void markedShown(DateTime now) => _lastShown = now;

  void reset() => _lastShown = null;
}
