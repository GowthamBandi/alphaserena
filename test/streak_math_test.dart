import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/utils/streak_math.dart';
import 'package:alphaserena/core/utils/lifestyle_math.dart' show dayKey;

void main() {
  final today = DateTime(2026, 7, 25); // fixed anchor — no wall-clock in tests

  Set<String> days(List<int> daysAgo) => {
        for (final n in daysAgo) dayKey(today.subtract(Duration(days: n))),
      };

  group('currentStreak', () {
    test('empty set → 0', () {
      expect(currentStreak(<String>{}, today), 0);
    });

    test('today only → 1', () {
      expect(currentStreak(days([0]), today), 1);
    });

    test('consecutive run ending today counts fully', () {
      expect(currentStreak(days([0, 1, 2, 3]), today), 4);
    });

    test('today unlogged: streak survives anchored on yesterday', () {
      expect(currentStreak(days([1, 2, 3]), today), 3);
    });

    test('a missed day breaks the run', () {
      // logged today + 2..4 days ago, but NOT yesterday → streak is just today.
      expect(currentStreak(days([0, 2, 3, 4]), today), 1);
    });

    test('gap older than the run does not extend it', () {
      expect(currentStreak(days([0, 1, 5, 6]), today), 2);
    });

    test('two-day-old log with today+yesterday missed → 0 (broken)', () {
      expect(currentStreak(days([2, 3]), today), 0);
    });

    test('cap bounds the walk', () {
      expect(currentStreak(days(List.generate(90, (i) => i)), today, cap: 60),
          60);
    });
  });

  group('daysLoggedInWindow', () {
    test('counts only days inside the window', () {
      // 0,1,6 in the last 7 days; 7 and 10 are outside.
      expect(daysLoggedInWindow(days([0, 1, 6, 7, 10]), today, 7), 3);
    });

    test('empty → 0', () {
      expect(daysLoggedInWindow(<String>{}, today, 7), 0);
    });
  });

  group('bestStreakInWindow', () {
    test('empty → 0', () {
      expect(bestStreakInWindow(<String>{}, today, 60), 0);
    });

    test('finds a past run longer than the current one', () {
      // current streak = 1 (today), but 5..9 days ago was a 5-day run.
      expect(bestStreakInWindow(days([0, 5, 6, 7, 8, 9]), today, 60), 5);
    });

    test('current run IS the best when longest', () {
      expect(bestStreakInWindow(days([0, 1, 2, 10]), today, 60), 3);
    });

    test('ignores days outside the window', () {
      // A long run entirely older than the 7-day window doesn't count.
      expect(bestStreakInWindow(days([10, 11, 12, 13, 0]), today, 7), 1);
    });
  });

  group('loggedToday', () {
    test('true only when today key present', () {
      expect(loggedToday(days([0]), today), true);
      expect(loggedToday(days([1]), today), false);
    });
  });
}
