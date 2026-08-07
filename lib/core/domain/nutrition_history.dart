/// NUTRITION HISTORY — the member's own food record, day by day.
///
/// The exact counterpart of `workout_history.dart`, and deliberately built the
/// same way: pure, I/O-free, fully unit-tested, and a TRANSFORMATION of one
/// production source rather than a second source.
///
///   • `client_nutrition_days/{clientId}_{yyyy-MM-dd}` documents — the same
///     documents `NutritionDayService` writes, `FoodLogController` renders and
///     TrainerHQ reads. Parsed by [NutritionDayModel.fromMap], the SAME parser
///     the live Food Log uses.
///
/// **There is no history collection, no history mirror and no history model.**
/// A day the member ate is a nutrition-day document. If that document says
/// nothing about a day, this file says nothing about it either.
///
/// ── THE ONE RULE THAT SHAPES EVERYTHING BELOW ─────────────────────────────
///
/// **A past day is never judged against today's target.**
///
/// This is the nutrition twin of the trap `workout_history.dart` documents:
/// resolving "rest" from a plan's CURRENT weekly schedule repaints history
/// every time a coach changes the split. The same shortcut here — scoring
/// March against the calorie target set in August — would silently relabel
/// months of a member's record every time their coach adjusted their goal.
///
/// So [NutritionDayState.partial] is derived ONLY from
/// `computed.targetAdherence`, which the backend writes ONTO THE DAY DOCUMENT
/// at the time (`rollupDaySummary` → `computeTargetAdherence`, itself
/// `clamp01(consumed / target)`). It is frozen historical truth for that date.
/// When it is absent — no targets were set then, or the day predates the
/// server summary — a day with food in it is [logged], never "partial",
/// because there is nothing it fell short OF.
library;

import '../models/nutrition_day_model.dart';
import '../utils/day_key_guard.dart' show localDayKey;

/// What one day of a member's food record says.
enum NutritionDayState {
  /// Food was recorded, and either the member met their targets that day or
  /// there were no targets to fall short of.
  logged,

  /// Food was recorded and the day's OWN frozen adherence says it came in
  /// under the targets that were in force then.
  partial,

  /// The day has ended and nothing was recorded. A fact about a past day —
  /// which is why [today] exists separately.
  empty,

  /// Today, still open. Nothing recorded YET is not the same claim as nothing
  /// recorded, and a calendar that marks a member "empty" over breakfast is
  /// judging a day that has not happened.
  today,

  /// Not yet.
  future,
}

/// One meal's worth of a day, in the canonical slot order.
///
/// Built only for slots that actually hold food: a fixed six-row grid with
/// four "—" rows is a form, not a record.
class MealGroup {
  /// The stored slug (`breakfast`, `mid_morning`, …) — never a display string.
  final String slot;

  /// Entries in the order they were EATEN, oldest first.
  final List<FoodEntry> entries;

  const MealGroup({required this.slot, required this.entries});

  /// The one place a human-facing meal name is resolved on this side.
  ///
  /// `FoodEntry.fromMap` runs every stored value through `canonicalMealSlot`,
  /// so an unknown slug cannot reach here — it has already become
  /// [kOtherMealSlot]. The fallback is belt-and-braces for a hand-built model
  /// in a test, and shows the slug rather than inventing a name for it.
  String get label => kMealLabels[slot] ?? slot;

  double get calories => _sum((e) => e.consumed.calories);
  double get protein => _sum((e) => e.consumed.protein);
  double get carbs => _sum((e) => e.consumed.carbs);
  double get fat => _sum((e) => e.consumed.fat);
  double get fiber => _sum((e) => e.consumed.fiber);

  double _sum(double Function(FoodEntry) f) =>
      entries.fold(0.0, (a, e) => a + f(e));

  /// When the member says they ATE this meal — the earliest `loggedAt` in it.
  ///
  /// Delegates to `mealStartedAt`, the model's own helper, rather than
  /// re-deriving it: two implementations of "when was this meal" is exactly
  /// the drift this module refuses to introduce. Null when not one entry
  /// carried a time, and the row then states no time rather than the
  /// document's write time — a different fact, which would move every time an
  /// entry was corrected.
  DateTime? get time {
    final ms = mealStartedAt(entries);
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }
}

/// One `client_nutrition_days` document, reduced to what a record needs.
///
/// Every figure is summed from the entries' FROZEN `consumed` snapshots — the
/// macros as they were at log time — so a coach editing a food's macros
/// tomorrow can never rewrite what a member ate today. It deliberately does
/// NOT read `computed.totals` for display: that map is server-written and can
/// lag a just-made edit by a round trip, and a member correcting a portion
/// must see their correction immediately.
class NutritionDayLog {
  final String dateKey;
  final DateTime date;
  final NutritionDayModel day;

  const NutritionDayLog({
    required this.dateKey,
    required this.date,
    required this.day,
  });

  /// Soft-deleted entries are excluded everywhere — the data is never
  /// destroyed, but a removed food is not part of what the member ate.
  List<FoodEntry> get entries => day.liveEntries.toList();

  bool get hasEntries => entries.isNotEmpty;
  int get entryCount => entries.length;

  double get calories => _sum((e) => e.consumed.calories);
  double get protein => _sum((e) => e.consumed.protein);
  double get carbs => _sum((e) => e.consumed.carbs);
  double get fat => _sum((e) => e.consumed.fat);
  double get fiber => _sum((e) => e.consumed.fiber);

  double _sum(double Function(FoodEntry) f) =>
      entries.fold(0.0, (a, e) => a + f(e));

  /// The day's frozen calorie adherence, or null when no targets were in force
  /// then. See the library doc: this is the ONLY thing allowed to call a past
  /// day short.
  double? get calorieAdherence => day.computed?.targetAdherence?['calories'];

  /// Meals in the canonical order, non-empty only, each sorted by eaten-time.
  ///
  /// An unrecognised slot sorts last rather than being dropped: a document is
  /// allowed to carry a slug this binary has not heard of, and losing a
  /// member's food because their app is a version behind is not acceptable.
  List<MealGroup> get meals {
    final bySlot = <String, List<FoodEntry>>{};
    for (final e in entries) {
      bySlot.putIfAbsent(e.mealSlot, () => []).add(e);
    }
    for (final list in bySlot.values) {
      list.sort((a, b) => (a.loggedAt ?? 0).compareTo(b.loggedAt ?? 0));
    }
    // `mealSlotOrder` is the model's own canonical ordering — the same one the
    // live Food Log sorts by, so a day cannot read in one order today and
    // another in history.
    final slots = bySlot.keys.toList()
      ..sort((a, b) => mealSlotOrder(a).compareTo(mealSlotOrder(b)));
    return [
      for (final s in slots) MealGroup(slot: s, entries: bySlot[s]!),
    ];
  }
}

/// One day of the history calendar.
class NutritionHistoryDay {
  final DateTime date;
  final NutritionDayState state;

  /// The day document, when one exists with food in it. This is what the day
  /// panel renders — the log itself, not a summary of it.
  final NutritionDayLog? log;

  const NutritionHistoryDay({
    required this.date,
    required this.state,
    this.log,
  });

  bool get hasLog => log != null && log!.hasEntries;

  /// Whether the day is worth opening. A day with nothing behind it opens an
  /// empty panel, and a cell that responds with nothing is worse than one that
  /// does not respond.
  bool get isOpenable => hasLog;
}

/// Delegates to the one canonical day-key minter — see `day_key_guard.dart`.
/// Kept as a NAME because the call sites read better for it, not as a second
/// implementation.
String nutritionDayKey(DateTime d) => localDayKey(d);

/// Every date in [month], 1st to last — the calendar's spine.
///
/// Built from the month itself rather than from the documents, so a month the
/// member logged nothing in still renders 31 cells to scroll rather than
/// collapsing to an empty strip with no sense of time.
List<DateTime> daysInMonth(DateTime month) {
  final first = DateTime(month.year, month.month, 1);
  final next = DateTime(month.year, month.month + 1, 1);
  final count = next.difference(first).inDays;
  return [for (var i = 0; i < count; i++) DateTime(first.year, first.month, 1 + i)];
}

/// Composes one month of the member's food record.
///
/// [today] is injected rather than read from the clock: "is this day still
/// open?" is the hinge of three of the five states, and a function that could
/// not be pinned to a date would be untestable in the only way that matters.
List<NutritionHistoryDay> composeNutritionMonth({
  required DateTime month,
  required Map<String, NutritionDayLog> logsByDay,
  required DateTime today,
}) {
  final t = DateTime(today.year, today.month, today.day);
  return [
    for (final date in daysInMonth(month))
      _dayFor(date, logsByDay[nutritionDayKey(date)], t),
  ];
}

NutritionHistoryDay _dayFor(DateTime date, NutritionDayLog? log, DateTime today) {
  final isToday = date == today;
  if (date.isAfter(today)) {
    return NutritionHistoryDay(date: date, state: NutritionDayState.future);
  }
  if (log == null || !log.hasEntries) {
    return NutritionHistoryDay(
      date: date,
      state: isToday ? NutritionDayState.today : NutritionDayState.empty,
    );
  }

  // TODAY IS NEVER CALLED SHORT.
  //
  // A daily total cannot be behind before the day is over — marking a member
  // "partial" at breakfast would be the calendar scolding them for not having
  // eaten dinner yet. Home already answers "am I on track right now?" with a
  // live ring against the same target; this screen is a RECORD, and it waits
  // until there is something to record.
  final adherence = log.calorieAdherence;
  final short = !isToday && adherence != null && adherence < 1.0;
  return NutritionHistoryDay(
    date: date,
    state: short ? NutritionDayState.partial : NutritionDayState.logged,
    log: log,
  );
}

/// What a whole month came to — the three figures the header states.
///
/// `daysLogged` counts DAYS WITH FOOD, not documents: an empty day document
/// (created and then emptied) is not a day the member logged, and counting it
/// would inflate the one number on this screen a member might quote.
class NutritionMonthSummary {
  final int daysLogged;
  final int entryCount;
  final double calories;

  const NutritionMonthSummary({
    required this.daysLogged,
    required this.entryCount,
    required this.calories,
  });

  /// Mean calories over the days that HAVE food — never over the whole month.
  /// Dividing by 31 would report a member who logged perfectly for a week as
  /// eating 400 kcal a day.
  double? get averageCalories =>
      daysLogged == 0 ? null : calories / daysLogged;
}

NutritionMonthSummary summariseNutritionMonth(List<NutritionHistoryDay> days) {
  var logged = 0;
  var entries = 0;
  var kcal = 0.0;
  for (final d in days) {
    final log = d.log;
    if (log == null || !log.hasEntries) continue;
    logged++;
    entries += log.entryCount;
    kcal += log.calories;
  }
  return NutritionMonthSummary(
    daysLogged: logged,
    entryCount: entries,
    calories: kcal,
  );
}
