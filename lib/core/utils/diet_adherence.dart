// Pure diet-adherence math + status vocabulary, shared by the member's diet
// logger. No Flutter/Firebase — unit-testable in isolation.
library;

/// The three adherence states the member can mark a prescribed food with.
/// These strings are written verbatim to `client_diet_logs` and read by the
/// trainer app — do not rename.
class DietStatus {
  static const String eaten = 'eaten';
  static const String partial = 'partial';
  static const String skipped = 'skipped';
}

/// Adherence weight of a status: eaten = full, partial = half, anything else
/// (skipped / unknown) = none.
double statusScore(String status) {
  switch (status) {
    case DietStatus.eaten:
      return 1.0;
    case DietStatus.partial:
      return 0.5;
    default:
      return 0.0;
  }
}

/// Today's adherence as a 0..1 fraction: the summed score of every logged food
/// over the TOTAL number of prescribed foods (so unlogged foods pull the score
/// down until they're marked). Returns 0 when there are no prescribed foods.
double dietAdherence(Map<int, String> statuses, int totalFoods) {
  if (totalFoods <= 0) return 0;
  var sum = 0.0;
  for (final s in statuses.values) {
    sum += statusScore(s);
  }
  return (sum / totalFoods).clamp(0.0, 1.0);
}

/// Consumed amount of a single macro (kcal / protein / …) given each prescribed
/// food's macro value ([perFoodMacro], indexed the same as the plan's food list)
/// and the member's per-food [statuses]. eaten = full value, partial = half,
/// skipped/unlogged = 0. Out-of-range indices are ignored (defensive against a
/// plan changing under a stale log).
double consumedMacro(List<double> perFoodMacro, Map<int, String> statuses) {
  var sum = 0.0;
  statuses.forEach((i, s) {
    if (i >= 0 && i < perFoodMacro.length) {
      sum += perFoodMacro[i] * statusScore(s);
    }
  });
  return sum;
}
