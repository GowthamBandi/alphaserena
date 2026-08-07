import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/prescription.dart';

/// CROSS-PLATFORM SCENARIO PARITY — the Dart resolver against the REAL server.
///
/// `assignment_scenario_fixtures.json` is emitted by
/// `trainershq-backend/functions/scripts/emit_assignment_scenarios.mjs`, which
/// runs the **compiled TypeScript resolver** over 18 scenarios. This test
/// replays the same wire input through the Dart port and asserts the answers
/// are identical, day by day.
///
/// ⚠️ TWO SELF-CONSISTENT SIDES ARE NOT A CONTRACT. That assumption is how this
/// platform shipped the `coaching_rollups` outage: each side was internally
/// correct about a shape that never existed. Asserting against bytes the server
/// actually produced is the only thing that catches a drifted port.
///
/// Twinned into `trainersHQ/test/assignment_scenario_parity_test.dart`; the
/// fixture is byte-identical in both apps.
///
/// RULE: any change to the resolver MUST re-run the emitter and re-commit the
/// fixture in BOTH apps.
void main() {
  final file = File('test/assignment_scenario_fixtures.json');
  final scenarios =
      (jsonDecode(file.readAsStringSync()) as List).cast<Map<String, dynamic>>();

  DateTime parseDay(String key) {
    final p = key.split('-').map(int.parse).toList();
    return DateTime(p[0], p[1], p[2]);
  }

  AssignmentSlice sliceFrom(Map<String, dynamic> m) => AssignmentSlice(
    id: m['id'] as String,
    status: m['status'] as String,
    createdAtMillis: m['createdAtMillis'] as int,
    prescription: m['prescription'] == null
        ? null
        : Prescription.fromMap(
            Map<String, dynamic>.from(m['prescription'] as Map),
          ),
    excusedDays: (m['excusedDays'] as Map).keys
        .map((k) => k.toString())
        .toSet(),
    createdOn: m['createdOn'] == null
        ? null
        : parseDay(m['createdOn'] as String),
    leftServiceOn: m['leftServiceOn'] == null
        ? null
        : parseDay(m['leftServiceOn'] as String),
  );

  String kindName(ExpectationKind k) => k.name;

  test('the fixture is present and complete — a silent 0 is not a pass', () {
    // This repository has twice shipped a suite that executed nothing and
    // reported success. An empty fixture would make every assertion below
    // vacuous, so the count is asserted first.
    expect(scenarios, hasLength(19));
    final days = scenarios.fold<int>(
      0,
      (n, s) => n + (s['days'] as List).length,
    );
    expect(days, 127);
  });

  for (final s in scenarios) {
    final name = s['name'] as String;
    final input = s['input'] as Map<String, dynamic>;
    final slices = (input['slices'] as List)
        .map((e) => sliceFrom(Map<String, dynamic>.from(e as Map)))
        .toList();
    final pauseRaw = input['coachingPause'];
    final pause = pauseRaw == null
        ? null
        : PrescriptionException.fromMap(
            Map<String, dynamic>.from(pauseRaw as Map),
          );

    group('scenario: $name', () {
      test('lifecycle and winner identity match the server', () {
        final pick = pickAssignmentForExpectation(slices);
        expect(pick.slice?.id, s['winnerId'], reason: '$name winnerId');
        expect(pick.fallback.name, s['fallback'], reason: '$name fallback');

        // `trackLifecycleFor` has no Dart twin by design — the member app is
        // TOLD the lifecycle by the server. Its derivation is asserted here
        // from the same pick, which is what makes the two inseparable.
        final derived = pick.slice != null
            ? 'active'
            : switch (pick.fallback) {
                ExpectationKind.paused => 'paused',
                ExpectationKind.ended => 'ended',
                _ => 'none',
              };
        expect(derived, s['lifecycle'], reason: '$name lifecycle');
      });

      for (final d in (s['days'] as List).cast<Map<String, dynamic>>()) {
        final day = parseDay(d['day'] as String);
        final asOf = d['asOf'] as Map<String, dynamic>;
        final asNow = d['asNow'] as Map<String, dynamic>;

        test('${d['day']} resolves identically on both platforms', () {
          // HISTORY REVIEW — `asOfDay` ON, what every coach surface uses.
          final scoped = resolveTrackExpectation(
            slices,
            day,
            coachingPause: pause,
            asOfDay: true,
          );
          expect(kindName(scoped.kind), asOf['kind'], reason: 'asOf.kind');
          expect(scoped.reason, asOf['reason'], reason: 'asOf.reason');
          expect(
            scoped.excusedToday,
            asOf['excusedToday'],
            reason: 'asOf.excusedToday',
          );
          expect(scoped.version, asOf['version'], reason: 'asOf.version');
          expect(
            scoped.needsHistory,
            asOf['needsHistory'],
            reason: 'asOf.needsHistory',
          );

          // TODAY'S SERVING PATH — `asOfDay` OFF.
          final now = resolveTrackExpectation(
            slices,
            day,
            coachingPause: pause,
          );
          expect(kindName(now.kind), asNow['kind'], reason: 'asNow.kind');
          expect(now.reason, asNow['reason'], reason: 'asNow.reason');
          expect(
            now.excusedToday,
            asNow['excusedToday'],
            reason: 'asNow.excusedToday',
          );
          expect(now.version, asNow['version'], reason: 'asNow.version');

          // The DATE-SCOPED winner — the #15 rule.
          expect(
            pickAssignmentForExpectation(slices, onDay: day).slice?.id,
            d['winnerAsOf'],
            reason: 'winnerAsOf',
          );
        });
      }
    });
  }

  group('the scenarios say what the product promises', () {
    Map<String, dynamic> byName(String n) =>
        scenarios.firstWhere((s) => s['name'] == n);

    List<String> kinds(String n, {bool asOf = true}) => (byName(n)['days']
            as List)
        .cast<Map<String, dynamic>>()
        .map((d) => (d[asOf ? 'asOf' : 'asNow'] as Map)['kind'] as String)
        .toList();

    test('TODAY ONLY asks once, then is finished — never a miss', () {
      final k = kinds('today_only');
      expect(k.first, 'required');
      // Every subsequent day, including a month later.
      expect(k.skip(1).toSet(), {'ended'});
    });

    test('ANY X PER WEEK never requires a specific day', () {
      expect(kinds('any_x_per_week').toSet(), {'optional'});
    });

    test('a PAUSED assignment asks for nothing all week', () {
      expect(kinds('pause').toSet(), {'paused'});
      expect(byName('pause')['lifecycle'], 'paused');
    });

    test('an ARCHIVED assignment asks for nothing all week', () {
      expect(kinds('archive').toSet(), {'ended'});
    });

    test('no assignment at all is disclosed unknown, never a miss', () {
      expect(kinds('membership_inactive').toSet(), {'unknown'});
      expect(byName('membership_inactive')['lifecycle'], 'none');
    });

    test('a QUEUED future block refuses to guess rather than inventing', () {
      // The block's `effectiveFrom` has not arrived, so NO version is in force
      // and the resolver reports the disclosed `unknown` plus `needsHistory` —
      // it does not fabricate `notYetStarted` from a version it cannot see.
      // Either way it is never a miss.
      expect(kinds('future_assignment').toSet(), {'unknown'});
      final flags = (byName('future_assignment')['days'] as List)
          .cast<Map<String, dynamic>>()
          .map((d) => (d['asOf'] as Map)['needsHistory'])
          .toSet();
      expect(flags, {true});
    });

    test('a plan whose START date is later reads notYetStarted', () {
      // The distinct case: the version IS in force, the plan simply has not
      // begun. It becomes required on its start day and not before.
      final k = kinds('not_yet_started');
      expect(k.take(3).toSet(), {'notYetStarted'});
      expect(k[3], 'required'); // 5 Mar — the start date
    });

    test('an EXCUSED day is flagged on exactly one day', () {
      final days = (byName('excused_day')['days'] as List)
          .cast<Map<String, dynamic>>();
      final excused = days
          .where((d) => (d['asOf'] as Map)['excusedToday'] == true)
          .map((d) => d['day'])
          .toList();
      expect(excused, ['2026-03-04']);
    });

    test('OVERLAPPING assignments break the tie to the LAST written', () {
      // Two assignments sharing a serverTimestamp. The server takes the last;
      // the coach app used to take the first. Its Tue/Thu rhythm is what makes
      // the difference observable — Monday is rest, not required.
      expect(byName('overlapping')['winnerId'], 'new');
      expect(kinds('overlapping').first, 'rest');
    });

    test('a CLIENT-level pause outranks the rhythm for its range only', () {
      final k = kinds('client_level_pause');
      expect(k[0], 'required'); // 2 Mar — before the pause
      expect(k[1], 'paused'); // 3 Mar
      expect(k[3], 'paused'); // 5 Mar
      expect(k[4], 'required'); // 6 Mar — after it
    });

    test('a CYCLE alternates across a DST transition without slipping', () {
      // 1-on/1-off from 1 Mar: 7 Mar on, 8 Mar off, 9 Mar on — and the same
      // alternation still holds at the EU transition three weeks later.
      expect(kinds('dst_transition'), [
        'required', 'rest', 'required',
        'rest', 'required', 'rest',
      ]);
    });

    test('a rhythm keeps its footing across a MONTH boundary', () {
      // Mon/Wed/Fri. 30 Mar Mon, 31 Mar Tue, 1 Apr Wed, 2 Apr Thu.
      expect(kinds('month_boundary'), [
        'required', 'rest', 'required', 'rest',
      ]);
    });

    test('and across a YEAR boundary', () {
      // 3-on/1-off from 1 Jan 2025: the pattern must not reset at new year.
      expect(kinds('year_boundary').length, 4);
      expect(kinds('year_boundary').toSet().difference({'required', 'rest'}),
          isEmpty);
    });
  });
}
