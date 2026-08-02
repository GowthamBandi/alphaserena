import 'package:alphaserena/core/domain/coaching_event.dart';
import 'package:alphaserena/core/utils/lifestyle_math.dart';
import 'package:flutter_test/flutter_test.dart';

/// CROSS-APP CONTRACT — the numbers TrainerHQ and AlphaSerena must agree on.
///
/// `lifestyle_math.dart` is DUPLICATED in both repositories (the two apps share
/// no package). The duplication is deliberate, but it drifts silently: the V2
/// intelligence helpers were added to TrainerHQ's copy alone and nothing
/// noticed. This file, and its byte-identical twin in
/// `trainersHQ/test/lifestyle_cross_app_contract_test.dart`, pin the shared
/// values as literals — so a change made on one side fails on the other rather
/// than quietly making the two apps disagree about the same member's day.
void main() {
  _habitHistoryTwins();

  group('platform default targets', () {
    test('are identical in both apps', () {
      expect(LifestyleDefaults.waterMl, 2500);
      expect(LifestyleDefaults.steps, 8000);
      expect(LifestyleDefaults.sleepHours, 8);
      expect(LifestyleDefaults.glassSizeMl, 250);
    });
  });

  group('validation bounds', () {
    test('are identical in both apps', () {
      expect(LifestyleLimits.minGlassMl, 50);
      expect(LifestyleLimits.maxGlassMl, 2000);
      expect(LifestyleLimits.maxWaterMl, 20000);
      expect(LifestyleLimits.maxWaterGlasses, 60);
      expect(LifestyleLimits.maxSteps, 100000);
      expect(LifestyleLimits.maxSleepHours, 24);
    });

    test('never admit a value the derivation would then discard', () {
      // THE INVARIANT THAT MATTERS. The event derivations drop readings above
      // their caps, so if validation were the more permissive of the two, an
      // entry could pass every check, be written as an event, and then be
      // ignored by every reader — the member watching their number vanish with
      // nothing reported. Validation must be the stricter gate.
      expect(LifestyleLimits.maxSteps, lessThanOrEqualTo(maxStepsSample));
      expect(LifestyleLimits.maxSleepHours * 60,
          lessThanOrEqualTo(maxSleepMinutes.toDouble()));
      expect(LifestyleLimits.maxGlassMl, lessThanOrEqualTo(maxDrinkMl));
    });
  });

  group('shared conversions behave identically', () {
    test('dayKey is a zero-padded local yyyy-MM-dd', () {
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(dayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });

    test('glasses <-> ml round-trip at the default glass size', () {
      expect(glassesFor(2500, 250), 10);
      expect(mlForGlasses(10, 250), 2500);
      expect(glassesFor(2500, 0), 0, reason: 'a zero glass cannot divide');
      expect(glassesFor(-100, 250), 0, reason: 'never a negative glass count');
    });

    test('effectiveTarget prefers a real coach target over the default', () {
      expect(effectiveTarget(3000, LifestyleDefaults.waterMl), 3000);
      expect(effectiveTarget(null, LifestyleDefaults.waterMl), 2500);
      expect(effectiveTarget(0, LifestyleDefaults.waterMl), 2500,
          reason: 'a zero target is not a target');
    });
  });
}

/// THE HABIT-HISTORY TWINS.
///
/// `habitStreaks`, `trendDirection` and `extremeDayFor` exist in BOTH apps'
/// `lifestyle_math.dart`. The member's history screen and the coach's compute
/// streaks and trends from the SAME server-derived rollup days, so a drift
/// between the two copies would show a member and their coach different
/// streaks off identical data.
///
/// These two files have silently drifted before, which is why the contract is
/// asserted rather than assumed. The values below are pinned identically in
/// trainersHQ's `test/lifestyle_math_test.dart`.
void _habitHistoryTwins() {
  final now = DateTime(2026, 8, 15);
  DateTime d(int daysAgo) {
    final x = now.subtract(Duration(days: daysAgo));
    return DateTime(x.year, x.month, x.day);
  }

  group('habitStreaks — twinned with TrainerHQ', () {
    test('counts back from today, and scans all history for the best', () {
      final s = habitStreaks({d(0), d(1), d(2), d(6), d(7)}, now);
      expect(s.current, 3);
      expect(s.best, 3);
    });

    test('a streak ending YESTERDAY still counts as current', () {
      // A member who has not logged yet today has not lost their streak.
      expect(habitStreaks({d(1), d(2)}, now).current, 2);
    });

    test('a LAPSED streak reads 0, never a stale count', () {
      expect(habitStreaks({d(3), d(4), d(5)}, now).current, 0);
      expect(habitStreaks({d(3), d(4), d(5)}, now).best, 3);
    });

    test('no hit days at all is zero on both counts', () {
      final s = habitStreaks(const {}, now);
      expect(s.current, 0);
      expect(s.best, 0);
    });
  });

  group('trendDirection — twinned with TrainerHQ', () {
    test('moves only outside the 5% band', () {
      expect(trendDirection(110, 100), 1);
      expect(trendDirection(90, 100), -1);
      expect(trendDirection(102, 100), 0, reason: 'inside the band is steady');
    });

    test('missing or zero history is steady, never a fabricated direction', () {
      expect(trendDirection(null, 100), 0);
      expect(trendDirection(100, null), 0);
      expect(trendDirection(100, 0), 0);
    });
  });

  group('extremeDayFor — twinned with TrainerHQ', () {
    test('names the highest and lowest LOGGED days', () {
      final values = {d(1): 3000.0, d(2): 4000.0, d(3): 500.0};
      expect(extremeDayFor(values, best: true)!.key, d(2));
      expect(extremeDayFor(values, best: false)!.key, d(3));
    });

    test('a tie resolves to the MOST RECENT day', () {
      final values = {d(9): 4000.0, d(2): 4000.0};
      expect(extremeDayFor(values, best: true)!.key, d(2));
    });

    test('nothing logged yields nothing', () {
      expect(extremeDayFor(const {}, best: true), isNull);
    });
  });
}
