import 'package:alphaserena/core/domain/coaching_event.dart';
import 'package:alphaserena/core/models/lifestyle_log_model.dart';
import 'package:alphaserena/core/models/lifestyle_targets.dart';
import 'package:alphaserena/core/services/lifestyle_event_service.dart';
import 'package:alphaserena/core/utils/lifestyle_math.dart';
import 'package:flutter_test/flutter_test.dart';

/// The COMPATIBILITY BRIDGE, pinned.
///
/// The member records events; TrainerHQ still reads the legacy totals
/// document. The bridge mirrored water, sleep and steps — and never
/// supplements — so a coach's supplement adherence read 0% however faithfully
/// the member ticked their stack.
CoachingEvent _event(String type, Map<String, dynamic> payload, {int at = 0}) =>
    CoachingEvent(
      eventId: 'e$at',
      type: type,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      payload: payload,
    );

CoachingEvent _dose(String itemId, {int at = 0}) => CoachingEvent(
      eventId: 'd${itemId}_$at',
      type: LifestyleEventType.supplementTaken,
      at: DateTime.fromMillisecondsSinceEpoch(at),
      payload: {'itemId': itemId},
    );

const _stack = [
  SupplementPlanItem(id: 'creatine', name: 'Creatine'),
  SupplementPlanItem(id: 'd3', name: 'Vitamin D3'),
  SupplementPlanItem(id: 'omega', name: 'Omega 3'),
];

void main() {
  group('projectSupplements — the field the mirror never wrote', () {
    test('ticks exactly the prescribed items the member dosed', () {
      final projected = LifestyleEventService.projectSupplements(
        [_dose('creatine'), _dose('omega', at: 10)],
        _stack,
      )!;
      expect(projected.map((s) => s.id), ['creatine', 'd3', 'omega']);
      expect(projected.map((s) => s.taken), [true, false, true]);
      // The coach's whole stack is projected, so taken/prescribed is 2/3 —
      // not 2/2, which would flatter the member.
      expect(projected.length, _stack.length);
    });

    test('several doses of one item is still one item taken', () {
      final projected = LifestyleEventService.projectSupplements(
        [_dose('creatine'), _dose('creatine', at: 10), _dose('creatine', at: 20)],
        _stack,
      )!;
      expect(projected.where((s) => s.taken).length, 1);
    });

    test('a withdrawn dose un-ticks the item', () {
      final projected = LifestyleEventService.projectSupplements(
        [_dose('creatine').copyWith(deleted: true)],
        _stack,
      )!;
      expect(projected.every((s) => !s.taken), isTrue);
    });

    test('no prescribed stack writes nothing rather than an empty array', () {
      // Writing [] would erase a legacy snapshot the member's old app wrote.
      expect(
        LifestyleEventService.projectSupplements([_dose('x')], const []),
        isNull,
      );
    });
  });

  group('legacySignature — the bridge writes only when it is behind', () {
    LifestyleLogModel logOf(Map<String, dynamic> m) =>
        LifestyleLogModel.fromMap(m, 'c_2026-08-01');

    test('an up-to-date projection produces no write', () {
      final events = [
        _event(LifestyleEventType.drink, {'ml': 250}),
        _event(LifestyleEventType.drink, {'ml': 250}, at: 5),
        _event(LifestyleEventType.stepsSample, {'count': 8000}, at: 10),
        _dose('creatine', at: 20),
      ];
      final mirrored = logOf({
        'waterMl': {'value': 500},
        'steps': {'value': 8000},
        'supplements': [
          {'id': 'creatine', 'name': 'Creatine', 'taken': true},
          {'id': 'd3', 'name': 'Vitamin D3', 'taken': false},
          {'id': 'omega', 'name': 'Omega 3', 'taken': false},
        ],
      });
      expect(
        LifestyleEventService.legacySignature(events, _stack),
        LifestyleEventService.legacySignatureOf(mirrored, _stack),
      );
    });

    test('a supplement tick alone makes the projection stale', () {
      // The exact case the old mirror could not detect, because it never
      // looked at supplements at all.
      final before = [_event(LifestyleEventType.drink, {'ml': 250})];
      final after = [...before, _dose('creatine', at: 5)];
      expect(
        LifestyleEventService.legacySignature(before, _stack),
        isNot(LifestyleEventService.legacySignature(after, _stack)),
      );
    });

    test('a day with no mirror document is always stale', () {
      expect(
        LifestyleEventService.legacySignatureOf(null, _stack),
        isNot(LifestyleEventService.legacySignature(
            [_event(LifestyleEventType.drink, {'ml': 250})], _stack)),
      );
    });

    test('sleep round-trips through the hours the legacy doc stores', () {
      final events = [
        _event(LifestyleEventType.sleep, {'minutes': 450}),
      ];
      final mirrored = logOf({
        'waterMl': {'value': 0},
        'sleepHours': {'value': 7.5},
      });
      expect(
        LifestyleEventService.legacySignature(events, const []),
        LifestyleEventService.legacySignatureOf(mirrored, const []),
      );
    });
  });

  group('withEventsWithdrawn — the rapid-tap withdrawal race', () {
    List<CoachingEvent> drinks(int n) => [
          for (var i = 0; i < n; i++)
            CoachingEvent(
              eventId: 'drink_$i',
              type: LifestyleEventType.drink,
              at: DateTime.fromMillisecondsSinceEpoch(i * 1000),
              payload: const {'ml': 250},
            ),
        ];

    test('an unwithdrawn day is returned untouched', () {
      final events = drinks(3);
      expect(identical(withEventsWithdrawn(events, const {}), events), isTrue);
      expect(totalWaterMl(events), 750);
    });

    test('a pending withdrawal is honoured before the server confirms it', () {
      final events = drinks(3);
      final live = withEventsWithdrawn(events, {'drink_2'});
      expect(totalWaterMl(live), 500);
      // The next tap must now find a DIFFERENT event to withdraw — this is
      // exactly what two quick taps used to get wrong.
      expect(lastDrink(live)!.eventId, 'drink_1');
    });

    test('two successive withdrawals remove two glasses, not one', () {
      final events = drinks(3);
      final pending = <String>{};
      for (var tap = 0; tap < 2; tap++) {
        final target = lastDrink(withEventsWithdrawn(events, pending));
        pending.add(target!.eventId);
      }
      expect(pending, {'drink_2', 'drink_1'});
      expect(totalWaterMl(withEventsWithdrawn(events, pending)), 250);
    });

    test('withdrawing every glass reaches zero and then stops', () {
      final events = drinks(2);
      final pending = {'drink_0', 'drink_1'};
      final live = withEventsWithdrawn(events, pending);
      expect(totalWaterMl(live), 0);
      expect(lastDrink(live), isNull, reason: 'nothing left to withdraw');
    });

    test('an id that is not on the day changes nothing', () {
      final events = drinks(2);
      expect(totalWaterMl(withEventsWithdrawn(events, {'ghost'})), 500);
    });

    test('the same rule applies to supplement doses', () {
      final events = [
        _dose('creatine'),
        _dose('creatine', at: 10),
      ];
      final live = withEventsWithdrawn(events, {events.last.eventId});
      expect(supplementItemsTaken(live), {'creatine'},
          reason: 'one dose remains, so the item is still taken');
      expect(lastDoseOf(live, 'creatine')!.eventId, events.first.eventId);
    });
  });

  group('member entry validation', () {
    test('refuses what the derivation would silently discard', () {
      // totalSteps drops count < 0 or > maxStepsSample, and sleepMinutes drops
      // anything over a day — so an unvalidated entry was written as an event
      // every reader then ignored.
      expect(validateStepsEntry('-1'), isNotNull);
      expect(validateStepsEntry('250000'), isNotNull);
      expect(validateSleepEntry('30'), isNotNull);
      expect(validateSleepEntry('-2'), isNotNull);
    });

    test('accepts a real day, including a zero-step rest day', () {
      expect(validateStepsEntry('8000'), isNull);
      expect(validateStepsEntry('0'), isNull);
      expect(validateSleepEntry('7.5'), isNull);
      expect(validateSleepEntry(''), isNull);
    });
  });
}
