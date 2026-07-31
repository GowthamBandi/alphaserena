import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/prescription.dart';

/// PRESCRIPTION ENGINE — Step 1 domain, every rule in the freeze.
///
/// The founding rule under test throughout: **every answer traces to a
/// prescription a coach actually wrote, or resolves to `unknown`.** Nothing is
/// inferred to make a screen look complete.
void main() {
  // Monday 2 Mar 2026, so weekday arithmetic is unambiguous.
  final mon = DateTime(2026, 3, 2);
  DateTime d(int offset) => mon.add(Duration(days: offset));

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

  // ── UNKNOWN: the honest default ────────────────────────────────────────
  group('unknown — every member on the platform today', () {
    test('no prescription resolves to unknown, never to daily', () {
      // THE rule. Assuming "daily" is what made a compliant Mon/Tue/Thu/Sat
      // member score 57%.
      expect(expectationFor([], mon).kind, ExpectationKind.unknown);
    });

    test('an unknown day is excluded from scoring entirely', () {
      final v = verdictFor([], mon, logged: false, today: d(5));
      expect(v.outcome, OutcomeKind.excluded);
      expect(v.isMiss, isFalse);
    });

    test('an unreadable prescription map yields null, not a default', () {
      expect(Prescription.fromMap(null), isNull);
      expect(Prescription.fromMap({'rhythm': 'garbage'}), isNull);
      expect(Prescription.fromMap({'version': 1}), isNull);
    });
  });

  // ── RHYTHMS ────────────────────────────────────────────────────────────
  group('rhythm: weekdays', () {
    const mtts = Rhythm.weekdays({
      DateTime.monday,
      DateTime.tuesday,
      DateTime.thursday,
      DateTime.saturday,
    });

    test('required on prescribed days, rest on the others', () {
      final p = [presc(rhythm: mtts)];
      expect(expectationFor(p, d(0)).kind, ExpectationKind.required); // Mon
      expect(expectationFor(p, d(1)).kind, ExpectationKind.required); // Tue
      expect(expectationFor(p, d(2)).kind, ExpectationKind.rest); // Wed
      expect(expectationFor(p, d(3)).kind, ExpectationKind.required); // Thu
      expect(expectationFor(p, d(4)).kind, ExpectationKind.rest); // Fri
      expect(expectationFor(p, d(5)).kind, ExpectationKind.required); // Sat
      expect(expectationFor(p, d(6)).kind, ExpectationKind.rest); // Sun
    });

    test('a prescribed rest day is NEVER a miss', () {
      // The defect this whole engine exists to close.
      final v = verdictFor([presc(rhythm: mtts)], d(2), logged: false, today: d(6));
      expect(v.expectation, ExpectationKind.rest);
      expect(v.isMiss, isFalse);
      expect(v.isExcluded, isTrue);
    });

    test('training on a rest day is a BONUS hit, never a penalty', () {
      final v = verdictFor([presc(rhythm: mtts)], d(2), logged: true, today: d(6));
      expect(v.isHit, isTrue);
      expect(v.isMiss, isFalse);
    });

    test('an empty weekday set is INVALID — not "no days"', () {
      // Would otherwise make every day rest and every member perfect.
      expect(const Rhythm.weekdays({}).isValid, isFalse);
      expect(presc(rhythm: const Rhythm.weekdays({})).isValid, isFalse);
    });
  });

  group('rhythm: frequency — the unit becomes the WEEK', () {
    const any4 = Rhythm.frequency(4);

    test('no individual day is required', () {
      // The member picks the days, so asking "did you train Tuesday?" is
      // meaningless. Every day is an opportunity; none is a miss.
      final p = [presc(rhythm: any4)];
      for (var i = 0; i < 7; i++) {
        expect(expectationFor(p, d(i)).kind, ExpectationKind.optional);
      }
    });

    test('an unlogged day under frequency is never a miss', () {
      final v = verdictFor([presc(rhythm: any4)], d(0), logged: false, today: d(6));
      expect(v.isMiss, isFalse);
    });

    test('the unit is week, not day', () {
      expect(any4.unit, ConsistencyUnit.week);
      expect(const Rhythm.daily().unit, ConsistencyUnit.day);
    });

    test('4 of 4 in a finished week is a hit, whichever days', () {
      final w = weekVerdict(any4, mon, loggedInWeek: 4, today: d(10));
      expect(w.outcome, WeekOutcome.hit);
    });

    test('6 of 4 is still a hit — never over 100%', () {
      expect(weekVerdict(any4, mon, loggedInWeek: 6, today: d(10)).outcome,
          WeekOutcome.hit);
    });

    test('2 of 4 in a FINISHED week is a miss', () {
      expect(weekVerdict(any4, mon, loggedInWeek: 2, today: d(10)).outcome,
          WeekOutcome.missed);
    });

    test('2 of 4 in the CURRENT week is OPEN, never a miss', () {
      // Judging a member on Wednesday for a weekly target would punish someone
      // who simply has not finished the week.
      expect(weekVerdict(any4, mon, loggedInWeek: 2, today: d(2)).outcome,
          WeekOutcome.open);
    });

    test('frequency is bounded — "8 per week" is a typo, not a plan', () {
      expect(const Rhythm.frequency(8).isValid, isFalse);
      expect(const Rhythm.frequency(0).isValid, isFalse);
      expect(const Rhythm.frequency(7).isValid, isTrue);
    });
  });

  group('rhythm: cycle', () {
    test('alternate day (1 on / 1 off) alternates correctly', () {
      final r = Rhythm.cycle(on: 1, off: 1, start: mon);
      final p = [presc(rhythm: r)];
      expect(expectationFor(p, d(0)).kind, ExpectationKind.required);
      expect(expectationFor(p, d(1)).kind, ExpectationKind.rest);
      expect(expectationFor(p, d(2)).kind, ExpectationKind.required);
    });

    test('3 on / 1 off drifts across weekdays — as it must', () {
      final r = Rhythm.cycle(on: 3, off: 1, start: mon);
      final p = [presc(rhythm: r)];
      for (final i in [0, 1, 2]) {
        expect(expectationFor(p, d(i)).kind, ExpectationKind.required);
      }
      expect(expectationFor(p, d(3)).kind, ExpectationKind.rest);
      expect(expectationFor(p, d(4)).kind, ExpectationKind.required);
    });

    test('dates before the cycle anchor are rest, not required', () {
      final r = Rhythm.cycle(on: 1, off: 1, start: d(5));
      expect(r.expectsOn(d(0)), isFalse);
    });

    test('a cycle without an anchor cannot be constructed OR parsed', () {
      // The type system forbids `start: null` at construction, so the only way
      // an anchorless cycle could enter the system is off the wire — and that
      // path rejects it rather than silently anchoring on today.
      expect(Rhythm.fromMap({'type': 'cycle', 'onDays': 1, 'offDays': 1}), isNull);
    });
  });

  // ── VALIDITY WINDOW ────────────────────────────────────────────────────
  group('validity', () {
    test('a client joining Wednesday is notYetStarted before that', () {
      final p = [presc(start: d(2))];
      expect(expectationFor(p, d(0)).kind, ExpectationKind.notYetStarted);
      expect(expectationFor(p, d(2)).kind, ExpectationKind.required);
    });

    test('notYetStarted is excluded, never a miss', () {
      final v = verdictFor([presc(start: d(2))], d(0), logged: false, today: d(6));
      expect(v.isMiss, isFalse);
      expect(v.isExcluded, isTrue);
    });

    test('after endDate the plan is ended and excluded', () {
      final p = [presc(end: d(3))];
      expect(expectationFor(p, d(4)).kind, ExpectationKind.ended);
      expect(
        verdictFor(p, d(4), logged: false, today: d(6)).isMiss,
        isFalse,
      );
    });

    test('endDate before startDate is invalid', () {
      expect(presc(start: d(5), end: d(1)).isValid, isFalse);
    });
  });

  // ── IMMUTABLE VERSIONS — history must never lie ────────────────────────
  group('versioning', () {
    test('a past date resolves the version in force THEN', () {
      // The rule that protects a coach's trust: moving a member 6 days → 4 must
      // not retroactively improve last month.
      final v1 = presc(version: 1, effectiveFrom: d(0), rhythm: const Rhythm.daily());
      final v2 = presc(
        version: 2,
        effectiveFrom: d(3),
        rhythm: const Rhythm.weekdays({DateTime.monday}),
      );
      final all = [v1, v2];

      // Wednesday (d2) predates v2 → daily was in force → required.
      expect(expectationFor(all, d(2)).kind, ExpectationKind.required);
      // Friday (d4) is under v2, and Friday is not a Monday → rest.
      expect(expectationFor(all, d(4)).kind, ExpectationKind.rest);
    });

    test('version order in the list does not matter', () {
      final v1 = presc(version: 1, effectiveFrom: d(0));
      final v2 = presc(version: 2, effectiveFrom: d(3));
      expect(versionEffectiveOn([v2, v1], d(4))!.version, 2);
      expect(versionEffectiveOn([v2, v1], d(1))!.version, 1);
    });

    test('a date before ANY version resolves to unknown', () {
      final v = presc(version: 1, effectiveFrom: d(5));
      expect(expectationFor([v], d(0)).kind, ExpectationKind.unknown);
    });

    test('same effectiveFrom → the higher version wins', () {
      final a = presc(version: 1, effectiveFrom: d(0));
      final b = presc(version: 2, effectiveFrom: d(0));
      expect(versionEffectiveOn([a, b], d(1))!.version, 2);
    });
  });

  // ── EXCEPTIONS ─────────────────────────────────────────────────────────
  group('exceptions', () {
    test('travel week suspends work without breaking anything', () {
      final p = [
        presc(
          exceptions: [
            PrescriptionException(
              from: d(1),
              to: d(4),
              type: ExceptionType.travel,
            ),
          ],
        ),
      ];
      expect(expectationFor(p, d(0)).kind, ExpectationKind.required);
      expect(expectationFor(p, d(2)).kind, ExpectationKind.rest);
      expect(expectationFor(p, d(5)).kind, ExpectationKind.required);
    });

    test('a deload REPLACES the rhythm rather than cancelling it', () {
      final p = [
        presc(
          exceptions: [
            PrescriptionException(
              from: d(0),
              to: d(6),
              type: ExceptionType.deload,
              replacementRhythm: const Rhythm.weekdays({DateTime.monday}),
            ),
          ],
        ),
      ];
      expect(expectationFor(p, d(0)).kind, ExpectationKind.required); // Mon
      expect(expectationFor(p, d(1)).kind, ExpectationKind.rest); // Tue
    });

    test('LATER exceptions win — travel layered on a deload', () {
      final p = [
        presc(
          exceptions: [
            PrescriptionException(
              from: d(0),
              to: d(6),
              type: ExceptionType.deload,
              replacementRhythm: const Rhythm.daily(),
            ),
            PrescriptionException(
              from: d(2),
              to: d(3),
              type: ExceptionType.travel,
            ),
          ],
        ),
      ];
      expect(expectationFor(p, d(1)).kind, ExpectationKind.required);
      expect(expectationFor(p, d(2)).kind, ExpectationKind.rest);
      expect(expectationFor(p, d(2)).reason, 'travel');
    });

    test('medical leave is OPEN-ENDED and pauses, not rests', () {
      // "I don't know when they're back" must be expressible.
      final p = [
        presc(
          exceptions: [
            PrescriptionException(from: d(2), type: ExceptionType.medical),
          ],
        ),
      ];
      expect(expectationFor(p, d(2)).kind, ExpectationKind.paused);
      expect(expectationFor(p, d(400)).kind, ExpectationKind.paused);
    });

    test('an exception ending before it starts is invalid', () {
      expect(
        presc(
          exceptions: [
            PrescriptionException(
              from: d(5),
              to: d(1),
              type: ExceptionType.travel,
            ),
          ],
        ).isValid,
        isFalse,
      );
    });
  });

  // ── CLIENT-LEVEL PAUSE ─────────────────────────────────────────────────
  group('client-level coaching pause', () {
    test('outranks the prescription entirely', () {
      // A coach pausing a member must not have to pause three tracks.
      final p = [presc()];
      final pause = PrescriptionException(
        from: d(1),
        to: d(3),
        type: ExceptionType.pause,
      );
      expect(
        expectationFor(p, d(2), coachingPause: pause).kind,
        ExpectationKind.paused,
      );
      expect(expectationFor(p, d(4), coachingPause: pause).kind,
          ExpectationKind.required);
    });

    test('paused days are excluded — the streak freezes, never breaks', () {
      final pause = PrescriptionException(
        from: d(1),
        type: ExceptionType.medical,
      );
      final v = verdictFor([presc()], d(2),
          logged: false, today: d(6), coachingPause: pause);
      expect(v.expectation, ExpectationKind.paused);
      expect(v.isMiss, isFalse);
      expect(v.isExcluded, isTrue);
    });
  });

  // ── OUTCOMES ───────────────────────────────────────────────────────────
  group('outcome axis', () {
    test('required + logged = hit', () {
      expect(verdictFor([presc()], d(0), logged: true, today: d(3)).isHit, isTrue);
    });

    test('required + ended day + unlogged = miss', () {
      expect(verdictFor([presc()], d(0), logged: false, today: d(3)).isMiss, isTrue);
    });

    test('TODAY is open, never a miss', () {
      final v = verdictFor([presc()], d(3), logged: false, today: d(3));
      expect(v.outcome, OutcomeKind.open);
      expect(v.isMiss, isFalse);
    });

    test('excusedByCoach protects the record without touching history', () {
      // Without this the only way to protect a member is retro-editing the
      // prescription, which corrupts every past number.
      final v = verdictFor([presc()], d(0),
          logged: false, today: d(3), excused: true);
      expect(v.outcome, OutcomeKind.excusedByCoach);
      expect(v.isMiss, isFalse);
      expect(v.isExcluded, isTrue);
    });
  });

  // ── CADENCE (check-in, weight, photo, measurements) ────────────────────
  group('cadence — due/overdue, never "missed"', () {
    test('no cadence set → never', () {
      expect(cadenceState(intervalDays: null, lastDone: null, today: mon),
          CadenceState.never);
      expect(cadenceState(intervalDays: 0, lastDone: null, today: mon),
          CadenceState.never);
    });

    test('never done with a cadence set → due', () {
      expect(cadenceState(intervalDays: 14, lastDone: null, today: mon),
          CadenceState.due);
    });

    test('inside the interval → not due', () {
      expect(cadenceState(intervalDays: 14, lastDone: d(0), today: d(3)),
          CadenceState.notDue);
    });

    test('one interval late → due, not overdue', () {
      // A coach does not want an alert the moment a member is an hour past due.
      expect(cadenceState(intervalDays: 7, lastDone: d(0), today: d(8)),
          CadenceState.due);
    });

    test('two intervals late → overdue', () {
      expect(cadenceState(intervalDays: 7, lastDone: d(0), today: d(14)),
          CadenceState.overdue);
    });
  });

  // ── TARGETS (water, sleep, steps, supplements) ─────────────────────────
  group('targets — only scored when the COACH set one', () {
    test('no coach target → noTargetSet, never "failed"', () {
      // A platform default must never masquerade as a prescription.
      expect(targetState(target: null, actual: 5), TargetState.noTargetSet);
      expect(targetState(target: 0, actual: 5), TargetState.noTargetSet);
    });

    test('met and not met', () {
      expect(targetState(target: 8, actual: 8), TargetState.met);
      expect(targetState(target: 8, actual: 9), TargetState.met);
      expect(targetState(target: 8, actual: 3), TargetState.notMet);
      expect(targetState(target: 8, actual: null), TargetState.notMet);
    });
  });

  // ── SERIALIZATION ──────────────────────────────────────────────────────
  group('serialization round-trips', () {
    test('every rhythm survives toMap → fromMap', () {
      final rhythms = <Rhythm>[
        const Rhythm.daily(),
        const Rhythm.weekdays({DateTime.monday, DateTime.thursday}),
        const Rhythm.frequency(4),
        Rhythm.cycle(on: 3, off: 1, start: mon),
      ];
      for (final r in rhythms) {
        final back = Rhythm.fromMap(r.toMap())!;
        expect(back.type, r.type);
        expect(back.weekdays, r.weekdays);
        expect(back.count, r.count);
        expect(back.onDays, r.onDays);
        expect(back.expectsOn(d(0)), r.expectsOn(d(0)));
      }
    });

    test('a full prescription round-trips including exceptions', () {
      final p = presc(
        version: 3,
        rhythm: const Rhythm.frequency(4),
        end: d(30),
        exceptions: [
          PrescriptionException(
            from: d(2),
            to: d(4),
            type: ExceptionType.travel,
            note: 'Delhi trip',
          ),
        ],
      );
      final back = Prescription.fromMap(p.toMap())!;
      expect(back.version, 3);
      expect(back.rhythm.type, RhythmType.frequency);
      expect(back.rhythm.count, 4);
      expect(back.endDate, d(30));
      expect(back.exceptions.length, 1);
      expect(back.exceptions.first.note, 'Delhi trip');
      expect(back.exceptions.first.type, ExceptionType.travel);
    });

    test('optional fields are OMITTED, not written as null', () {
      // Keeps documents small and makes "absent" unambiguous downstream.
      final m = presc().toMap();
      expect(m.containsKey('endDate'), isFalse);
      expect(m.containsKey('exceptions'), isFalse);
      expect(m.containsKey('note'), isFalse);
    });

    test('an ISO date string parses (the wire format)', () {
      final back = Prescription.fromMap({
        'version': 1,
        'effectiveFrom': '2026-03-02',
        'startDate': '2026-03-02',
        'rhythm': {'type': 'daily'},
      })!;
      expect(back.effectiveFrom, mon);
    });
  });

  // ── MISSION VERIFICATION SCENARIOS ─────────────────────────────────────
  group('mission scenarios', () {
    test('specific weekdays — a compliant member is never marked down', () {
      const mtts = Rhythm.weekdays({
        DateTime.monday,
        DateTime.tuesday,
        DateTime.thursday,
        DateTime.saturday,
      });
      final p = [presc(rhythm: mtts)];
      final logged = {0, 1, 3, 5}; // exactly the prescription
      var misses = 0, hits = 0;
      for (var i = 0; i < 7; i++) {
        final v = verdictFor(p, d(i), logged: logged.contains(i), today: d(7));
        if (v.isMiss) misses++;
        if (v.isHit) hits++;
      }
      expect(misses, 0, reason: 'following the coach exactly cannot produce a miss');
      expect(hits, 4);
    });

    test('any 4 sessions/week — days chosen freely, week scored', () {
      const any4 = Rhythm.frequency(4);
      final p = [presc(rhythm: any4)];
      // Trained Tue/Wed/Fri/Sun — none of them "prescribed" days.
      for (final i in [1, 2, 4, 6]) {
        expect(verdictFor(p, d(i), logged: true, today: d(7)).isHit, isTrue);
      }
      expect(weekVerdict(any4, mon, loggedInWeek: 4, today: d(7)).outcome,
          WeekOutcome.hit);
    });

    test('Ramadan — a date-ranged rhythm replacement', () {
      final p = [
        presc(
          rhythm: const Rhythm.weekdays({
            DateTime.monday,
            DateTime.tuesday,
            DateTime.wednesday,
            DateTime.thursday,
            DateTime.friday,
          }),
          exceptions: [
            PrescriptionException(
              from: d(0),
              to: d(29),
              type: ExceptionType.custom,
              replacementRhythm: const Rhythm.frequency(3),
              note: 'Ramadan — post-iftar',
            ),
          ],
        ),
      ];
      // During: frequency → no day is required, none is a miss.
      expect(expectationFor(p, d(0)).kind, ExpectationKind.optional);
      // After: the base rhythm resumes.
      expect(expectationFor(p, d(30)).kind, ExpectationKind.required);
    });

    test('future prescription — queued next block', () {
      final now = presc(version: 1, effectiveFrom: d(0));
      final next = presc(
        version: 2,
        effectiveFrom: d(28),
        rhythm: const Rhythm.frequency(5),
      );
      expect(versionEffectiveOn([now, next], d(10))!.version, 1);
      expect(versionEffectiveOn([now, next], d(30))!.version, 2);
    });

    test('recovery week then back to normal', () {
      final p = [
        presc(
          exceptions: [
            PrescriptionException(
              from: d(7),
              to: d(13),
              type: ExceptionType.deload,
              replacementRhythm: const Rhythm.frequency(2),
            ),
          ],
        ),
      ];
      expect(expectationFor(p, d(3)).kind, ExpectationKind.required);
      expect(expectationFor(p, d(9)).kind, ExpectationKind.optional);
      expect(expectationFor(p, d(20)).kind, ExpectationKind.required);
    });

    test('a day cannot be both a hit and a miss, in any configuration', () {
      // Invariant sweep across rhythms, logs and exception states.
      final configs = <List<Prescription>>[
        [presc()],
        [presc(rhythm: const Rhythm.weekdays({DateTime.monday}))],
        [presc(rhythm: const Rhythm.frequency(3))],
        [presc(rhythm: Rhythm.cycle(on: 2, off: 1, start: mon))],
        [presc(start: d(3))],
        [presc(end: d(2))],
      ];
      for (final cfg in configs) {
        for (var i = 0; i < 10; i++) {
          for (final logged in [true, false]) {
            final v = verdictFor(cfg, d(i), logged: logged, today: d(9));
            expect(v.isHit && v.isMiss, isFalse);
            if (v.isMiss) {
              expect(v.expectation, ExpectationKind.required,
                  reason: 'only a REQUIRED day can ever be a miss');
            }
          }
        }
      }
    });
  });
}
