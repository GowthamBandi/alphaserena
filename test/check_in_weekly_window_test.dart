import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/utils/check_in_math.dart';

/// REGRESSION — BUG 3: "the questionnaire is editable every day of the week".
///
/// Reproduced on a real device on Thursday 6 Aug 2026: the full editor — seven
/// rating rows, a weight field and a live Submit button — with no previous
/// review, no coach response and no history above it.
///
/// The cause was that NOTHING in the stack had a concept of a week:
///   · `CheckInController.canSubmit` asked only "has the member typed
///     anything?" — no day, no week, no lock;
///   · `CheckInSubmissionService.submit` wrote to `_col.doc()`, a FRESH RANDOM
///     id, whenever no open packet existed, so duplicates were possible;
///   · `CheckInSubmissionModel` carried no week field at all;
///   · `firestore.rules` constrained ownership and `status` and nothing else.
void main() {
  // 2026: 3 Aug is a Monday, so 9 Aug is the Sunday that closes that week.
  final mon = DateTime(2026, 8, 3);
  final thu = DateTime(2026, 8, 6);
  final sat = DateTime(2026, 8, 8);
  final sun = DateTime(2026, 8, 9);
  final nextMon = DateTime(2026, 8, 10);

  group('the submission window', () {
    test('SUNDAY UNLOCKS the editor', () {
      expect(isCheckInWindowOpen(sun), isTrue);
      expect(canAuthorCheckIn(now: sun, submittedWeekKeys: const {}), isTrue);
      expect(checkInLockReason(now: sun, submittedWeekKeys: const {}), isNull);
    });

    test('MONDAY THROUGH SATURDAY the editor is locked', () {
      for (final d in [mon, thu, sat, DateTime(2026, 8, 4), DateTime(2026, 8, 5),
                       DateTime(2026, 8, 7)]) {
        expect(isCheckInWindowOpen(d), isFalse, reason: '$d must be locked');
        expect(canAuthorCheckIn(now: d, submittedWeekKeys: const {}), isFalse);
        expect(checkInLockReason(now: d, submittedWeekKeys: const {}),
            isNotNull,
            reason: 'a locked day must always say WHY');
      }
    });

    test('the reported state — Thursday — is locked and explains itself', () {
      expect(isCheckInWindowOpen(thu), isFalse);
      expect(checkInLockReason(now: thu, submittedWeekKeys: const {}),
          contains('Sunday'));
    });

    test('Saturday says the window opens TOMORROW', () {
      expect(checkInLockReason(now: sat, submittedWeekKeys: const {}),
          contains('tomorrow'));
    });
  });

  group('one review per week', () {
    test('submitting LOCKS THE WINDOW IMMEDIATELY, same day', () {
      final filed = {weekKeyFor(sun)};
      expect(canAuthorCheckIn(now: sun, submittedWeekKeys: filed), isFalse,
          reason: 'a second review for a filed week must be impossible');
      expect(checkInLockReason(now: sun, submittedWeekKeys: filed),
          contains('submitted'));
    });

    test('a filed week does not lock the NEXT week', () {
      final filed = {weekKeyFor(sun)};
      final nextSun = DateTime(2026, 8, 16);
      expect(canAuthorCheckIn(now: nextSun, submittedWeekKeys: filed), isTrue);
    });

    test('the week key is the same for every day of one ISO week', () {
      // Mon..Sun all belong to the week the Sunday closes — which is why the
      // Sunday author reviews a week that has FINISHED.
      final key = weekKeyFor(mon);
      for (final d in [mon, thu, sat, sun]) {
        expect(weekKeyFor(d), key, reason: '$d belongs to the same ISO week');
      }
      expect(weekKeyFor(nextMon), isNot(key), reason: 'a new week starts Monday');
    });
  });

  group('week-key boundaries', () {
    test('the ISO year comes from the THURSDAY, not from January 1st', () {
      // 2026-01-01 is a Thursday, so that week is 2026-W01.
      expect(weekKeyFor(DateTime(2026, 1, 1)), '2026-W01');
      // 2025-12-29 is the Monday of that same ISO week.
      expect(weekKeyFor(DateTime(2025, 12, 29)), '2026-W01',
          reason: 'a week spanning New Year must not split into two keys');
    });

    test('week numbers are zero-padded so keys sort chronologically', () {
      expect(weekKeyFor(DateTime(2026, 1, 1)), matches(r'^\d{4}-W\d{2}$'));
      expect('2026-W02'.compareTo('2026-W10') < 0, isTrue);
    });

    test('a local-midnight boundary does not move the week', () {
      // The window is judged in the MEMBER'S local calendar: a UTC test would
      // open it on Saturday evening west of Greenwich.
      expect(isCheckInWindowOpen(DateTime(2026, 8, 9, 0, 0, 1)), isTrue);
      expect(isCheckInWindowOpen(DateTime(2026, 8, 9, 23, 59, 59)), isTrue);
      expect(isCheckInWindowOpen(DateTime(2026, 8, 10, 0, 0, 1)), isFalse);
      expect(isCheckInWindowOpen(DateTime(2026, 8, 8, 23, 59, 59)), isFalse);
    });
  });

  group('a missed week is never back-filled', () {
    test('missing last week does not reopen it', () {
      // The member skipped the week ending 9 Aug. On Monday the 10th the
      // window is shut, and the key on offer is the CURRENT week — a missed
      // week is simply absent from the record, never retroactively editable.
      expect(isCheckInWindowOpen(nextMon), isFalse);
      expect(weekKeyFor(nextMon), isNot(weekKeyFor(sun)));
    });
  });
}
