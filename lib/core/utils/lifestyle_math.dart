// Pure, Firebase-free math for the daily lifestyle tracker. Water is stored in
// millilitres and shown as glasses; targets fall back to platform defaults when
// the coach hasn't set one. Kept dependency-light so it unit-tests in isolation.

/// Platform default daily targets (used when a coach target is absent).
class LifestyleDefaults {
  static const double waterMl = 2500;
  static const int steps = 8000;
  static const double sleepHours = 8;
  static const double glassSizeMl = 250;
}

/// 'yyyy-MM-dd' from a local DateTime (day key + doc-id suffix).
String dayKey(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// Nearest whole glasses for [ml] at [glassSizeMl] each (guards bad size).
int glassesFor(double ml, double glassSizeMl) {
  if (glassSizeMl <= 0) return 0;
  final g = (ml / glassSizeMl).round();
  return g < 0 ? 0 : g;
}

/// Millilitres for [glasses] at [glassSizeMl] each.
double mlForGlasses(int glasses, double glassSizeMl) => glasses * glassSizeMl;

/// The coach target when set (> 0), otherwise the platform [fallback].
double effectiveTarget(double? coachTarget, double fallback) {
  if (coachTarget != null && coachTarget > 0) return coachTarget;
  return fallback;
}

/// Adherence over a window. [perDayValues] entries are null for days not logged;
/// average is over logged days only, hit = value >= target (target must be > 0).
class Adherence {
  final int loggedDays;
  final int hitDays;
  final double average;
  final double hitRate;

  const Adherence({
    this.loggedDays = 0,
    this.hitDays = 0,
    this.average = 0,
    this.hitRate = 0,
  });
}

Adherence adherenceFor(List<double?> perDayValues, double target) {
  final logged = perDayValues.whereType<double>().toList();
  if (logged.isEmpty) return const Adherence();
  final hits = (target > 0) ? logged.where((v) => v >= target).length : 0;
  final avg = logged.reduce((a, b) => a + b) / logged.length;
  return Adherence(
    loggedDays: logged.length,
    hitDays: hits,
    average: avg,
    hitRate: hits / logged.length,
  );
}

/// Supplement adherence as taken / prescribed (0 when nothing prescribed).
double supplementRate(int taken, int prescribed) {
  if (prescribed <= 0) return 0;
  return taken / prescribed;
}
