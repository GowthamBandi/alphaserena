import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/utils/diet_adherence.dart';

void main() {
  test('statusScore weights eaten/partial/skipped', () {
    expect(statusScore(DietStatus.eaten), 1.0);
    expect(statusScore(DietStatus.partial), 0.5);
    expect(statusScore(DietStatus.skipped), 0.0);
    expect(statusScore('anything-else'), 0.0);
  });

  test('dietAdherence sums logged scores over total foods', () {
    final s = {0: DietStatus.eaten, 1: DietStatus.partial, 2: DietStatus.skipped};
    expect(dietAdherence(s, 4), closeTo(0.375, 0.0001)); // (1 + 0.5 + 0) / 4
  });

  test('dietAdherence is 0 with nothing logged and 1 when all eaten', () {
    expect(dietAdherence(const {}, 3), 0);
    expect(dietAdherence({0: DietStatus.eaten}, 1), 1.0);
  });

  test('dietAdherence guards an empty plan', () {
    expect(dietAdherence({0: DietStatus.eaten}, 0), 0);
  });

  group('consumedMacro', () {
    final macros = [100.0, 200.0, 50.0]; // e.g. calories per prescribed food

    test('eaten counts full, partial half, skipped/unlogged zero', () {
      final s = {0: DietStatus.eaten, 1: DietStatus.partial, 2: DietStatus.skipped};
      expect(consumedMacro(macros, s), closeTo(100 + 100 + 0, 0.0001));
    });

    test('nothing logged consumes nothing', () {
      expect(consumedMacro(macros, const {}), 0.0);
    });

    test('all eaten consumes the full prescribed total', () {
      final s = {0: DietStatus.eaten, 1: DietStatus.eaten, 2: DietStatus.eaten};
      expect(consumedMacro(macros, s), closeTo(350.0, 0.0001));
    });

    test('ignores out-of-range indices (stale log vs shorter plan)', () {
      final s = {0: DietStatus.eaten, 9: DietStatus.eaten};
      expect(consumedMacro(macros, s), closeTo(100.0, 0.0001));
    });
  });
}
