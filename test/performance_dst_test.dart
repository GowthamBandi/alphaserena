import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/performance.dart';
import 'package:alphaserena/core/utils/day_key_guard.dart' show localDayKey;

/// DAYLIGHT SAVING — the member's own calendar must not lose or repeat a day.
///
/// Every day-walk in this module stepped by `Duration`, which is exact elapsed
/// time rather than a calendar day. Across a 23- or 25-hour day the wall clock
/// shifts, `localDayKey` then names the wrong day, and the walk drifts:
///
///   • the 30-day timeline SKIPPED 8 March 2026 entirely (spring-forward), so a
///     miss that day could not break a streak and a session that day could not
///     extend one;
///   • the November month grid rendered 1 Nov TWICE and never drew 30 Nov, so a
///     session logged on the 30th was invisible on the member's own history;
///   • `bestDailyStreak` walked 365 slots covering 364 distinct days, letting a
///     duplicated day double-count toward a personal best.
///
/// These pass in a no-DST zone whatever the arithmetic does — which is exactly
/// why this shipped. Run under `TZ=America/New_York`.
void main() {
  // A member with a plan but no logs; we are testing the CALENDAR, not scoring.
  TrackHistory history() => TrackHistory(
        versions: const [],
        coachingPause: null,
      );

  group('the 30-day timeline covers every calendar day', () {
    test('spring-forward: no day is skipped and none repeats', () {
      // US DST springs forward on Sunday 8 March 2026.
      final days = timeline(
        history(),
        logged: const <String>{},
        today: DateTime(2026, 3, 9),
      );
      final keys = days.map((d) => localDayKey(d.date)).toList();
      expect(keys.toSet().length, keys.length, reason: 'no day may repeat');
      expect(
        keys,
        contains('2026-03-08'),
        reason: 'the DST day itself must be resolved, not stepped over',
      );
      // Consecutive and descending, with no gaps.
      for (var i = 1; i < days.length; i++) {
        expect(
          days[i].date,
          DateTime(days[i - 1].date.year, days[i - 1].date.month,
              days[i - 1].date.day - 1),
          reason: 'every step must be exactly one calendar day',
        );
      }
    });

    test('autumn fall-back: no day is skipped and none repeats', () {
      final days = timeline(
        history(),
        logged: const <String>{},
        today: DateTime(2026, 11, 2),
      );
      final keys = days.map((d) => localDayKey(d.date)).toList();
      expect(keys.toSet().length, keys.length);
      expect(keys, contains('2026-11-01'));
    });
  });

  group('the month grid draws each day of the month exactly once', () {
    test('November 2026 (fall-back) renders all 30 days', () {
      final cells = monthCells(
        history(),
        logged: const <String>{},
        month: DateTime(2026, 11),
        today: DateTime(2026, 11, 20),
      );
      final keys = cells.map((c) => localDayKey(c.date)).toList();
      expect(cells.length, 30);
      expect(keys.toSet().length, 30, reason: '1 Nov was drawn twice');
      expect(
        keys,
        contains('2026-11-30'),
        reason: '30 Nov had no cell at all — a session that day was invisible',
      );
    });

    test('March 2026 (spring-forward) renders all 31 days', () {
      final cells = monthCells(
        history(),
        logged: const <String>{},
        month: DateTime(2026, 3),
        today: DateTime(2026, 3, 20),
      );
      final keys = cells.map((c) => localDayKey(c.date)).toList();
      expect(cells.length, 31);
      expect(keys.toSet().length, 31);
      expect(keys.first, '2026-03-01');
      expect(keys.last, '2026-03-31');
    });

    test("today's own cell is not pushed into the future by an hour", () {
      // The shifted timestamp made `date.isAfter(today)` true for TODAY, which
      // rendered the current day at 0.4 alpha with onTap: null — untappable.
      final cells = monthCells(
        history(),
        logged: const <String>{},
        month: DateTime(2026, 11),
        today: DateTime(2026, 11, 20),
      );
      final todayCell =
          cells.firstWhere((c) => localDayKey(c.date) == '2026-11-20');
      expect(todayCell.state, isNot(MonthCellState.future));
    });
  });

  group('streaks count distinct days', () {
    test('one logged day is a streak of one, not two', () {
      final best = bestDailyStreak(
        history(),
        logged: {'2025-11-02'},
        today: DateTime(2026, 8, 7),
      );
      expect(best, 1, reason: 'a duplicated day inflated the personal best');
    });
  });
}
