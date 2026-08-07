import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/performance.dart';
import 'package:alphaserena/core/domain/prescription.dart';

/// F4 — THE ASSIGNMENT'S LIFECYCLE MUST REACH THE MEMBER'S OWN ENGINE.
///
/// `prescriptionData` carried versions, excuses and the CLIENT-level pause and
/// nothing else. An assignment-level pause has no representation in any
/// prescription version, so the member app's local per-day engine could not
/// know the coach had benched the plan:
///
///   Home           → `expectation.kind == paused`  (server-resolved)
///   Consistency    → `required`, scored as a MISS  (locally resolved)
///
/// One response, two answers, about the same day — the same Home-vs-Consistency
/// split as the closed finding #37, in a new place.
///
/// The server now ships `lifecycle`, resolved by the ONE canonical pick, so the
/// two cannot disagree.
void main() {
  final monday = DateTime(2026, 3, 2);
  DateTime day(int o) => DateTime(2026, 3, 2 + o);

  Prescription daily() => Prescription(
    version: 1,
    effectiveFrom: DateTime(2026, 1, 1),
    startDate: DateTime(2026, 1, 1),
    rhythm: const Rhythm.daily(),
  );

  Map<String, dynamic> served({String? lifecycle}) => {
    'versions': [
      {
        'version': 1,
        'effectiveFrom': '2026-01-01',
        'startDate': '2026-01-01',
        'rhythm': {'type': 'daily'},
      },
    ],
    'excusedDays': <String, dynamic>{},
    'lifecycle': ?lifecycle,
  };

  group('the wire carries the lifecycle', () {
    test('a paused track parses as paused', () {
      final h = TrackHistory.fromServed(served(lifecycle: 'paused'));
      expect(h.lifecycle, TrackLifecycle.paused);
      expect(h.isPaused, isTrue);
    });

    test('active and ended parse too', () {
      expect(
        TrackHistory.fromServed(served(lifecycle: 'active')).lifecycle,
        TrackLifecycle.active,
      );
      expect(
        TrackHistory.fromServed(served(lifecycle: 'ended')).lifecycle,
        TrackLifecycle.ended,
      );
    });

    test('an OLDER BACKEND omitting the field changes nothing', () {
      // Zero-migration guarantee: a member on a build that predates the field
      // must behave exactly as before, not inherit an invented lifecycle.
      final h = TrackHistory.fromServed(served());
      expect(h.lifecycle, TrackLifecycle.none);
      expect(h.isPaused, isFalse);
      expect(
        h.verdictOn(monday, logged: const {}, today: monday).expectation,
        ExpectationKind.required,
      );
    });

    test('junk in the field degrades to none, never throws', () {
      expect(
        TrackHistory.fromServed(served(lifecycle: 'nonsense')).lifecycle,
        TrackLifecycle.none,
      );
    });
  });

  group('a paused track asks for nothing from today forward', () {
    test('today resolves paused, not required — THE defect', () {
      final h = TrackHistory.fromServed(served(lifecycle: 'paused'));
      final v = h.verdictOn(monday, logged: const {}, today: monday);
      expect(v.expectation, ExpectationKind.paused);
      // And therefore never a miss.
      expect(v.outcome, isNot(OutcomeKind.missed));
    });

    test('a day the member trained through the pause still counts as done', () {
      // The two-axis rule: a day the member trained is a day the member
      // trained, whatever the paperwork says.
      final h = TrackHistory.fromServed(served(lifecycle: 'paused'));
      final v = h.verdictOn(
        monday,
        logged: {'2026-03-02'},
        today: monday,
      );
      expect(v.expectation, ExpectationKind.paused);
      expect(v.outcome, OutcomeKind.done);
    });

    test('the current week reports paused rather than a wall of misses', () {
      final h = TrackHistory.fromServed(served(lifecycle: 'paused'));
      final w = weekSummary(h, logged: const {}, today: monday);
      expect(w.paused, isTrue);
    });
  });

  group('⚠️ a pause is NEVER applied backwards — it carries no date stamp', () {
    test('a day BEFORE today still resolves from the version history', () {
      // The pause document says only that the plan is paused NOW. Claiming the
      // member was benched last Tuesday would be the same present-tense error
      // this platform has already shipped twice — and it would erase a genuine
      // miss from their record.
      final h = TrackHistory.fromServed(served(lifecycle: 'paused'));
      final past = h.verdictOn(day(-5), logged: const {}, today: monday);
      expect(past.expectation, ExpectationKind.required);
      expect(past.outcome, OutcomeKind.missed);
    });

    test('and a past day they DID train still reads done', () {
      final h = TrackHistory.fromServed(served(lifecycle: 'paused'));
      final past = h.verdictOn(
        day(-5),
        logged: {'2026-02-25'},
        today: monday,
      );
      expect(past.outcome, OutcomeKind.done);
    });

    test('tomorrow is paused too — forward, not just today', () {
      final h = TrackHistory.fromServed(served(lifecycle: 'paused'));
      expect(
        h.verdictOn(day(1), logged: const {}, today: monday).expectation,
        ExpectationKind.paused,
      );
    });
  });

  group('an ACTIVE lifecycle changes nothing', () {
    test('a live plan still resolves required and still misses', () {
      final h = TrackHistory.fromServed(served(lifecycle: 'active'));
      final v = h.verdictOn(day(-1), logged: const {}, today: monday);
      expect(v.expectation, ExpectationKind.required);
      expect(v.outcome, OutcomeKind.missed);
      expect(daily().rhythm.type, RhythmType.daily);
    });
  });

  group('F6 — the tapped-day sheet must not contradict the cell', () {
    // `expectationDetailOf` called `expectationFor` on `versions` directly, so
    // the sheet resolved from a strictly SMALLER set of facts than the calendar
    // cell that opens it: it could see neither the assignment-level pause nor
    // the merged excuse set. Tapping a "Coaching paused" cell opened a sheet
    // saying "Session expected".
    test('a paused day reads paused in the DETAIL, not just the cell', () {
      final h = TrackHistory.fromServed(served(lifecycle: 'paused'));
      final cell = h.verdictOn(monday, logged: const {}, today: monday);
      final sheet = h.expectationOn(monday, today: monday);
      expect(cell.expectation, ExpectationKind.paused);
      expect(sheet.kind, ExpectationKind.paused);
      expect(sheet.kind, cell.expectation);
    });

    test('cell and sheet agree on EVERY day of a fortnight', () {
      // The invariant, not a single case: whatever the cell says the day was,
      // the sheet that opens it must say the same.
      for (final lc in ['active', 'paused', 'ended', null]) {
        final h = TrackHistory.fromServed(served(lifecycle: lc));
        for (var i = -7; i <= 7; i++) {
          final d = day(i);
          final cell = h.verdictOn(d, logged: const {}, today: monday);
          final sheet = h.expectationOn(d, today: monday);
          expect(
            sheet.kind,
            cell.expectation,
            reason: 'lifecycle=$lc day=$i',
          );
        }
      }
    });

    test('a past day still reads required in the detail, pause or not', () {
      // The never-backwards rule must hold on the sheet too, or the detail
      // would quietly excuse a genuine miss the cell still counts.
      final h = TrackHistory.fromServed(served(lifecycle: 'paused'));
      expect(
        h.expectationOn(day(-3), today: monday).kind,
        ExpectationKind.required,
      );
    });
  });
}
