import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/performance.dart';
import 'package:alphaserena/core/domain/prescription.dart';
import 'package:alphaserena/core/domain/today_expectation.dart'
    show localDayKey;

/// PRESCRIPTION ENGINE — Phase 4: the Member Performance domain.
///
/// The invariant under test throughout: every verdict, week count, streak and
/// insight traces to a prescription a coach actually wrote plus the member's
/// own logs — or resolves to an excluded/unknown state. No fabricated misses,
/// no guilt, no invented schedules.
void main() {
  // Monday 2 Mar 2026 — the shared anchor of every suite in this program.
  final mon = DateTime(2026, 3, 2);
  DateTime d(int offset) => mon.add(Duration(days: offset));
  String k(int offset) => localDayKey(d(offset));

  Prescription presc({
    int version = 1,
    DateTime? effectiveFrom,
    DateTime? start,
    DateTime? end,
    Rhythm rhythm = const Rhythm.daily(),
    List<PrescriptionException> exceptions = const [],
  }) => Prescription(
    version: version,
    effectiveFrom: effectiveFrom ?? mon,
    startDate: start ?? mon,
    endDate: end,
    rhythm: rhythm,
    exceptions: exceptions,
  );

  const mwf = Rhythm.weekdays({
    DateTime.monday,
    DateTime.wednesday,
    DateTime.friday,
  });

  group('TrackHistory.fromServed — parsing never invents', () {
    test('parses versions and excused days from the served map', () {
      final h = TrackHistory.fromServed({
        'versions': [
          {
            'version': 1,
            'effectiveFrom': '2026-03-02',
            'startDate': '2026-03-02',
            'rhythm': {'type': 'weekdays', 'weekdays': [1, 3, 5]},
          },
          'junk',
          {'broken': true},
        ],
        'excusedDays': {'2026-03-04': {'byId': 'coach'}},
      });
      expect(h.versions, hasLength(1));
      expect(h.excusedDays, {'2026-03-04'});
      expect(h.hasPrescription, isTrue);
    });

    test('absent / junk served data is an EMPTY history, not a schedule', () {
      expect(TrackHistory.fromServed(null).hasPrescription, isFalse);
      expect(TrackHistory.fromServed('junk').hasPrescription, isFalse);
    });
  });

  group('timeline — the coaching story', () {
    test('a compliant Mon/Wed/Fri member has ZERO misses', () {
      // The founding defect, closed at the timeline level: the old screen
      // showed ~4 fabricated misses per compliant week.
      final h = TrackHistory(versions: [presc(rhythm: mwf)]);
      final logged = {k(0), k(2), k(4)}; // Mon Wed Fri all done
      // Window d(0)..d(6): the full first week.
      final t = timeline(h, logged: logged, today: d(6), days: 7);
      expect(t.where((v) => v.isMiss), isEmpty);
      expect(t.where((v) => v.isHit).length, 3);
      expect(
        t.where((v) => v.expectation == ExpectationKind.rest).length,
        4,
      );
    });

    test('a skipped required day IS a miss — truth is not flattery', () {
      final h = TrackHistory(versions: [presc(rhythm: mwf)]);
      final t = timeline(h, logged: {k(0)}, today: d(7), days: 7);
      expect(t.where((v) => v.isMiss).length, 2); // Wed + Fri skipped
    });

    test('an excused day is never a miss', () {
      final h = TrackHistory(
        versions: [presc(rhythm: mwf)],
        excusedDays: {k(2)}, // coach excused Wednesday
      );
      final t = timeline(h, logged: {k(0)}, today: d(7), days: 7);
      expect(t.where((v) => v.isMiss).length, 1); // only Friday
      expect(
        t.where((v) => v.outcome == OutcomeKind.excusedByCoach).length,
        1,
      );
    });

    test('no prescription: every day excluded, none missed', () {
      final t = timeline(
        const TrackHistory(),
        logged: {k(1)},
        today: d(7),
        days: 7,
      );
      expect(t.where((v) => v.isMiss), isEmpty);
      expect(t.every((v) => v.expectation == ExpectationKind.unknown), isTrue);
    });
  });

  group('month view — every day an honest state', () {
    test('the full state vocabulary renders from one month', () {
      final h = TrackHistory(
        versions: [
          presc(
            rhythm: mwf,
            exceptions: [
              PrescriptionException(
                from: d(7),
                to: d(9),
                type: ExceptionType.medical,
              ),
            ],
          ),
        ],
        excusedDays: {k(4)}, // Friday excused
      );
      final cells = monthCells(
        h,
        logged: {k(0)},
        month: mon,
        // Friday d(11) — a REQUIRED today, so the open ring is reachable.
        today: d(11),
      );
      MonthCellState stateOn(int offset) =>
          cells.firstWhere((c) => c.date == d(offset)).state;

      expect(stateOn(0), MonthCellState.done); // Mon trained
      expect(stateOn(1), MonthCellState.rest); // Tue rest
      expect(stateOn(2), MonthCellState.missed); // Wed skipped
      expect(stateOn(4), MonthCellState.excused); // Fri excused
      expect(stateOn(7), MonthCellState.paused); // medical range
      expect(stateOn(10), MonthCellState.rest); // a rest TODAY-1 stays rest
      expect(stateOn(11), MonthCellState.today); // open required today
      expect(stateOn(12), MonthCellState.future); // not lived yet
      // Before the prescription started: unknown, faint — never a miss.
      final before = cells.firstWhere((c) => c.date == DateTime(2026, 3, 1));
      expect(before.state, MonthCellState.unknown);
    });

    test('training on a rest day shows DONE — bonus is celebrated', () {
      final h = TrackHistory(versions: [presc(rhythm: mwf)]);
      final cells = monthCells(
        h,
        logged: {k(1)}, // trained on rest Tuesday
        month: mon,
        today: d(7),
      );
      expect(
        cells.firstWhere((c) => c.date == d(1)).state,
        MonthCellState.done,
      );
    });
  });

  group('this week — Completed / Expected in the right unit', () {
    test('weekday prescription: expected = required days of the week', () {
      final h = TrackHistory(versions: [presc(rhythm: mwf)]);
      final w = weekSummary(h, logged: {k(0), k(2)}, today: d(3));
      expect(w.expected, 3); // Mon Wed Fri
      expect(w.done, 2);
      expect(w.isFrequency, isFalse);
    });

    test('frequency prescription: the unit is sessions, member picks days', () {
      final h = TrackHistory(versions: [presc(rhythm: const Rhythm.frequency(4))]);
      final w = weekSummary(h, logged: {k(1), k(3)}, today: d(4));
      expect(w.isFrequency, isTrue);
      expect(w.expected, 4);
      expect(w.done, 2);
      expect(w.remaining, 2);
    });

    test('an excused day leaves the ask — coach approval is visible', () {
      final h = TrackHistory(
        versions: [presc(rhythm: mwf)],
        excusedDays: {k(4)},
      );
      final w = weekSummary(h, logged: {k(0)}, today: d(5));
      expect(w.expected, 2); // Fri excused → not asked
      expect(w.coachApproved, 1);
    });

    test('a fully-paused week says paused, not zero-of-N', () {
      final h = TrackHistory(
        versions: [presc(rhythm: mwf)],
        coachingPause: PrescriptionException(
          from: d(-7),
          type: ExceptionType.medical,
        ),
      );
      expect(weekSummary(h, logged: {}, today: d(3)).paused, isTrue);
    });

    test('no prescription reads unknown — never 0 of 0 dressed up', () {
      expect(
        weekSummary(const TrackHistory(), logged: {}, today: d(3)).unknown,
        isTrue,
      );
    });
  });

  group('streaks — only the freeze-approved ones', () {
    test('weekly adherence: perfect Mon/Wed/Fri weeks count as weeks', () {
      final h = TrackHistory(versions: [presc(rhythm: mwf)]);
      // Two full perfect weeks, then the current (open) week with Monday done.
      final logged = {
        k(0), k(2), k(4), // week 1
        k(7), k(9), k(11), // week 2
        k(14), // current Monday
      };
      final s = weeklyAdherenceStreak(h, logged: logged, today: d(15));
      expect(s, 2); // current week transparent while open
    });

    test('a 4×/week member CAN exceed 2 — the original defect, closed', () {
      final h = TrackHistory(
        versions: [presc(rhythm: const Rhythm.frequency(4))],
      );
      final logged = {
        k(0), k(1), k(3), k(5), // 4 sessions week 1
        k(7), k(8), k(10), k(12), // 4 sessions week 2
        k(14), k(15), k(17), k(19), // 4 sessions week 3
      };
      expect(
        weeklyAdherenceStreak(h, logged: logged, today: d(21)),
        3,
      );
    });

    test('a paused week is transparent — never breaks the streak', () {
      final h = TrackHistory(
        versions: [
          presc(
            rhythm: mwf,
            exceptions: [
              PrescriptionException(
                from: d(7),
                to: d(13),
                type: ExceptionType.medical,
              ),
            ],
          ),
        ],
      );
      final logged = {
        k(0), k(2), k(4), // perfect week 1
        // week 2 fully paused, nothing logged
        k(14), k(16), k(18), // perfect week 3
      };
      expect(
        weeklyAdherenceStreak(h, logged: logged, today: d(20)),
        2, // both real weeks count; the paused one is invisible
      );
    });

    test('a missed required day ends the weekly streak at that week', () {
      final h = TrackHistory(versions: [presc(rhythm: mwf)]);
      final logged = {
        k(0), k(2), // Friday week 1 missed
        k(7), k(9), k(11), // perfect week 2
      };
      expect(weeklyAdherenceStreak(h, logged: logged, today: d(14)), 1);
    });

    test('dailyStreak: rest and paused days are transparent', () {
      final h = TrackHistory(versions: [presc(rhythm: mwf)]);
      final logged = {k(0), k(2), k(4), k(7)}; // every required day + next Mon
      // From Tue d(8): Mon done, weekend rest, Fri done … → unbroken run of 4.
      expect(dailyStreak(h, logged: logged, today: d(8)), 4);
    });

    test('no prescription → weekly streak 0, honestly', () {
      expect(
        weeklyAdherenceStreak(const TrackHistory(), logged: {k(0)},
            today: d(7)),
        0,
      );
    });
  });

  group('insights — evidence-gated, guilt-free', () {
    test('a compliant member gets the clean-week insight', () {
      final h = TrackHistory(versions: [presc(rhythm: mwf)]);
      final logged = {k(0), k(2), k(4), k(7), k(9), k(11)};
      final ins = insightsFor(
        h,
        logged: logged,
        today: d(12),
        trackLabel: 'workouts',
      );
      expect(ins.any((i) => i.kind == InsightKind.cleanWeek), isTrue);
    });

    test('a repeated weekday miss surfaces as a pattern, kindly worded', () {
      final h = TrackHistory(versions: [presc(rhythm: mwf)]);
      // Miss BOTH Wednesdays; hit everything else.
      final logged = {k(0), k(4), k(7), k(11)};
      final ins = insightsFor(
        h,
        logged: logged,
        today: d(14),
        trackLabel: 'workouts',
      );
      final pattern = ins.where((i) => i.kind == InsightKind.pattern);
      expect(pattern, isNotEmpty);
      expect(pattern.first.text, contains('Wednesdays'));
      expect(pattern.first.text.toLowerCase(), isNot(contains('fail')));
    });

    test('recovery-respected requires real rest days actually rested', () {
      final h = TrackHistory(versions: [presc(rhythm: mwf)]);
      final logged = {k(0), k(2), k(4), k(7), k(9), k(11)};
      final ins = insightsFor(
        h,
        logged: logged,
        today: d(13),
        trackLabel: 'workouts',
      );
      expect(ins.any((i) => i.kind == InsightKind.recovery), isTrue);
    });

    test('no prescription yields NO insights — nothing to say, said', () {
      expect(
        insightsFor(const TrackHistory(), logged: {k(0)}, today: d(7),
            trackLabel: 'workouts'),
        isEmpty,
      );
    });

    test('never more than three', () {
      final h = TrackHistory(versions: [presc(rhythm: mwf)]);
      final logged = {k(0), k(2), k(4), k(7), k(9), k(11)};
      expect(
        insightsFor(h, logged: logged, today: d(12), trackLabel: 'workouts')
            .length,
        lessThanOrEqualTo(3),
      );
    });
  });
}
