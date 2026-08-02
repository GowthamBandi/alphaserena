import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/food_portion_math.dart';

/// PORTION ARITHMETIC — the member side of a CROSS-BINARY contract.
///
/// The `consumed` block on a logged entry is frozen at log time, and the client
/// is what computes it (the member is choosing the portion, and the preview has
/// to update as they drag). So these numbers must equal what the backend's
/// `scaleHydratedMacros` would produce for the same input.
///
/// The PER100 fixture and the expected values below are copied verbatim from
/// `trainershq-backend/functions/test/nutrition.test.mjs`
/// ("scaleHydratedMacros: scales per-100 by the item's grams"). This codebase
/// has already had two copies of one calculation drift silently — the two
/// `lifestyle_math.dart` files — so the fixture is duplicated deliberately: a
/// change on either side fails on that side.
void main() {
  // Verbatim from the backend test.
  const per100 = {
    'calories': 250.0,
    'protein': 10.0,
    'carbs': 40.0,
    'fat': 5.0,
    'fiber': 3.0,
    'sugar': 2.0,
    'saturatedFat': 1.0,
  };

  group('scaleMacros — twinned with the backend', () {
    test('scales per-100 by the actual grams', () {
      final scaled = scaleMacros(per100, 40); // a 40 g roti
      // These three are asserted with the SAME numbers in nutrition.test.mjs.
      expect(scaled['calories'], 100);
      expect(scaled['protein'], 4);
      expect(scaled['carbs'], 16);
      // The rest follow the same factor.
      expect(scaled['fat'], 2);
      expect(scaled['fiber'], 1.2);
    });

    test('no grams → per-100 returned unchanged (legacy items hold)', () {
      final scaled = scaleMacros(per100, null);
      expect(scaled['calories'], 250);
      expect(scaled['protein'], 10);
      final zero = scaleMacros(per100, 0);
      expect(zero['calories'], 250,
          reason: 'zero grams is "unknown", not "ate nothing"');
    });

    test('rounds to ONE decimal, exactly as the backend does', () {
      // 33 g of the fixture: 3.3 g protein, 0.99 g fiber → 1.0.
      final scaled = scaleMacros(per100, 33);
      expect(scaled['protein'], 3.3);
      expect(scaled['fiber'], 1.0);
      expect(scaled['saturatedFat'], 0.3);
    });

    test('every macro field the backend carries is produced', () {
      final scaled = scaleMacros(per100, 100);
      expect(scaled.keys.toSet(), kMacroFields.toSet());
      expect(kMacroFields, [
        'calories', 'protein', 'carbs', 'fat', 'fiber', 'sugar', 'saturatedFat',
      ]);
    });

    test('a missing or non-numeric macro reads as zero, never as a crash', () {
      final scaled = scaleMacros({'calories': '250', 'protein': null}, 50);
      expect(scaled['calories'], 125, reason: 'string numbers are tolerated');
      expect(scaled['protein'], 0);
      expect(scaled['carbs'], 0);
    });
  });

  group('PortionSelection — how an amount becomes grams', () {
    test('a portion multiplies its own gram weight', () {
      const s = PortionSelection(
        mode: PortionMode.portion,
        quantity: 2,
        portionLabel: 'katori',
        gramsPerPortion: 150,
      );
      expect(s.totalGrams, 300);
      expect(s.storedQuantity, 2);
      expect(s.storedUnit, 'katori',
          reason: 'the coach must read "2 katori", not only the macros');
      expect(s.isValid, isTrue);
    });

    test('grams mode stores the grams themselves', () {
      const s = PortionSelection.grams(180);
      expect(s.totalGrams, 180);
      expect(s.storedQuantity, 180);
      expect(s.storedUnit, 'g');
      expect(s.isValid, isTrue);
    });

    test('a half portion is expressible', () {
      const s = PortionSelection(
        mode: PortionMode.portion,
        quantity: 0.5,
        portionLabel: 'bowl',
        gramsPerPortion: 200,
      );
      expect(s.totalGrams, 100);
      expect(s.isValid, isTrue);
    });

    test('an unloggable amount is refused BEFORE it reaches Firestore', () {
      // Zero and negative amounts.
      expect(const PortionSelection.grams(0).isValid, isFalse);
      expect(const PortionSelection.grams(-5).isValid, isFalse);
      // Past the backend's MAX_ENTRY_GRAMS — the trigger would flag it, but
      // the member deserves to be told at the point of entry.
      expect(const PortionSelection.grams(kMaxEntryGrams + 1).isValid, isFalse);
      expect(const PortionSelection.grams(kMaxEntryGrams).isValid, isTrue);
      // A portion with no label cannot be rendered back to the member.
      expect(
        const PortionSelection(
          mode: PortionMode.portion,
          quantity: 1,
          gramsPerPortion: 100,
        ).isValid,
        isFalse,
      );
      // A portion whose gram weight is unknown yields zero grams.
      expect(
        const PortionSelection(
          mode: PortionMode.portion,
          quantity: 1,
          portionLabel: 'katori',
        ).isValid,
        isFalse,
      );
    });
  });

  group('sumMacros — the client preview of the server total', () {
    test('sums entries the way computeDayTotals does', () {
      final a = scaleMacros(per100, 40);
      final b = scaleMacros(per100, 60);
      final total = sumMacros([a, b]);
      // 40 g + 60 g = 100 g = exactly the per-100 row.
      expect(total['calories'], 250);
      expect(total['protein'], 10);
      expect(total['carbs'], 40);
    });

    test('an empty day totals zero across every field', () {
      final total = sumMacros(const []);
      for (final k in kMacroFields) {
        expect(total[k], 0, reason: '$k must be present and zero');
      }
    });

    test('rounding does not accumulate across many entries', () {
      // Thirty 33 g servings: each 0.99 g fiber → 1.0 after round1. The sum is
      // 30.0, not 29.7 — the same round-at-each-step the backend performs, so
      // the two agree exactly rather than drifting apart entry by entry.
      final parts = List.generate(30, (_) => scaleMacros(per100, 33));
      expect(sumMacros(parts)['fiber'], 30.0);
    });
  });

  group('backend limits are mirrored, not re-invented', () {
    test('the constants match the backend contract', () {
      expect(kFoodBaseGrams, 100, reason: 'FOOD_BASE_GRAMS');
      expect(kMaxEntryGrams, 5000, reason: 'MAX_ENTRY_GRAMS');
      expect(kMaxEntryCalories, 5000, reason: 'MAX_ENTRY_CALORIES');
      expect(kMaxEntriesPerDay, 80, reason: 'MAX_ENTRIES_PER_DAY');
    });
  });
}
