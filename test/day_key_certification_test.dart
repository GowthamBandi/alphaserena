import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/utils/day_key_guard.dart';
import 'package:alphaserena/core/utils/lifestyle_math.dart';

/// P0 CERTIFICATION — day-key behaviour over TIME.
///
/// Phases 8, 10 and 13 of the certification mission. The clock is INJECTED
/// throughout; nothing here reads the wall clock, so these assertions mean the
/// same thing whenever they run.
void main() {
  // The certification day. Real server time when this was written.
  final today = DateTime(2026, 8, 6, 10, 9);

  group('PHASE 8 — TOMORROW SIMULATION (no manual clock change)', () {
    test('a day logged today belongs to today, and only today', () {
      final key = dayKey(today);
      expect(key, '2026-08-06');
      expect(isPlausibleDayKey(key, today.toUtc()), isTrue);
    });

    test("tomorrow, YESTERDAY's key still resolves to yesterday", () {
      // The document is unchanged; only the clock moved. Its day must not move
      // with the clock — that was the whole defect on the reader side.
      final tomorrow = DateTime(2026, 8, 7, 9, 0);
      final loggedKey = dayKey(today); // '2026-08-06'
      expect(loggedKey, isNot(dayKey(tomorrow)));
      // Still writable/valid history, never refused.
      expect(isPlausibleDayKey(loggedKey, tomorrow.toUtc()), isTrue);
    });

    test('tomorrow has NO document until one is written — no carry-over', () {
      // Nothing derives tomorrow's key from today's data; the key is a pure
      // function of the clock. A new day therefore starts empty by
      // construction, not by a clearing step that could be forgotten.
      final tomorrow = DateTime(2026, 8, 7, 0, 1);
      expect(dayKey(tomorrow), '2026-08-07');
      expect(dayKey(tomorrow), isNot(dayKey(today)));
    });

    test('a rollover at 00:00:00 lands on the new day, not the old', () {
      expect(dayKey(DateTime(2026, 8, 6, 23, 59, 59)), '2026-08-06');
      expect(dayKey(DateTime(2026, 8, 7, 0, 0, 0)), '2026-08-07');
    });

    test('a MONTH rollover does not produce an impossible key', () {
      expect(dayKey(DateTime(2026, 8, 31, 23, 59)), '2026-08-31');
      expect(dayKey(DateTime(2026, 9, 1, 0, 0)), '2026-09-01');
    });

    test('a YEAR rollover does not produce an impossible key', () {
      expect(dayKey(DateTime(2026, 12, 31, 23, 59)), '2026-12-31');
      expect(dayKey(DateTime(2027, 1, 1, 0, 0)), '2027-01-01');
    });
  });

  group('PHASE 10 — PAST-DATE VALIDATION (offline replay must survive)', () {
    test('yesterday, last week and last month remain writable', () {
      final serverNow = today.toUtc();
      for (final d in [1, 7, 30, 90, 365]) {
        final key = dayKey(today.subtract(Duration(days: d)));
        expect(isPlausibleDayKey(key, serverNow), isTrue,
            reason: '$key ($d days ago) must remain writable');
      }
    });

    test('a replay that lands DAYS after the fact is still accepted', () {
      // The device was offline 2026-07-27..2026-08-06 and flushes its queue
      // now. Every one of those keys describes a day the member lived.
      final serverNow = today.toUtc();
      for (var d = 1; d <= 10; d++) {
        final key = dayKey(DateTime(2026, 8, 6).subtract(Duration(days: d)));
        expect(ServerClockBound.instance.permits(key), isTrue);
        expect(isPlausibleDayKey(key, serverNow), isTrue);
      }
    });

    test('a slow device clock is indistinguishable from replay, and allowed',
        () {
      // Refusing this would silently discard a real log.
      final slow = DateTime(2026, 8, 1, 9, 0);
      expect(isPlausibleDayKey(dayKey(slow), today.toUtc()), isTrue);
    });
  });

  group('PHASE 13 — 30 CONSECUTIVE DAYS', () {
    test('30 consecutive days produce 30 distinct, consecutive, valid keys',
        () {
      final start = DateTime(2026, 7, 20);
      final keys = <String>[];
      for (var i = 0; i < 30; i++) {
        keys.add(dayKey(start.add(Duration(days: i))));
      }

      // No duplicates.
      expect(keys.toSet().length, 30, reason: 'no duplicated day');
      // Strictly increasing — string order is chronological for this format,
      // so this also proves no day was SHIFTED out of sequence.
      final sorted = [...keys]..sort();
      expect(keys, sorted, reason: 'no shifted day');
      // No gaps: 30 days spanning exactly 29 days of distance.
      final first = DateTime.parse(keys.first);
      final last = DateTime.parse(keys.last);
      expect(last.difference(first).inDays, 29, reason: 'no skipped day');
      // Crosses a month boundary, which is where naive arithmetic breaks.
      expect(keys.contains('2026-07-31'), isTrue);
      expect(keys.contains('2026-08-01'), isTrue);
    });

    test('all 30 are writable against a clock at the END of the run', () {
      final start = DateTime(2026, 7, 20);
      final end = DateTime(2026, 8, 18).toUtc();
      for (var i = 0; i < 30; i++) {
        final k = dayKey(start.add(Duration(days: i)));
        expect(isPlausibleDayKey(k, end), isTrue, reason: k);
      }
    });

    test('none of the 30 was writable BEFORE its own day arrived', () {
      // The guard is not merely "not too far ahead" in aggregate — each day
      // only becomes writable when it is genuinely near.
      final start = DateTime(2026, 7, 20);
      final clockAtStart = start.toUtc();
      var refused = 0;
      for (var i = 0; i < 30; i++) {
        final k = dayKey(start.add(Duration(days: i)));
        if (!isPlausibleDayKey(k, clockAtStart)) refused++;
      }
      // ONLY DAY 0 is writable at that instant — 29 refused.
      //
      // Worth spelling out, because the naive expectation (28) is wrong and
      // the reason is the whole design: the ceiling is computed from the
      // clock in UTC. `DateTime(2026, 7, 20)` is local midnight, which on this
      // IST (+05:30) host is 2026-07-19T18:30Z, so `maxPlausibleDayKey` is
      // '2026-07-20' — day 0 exactly. The one day of slack is spent crossing
      // the member's own UTC offset, which is precisely what it exists for; it
      // does NOT hand a device an extra local day of runway.
      expect(refused, 29);
    });

    test('a 30-day span crossing a leap day stays consecutive', () {
      final start = DateTime(2028, 2, 15);
      final keys = [
        for (var i = 0; i < 30; i++) dayKey(start.add(Duration(days: i)))
      ];
      expect(keys.toSet().length, 30);
      expect(keys.contains('2028-02-29'), isTrue, reason: 'leap day present');
      expect(keys.contains('2028-03-01'), isTrue);
    });
  });

  group('PHASE 11 — the app and the server agree on the same day', () {
    test('the key the app mints is the key the guard accepts', () {
      // If `dayKey` and `isPlausibleDayKey` disagreed about format or
      // timezone, every legitimate write would be refused at the rules layer
      // and the member would silently stop being able to log.
      for (var i = 0; i < 400; i++) {
        final d = DateTime(2026, 1, 1).add(Duration(days: i));
        final k = dayKey(d);
        expect(isPlausibleDayKey(k, d.toUtc().add(const Duration(days: 1))),
            isTrue,
            reason: k);
      }
    });
  });
}
