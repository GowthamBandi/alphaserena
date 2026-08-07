import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/prescription.dart';

/// THE ONE ASSIGNMENT RESOLUTION RULE.
///
/// Every surface in the platform that answers "which plan?", "what is asked of
/// this member today?" or "did they miss this day?" resolves through
/// [resolveTrackExpectation]. These tests pin the rule itself, and each one
/// that names a defect FAILED against the hand-rolled copy it replaced.
///
/// Twinned into `trainersHQ/test/assignment_resolution_test.dart` — the only
/// difference is the package import. Re-diff both after any change here.
void main() {
  // Monday 2 Mar 2026, so weekday arithmetic is unambiguous.
  final mon = DateTime(2026, 3, 2);
  DateTime day(int offset) => DateTime(2026, 3, 2 + offset);

  Prescription daily({
    int version = 1,
    DateTime? from,
    DateTime? start,
    DateTime? end,
  }) =>
      Prescription(
        version: version,
        effectiveFrom: from ?? mon,
        startDate: start ?? mon,
        endDate: end,
        rhythm: const Rhythm.daily(),
      );

  AssignmentSlice slice({
    String status = 'active',
    required int createdAtMillis,
    Prescription? prescription,
    Set<String> excused = const {},
    DateTime? createdOn,
    DateTime? leftServiceOn,
  }) =>
      AssignmentSlice(
        status: status,
        createdAtMillis: createdAtMillis,
        prescription: prescription,
        excusedDays: excused,
        createdOn: createdOn,
        leftServiceOn: leftServiceOn,
      );

  group('pickAssignmentForExpectation — latest active wins', () {
    test('the most recently created ACTIVE assignment wins', () {
      final older = slice(createdAtMillis: 100, prescription: daily());
      final newer =
          slice(createdAtMillis: 200, prescription: daily(version: 2));
      expect(
        pickAssignmentForExpectation([older, newer]).slice,
        same(newer),
      );
      // Order of the input must not decide the answer.
      expect(
        pickAssignmentForExpectation([newer, older]).slice,
        same(newer),
      );
    });

    test(
      'IDENTICAL createdAt ties break to the LAST, matching the server',
      () {
        // REGRESSION: the coach workspace used a strict `.isAfter`, which keeps
        // the FIRST of two equal timestamps, while the server uses `>=` and
        // keeps the LAST. Two assignments written in one batch share a
        // serverTimestamp, so the coach and the member named different plans as
        // live for the same member at the same instant.
        final a = slice(createdAtMillis: 500, prescription: daily());
        final b = slice(createdAtMillis: 500, prescription: daily(version: 2));
        expect(pickAssignmentForExpectation([a, b]).slice, same(b));
      },
    );

    test('a missing/unknown status counts as active (legacy documents)', () {
      final legacy = slice(status: '', createdAtMillis: 100);
      expect(pickAssignmentForExpectation([legacy]).slice, same(legacy));
      expect(slice(status: 'garbage', createdAtMillis: 1).normalizedStatus,
          'active');
    });

    test('no active → most recent paused resolves paused, serving nothing', () {
      final p = pickAssignmentForExpectation([
        slice(status: 'paused', createdAtMillis: 100, prescription: daily()),
        slice(status: 'paused', createdAtMillis: 200, prescription: daily()),
      ]);
      expect(p.slice, isNull);
      expect(p.fallback, ExpectationKind.paused);
    });

    test('no active or paused → ended', () {
      final p = pickAssignmentForExpectation(
        [slice(status: 'ended', createdAtMillis: 100, prescription: daily())],
      );
      expect(p.slice, isNull);
      expect(p.fallback, ExpectationKind.ended);
    });

    test('an empty set is unknown, never a fabricated answer', () {
      final p = pickAssignmentForExpectation(const []);
      expect(p.slice, isNull);
      expect(p.fallback, ExpectationKind.unknown);
    });

    test('a paused plan never outranks a live one', () {
      final live = slice(createdAtMillis: 100, prescription: daily());
      final paused = slice(
        status: 'paused',
        createdAtMillis: 999,
        prescription: daily(),
      );
      expect(pickAssignmentForExpectation([live, paused]).slice, same(live));
    });
  });

  group('date scoping — a past day is answered about the past', () {
    test('an assignment created AFTER the day never wins that day', () {
      final old = slice(
        createdAtMillis: 100,
        prescription: daily(),
        createdOn: day(-30),
      );
      final assignedToday = slice(
        createdAtMillis: 900,
        prescription: daily(version: 9),
        createdOn: day(0),
      );
      // Unscoped, today's question: the new plan wins.
      expect(
        pickAssignmentForExpectation([old, assignedToday]).slice,
        same(assignedToday),
      );
      // Scoped to last week: it did not exist yet.
      expect(
        pickAssignmentForExpectation([old, assignedToday], onDay: day(-7))
            .slice,
        same(old),
      );
    });

    test('a plan ENDED today was still running on a day it served', () {
      final ended = slice(
        status: 'ended',
        createdAtMillis: 100,
        prescription: daily(),
        createdOn: day(-30),
        leftServiceOn: day(0),
      );
      // Today: the coach removed it, so it serves nothing.
      expect(pickAssignmentForExpectation([ended]).fallback,
          ExpectationKind.ended);
      // Last week: it was demonstrably in service, so it answers that day.
      expect(
        pickAssignmentForExpectation([ended], onDay: day(-7)).slice,
        same(ended),
      );
    });

    test('a scoped pick NEVER answers from an empty set', () {
      // Nothing provably served that day, but a plan exists. A fabricated
      // absence is worse than an approximate identity.
      final s = slice(
        createdAtMillis: 100,
        prescription: daily(),
        createdOn: day(0),
      );
      expect(
        pickAssignmentForExpectation([s], onDay: day(-7)).slice,
        same(s),
      );
    });

    test('paused is NOT re-labelled by date — a pause has no date stamp', () {
      final paused = slice(
        status: 'paused',
        createdAtMillis: 100,
        prescription: daily(),
        createdOn: day(-30),
      );
      expect(
        pickAssignmentForExpectation([paused], onDay: day(-7)).fallback,
        ExpectationKind.paused,
      );
    });
  });

  group('resolveTrackExpectation — the canonical answer', () {
    test('a client-level pause outranks everything, including no plan', () {
      final r = resolveTrackExpectation(
        const [],
        mon,
        coachingPause: PrescriptionException(
          type: ExceptionType.medical,
          from: day(-1),
          to: day(1),
          note: 'knee',
        ),
      );
      expect(r.kind, ExpectationKind.paused);
      expect(r.reason, 'medical');
      expect(r.note, 'knee');
      expect(r.isRequired, isFalse);
    });

    test('a daily rhythm on a serving plan is required', () {
      final r = resolveTrackExpectation(
        [slice(createdAtMillis: 100, prescription: daily())],
        mon,
      );
      expect(r.kind, ExpectationKind.required);
      expect(r.prescribed, isTrue);
      expect(r.version, 1);
      expect(r.rhythm?.type, RhythmType.daily);
      expect(r.isRequired, isTrue);
    });

    test('an assignment with no prescription resolves disclosed-unknown', () {
      final r = resolveTrackExpectation(
        [slice(createdAtMillis: 100)],
        mon,
      );
      expect(r.kind, ExpectationKind.unknown);
      expect(r.prescribed, isFalse);
      expect(r.isRequired, isFalse);
    });

    test('a PAUSED assignment asks for nothing, and says why', () {
      final r = resolveTrackExpectation(
        [slice(status: 'paused', createdAtMillis: 100, prescription: daily())],
        mon,
      );
      expect(r.kind, ExpectationKind.paused);
      expect(r.isRequired, isFalse);
    });

    test('an ENDED assignment asks for nothing', () {
      final r = resolveTrackExpectation(
        [slice(status: 'ended', createdAtMillis: 100, prescription: daily())],
        mon,
      );
      expect(r.kind, ExpectationKind.ended);
      expect(r.isRequired, isFalse);
    });

    test(
      'an excuse on ANY assignment cancels the ask — merged, not per-slice',
      () {
        // REGRESSION: the coach workspace read no excuses at all, so a coach
        // was shown their own member as owing work on a day that same coach
        // had excused. `excuseDay` targets an arbitrary assignment id, so an
        // excuse landing on a non-picked assignment is a normal outcome.
        final serving = slice(createdAtMillis: 200, prescription: daily());
        final other = slice(
          status: 'ended',
          createdAtMillis: 100,
          prescription: daily(),
          excused: {'2026-03-02'},
        );
        final r = resolveTrackExpectation([serving, other], mon);
        expect(r.kind, ExpectationKind.required);
        expect(r.excusedToday, isTrue);
        // The whole point: an excused day is NOT asked for.
        expect(r.isRequired, isFalse);
      },
    );

    test('ONE DAY finishes overnight and never becomes a miss', () {
      // ONE DAY is the assign default, so this is the ordinary case now.
      final oneDay = slice(
        createdAtMillis: 100,
        prescription: Prescription(
          version: 1,
          effectiveFrom: mon,
          startDate: mon,
          rhythm: const Rhythm.oneDay(),
        ),
      );
      expect(
        resolveTrackExpectation([oneDay], mon).kind,
        ExpectationKind.required,
      );
      final tomorrow = resolveTrackExpectation([oneDay], day(1));
      expect(tomorrow.kind, ExpectationKind.ended);
      expect(tomorrow.isRequired, isFalse);
    });

    test('a queued future block reports needsHistory rather than guessing', () {
      final queued = slice(
        createdAtMillis: 100,
        prescription: daily(version: 2, from: day(7)),
      );
      final first = resolveTrackExpectation([queued], mon);
      expect(first.needsHistory, isTrue);
      expect(first.prescribed, isTrue);

      // Re-resolved with the superseded version, it answers from history.
      final second = resolveTrackExpectation(
        [queued],
        mon,
        historyVersions: [daily()],
      );
      expect(second.needsHistory, isFalse);
      expect(second.kind, ExpectationKind.required);
      expect(second.version, 1);
    });

    test('asOfDay resolves the day as it stood, not as it stands now', () {
      // The block has been in force for a month, so day(-7) is inside it —
      // otherwise the version simply had not started and `unknown` is right.
      final ended = slice(
        status: 'ended',
        createdAtMillis: 100,
        prescription: daily(from: day(-30), start: day(-30)),
        createdOn: day(-30),
        leftServiceOn: day(0),
      );
      // Today's question: the coach removed it.
      expect(
        resolveTrackExpectation([ended], mon).kind,
        ExpectationKind.ended,
      );
      // A review of last week: the member was demonstrably on it.
      expect(
        resolveTrackExpectation([ended], day(-7), asOfDay: true).kind,
        ExpectationKind.required,
      );
    });

    test('a rest day in the rhythm is not required and not a miss', () {
      final weekdays = slice(
        createdAtMillis: 100,
        prescription: Prescription(
          version: 1,
          effectiveFrom: mon,
          startDate: mon,
          // Mon / Wed / Fri
          rhythm: const Rhythm.weekdays({1, 3, 5}),
        ),
      );
      expect(
        resolveTrackExpectation([weekdays], mon).kind,
        ExpectationKind.required,
      );
      final tue = resolveTrackExpectation([weekdays], day(1));
      expect(tue.kind, ExpectationKind.rest);
      expect(tue.isRequired, isFalse);
    });

    test('a frequency rhythm requires no SPECIFIC day', () {
      final freq = slice(
        createdAtMillis: 100,
        prescription: Prescription(
          version: 1,
          effectiveFrom: mon,
          startDate: mon,
          rhythm: const Rhythm.frequency(3),
        ),
      );
      for (var i = 0; i < 7; i++) {
        final r = resolveTrackExpectation([freq], day(i));
        expect(r.kind, ExpectationKind.optional, reason: 'day $i');
        expect(r.isRequired, isFalse, reason: 'day $i');
      }
    });
  });
}
