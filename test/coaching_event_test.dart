import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/coaching_event.dart';
import 'package:alphaserena/core/services/coaching_event_writer.dart';

/// WS-6 — AlphaSerena as an EVENT PRODUCER.
///
/// The member records events; the server derives every metric. These tests pin
/// the client mirror of the WS-5 derivations against the SAME fixtures the
/// backend suite uses (`functions/test/coaching_events.test.mjs`), following
/// the established cross-app parity pattern. If the two ever disagree, the
/// member's optimistic total and the coach's number diverge — which is the
/// class of defect this workstream exists to end.
void main() {
  final base = DateTime.utc(2026, 3, 1, 8);
  int ms(DateTime d) => d.millisecondsSinceEpoch;

  Map<String, dynamic> drink(int mlValue, {int minute = 0, String? key}) => {
        'type': LifestyleEventType.drink,
        'at': ms(base.add(Duration(minutes: minute))),
        'source': EventSource.manual,
        'sourceKey': ?key,
        'ml': mlValue,
      };

  group('event envelope', () {
    test('parses a map into time-ordered events, ties broken by id', () {
      final events = parseCoachingEvents({
        'b': drink(250, minute: 10),
        'a': drink(250),
        'c': drink(250, minute: 10),
      });
      expect(events.map((e) => e.eventId), ['a', 'b', 'c']);
    });

    test('a non-map container yields nothing rather than throwing', () {
      expect(parseCoachingEvents(null), isEmpty);
      expect(parseCoachingEvents([1, 2]), isEmpty);
    });

    test('soft-deleted events stay in the record but leave the totals', () {
      final events = parseCoachingEvents({
        'a': drink(250),
        'b': {...drink(250, minute: 5), 'deleted': true},
      });
      expect(events.length, 2, reason: 'the correction is part of the record');
      expect(totalWaterMl(events), 250);
    });

    test('toMap round-trips through the wire shape', () {
      final e = CoachingEvent(
        eventId: 'x',
        type: LifestyleEventType.drink,
        at: base,
        source: EventSource.wearable,
        sourceKey: 'k1',
        payload: const {'ml': 330},
      );
      final m = e.toMap();
      expect(m['type'], LifestyleEventType.drink);
      expect(m['source'], EventSource.wearable);
      expect(m['sourceKey'], 'k1');
      expect(m['ml'], 330);
      expect(m.containsKey('deleted'), isFalse,
          reason: 'absent means live — never write a false flag');
    });
  });

  group('duplication and concurrency', () {
    test('the same reading re-delivered counts ONCE', () {
      final events = parseCoachingEvents({
        'a': drink(250, key: 'abc'),
        'b': drink(250, minute: 1, key: 'abc'),
      });
      expect(totalWaterMl(events), 250);
    });

    test('two devices adding a glass concurrently BOTH count', () {
      // The legacy path reads the streamed total, adds, and writes an absolute
      // figure — so one device's glass silently overwrites the other's.
      final events = parseCoachingEvents({
        'phone-1': drink(250),
        'tablet-1': drink(250),
      });
      expect(totalWaterMl(events), 500);
    });

    test('unkeyed events never dedupe against each other', () {
      final events =
          parseCoachingEvents({'a': drink(250), 'b': drink(250)});
      expect(totalWaterMl(events), 500);
    });
  });

  group('derivations mirror the server', () {
    test('water is summed and implausible volumes ignored', () {
      final events = parseCoachingEvents({
        'a': drink(250),
        'b': drink(330, minute: 1),
        'c': drink(-100, minute: 2),
        'd': drink(999999, minute: 3),
      });
      expect(totalWaterMl(events), 580);
    });

    test('sleep duration derives from instants and merges overlaps', () {
      final night = DateTime.utc(2026, 3, 1, 22);
      final events = parseCoachingEvents({
        'a': {
          'type': LifestyleEventType.sleep,
          'at': ms(night),
          'source': EventSource.manual,
          'start': ms(night),
          'end': ms(DateTime.utc(2026, 3, 2, 6)),
        },
        'b': {
          'type': LifestyleEventType.sleep,
          'at': ms(night),
          'source': EventSource.wearable,
          'start': ms(DateTime.utc(2026, 3, 1, 23)),
          'end': ms(DateTime.utc(2026, 3, 2, 5)),
        },
      });
      expect(sleepMinutes(events), 480);
    });

    test('a stated duration is used only when no period was recorded', () {
      final stated = parseCoachingEvents({
        'a': {
          'type': LifestyleEventType.sleep,
          'at': ms(base),
          'source': EventSource.manual,
          'minutes': 450,
        },
      });
      expect(sleepMinutes(stated), 450);
    });

    test('no sleep recorded is null, never zero', () {
      expect(sleepMinutes(const []), isNull);
    });

    test('steps: device sums, manual is absolute, device wins', () {
      Map<String, dynamic> sample(int c,
              {required String source, String? key, int minute = 0}) =>
          {
            'type': LifestyleEventType.stepsSample,
            'at': ms(base.add(Duration(minutes: minute))),
            'source': source,
            'sourceKey': ?key,
            'count': c,
          };

      expect(
          totalSteps(parseCoachingEvents({
            'a': sample(3000, source: EventSource.healthKit, key: 'w1'),
            'b': sample(5000,
                source: EventSource.healthKit, key: 'w2', minute: 1),
            'c': sample(5000,
                source: EventSource.healthKit, key: 'w2', minute: 2),
          })),
          8000);

      expect(
          totalSteps(parseCoachingEvents({
            'a': sample(5000, source: EventSource.manual),
            'b': sample(8000, source: EventSource.manual, minute: 1),
          })),
          8000,
          reason: 'a manual entry is absolute — it replaces, never adds');

      expect(
          totalSteps(parseCoachingEvents({
            'a': sample(12000, source: EventSource.manual),
            'b': sample(9000,
                source: EventSource.googleFit, key: 'w', minute: 1),
          })),
          9000,
          reason: 'a measurement beats an estimate');
    });

    test('each supplement dose is its own event', () {
      Map<String, dynamic> dose(String item, int minute) => {
            'type': LifestyleEventType.supplementTaken,
            'at': ms(base.add(Duration(minutes: minute))),
            'source': EventSource.manual,
            'itemId': item,
          };
      final events = parseCoachingEvents({
        'a': dose('creatine', 0),
        'b': dose('creatine', 60),
        'c': dose('creatine', 120),
        'd': dose('omega3', 0),
      });
      expect(supplementDoses(events), 4,
          reason: '3x/day counts three — the legacy boolean could not');
      expect(supplementItemsTaken(events), {'creatine', 'omega3'});
    });
  });

  group('corrections withdraw events', () {
    test('lastDrink finds the most recent live drink', () {
      final events = parseCoachingEvents({
        'a': drink(250),
        'b': drink(330, minute: 5),
        'c': {...drink(500, minute: 9), 'deleted': true},
      });
      expect(lastDrink(events)!.eventId, 'b',
          reason: 'an already-withdrawn drink is not withdrawn twice');
    });

    test('lastDoseOf is scoped to one supplement', () {
      Map<String, dynamic> dose(String item, int minute) => {
            'type': LifestyleEventType.supplementTaken,
            'at': ms(base.add(Duration(minutes: minute))),
            'source': EventSource.manual,
            'itemId': item,
          };
      final events = parseCoachingEvents({
        'a': dose('creatine', 0),
        'b': dose('omega3', 5),
        'c': dose('creatine', 10),
      });
      expect(lastDoseOf(events, 'creatine')!.eventId, 'c');
      expect(lastDoseOf(events, 'nothing'), isNull);
    });

    test('withdrawing the only drink leaves an empty, not negative, day', () {
      final events = parseCoachingEvents({
        'a': {...drink(250), 'deleted': true},
      });
      expect(totalWaterMl(events), 0);
      expect(lastDrink(events), isNull);
    });
  });

  group('event ids', () {
    test('are unique across rapid minting', () {
      final ids = List.generate(500, (_) => newEventId());
      expect(ids.toSet().length, 500,
          reason: 'two taps must never collide into one event');
    });

    test('sort chronologically by their time prefix', () {
      final first = newEventId();
      final second = newEventId();
      expect(first.split('_').first.compareTo(second.split('_').first) <= 0,
          isTrue);
    });
  });

  group('day document identity', () {
    test('is deterministic so an offline replay targets the same document', () {
      expect(CoachingEventWriter.dayDocId('c1', '2026-03-01'),
          'c1_2026-03-01');
    });
  });
}
