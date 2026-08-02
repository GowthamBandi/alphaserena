import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:alphaserena/controllers/lifestyle_history_controller.dart';
import 'package:alphaserena/core/services/member_rollup_service.dart';

/// THE MEMBER'S LIFESTYLE HISTORY.
///
/// Reads `coaching_rollups` — the SAME server-derived read model TrainerHQ
/// reads — so a member and their coach can never disagree about a past day.
/// These pin the parse, the statistics, and the distinctions that keep the
/// screen honest.
class _FakeRollups extends MemberRollupService {
  _FakeRollups(this._days);
  List<RollupDay> _days;
  bool fail = false;
  final _controller = StreamController<List<RollupDay>>.broadcast();

  void emit(List<RollupDay> next) {
    _days = next;
    _controller.add(next);
  }

  @override
  bool get canRead => true;

  @override
  Stream<List<RollupDay>> watchDays({int months = 3, DateTime? now}) {
    if (fail) return Stream.error(Exception('offline'));
    return Stream<List<RollupDay>>.value(_days)
        .asyncExpand((v) async* {
      yield v;
      yield* _controller.stream;
    });
  }
}

void main() {
  final now = DateTime(2026, 8, 15, 10);
  DateTime dayAgo(int n) {
    final d = now.subtract(Duration(days: n));
    return DateTime(d.year, d.month, d.day);
  }

  RollupDay day(
    int daysAgo, {
    double? waterMl,
    double? steps,
    double? sleepHours,
    int? supplementItems,
  }) =>
      RollupDay(
        date: dayAgo(daysAgo),
        waterMl: waterMl,
        steps: steps,
        sleepHours: sleepHours,
        supplementItems: supplementItems,
      );

  Map<String, dynamic> client({
    double? waterTargetMl = 3000,
    int? stepsTarget = 8000,
    double? sleepHoursTarget = 8,
    int stack = 2,
  }) =>
      {
        // Built explicitly rather than with collection-ifs: an absent target
        // and a null one are the same fact to the parser, and spelling it out
        // keeps the fixture readable.
        'lifestyleTargets': <String, dynamic>{
          'waterTargetMl': waterTargetMl,
          'stepsTarget': stepsTarget,
          'sleepHoursTarget': sleepHoursTarget,
        }..removeWhere((_, v) => v == null),
        'supplementPlan': [for (var i = 0; i < stack; i++) {'id': 's$i'}],
      };

  setUp(() => Get.testMode = true);
  tearDown(Get.reset);

  LifestyleHistoryController build(
    List<RollupDay> days, {
    Map<String, dynamic>? doc,
    bool fail = false,
  }) {
    final c = LifestyleHistoryController(
      rollups: _FakeRollups(days)..fail = fail,
      clientDoc: () => doc ?? client(),
      now: now,
    );
    c.onInit();
    return c;
  }

  // ── PARSING THE ROLLUP ───────────────────────────────────────────────────

  group('rollup parsing', () {
    test('reads the NESTED tracks.lifestyle.days map', () {
      // Nested, not a dotted key: `set()` does not interpret dots as field
      // paths, and the writer's dotted key once produced one field whose
      // literal NAME contained dots and no `tracks` map at all.
      final days = MemberRollupService.daysFrom({
        'tracks': {
          'lifestyle': {
            'days': {
              '2026-08-01': {
                'metrics': {
                  'waterMl': 2100, 'steps': 9200, 'sleepHours': 7.5,
                  'supplementItems': 2,
                },
              },
            },
          },
        },
      });
      expect(days, hasLength(1));
      expect(days.single.waterMl, 2100);
      expect(days.single.steps, 9200);
      expect(days.single.sleepHours, 7.5);
      expect(days.single.supplementItems, 2);
    });

    test('a metric the day never recorded stays NULL, never zero', () {
      final days = MemberRollupService.daysFrom({
        'tracks': {
          'lifestyle': {
            'days': {
              '2026-08-01': {'metrics': {'waterMl': 2100}},
            },
          },
        },
      });
      expect(days.single.waterMl, 2100);
      expect(days.single.steps, isNull, reason: '"did not log" is not "0"');
      expect(days.single.sleepHours, isNull);
    });

    test('a malformed or absent document yields nothing, never throws', () {
      expect(MemberRollupService.daysFrom(null), isEmpty);
      expect(MemberRollupService.daysFrom({}), isEmpty);
      expect(MemberRollupService.daysFrom({'tracks': 'nope'}), isEmpty);
      expect(
        MemberRollupService.daysFrom({'tracks': {'lifestyle': {'days': 5}}}),
        isEmpty,
      );
      // A day whose key is not a date is dropped rather than guessed at.
      expect(
        MemberRollupService.daysFrom({
          'tracks': {'lifestyle': {'days': {'not-a-date': {'metrics': {}}}}},
        }),
        isEmpty,
      );
    });

    test('month keys walk backwards and cross a year boundary', () {
      expect(MemberRollupService.monthKeys(DateTime(2026, 8, 15), 3),
          ['2026-08', '2026-07', '2026-06']);
      expect(MemberRollupService.monthKeys(DateTime(2026, 1, 5), 3),
          ['2026-01', '2025-12', '2025-11']);
    });

    test('the member window matches the coach window', () {
      // A different depth would let a coach reference a month the member
      // cannot open.
      expect(MemberRollupService.defaultMonths, 3);
    });
  });

  // ── STATISTICS ───────────────────────────────────────────────────────────

  group('statistics', () {
    test('averages, streaks and trend come from the logged days', () async {
      final c = build([
        for (var i = 1; i <= 6; i++) day(i, waterMl: 3200),
      ]);
      await Future<void>.delayed(Duration.zero);
      final h = c.historyFor(HabitKind.water);
      expect(h.avg7, 3200);
      expect(h.bestStreak, 6);
      // The current streak counts back from today/yesterday only.
      expect(h.currentStreak, 6);
    });

    test('an unlogged day is ABSENT, so it breaks no average', () async {
      final c = build([day(1, waterMl: 3000), day(3, waterMl: 1000)]);
      await Future<void>.delayed(Duration.zero);
      final h = c.historyFor(HabitKind.water);
      expect(h.dayValues, hasLength(2));
      expect(h.avg7, 2000, reason: 'two logged days, not seven');
      expect(h.dayValues.containsKey(dayAgo(2)), isFalse);
    });

    test('goal hit rate is over LOGGED days, never the calendar', () async {
      final c = build([
        day(1, waterMl: 3200), // hit
        day(2, waterMl: 1000), // miss
      ]);
      await Future<void>.delayed(Duration.zero);
      expect(c.historyFor(HabitKind.water).goalHitRate, 0.5);
    });

    test('no target means no hit rate, not a zero', () async {
      final c = build([day(1, waterMl: 3200)],
          doc: client(waterTargetMl: null));
      await Future<void>.delayed(Duration.zero);
      final h = c.historyFor(HabitKind.water);
      expect(h.hasTarget, isFalse);
      expect(h.goalHitRate, isNull);
      expect(h.currentStreak, 0, reason: 'no goal, so no goal-hit streak');
    });

    test('a FUTURE-dated day is excluded — a wrong device clock', () async {
      final c = build([day(-3, waterMl: 9000), day(1, waterMl: 3000)]);
      await Future<void>.delayed(Duration.zero);
      final h = c.historyFor(HabitKind.water);
      expect(h.dayValues, hasLength(1));
      expect(h.avg7, 3000);
    });

    test('best and toughest day come from logged days, ties to the newest',
        () async {
      final c = build([
        day(1, waterMl: 3000),
        day(2, waterMl: 4000),
        day(5, waterMl: 4000),
        day(3, waterMl: 500),
      ]);
      await Future<void>.delayed(Duration.zero);
      final h = c.historyFor(HabitKind.water);
      expect(h.bestDay!.key, dayAgo(2), reason: 'tie resolves to most recent');
      expect(h.worstDay!.key, dayAgo(3));
    });

    test('SUPPLEMENTS score against the prescribed stack, not against one',
        () async {
      // A target of 1.0 against an item COUNT would have scored "took any one
      // supplement" as a perfect day.
      final c = build([
        day(1, supplementItems: 2), // all of a 2-item stack
        day(2, supplementItems: 1), // half
      ], doc: client(stack: 2));
      await Future<void>.delayed(Duration.zero);
      final h = c.historyFor(HabitKind.supplements);
      expect(h.target, 2);
      expect(h.goalHitRate, 0.5);
      expect(h.currentStreak, 1);
    });

    test('no prescribed stack means no supplement target at all', () async {
      final c = build([day(1, supplementItems: 1)], doc: client(stack: 0));
      await Future<void>.delayed(Duration.zero);
      expect(c.historyFor(HabitKind.supplements).hasTarget, isFalse);
    });

    test('each habit reads only its own metric', () async {
      final c = build([day(1, waterMl: 3000)]);
      await Future<void>.delayed(Duration.zero);
      expect(c.historyFor(HabitKind.water).hasData, isTrue);
      // Steps were never recorded that day, so steps history is empty rather
      // than a row of zeroes.
      expect(c.historyFor(HabitKind.steps).hasData, isFalse);
    });
  });

  // ── STATES ───────────────────────────────────────────────────────────────

  group('states', () {
    test('a failed read is an ERROR, never an empty history', () async {
      final c = build(const [], fail: true);
      await Future<void>.delayed(Duration.zero);
      expect(c.loadError.value, isTrue);
      expect(c.isLoading.value, isFalse);
    });

    test('nothing logged is empty, and is not an error', () async {
      final c = build(const []);
      await Future<void>.delayed(Duration.zero);
      expect(c.loadError.value, isFalse);
      expect(c.historyFor(HabitKind.water).hasData, isFalse);
    });

    test('a new emission invalidates the memoized stats', () async {
      final rollups = _FakeRollups([day(1, waterMl: 1000)]);
      final c = LifestyleHistoryController(
        rollups: rollups,
        clientDoc: client,
        now: now,
      )..onInit();
      await Future<void>.delayed(Duration.zero);
      expect(c.historyFor(HabitKind.water).avg7, 1000);

      rollups.emit([day(1, waterMl: 1000), day(2, waterMl: 3000)]);
      await Future<void>.delayed(Duration.zero);
      // Stale memoized stats here would freeze a member's history the moment
      // they logged again.
      expect(c.historyFor(HabitKind.water).avg7, 2000);
    });
  });
}
