/// Pure body-measurement unit conversions + validation for the identity flow.
///
/// Canonical storage is ALWAYS metric (`heightCm` / `weightKg` — what the
/// UMHIPP projection and TrainerHQ consume); these helpers only convert for
/// display/entry in the member's preferred units.
class BodyUnits {
  BodyUnits._();

  static const double cmPerInch = 2.54;
  static const double lbPerKg = 2.2046226218;

  // Canonical validation bounds (metric).
  static const double minHeightCm = 100;
  static const double maxHeightCm = 250;
  static const double minWeightKg = 20;
  static const double maxWeightKg = 400;

  // ── Conversions ─────────────────────────────────────────────────────

  /// 172 cm → (5 ft, 8 in). Inches are rounded to the nearest whole inch and
  /// a 12-inch carry rolls into feet (so 182.9 cm is 6 ft 0 in, never 5 ft 12).
  static (int feet, int inches) cmToFtIn(double cm) {
    final totalInches = (cm / cmPerInch).round();
    return (totalInches ~/ 12, totalInches % 12);
  }

  static double ftInToCm(int feet, int inches) =>
      (feet * 12 + inches) * cmPerInch;

  static double kgToLb(double kg) => kg * lbPerKg;

  static double lbToKg(double lb) => lb / lbPerKg;

  // ── Validation (against the canonical metric bounds) ────────────────

  static bool isValidHeightCm(double cm) =>
      cm >= minHeightCm && cm <= maxHeightCm;

  static bool isValidWeightKg(double kg) =>
      kg >= minWeightKg && kg <= maxWeightKg;

  // ── Display formatting ──────────────────────────────────────────────

  /// One decimal at most, no trailing ".0" (68.0 → "68", 149.91 → "149.9").
  static String trim(double v) {
    final r = (v * 10).round() / 10;
    return r == r.roundToDouble() ? r.round().toString() : r.toStringAsFixed(1);
  }
}
