import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/utils/day_key_guard.dart';
import 'package:alphaserena/core/utils/lifestyle_math.dart';

/// P0 — DAY-KEY PLAUSIBILITY, member-app half.
///
/// Pins the production incident (captured 2026-08-06 from `trainershq-f5ded`,
/// member EkNg2Yux4lPAQtSpQjds) in which a device with a fast clock wrote:
///
///   client_lifestyle_days/…_2026-08-06  server receipt 2026-08-03 08:24 IST (+3.18 d)
///   client_lifestyle_days/…_2026-08-09  server receipt 2026-08-03 09:07 IST (+6.00 d)
///
/// Every clock is INJECTED. A boundary test that reads the wall clock passes or
/// fails depending on when it happens to run.
void main() {
  /// The real server instant the first impossible document was received at.
  final incident = DateTime.utc(2026, 8, 3, 2, 54, 19); // 08:24:19 IST
  final serverNow = DateTime.utc(2026, 8, 6, 3, 11); // 08:41 IST

  group('utcDayKey', () {
    test('is UTC-based and zero-padded', () {
      expect(utcDayKey(DateTime.utc(2026, 8, 6, 3, 11)), '2026-08-06');
      expect(utcDayKey(DateTime.utc(2026, 1, 2)), '2026-01-02');
      expect(utcDayKey(DateTime.utc(2026, 8, 6, 23, 59, 59)), '2026-08-06');
      expect(utcDayKey(DateTime.utc(2026, 8, 7, 0, 0, 0)), '2026-08-07');
    });

    test('zero-padding is what makes string order chronological', () {
      // The whole guard is a string '<='. Unpadded '2026-8-6' sorts AFTER
      // '2026-08-09' and would defeat it.
      expect('2026-01-02'.compareTo('2026-08-09') < 0, isTrue);
    });

    test('converts a local instant to its UTC day', () {
      final local = DateTime.utc(2026, 8, 6, 20, 0).toLocal();
      expect(utcDayKey(local), '2026-08-06');
    });
  });

  group('the tolerance is the width of the world', () {
    test('exactly one day', () {
      expect(kDayKeyFutureToleranceDays, 1);
      expect(maxPlausibleDayKey(serverNow), '2026-08-07');
    });

    test('+1 is accepted — UTC+14 is a real place', () {
      expect(isPlausibleDayKey('2026-08-07', serverNow), isTrue);
    });

    test('+2 is refused — nowhere on earth is there', () {
      expect(isPlausibleDayKey('2026-08-08', serverNow), isFalse);
    });
  });

  group('THE INCIDENT', () {
    test('2026-08-06 written on 2026-08-03 is refused', () {
      expect(isPlausibleDayKey('2026-08-06', incident), isFalse);
    });

    test('2026-08-09 written on 2026-08-03 is refused', () {
      expect(isPlausibleDayKey('2026-08-09', incident), isFalse);
    });

    test('the days that were genuine on that device are still accepted', () {
      // 08-02/03/04 were written with the clock correct (server and client
      // agreed to within a second). The guard must not discard real data.
      expect(isPlausibleDayKey('2026-08-02', DateTime.utc(2026, 8, 2, 16, 9)),
          isTrue);
      expect(isPlausibleDayKey('2026-08-03', DateTime.utc(2026, 8, 3, 5, 19)),
          isTrue);
      expect(isPlausibleDayKey('2026-08-04', DateTime.utc(2026, 8, 4, 7, 58)),
          isTrue);
    });
  });

  group('NORMAL / YESTERDAY / TODAY', () {
    test('today and yesterday are accepted', () {
      expect(isPlausibleDayKey('2026-08-06', serverNow), isTrue);
      expect(isPlausibleDayKey('2026-08-05', serverNow), isTrue);
    });
  });

  group('OFFLINE REPLAY — the past is unbounded', () {
    test('a week-old day is accepted', () {
      expect(isPlausibleDayKey('2026-07-30', serverNow), isTrue);
    });

    test('a month-old and a year-old day are accepted', () {
      expect(isPlausibleDayKey('2026-07-06', serverNow), isTrue);
      expect(isPlausibleDayKey('2025-08-06', serverNow), isTrue);
    });
  });

  group('DEVICE CLOCK AHEAD / BEHIND', () {
    test('ahead: the key it mints is refused', () {
      // Device believes it is 2026-08-09; the server knows it is 2026-08-03.
      final deviceNow = DateTime(2026, 8, 9, 9, 4);
      expect(isPlausibleDayKey(dayKey(deviceNow), incident), isFalse);
    });

    test('behind: the key it mints is still accepted', () {
      // A slow clock produces an OLD key, which is indistinguishable from an
      // offline replay and must not be refused — the member really did live
      // that day, and refusing it would lose the log.
      final deviceNow = DateTime(2026, 8, 1, 9, 0);
      expect(isPlausibleDayKey(dayKey(deviceNow), serverNow), isTrue);
    });
  });

  group('TIMEZONE / UTC / IST / DST', () {
    test('IST (+05:30) near midnight stays within tolerance', () {
      // 2026-08-07 00:30 IST is 2026-08-06 19:00 UTC. The local key is one day
      // ahead of the UTC key — the exact case the tolerance exists for.
      final utcInstant = DateTime.utc(2026, 8, 6, 19, 0);
      expect(utcDayKey(utcInstant), '2026-08-06');
      expect(isPlausibleDayKey('2026-08-07', utcInstant), isTrue);
    });

    test('UTC+14 at local midnight is accepted', () {
      // Kiritimati 2026-08-07 00:30 local = 2026-08-06 10:30 UTC.
      expect(isPlausibleDayKey('2026-08-07', DateTime.utc(2026, 8, 6, 10, 30)),
          isTrue);
    });

    test('UTC-12 lagging a day is accepted', () {
      expect(isPlausibleDayKey('2026-08-05', DateTime.utc(2026, 8, 6, 3, 0)),
          isTrue);
    });

    test('DST does not move the ceiling — the reference is UTC', () {
      // UTC has no DST, which is precisely why it is the reference. A local
      // reference would shift by an hour twice a year and could flip a
      // near-midnight key.
      expect(maxPlausibleDayKey(DateTime.utc(2026, 3, 29, 1, 30)), '2026-03-30');
      expect(maxPlausibleDayKey(DateTime.utc(2026, 3, 29, 2, 30)), '2026-03-30');
    });
  });

  group('MONTH / YEAR / LEAP BOUNDARIES', () {
    test('the ceiling does not produce an impossible date', () {
      expect(maxPlausibleDayKey(DateTime.utc(2026, 8, 31, 12)), '2026-09-01');
      expect(maxPlausibleDayKey(DateTime.utc(2026, 12, 31, 12)), '2027-01-01');
      expect(maxPlausibleDayKey(DateTime.utc(2028, 2, 28, 12)), '2028-02-29');
      expect(maxPlausibleDayKey(DateTime.utc(2028, 2, 29, 12)), '2028-03-01');
    });
  });

  group('MALFORMED KEYS', () {
    test('are refused', () {
      for (final bad in ['', 'banana', '2026-8-6', '2026/08/06', '20260806',
        '2026-08-06T00:00:00Z']) {
        expect(isPlausibleDayKey(bad, serverNow), isFalse, reason: bad);
      }
    });
  });

  group('ServerClockBound — a lower bound learned from the server', () {
    setUp(() => ServerClockBound.instance.resetForTest());
    tearDown(() => ServerClockBound.instance.resetForTest());

    test('permits everything before any server instant is seen', () {
      // A fresh install has no trustworthy reference. Refusing here would
      // block a member's first log for a reason the app cannot substantiate;
      // the rules are the backstop for that window.
      expect(ServerClockBound.instance.permits('2099-01-01'), isTrue);
    });

    test('refuses an impossible key once a server instant is known', () {
      ServerClockBound.instance.observe(incident);
      expect(ServerClockBound.instance.permits('2026-08-09'), isFalse);
      expect(ServerClockBound.instance.permits('2026-08-06'), isFalse);
    });

    test('still permits today and the past against that bound', () {
      ServerClockBound.instance.observe(incident);
      expect(ServerClockBound.instance.permits('2026-08-03'), isTrue);
      expect(ServerClockBound.instance.permits('2026-07-20'), isTrue);
    });

    test('the bound only ever tightens — an older instant cannot loosen it',
        () {
      ServerClockBound.instance.observe(serverNow);
      ServerClockBound.instance.observe(incident); // older
      expect(ServerClockBound.instance.latest, serverNow);
      expect(ServerClockBound.instance.permits('2026-08-08'), isFalse);
    });

    test('a null observation is ignored', () {
      ServerClockBound.instance.observe(null);
      expect(ServerClockBound.instance.latest, isNull);
    });

    test('BACKGROUND SYNC: a later server instant advances the bound', () {
      ServerClockBound.instance.observe(incident);
      expect(ServerClockBound.instance.permits('2026-08-06'), isFalse);
      // Three days later the app syncs and sees a fresh server timestamp.
      ServerClockBound.instance.observe(serverNow);
      // The same key is now legitimately today and must be writable again.
      expect(ServerClockBound.instance.permits('2026-08-06'), isTrue);
    });
  });

  group('CROSS-BOUNDARY: the app and the server agree', () {
    test('dayKey output is always shape-valid for the guard', () {
      // `dayKey` mints the key; `isPlausibleDayKey` judges it. If the two
      // disagreed about the format, every write would be refused.
      for (final d in [
        DateTime(2026, 1, 1),
        DateTime(2026, 8, 6),
        DateTime(2026, 12, 31),
        DateTime(2028, 2, 29),
      ]) {
        expect(isPlausibleDayKey(dayKey(d), DateTime(2029)), isTrue,
            reason: dayKey(d));
      }
    });
  });
}
