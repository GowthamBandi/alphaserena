import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/utils/diet_log_restore.dart';

/// MID-SESSION PLAN CHANGE — the case the one-time restore deliberately skips.
///
/// `restoreAction` returns `noop` the moment the member has local marks, and
/// that is correct: re-running a full restore would clobber in-flight toggles
/// with whatever the server last echoed. But it means a plan arriving LATER in
/// the session — the member pulls to refresh after the coach edited the diet —
/// leaves an index-keyed status map describing a food list that no longer
/// exists.
///
/// The failure is silent and specific: mark Roti at index 3, have the coach
/// delete a food above it, refresh. Index 3 is now Paneer. The screen shows the
/// wrong food ticked, and the next write logs Paneer as eaten. Nothing errors.
///
/// These pin the remap that closes it.
void main() {
  group('remapStatusesOnPlanChange', () {
    test('a mark follows its food when a food ABOVE it is deleted', () {
      // The headline case. Old plan: [Oats, Milk, Egg, Roti]; the coach removes
      // Milk; Roti moves from index 3 to index 2 and must take its mark along.
      final old = <PlanFood>[
        (foodId: 'oats', meal: 'Breakfast'),
        (foodId: 'milk', meal: 'Breakfast'),
        (foodId: 'egg', meal: 'Breakfast'),
        (foodId: 'roti', meal: 'Dinner'),
      ];
      final next = <PlanFood>[
        (foodId: 'oats', meal: 'Breakfast'),
        (foodId: 'egg', meal: 'Breakfast'),
        (foodId: 'roti', meal: 'Dinner'),
      ];

      final remapped = remapStatusesOnPlanChange({3: 'eaten'}, old, next);

      expect(remapped, {2: 'eaten'});
      expect(
        remapped[3],
        isNull,
        reason: 'the mark must not stay on an index that now means another food',
      );
    });

    test('a pure REORDER moves every mark with its food', () {
      final old = <PlanFood>[
        (foodId: 'a', meal: 'Breakfast'),
        (foodId: 'b', meal: 'Lunch'),
      ];
      final next = <PlanFood>[
        (foodId: 'b', meal: 'Lunch'),
        (foodId: 'a', meal: 'Breakfast'),
      ];

      expect(
        remapStatusesOnPlanChange({0: 'eaten', 1: 'skipped'}, old, next),
        {1: 'eaten', 0: 'skipped'},
      );
    });

    test('a mark on a DELETED food is dropped, not reassigned', () {
      final old = <PlanFood>[
        (foodId: 'a', meal: 'Breakfast'),
        (foodId: 'b', meal: 'Lunch'),
      ];
      final next = <PlanFood>[(foodId: 'a', meal: 'Breakfast')];

      final remapped = remapStatusesOnPlanChange(
        {0: 'eaten', 1: 'eaten'},
        old,
        next,
      );
      expect(remapped, {0: 'eaten'});
    });

    test('an INSERTED food arrives unmarked', () {
      final old = <PlanFood>[(foodId: 'a', meal: 'Breakfast')];
      final next = <PlanFood>[
        (foodId: 'new', meal: 'Breakfast'),
        (foodId: 'a', meal: 'Breakfast'),
      ];

      final remapped = remapStatusesOnPlanChange({0: 'eaten'}, old, next);
      expect(remapped, {1: 'eaten'});
      expect(
        remapped.containsKey(0),
        isFalse,
        reason: 'a food the member has never seen must not arrive pre-ticked',
      );
    });

    test('the same food in two meals stays distinct', () {
      // A whey shake at breakfast and post-workout is one foodId in two meals;
      // marking one must never tick the other.
      final old = <PlanFood>[
        (foodId: 'whey', meal: 'Breakfast'),
        (foodId: 'whey', meal: 'Post-workout'),
      ];
      final next = <PlanFood>[
        (foodId: 'whey', meal: 'Post-workout'),
        (foodId: 'whey', meal: 'Breakfast'),
      ];

      expect(
        remapStatusesOnPlanChange({0: 'eaten'}, old, next),
        {1: 'eaten'},
      );
    });

    test('partial and skipped survive the remap unchanged', () {
      final old = <PlanFood>[
        (foodId: 'a', meal: 'Breakfast'),
        (foodId: 'b', meal: 'Lunch'),
        (foodId: 'c', meal: 'Dinner'),
      ];
      final next = <PlanFood>[
        (foodId: 'c', meal: 'Dinner'),
        (foodId: 'b', meal: 'Lunch'),
        (foodId: 'a', meal: 'Breakfast'),
      ];

      expect(
        remapStatusesOnPlanChange(
          {0: 'eaten', 1: 'partial', 2: 'skipped'},
          old,
          next,
        ),
        {2: 'eaten', 1: 'partial', 0: 'skipped'},
      );
    });

    test('an emptied plan drops every mark rather than stranding one', () {
      final old = <PlanFood>[(foodId: 'a', meal: 'Breakfast')];
      expect(remapStatusesOnPlanChange({0: 'eaten'}, old, const []), isEmpty);
    });

    test('freehand foods (no foodId) fall back to position', () {
      // Legacy/freehand items carry no identity, so position is all there is.
      final old = <PlanFood>[
        (foodId: '', meal: 'Breakfast'),
        (foodId: 'b', meal: 'Lunch'),
      ];
      final next = <PlanFood>[
        (foodId: '', meal: 'Breakfast'),
        (foodId: 'b', meal: 'Lunch'),
      ];
      expect(
        remapStatusesOnPlanChange({0: 'eaten', 1: 'eaten'}, old, next),
        {0: 'eaten', 1: 'eaten'},
      );
    });
  });

  group('planFoodsDiffer', () {
    test('identical plans do not differ — no needless remap or write', () {
      final a = <PlanFood>[
        (foodId: 'x', meal: 'Breakfast'),
        (foodId: 'y', meal: 'Lunch'),
      ];
      final b = <PlanFood>[
        (foodId: 'x', meal: 'Breakfast'),
        (foodId: 'y', meal: 'Lunch'),
      ];
      expect(planFoodsDiffer(a, b), isFalse);
    });

    test('a REORDER counts as different — the case a length check misses', () {
      // Same foods, same count, every index changed meaning. This is precisely
      // why the check compares position and not just membership.
      final a = <PlanFood>[
        (foodId: 'x', meal: 'Breakfast'),
        (foodId: 'y', meal: 'Lunch'),
      ];
      final b = <PlanFood>[
        (foodId: 'y', meal: 'Lunch'),
        (foodId: 'x', meal: 'Breakfast'),
      ];
      expect(planFoodsDiffer(a, b), isTrue);
    });

    test('a changed length differs', () {
      expect(
        planFoodsDiffer(
          const [(foodId: 'x', meal: 'Breakfast')],
          const [],
        ),
        isTrue,
      );
    });

    test('a swapped MEAL on the same food differs', () {
      expect(
        planFoodsDiffer(
          const [(foodId: 'x', meal: 'Breakfast')],
          const [(foodId: 'x', meal: 'Lunch')],
        ),
        isTrue,
      );
    });
  });
}
