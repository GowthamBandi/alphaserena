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

/// Sum of one macro key across a set of served food maps.
///
/// This is the PRESCRIBED total — what the coach is asking the member to eat —
/// as opposed to [consumedMacro], which weights by what they actually logged.
/// Both the day total and each meal total go through it, so a meal's numbers
/// can never be computed a different way from the day's.
///
/// Deliberately a plain sum of the served per-item values, which is exactly
/// what TrainerHQ's `planTotals` does over the same items. The coach's app and
/// the member's app must never show two different numbers for one plan, and the
/// only way to guarantee that is to perform the identical operation on the
/// identical inputs — the served item already carries resolved, gram-scaled
/// nutrition, so neither side re-derives anything.
double sumMacro(List<Map<String, dynamic>> foods, String key) {
  var sum = 0.0;
  for (final f in foods) {
    final v = f[key];
    if (v is num) {
      sum += v.toDouble();
    } else if (v is String) {
      sum += double.tryParse(v) ?? 0;
    }
  }
  return sum;
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
