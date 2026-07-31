/// THE CONSISTENCY MODEL — one rule set, one source of truth.
///
/// Built entirely from the `Set<String>` of `yyyy-MM-dd` day keys that
/// `ActivityHistoryService` already fetches (365 days for workouts and for diet
/// logs). **No new backend, no new reads, no new collection.** Everything below
/// is a different question asked of data the member's app has already loaded and
/// the Home card was throwing away.
///
/// ── WHY THIS EXISTS ────────────────────────────────────────────────────────
/// "Consistency" and "adherence" were two different measurements wearing
/// similar names:
///
///   • AlphaSerena consistency = DID YOU SHOW UP on a day (presence).
///   • TrainerHQ workout adherence = mean `adherence.targetHitPct`, the share of
///     completed sets that hit their prescription (quality).
///
/// Both are legitimate and they answer different questions, but a coach reading
/// "adherence 64%" and a member reading "7-day streak" were never looking at the
/// same fact. This module defines PRESENCE precisely and exclusively, so that
/// when the coach app adopts it the two products state one identical number.
///
/// ── HONESTY RULES ──────────────────────────────────────────────────────────
/// 1. Every field is derived from real logged days. Nothing is estimated.
/// 2. Windows are explicit. `bestStreak` is the best run WITHIN the loaded
///    window and is never presented as an all-time record.
/// 3. Days before the member's first ever log are NOT counted as misses — a
///    member cannot miss a day that pre-dates their membership, and counting
///    them would make every new member's completion rate look catastrophic.
/// 4. TODAY is never a miss. It is in progress until it ends.
library;

import '../utils/lifestyle_math.dart' show dayKey;
import '../utils/streak_math.dart';

/// The coach's weekly prescription: which weekdays the member is expected to
/// train (`DateTime.monday`..`DateTime.sunday`).
///
/// Indian coaching businesses routinely prescribe patterns like Mon/Tue/Thu/Sat
/// with Wed/Sun as rest. Without this, a member who follows their coach exactly
/// is scored as missing two days every week — the system punishes compliance,
/// which is the worst thing a consistency tracker can do.
///
/// **Null means UNKNOWN, never "every day".** When no schedule has been
/// assigned the engine falls back to daily expectation and says so, rather than
/// inventing a prescription nobody wrote.
class WeeklySchedule {
  /// Weekday numbers the member is expected to train on.
  final Set<int> trainingWeekdays;

  const WeeklySchedule(this.trainingWeekdays);

  bool expects(DateTime d) => trainingWeekdays.contains(d.weekday);

  bool get isEmpty => trainingWeekdays.isEmpty;
}

/// What a single calendar day was.
enum DayState {
  /// A qualifying log exists.
  done,

  /// No log, and the day has ended — AND the coach expected one.
  missed,

  /// The coach did not prescribe this weekday. Never a failure.
  rest,

  /// Today, still open. Never a miss.
  today,

  /// Before the member's first log — outside their history, not a failure.
  beforeStart,
}

/// One day on the calendar.
class ConsistencyDay {
  final DateTime date;
  final DayState state;
  const ConsistencyDay(this.date, this.state);

  bool get isDone => state == DayState.done;

  /// Counts against the member. `today`, `rest` and `beforeStart` never do —
  /// a member cannot miss a day their coach did not ask them to train.
  bool get isMiss => state == DayState.missed;

  bool get isRest => state == DayState.rest;
}

/// The complete presence picture for ONE track (workout or nutrition).
class ConsistencySummary {
  /// Consecutive qualifying days ending today, or yesterday while today is
  /// still open.
  final int currentStreak;

  /// Longest run inside the loaded window. NOT all-time — see [windowDays].
  final int bestStreak;

  /// The window these numbers were computed over.
  final int windowDays;

  final bool doneToday;

  /// Logged days in the last 7 / 30 days.
  final int last7;
  final int last30;

  /// Days elapsed since the member's first ever log, capped to the window.
  /// The honest denominator for a completion rate.
  final int activeDays;

  /// Total qualifying days in the window.
  final int totalDone;

  /// The most recent day with a log, or null when there has never been one.
  final DateTime? lastDone;

  /// The most recent ENDED day with no log, after the member's first log.
  /// Null when they have never missed one.
  final DateTime? lastMissed;

  /// The streak that was running before [lastMissed] broke it. 0 when there is
  /// no prior streak to speak of. This is the "you were on 12 days" fact that
  /// makes a comeback feel like a comeback.
  final int streakBeforeLastMiss;

  /// Whether the member has logged since their last miss — i.e. they are
  /// actively recovering rather than lapsed.
  final bool recovering;

  /// A coach prescription was applied. False → every ended day was treated as
  /// expected, which the UI must disclose rather than imply a schedule.
  final bool scheduled;

  /// weekday (`DateTime.monday`..`sunday`) → how many times it was missed.
  /// Answers the coach's "does this client always miss Mondays?" directly.
  final Map<int, int> missesByWeekday;

  const ConsistencySummary({
    required this.currentStreak,
    required this.bestStreak,
    required this.windowDays,
    required this.doneToday,
    required this.last7,
    required this.last30,
    required this.activeDays,
    required this.totalDone,
    required this.lastDone,
    required this.lastMissed,
    required this.streakBeforeLastMiss,
    required this.recovering,
    this.scheduled = false,
    this.missesByWeekday = const {},
  });

  /// The weekday most often missed, or null when there is no clear pattern
  /// (fewer than two misses on any one day — one miss is an event, not a
  /// pattern, and calling it one would send a coach chasing noise).
  int? get worstWeekday {
    int? worst;
    var best = 1;
    missesByWeekday.forEach((day, count) {
      if (count > best) {
        best = count;
        worst = day;
      }
    });
    return worst;
  }

  static const ConsistencySummary empty = ConsistencySummary(
    currentStreak: 0,
    bestStreak: 0,
    windowDays: 0,
    doneToday: false,
    last7: 0,
    last30: 0,
    activeDays: 0,
    totalDone: 0,
    lastDone: null,
    lastMissed: null,
    streakBeforeLastMiss: 0,
    recovering: false,
  );

  /// The member has ever logged anything at all.
  bool get hasHistory => lastDone != null;

  /// Completion over the member's ACTIVE days — never over the raw window.
  /// Null when there is no history, because 0/0 is not 0%.
  double? get completionRate {
    if (activeDays <= 0) return null;
    return (totalDone / activeDays).clamp(0.0, 1.0);
  }

  /// Completion over the last 7 days of active history.
  double? rateOver(int days, {DateTime? now}) {
    final span = activeDays < days ? activeDays : days;
    if (span <= 0) return null;
    final done = days == 7 ? last7 : last30;
    return (done / span).clamp(0.0, 1.0);
  }
}

/// Derives the full summary from a set of logged day keys.
///
/// [days] is the raw set already held by `StreakController`. [window] is how far
/// back it was fetched — passed explicitly so nothing can silently claim a
/// longer history than was actually read.
ConsistencySummary summarise(
  Set<String>? days,
  DateTime now, {
  int window = 365,
  WeeklySchedule? schedule,
}) {
  if (days == null || days.isEmpty) {
    return _emptyFor(window);
  }
  final today = DateTime(now.year, now.month, now.day);

  // The member's first log inside the window — the point from which a missed
  // day is meaningful. Before it they simply were not here.
  DateTime? firstDone;
  DateTime? lastDone;
  for (var i = window - 1; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    if (days.contains(dayKey(d))) {
      firstDone ??= d;
      lastDone = d;
    }
  }
  if (firstDone == null) return _emptyFor(window);

  final activeDays = today.difference(firstDone).inDays + 1;

  // Walk forward from the first log. A day the coach did NOT prescribe is
  // SKIPPED entirely: it neither breaks the run nor counts as a miss. This is
  // what makes a Mon/Tue/Thu/Sat member's perfect week read as a clean streak
  // instead of four hits and three failures.
  bool expected(DateTime d) =>
      schedule == null || schedule.isEmpty || schedule.expects(d);

  DateTime? lastMissed;
  var streakBefore = 0;
  var run = 0;
  var expectedDays = 0;
  final missesByWeekday = <int, int>{};
  for (
    var d = firstDone;
    d.isBefore(today);
    d = d.add(const Duration(days: 1))
  ) {
    if (!expected(d)) continue;
    expectedDays++;
    if (days.contains(dayKey(d))) {
      run++;
    } else {
      lastMissed = d;
      streakBefore = run;
      run = 0;
      missesByWeekday[d.weekday] = (missesByWeekday[d.weekday] ?? 0) + 1;
    }
  }
  // Today counts toward the expectation only once LOGGED. An open day is never
  // a miss, but a completed one is a hit.
  if (expected(today) && days.contains(dayKey(today))) expectedDays++;

  var totalDone = 0;
  for (var i = 0; i < activeDays; i++) {
    final d = today.subtract(Duration(days: i));
    if (!expected(d)) continue;
    if (days.contains(dayKey(d))) totalDone++;
  }

  return ConsistencySummary(
    currentStreak: _streakWithSchedule(days, today, window, schedule),
    bestStreak: bestStreakInWindow(days, now, window),
    windowDays: window,
    doneToday: loggedToday(days, now),
    last7: daysLoggedInWindow(days, now, 7),
    last30: daysLoggedInWindow(days, now, 30),
    // The DENOMINATOR is SCHEDULED days, not calendar days, whenever a
    // prescription exists. A member asked to train four times a week and doing
    // so is at 100% — not 57%.
    activeDays: schedule == null || schedule.isEmpty
        ? activeDays
        : expectedDays,
    scheduled: schedule != null && !schedule.isEmpty,
    missesByWeekday: Map.unmodifiable(missesByWeekday),
    totalDone: totalDone,
    lastDone: lastDone,
    lastMissed: lastMissed,
    streakBeforeLastMiss: streakBefore,
    // Logged since the last miss → actively back, not lapsed.
    recovering:
        lastMissed != null && lastDone != null && lastDone.isAfter(lastMissed),
  );
}

/// An empty summary that still reports the window it was computed over, so a
/// member with no history never implies a longer history than was read.
ConsistencySummary _emptyFor(int window) => ConsistencySummary(
  currentStreak: 0,
  bestStreak: 0,
  windowDays: window,
  doneToday: false,
  last7: 0,
  last30: 0,
  activeDays: 0,
  totalDone: 0,
  lastDone: null,
  lastMissed: null,
  streakBeforeLastMiss: 0,
  recovering: false,
);

/// Current streak, skipping days the coach did not prescribe.
///
/// A prescribed rest day is transparent: it neither extends nor breaks the run.
/// Without this a Mon/Tue/Thu/Sat member could never exceed a 2-day streak no
/// matter how perfectly they followed their coach.
int _streakWithSchedule(
  Set<String> days,
  DateTime today,
  int window,
  WeeklySchedule? schedule,
) {
  bool expected(DateTime d) =>
      schedule == null || schedule.isEmpty || schedule.expects(d);

  var d = today;
  // Today is still open: if it is expected and unlogged, start from yesterday
  // rather than declaring the streak broken before the day has ended.
  if (expected(d) && !days.contains(dayKey(d))) {
    d = d.subtract(const Duration(days: 1));
  }
  var streak = 0;
  var walked = 0;
  while (walked < window) {
    walked++;
    if (!expected(d)) {
      d = d.subtract(const Duration(days: 1));
      continue;
    }
    if (!days.contains(dayKey(d))) break;
    streak++;
    d = d.subtract(const Duration(days: 1));
  }
  return streak;
}

/// The last [count] days, oldest→newest, for a calendar strip or grid.
///
/// Days before the member's first log are marked [DayState.beforeStart] so the
/// UI can render them as absent rather than as failures.
List<ConsistencyDay> calendar(
  Set<String>? days,
  DateTime now, {
  required int count,
  DateTime? firstEver,
  WeeklySchedule? schedule,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final out = <ConsistencyDay>[];
  for (var i = count - 1; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    final logged = days?.contains(dayKey(d)) ?? false;
    final DayState state;
    if (logged) {
      state = DayState.done;
    } else if (d.isAtSameMomentAs(today)) {
      state = DayState.today;
    } else if (firstEver != null && d.isBefore(firstEver)) {
      state = DayState.beforeStart;
    } else if (firstEver == null) {
      // No history at all — nothing can be called a miss.
      state = DayState.beforeStart;
    } else if (schedule != null && !schedule.isEmpty && !schedule.expects(d)) {
      // The coach did not ask for this day. Rendering it as a miss would
      // punish the member for following their prescription exactly.
      state = DayState.rest;
    } else {
      state = DayState.missed;
    }
    out.add(ConsistencyDay(d, state));
  }
  return out;
}

/// The member's first logged day inside [window], or null.
DateTime? firstLoggedDay(Set<String>? days, DateTime now, {int window = 365}) {
  if (days == null || days.isEmpty) return null;
  final today = DateTime(now.year, now.month, now.day);
  for (var i = window - 1; i >= 0; i--) {
    final d = today.subtract(Duration(days: i));
    if (days.contains(dayKey(d))) return d;
  }
  return null;
}

/// ── MILESTONES ────────────────────────────────────────────────────────────
/// Deliberately sparse and deliberately reachable. A milestone every 3 days is
/// a participation trophy; one that takes a year is invisible. These are the
/// points where a habit measurably changes state.
const List<int> kStreakMilestones = [3, 7, 14, 30, 60, 100, 365];

/// The next milestone above [streak], or null once the last one is passed.
int? nextMilestone(int streak) {
  for (final m in kStreakMilestones) {
    if (streak < m) return m;
  }
  return null;
}

/// The highest milestone [streak] has reached, or null.
int? reachedMilestone(int streak) {
  int? best;
  for (final m in kStreakMilestones) {
    if (streak >= m) best = m;
  }
  return best;
}

/// ── THE MESSAGE ───────────────────────────────────────────────────────────
/// One honest sentence about where the member stands.
///
/// **Never guilt.** A missed day is stated as a fact and immediately reframed
/// toward the next action; the word "failed" and its cousins do not appear.
/// Behavioural rationale: shame reliably predicts disengagement, whereas an
/// explicit, low-cost re-entry point predicts return. This is also why a broken
/// streak surfaces the PREVIOUS streak — "you were on 12 days" is evidence of
/// capability, not a reprimand.
String consistencyMessage(ConsistencySummary s, {required String track}) {
  if (!s.hasHistory) {
    return 'Log your first $track day to start a streak.';
  }
  if (s.doneToday) {
    // "Best streak yet" only when the run is actually notable. For a new
    // member every streak is trivially their best, and congratulating a 2-day
    // run devalues the words for the day they hit 30.
    if (s.currentStreak == s.bestStreak &&
        s.currentStreak >= kStreakMilestones.first) {
      return 'Best streak yet — ${s.currentStreak} days.';
    }
    final next = nextMilestone(s.currentStreak);
    if (next != null) {
      final togo = next - s.currentStreak;
      return togo == 1
          ? 'One more day to hit $next.'
          : '$togo days to hit $next.';
    }
    return '${s.currentStreak} days and counting.';
  }
  if (s.currentStreak > 0) {
    return 'Log today to keep your ${s.currentStreak}-day streak.';
  }
  // No live streak. Cite the best previous run as EVIDENCE OF CAPABILITY — the
  // member has already proved they can do this, which is the single most useful
  // thing to say to someone deciding whether to start again.
  //
  // Gated on `streakBeforeLastMiss`, NOT on `recovering`: a member whose streak
  // is 0 has by definition missed since their last log, so `recovering` is
  // false in every reachable state here. Gating on it made this branch dead
  // code, and a member restarting saw the same blank prompt as a member who had
  // never logged at all.
  final prior = s.streakBeforeLastMiss > s.bestStreak
      ? s.streakBeforeLastMiss
      : s.bestStreak;
  if (prior >= kStreakMilestones.first) {
    return 'You reached $prior days before. Start again today.';
  }
  return 'Log today to start a new streak.';
}
