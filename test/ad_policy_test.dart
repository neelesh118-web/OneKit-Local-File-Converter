import 'package:flutter_test/flutter_test.dart';
import 'package:onekit_converter/core/ads/ad_policy.dart';

/// The ad rules, tested against a clock the test owns.
///
/// Every one of these is arithmetic, which is the reason it lives outside the
/// ad manager: a cooldown that needs two real minutes to observe is a cooldown
/// nobody checks.
void main() {
  final t0 = DateTime(2026, 10, 2, 12);

  group('InterstitialSchedule', () {
    test('says nothing for the first two runs, then asks on the third', () {
      final schedule = InterstitialSchedule();
      schedule.runFinished();
      expect(schedule.due(t0), isFalse);
      schedule.runFinished();
      expect(schedule.due(t0), isFalse);
      schedule.runFinished();
      expect(schedule.due(t0), isTrue);
    });

    test('holds the ad back inside the cooldown, then gives it on the next run', () {
      final schedule = InterstitialSchedule();
      for (var i = 0; i < 3; i++) {
        schedule.runFinished();
      }
      schedule.markedShown(t0);

      // Two more runs inside the two-minute cooldown, and the ad is not due.
      schedule.runFinished();
      schedule.runFinished();
      expect(schedule.due(t0.add(const Duration(minutes: 1))), isFalse);
      expect(schedule.due(t0.add(const Duration(minutes: 1, seconds: 30))), isFalse);

      // The runs that were held back still counted: the first moment past the
      // cooldown is the one that gets the ad.
      schedule.runFinished();
      expect(schedule.due(t0.add(const Duration(minutes: 3))), isTrue);
    });

    test('a run inside a batch is not counted separately', () {
      final schedule = InterstitialSchedule();
      // Forty images in one batch: one run, and the count starts at one.
      schedule.runFinished();
      expect(schedule.runs, 1);
    });

    test('an ad that was never shown leaves the count where it was', () {
      final schedule = InterstitialSchedule();
      // The caller asked, found nothing loaded, and did not mark it shown: the
      // count is untouched, so the ad is offered again at the next finish.
      for (var i = 0; i < 3; i++) {
        schedule.runFinished();
      }
      expect(schedule.due(t0), isTrue);
      expect(schedule.due(t0.add(const Duration(hours: 1))), isTrue);
      expect(schedule.runs, 3);
    });

    test('marking it shown restarts the count and the cooldown', () {
      final schedule = InterstitialSchedule();
      for (var i = 0; i < 3; i++) {
        schedule.runFinished();
      }
      schedule.markedShown(t0);
      expect(schedule.runs, 0);

      for (var i = 0; i < 3; i++) {
        schedule.runFinished();
      }
      // Three runs again, but only half a minute has passed.
      expect(schedule.due(t0.add(const Duration(seconds: 30))), isFalse);
      expect(schedule.due(t0.add(const Duration(minutes: 5))), isTrue);
    });

    test('the thresholds are the documented ones', () {
      final schedule = InterstitialSchedule();
      expect(schedule.everyN, AdPolicy.interstitialEveryNConversions);
      expect(schedule.cooldown, AdPolicy.interstitialCooldown);
    });
  });

  group('AppOpenSchedule', () {
    test('a cold start is due the first time and not again for an hour', () {
      final schedule = AppOpenSchedule();
      expect(schedule.launchDue(t0), isTrue);
      schedule.markedShown(t0);
      expect(schedule.launchDue(t0.add(const Duration(minutes: 59))), isFalse);
      expect(schedule.launchDue(t0.add(const Duration(hours: 1))), isTrue);
    });

    test('coming back after a moment is not an app open', () {
      final schedule = AppOpenSchedule();
      schedule.markedShown(t0);
      // Switching to another app and straight back is not a new session, and
      // an ad on top of it is an interruption rather than a greeting.
      expect(schedule.resumeDue(t0.add(const Duration(hours: 2)), const Duration(seconds: 20)), isFalse);
      expect(schedule.resumeDue(t0.add(const Duration(hours: 2)), const Duration(minutes: 1, seconds: 59)), isFalse);
      expect(schedule.resumeDue(t0.add(const Duration(hours: 2)), const Duration(minutes: 2)), isTrue);
    });

    test('one launch ad and one resume ad cannot both land inside the hour', () {
      final schedule = AppOpenSchedule();
      expect(schedule.launchDue(t0), isTrue);
      schedule.markedShown(t0);
      // Away for ten minutes, back well inside the cooldown.
      expect(schedule.resumeDue(t0.add(const Duration(minutes: 10)), const Duration(minutes: 10)), isFalse);
      // And past it.
      expect(schedule.resumeDue(t0.add(const Duration(minutes: 61)), const Duration(minutes: 10)), isTrue);
    });

    test('a reset makes the next launch due again, for tests', () {
      final schedule = AppOpenSchedule();
      schedule.markedShown(t0);
      schedule.reset();
      expect(schedule.launchDue(t0), isTrue);
    });
  });

  group('the rewarded hour', () {
    test('is not ad-free without a reward', () {
      expect(isAdFreeUntil(null, t0), isFalse);
    });

    test('covers an hour from the moment it was earned', () {
      final until = t0.add(AdPolicy.adFreeAfterReward);
      expect(isAdFreeUntil(until, t0), isTrue);
      expect(isAdFreeUntil(until, t0.add(const Duration(minutes: 59))), isTrue);
      expect(isAdFreeUntil(until, t0.add(const Duration(hours: 1))), isFalse);
    });

    test('a stored end time in the past is not ad-free', () {
      expect(isAdFreeUntil(t0.subtract(const Duration(hours: 3)), t0), isFalse);
    });
  });
}
