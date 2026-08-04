/// What a metric's day looks like, so the UI never has to infer it from a
/// number that cannot carry the distinction.
///
/// The four states exist because "0.4" and "no target" and "nothing logged"
/// are three different facts and only one of them is a shortfall. Collapsing
/// them into a single percentage is how a dashboard ends up telling a member
/// they are at 0% of a goal nobody set.
enum MetricStatus {
  /// The coach set no target. Nothing to be behind on.
  noTarget,

  /// A target exists; the member has recorded nothing yet today.
  notLogged,

  /// Logged, below target.
  behind,

  /// Logged, target reached or passed.
  met,
}

/// ONE metric on the Home dashboard: what it is, where the member is, and
/// where they are going.
///
/// Deliberately free of any adherence vocabulary. Nothing here is "eaten",
/// "skipped" or "partial" — those describe compliance with a prescribed list,
/// which is a different question from "how much water have you drunk today".
///
/// This is the DATA CONTRACT shared by the two Home progress cards
/// (`NutritionProgressCard`, `LifestyleProgressCard`). It carries no layout of
/// its own on purpose: the two cards look nothing alike now, but the rules for
/// what a number MEANS must stay identical or the same shortfall would read
/// differently in two places on one screen.
class DailyMetric {
  final String label;

  /// Today's value, or null when nothing has been recorded.
  final double? current;

  /// The coach's target, or null when none is set.
  final double? target;

  final String unit;

  /// Renders a value for display. Owned by the caller because glasses, hours,
  /// steps and grams round differently and none of them is a general rule.
  final String Function(double) format;

  const DailyMetric({
    required this.label,
    required this.unit,
    required this.format,
    this.current,
    this.target,
  });

  bool get hasTarget => target != null && target! > 0;

  MetricStatus get status {
    if (!hasTarget) return MetricStatus.noTarget;
    if (current == null) return MetricStatus.notLogged;
    return current! >= target! ? MetricStatus.met : MetricStatus.behind;
  }

  /// 0..1 for the bar/ring. Null when there is no meaningful fraction to draw —
  /// a bar against no target would be a bar against nothing.
  double? get progress {
    if (!hasTarget || current == null) return null;
    return (current! / target!).clamp(0.0, 1.0);
  }

  /// The percentage, UNCLAMPED, so passing a target reads as the achievement
  /// it is rather than being flattened to 100%.
  int? get percent => percentFor(current);

  /// [percent] at an intermediate figure — see [valueLabelFor].
  int? percentFor(double? shown) {
    if (!hasTarget || shown == null) return null;
    return ((shown / target!) * 100).round();
  }

  String get currentLabel => currentLabelFor(current);

  /// [currentLabel] at an intermediate figure — see [valueLabelFor].
  String currentLabelFor(double? shown) =>
      shown == null ? '—' : '${format(shown)} $unit'.trim();

  String get targetLabel =>
      hasTarget ? '${format(target!)} $unit'.trim() : 'No target set';

  /// "65 / 150 g", the bare value when there is no target to divide by, or an
  /// em dash when nothing was recorded. Three different facts, three different
  /// strings — and ONE implementation, so the nutrition grid and the lifestyle
  /// tiles cannot phrase the same fact differently.
  String get valueLabel => valueLabelFor(current);

  /// [valueLabel] with the current figure replaced by [shown] — the frame of a
  /// counting animation.
  ///
  /// The STATUS and the TARGET are always derived from the REAL values; only
  /// the numerator moves. Re-deriving status from the intermediate figure
  /// would flicker a met metric back through "behind" on its way to the very
  /// number that met it, and would count the coach's target up from zero —
  /// a figure the member did not change and must never appear to.
  String valueLabelFor(double? shown) {
    if (status == MetricStatus.noTarget) {
      return shown == null ? '—' : '${format(shown)} $unit'.trim();
    }
    return '${shown == null ? '—' : format(shown)} / $targetLabel';
  }

  /// One sentence for a screen reader: "Water, 6 of 12 glasses, 50%".
  String get semanticLabel =>
      '$label, $currentLabel of $targetLabel'
      '${percent == null ? '' : ', $percent%'}';
}

/// The one sentence under the Home nutrition card's title.
///
/// Four different facts, four different sentences — and the ORDER is the whole
/// point. [loadError] comes first because a failed read tells us nothing about
/// what the member ate: reading it last (or, as Home did for a release, not at
/// all) turns the app's own failure into the sentence "Nothing logged yet
/// today", which is a claim about the MEMBER'S BEHAVIOUR that the app has no
/// evidence for. The Diet screen has always branched on this flag; this exists
/// so the two surfaces cannot phrase the same fact differently again.
///
/// Pure and caller-independent precisely because the defect lived in the
/// CALLER: the card widget is a presenter with no error input, so testing the
/// widget could never have caught it.
String nutritionCardSubtitle({
  required bool loadError,
  required bool hasAnyTarget,
  required int entryCount,
}) {
  if (loadError) return "Couldn't load today's food";
  if (!hasAnyTarget) return 'No coach targets yet';
  if (entryCount == 0) return 'Nothing logged yet today';
  return "Today's nutrition";
}
