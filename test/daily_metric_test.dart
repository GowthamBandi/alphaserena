import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/screens/dashboard/home/daily_metric.dart';

/// THE DATA CONTRACT BEHIND BOTH HOME PROGRESS CARDS.
///
/// Nutrition and Lifestyle no longer share a layout, so this is the only thing
/// left that keeps them honest in the same way. It pins the distinctions the
/// model exists to preserve: a target nobody set, a day nobody logged, a
/// shortfall and an achievement are four different facts and only one of them
/// is a failure.
DailyMetric metric({
  String label = 'Water',
  double? current,
  double? target,
  String unit = 'glasses',
}) =>
    DailyMetric(
      label: label,
      unit: unit,
      format: (v) => v.round().toString(),
      current: current,
      target: target,
    );

void main() {
  group('status distinguishes four different facts', () {
    test('no target set is NOT a shortfall', () {
      final m = metric(current: 6);
      expect(m.status, MetricStatus.noTarget);
      expect(m.progress, isNull, reason: 'a bar against no target draws nothing');
      expect(m.percent, isNull);
      expect(m.targetLabel, 'No target set');
    });

    test('nothing logged is distinct from logging zero', () {
      final m = metric(target: 12);
      expect(m.status, MetricStatus.notLogged);
      expect(m.currentLabel, '—', reason: 'never a fabricated 0');
      expect(m.progress, isNull);
    });

    test('logged below target is behind', () {
      final m = metric(current: 6, target: 12);
      expect(m.status, MetricStatus.behind);
      expect(m.progress, 0.5);
      expect(m.percent, 50);
    });

    test('reaching the target is met', () {
      expect(metric(current: 12, target: 12).status, MetricStatus.met);
    });

    test('passing the target reads as the achievement it is', () {
      final m = metric(current: 18, target: 12);
      expect(m.status, MetricStatus.met);
      // The RING/BAR clamps so it cannot overflow its track...
      expect(m.progress, 1.0);
      // ...but the PERCENTAGE does not, so 150% is not flattened to 100%.
      expect(m.percent, 150);
    });

    test('a zero or negative target counts as no target', () {
      // A stored 0 is "not set", not a goal of nothing.
      expect(metric(current: 5, target: 0).status, MetricStatus.noTarget);
      expect(metric(current: 5, target: -3).status, MetricStatus.noTarget);
    });
  });

  group('one phrasing per fact', () {
    // ONE implementation, so the calorie ring and a lifestyle tile cannot
    // phrase the same fact two ways on one screen.
    test('a ratio when there is a target', () {
      expect(metric(current: 6, target: 12).valueLabel, '6 / 12 glasses');
    });

    test('the bare value when there is nothing to divide by', () {
      expect(metric(current: 6).valueLabel, '6 glasses');
    });

    test('a dash against the target when nothing is logged', () {
      expect(metric(target: 12).valueLabel, '— / 12 glasses');
      expect(metric(target: 12).valueLabel, isNot(contains('0 /')));
    });

    test('an em dash alone when there is neither', () {
      expect(metric().valueLabel, '—');
    });

    test('a screen reader hears one sentence, with the percentage', () {
      expect(
        metric(current: 6, target: 12).semanticLabel,
        'Water, 6 glasses of 12 glasses, 50%',
      );
      // No ratio → no percentage claimed.
      expect(metric(current: 6).semanticLabel, 'Water, 6 glasses of No target set');
    });
  });

  // THE DEFECT: Home's nutrition card derived its one sentence from
  // `entryCount` and `isLoading` and never consulted `loadError`. A FAILED read
  // leaves loading false and the entry count at zero, so the card told the
  // member "Nothing logged yet today" — a claim about their BEHAVIOUR made on
  // the strength of the app's own failure to read. The Diet screen branched on
  // the same flag correctly, so one fact was honest on one screen and false on
  // another.
  //
  // The numbers were never wrong (an absent value renders as an em dash, not a
  // zero). It was only ever the sentence, which is what makes it easy to miss
  // and worth pinning here.
  group('the nutrition card subtitle', () {
    test('a failed read is never reported as an empty log', () {
      expect(
        nutritionCardSubtitle(
            loadError: true, hasAnyTarget: true, entryCount: 0),
        "Couldn't load today's food",
      );
    });

    test('the failure outranks every other state', () {
      // We know nothing about what the member ate, so no other sentence can be
      // justified — including the reassuring ones.
      for (final hasTarget in [true, false]) {
        for (final count in [0, 3]) {
          expect(
            nutritionCardSubtitle(
                loadError: true, hasAnyTarget: hasTarget, entryCount: count),
            "Couldn't load today's food",
          );
        }
      }
    });

    test('no coach targets is distinct from nothing logged', () {
      expect(
        nutritionCardSubtitle(
            loadError: false, hasAnyTarget: false, entryCount: 0),
        'No coach targets yet',
      );
      expect(
        nutritionCardSubtitle(
            loadError: false, hasAnyTarget: true, entryCount: 0),
        'Nothing logged yet today',
      );
    });

    test('a logged day with targets reads as the normal state', () {
      expect(
        nutritionCardSubtitle(
            loadError: false, hasAnyTarget: true, entryCount: 2),
        "Today's nutrition",
      );
    });
  });
}
