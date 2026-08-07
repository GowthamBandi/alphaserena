/// PRESCRIPTION ENGINE — Phase 3: what the SERVER said is expected today.
///
/// `getMyTraining` resolves today's expectation server-side (Phase 2) so the
/// two apps can never disagree; this module is the member app's *reader* of
/// that answer. It computes nothing itself — parsing the served map and
/// choosing which words the member sees are its whole job.
///
/// THE ONE RULE, unchanged: nothing here ever invents an expectation. A
/// missing or unreadable `expectation` field (old backend, error, offline
/// cache) parses to null and the UI renders exactly its pre-Phase-3 self —
/// which is also what `unknown` discloses.
library;

import 'prescription.dart' show ExpectationKind, RhythmType;

// THE MEMBER'S LOCAL DAY KEY IS RE-EXPORTED, NOT REDEFINED.
//
// A dozen call sites across the app already say
// `import 'today_expectation.dart' show localDayKey`, and they read correctly
// that way — this module is where the member's own day is a subject. But the
// RULE belongs beside the plausibility check that judges what it produces, so
// the declaration lives in `day_key_guard.dart` and this library forwards it.
// One declaration, reached by two names, is not the same thing as two
// implementations — which is what was here before.
import '../utils/day_key_guard.dart' show addCalendarDays, localDayKey;
export '../utils/day_key_guard.dart' show localDayKey;

/// One track's served expectation for the member's local day.
class ServedExpectation {
  final ExpectationKind kind;

  /// Why — the exception/rhythm word: 'rhythm' | 'frequency' | 'travel' |
  /// 'deload' | 'medical' | 'pause' | 'closure' | 'custom' | 'coachPause' | ''.
  final String reason;

  /// The coach's note for this day/range, verbatim. '' when none.
  final String note;

  /// Whether a coach-authored prescription exists at all. False = `unknown`
  /// must be DISCLOSED, never dressed up as a schedule.
  final bool prescribed;

  /// Rhythm summary of the version in force (for phrasing only).
  final RhythmType? rhythmType;

  /// frequency rhythms only — the N in "any N per week".
  final int frequencyCount;

  /// The coach excused this specific day ("skip today").
  final bool excusedToday;

  const ServedExpectation({
    required this.kind,
    this.reason = '',
    this.note = '',
    this.prescribed = false,
    this.rhythmType,
    this.frequencyCount = 0,
    this.excusedToday = false,
  });

  /// Null when the map is absent or unreadable — the legacy-safe answer,
  /// never a fabricated default.
  static ServedExpectation? fromMap(dynamic m) {
    if (m is! Map) return null;
    final kindName = (m['kind'] ?? '').toString();
    ExpectationKind? kind;
    for (final k in ExpectationKind.values) {
      if (k.name == kindName) kind = k;
    }
    if (kind == null) return null;
    final rhythm = m['rhythm'];
    RhythmType? rhythmType;
    var frequencyCount = 0;
    if (rhythm is Map) {
      final t = (rhythm['type'] ?? '').toString();
      for (final r in RhythmType.values) {
        if (r.name == t) rhythmType = r;
      }
      final c = rhythm['count'];
      frequencyCount = c is num ? c.toInt() : 0;
    }
    return ServedExpectation(
      kind: kind,
      reason: (m['reason'] ?? '').toString(),
      note: (m['note'] ?? '').toString(),
      prescribed: m['prescribed'] == true,
      rhythmType: rhythmType,
      frequencyCount: frequencyCount,
      excusedToday: m['excusedToday'] == true,
    );
  }
}

/// Both tracks + the day the server resolved them FOR (the member's clamped
/// local day) — kept so a day rollover can be detected and refetched.
class TodayExpectations {
  final String date; // yyyy-MM-dd, '' when the server predates Phase 2
  final ServedExpectation? workout;
  final ServedExpectation? diet;

  const TodayExpectations({this.date = '', this.workout, this.diet});

  static TodayExpectations? fromResponse(dynamic data) {
    if (data is! Map) return null;
    final e = data['expectation'];
    if (e is! Map) return null;
    return TodayExpectations(
      date: (e['date'] ?? '').toString(),
      workout: ServedExpectation.fromMap(e['workout']),
      diet: ServedExpectation.fromMap(e['diet']),
    );
  }
}

/// The member's local day key — the day THEY lived, sent to the server which
/// clamps it to the plausible ±1-day window.
// ═══════════════════════════════════════════════════════════════════════════
// PRESENTATION — the words, decided in one pure place
// ═══════════════════════════════════════════════════════════════════════════

/// How Home's workout card should render. One value per visual variant, so
/// the widget is a dumb switch and THIS function is the tested truth.
enum TodayWorkoutMode {
  /// A required session: the full hero card + primary CTA. Also the exact
  /// legacy rendering when no expectation is available (pre-Phase-2 backend).
  training,

  /// Flexible week (any N/week): content shown, session CTA, week progress.
  flexible,

  /// Prescribed rest (rhythm or a rest-type exception): a POSITIVE state.
  rest,

  /// The coach excused today specifically.
  excused,

  /// Coaching paused (any level). No CTA, no pressure.
  paused,

  /// Prescription exists but hasn't started yet.
  notYetStarted,

  /// The plan's end date has passed.
  ended,

  /// A plan is served but NO schedule exists — legacy rendering PLUS the
  /// honest disclosure line.
  unknownDisclosed,

  /// Nothing assigned at all — "waiting for your coach" (existing state).
  waiting,
}

/// Everything the workout card needs to render truthfully.
class TodayWorkoutPresentation {
  final TodayWorkoutMode mode;
  final String title;
  final String body;

  /// Reason chip ('Travel', 'Deload week', …). '' hides it.
  final String chip;

  /// Whether the plan's content (exercise preview) is shown.
  final bool showContent;

  /// Primary CTA ('' = none) and whether the quiet "Train anyway" link shows.
  final String cta;
  final bool trainAnyway;

  /// Extra one-liner under the card ('' = none) — the `unknown` disclosure.
  final String disclosure;

  const TodayWorkoutPresentation({
    required this.mode,
    this.title = '',
    this.body = '',
    this.chip = '',
    this.showContent = false,
    this.cta = '',
    this.trainAnyway = false,
    this.disclosure = '',
  });
}

String _chipFor(String reason) {
  switch (reason) {
    case 'travel':
      return 'Travel';
    case 'deload':
      return 'Deload week';
    case 'medical':
      return 'Medical leave';
    case 'closure':
      return 'Gym closed';
    case 'custom':
      return 'Coach exception';
    default:
      return '';
  }
}

/// The single decision point for Home's workout card.
///
/// [hasPlan] — a workout plan is being served (content exists to show).
/// [doneToday] — a session was logged today (presence, from the log sets).
/// [doneThisWeek] — sessions logged in the current week (for flexible weeks).
/// [coachName] — '' falls back to "your coach".
TodayWorkoutPresentation todayWorkoutPresentation({
  required ServedExpectation? expectation,
  required bool hasPlan,
  required bool doneToday,
  required int doneThisWeek,
  required String coachName,
}) {
  final coach = coachName.isEmpty ? 'your coach' : coachName;
  final e = expectation;

  // No expectation served (old backend / unreadable): EXACTLY the legacy
  // behaviour — never guess, never disclose what we don't know.
  if (e == null) {
    return TodayWorkoutPresentation(
      mode: hasPlan ? TodayWorkoutMode.training : TodayWorkoutMode.waiting,
      showContent: hasPlan,
      cta: hasPlan ? 'Start Full Workout' : '',
    );
  }

  // A coach excuse outranks the day's own kind everywhere the member looks:
  // "I told them to skip today" must never read as pressure.
  if (e.excusedToday) {
    return TodayWorkoutPresentation(
      mode: TodayWorkoutMode.excused,
      title: 'Today is excused',
      body:
          '$coach excused today — it won\'t count against you. '
          'Rest up, or train if you feel like it.',
      chip: 'Excused',
      trainAnyway: hasPlan,
    );
  }

  switch (e.kind) {
    case ExpectationKind.required:
      return TodayWorkoutPresentation(
        mode: hasPlan ? TodayWorkoutMode.training : TodayWorkoutMode.waiting,
        showContent: hasPlan,
        cta: hasPlan ? 'Start Full Workout' : '',
        chip: _chipFor(e.reason),
      );

    case ExpectationKind.optional:
      if (e.reason == 'frequency' && e.frequencyCount > 0) {
        final n = e.frequencyCount;
        final done = doneThisWeek > n ? n : doneThisWeek;
        return TodayWorkoutPresentation(
          mode: TodayWorkoutMode.flexible,
          title: 'Flexible week',
          body: done >= n
              ? 'You\'ve hit all $n sessions this week. Anything more is bonus.'
              : '$done of $n sessions done this week — you pick the days.',
          chip: 'Any $n × / week',
          showContent: hasPlan,
          cta: hasPlan ? 'Start a Session' : '',
        );
      }
      // Optional for another reason (refeed / deload replacement): offered,
      // never owed.
      return TodayWorkoutPresentation(
        mode: TodayWorkoutMode.flexible,
        title: 'Optional today',
        body: e.note.isNotEmpty
            ? e.note
            : 'Training today is optional — it helps if you do, and never '
                'hurts if you don\'t.',
        chip: _chipFor(e.reason),
        showContent: hasPlan,
        cta: hasPlan ? 'Start a Session' : '',
      );

    case ExpectationKind.rest:
      return TodayWorkoutPresentation(
        mode: TodayWorkoutMode.rest,
        title: doneToday ? 'Rest day — and you trained anyway' : 'Rest day',
        body: e.note.isNotEmpty
            ? e.note
            : doneToday
                ? 'Prescribed rest by $coach — today\'s session counts as a '
                    'bonus.'
                : 'Prescribed by $coach. Recovery is part of the program — '
                    'today counts by resting.',
        chip: _chipFor(e.reason),
        trainAnyway: hasPlan && !doneToday,
      );

    case ExpectationKind.paused:
      return TodayWorkoutPresentation(
        mode: TodayWorkoutMode.paused,
        title: 'Coaching paused',
        body: e.note.isNotEmpty
            ? e.note
            : 'Your coaching is paused right now — nothing counts against '
                'you, and your streak is safe. $coach will resume it.',
        chip: _chipFor(e.reason),
      );

    case ExpectationKind.notYetStarted:
      return TodayWorkoutPresentation(
        mode: TodayWorkoutMode.notYetStarted,
        title: 'Your plan hasn\'t started yet',
        body: 'The schedule $coach set begins soon. Nothing is expected '
            'until then.',
      );

    case ExpectationKind.ended:
      return TodayWorkoutPresentation(
        mode: TodayWorkoutMode.ended,
        title: 'Plan finished',
        body: 'This training block has ended. Ask $coach for your next one.',
      );

    case ExpectationKind.unknown:
      // The honest fallback, DISCLOSED — never dressed up as a schedule.
      return TodayWorkoutPresentation(
        mode: hasPlan
            ? TodayWorkoutMode.unknownDisclosed
            : TodayWorkoutMode.waiting,
        showContent: hasPlan,
        cta: hasPlan ? 'Start Full Workout' : '',
        disclosure: hasPlan
            ? 'No schedule set — showing your plan daily.'
            : '',
      );
  }
}

/// Sessions logged in the CURRENT week (Monday-based), from the logged
/// day-key set. This counts what HAPPENED — never what is expected — so it is
/// safe to compute client-side.
int sessionsThisWeek(Set<String>? loggedDays, DateTime now) {
  if (loggedDays == null || loggedDays.isEmpty) return 0;
  final today = DateTime(now.year, now.month, now.day);
  final monday = addCalendarDays(today, -(today.weekday - 1));
  var count = 0;
  for (var i = 0; i < 7; i++) {
    final d = addCalendarDays(monday, i);
    if (d.isAfter(today)) break;
    if (loggedDays.contains(localDayKey(d))) count++;
  }
  return count;
}

/// Whether the workout consistency card should stop saying "Pending today":
/// on a day the coach did not ask for training, an unlogged day is not
/// pending — it is the plan working.
bool workoutNotExpectedToday(ServedExpectation? e) {
  if (e == null) return false;
  if (e.excusedToday) return true;
  switch (e.kind) {
    case ExpectationKind.rest:
    case ExpectationKind.paused:
    case ExpectationKind.notYetStarted:
    case ExpectationKind.ended:
      return true;
    case ExpectationKind.optional:
      // A flexible-week day is an opportunity, not an obligation.
      return true;
    case ExpectationKind.required:
    case ExpectationKind.unknown:
      return false;
  }
}

/// The nutrition card's one-line expectation note. '' = render as today.
/// Diet stays quiet by design: eating happens every day, so only pause and
/// coach-declared optional days change the frame.
String nutritionExpectationNote(ServedExpectation? e) {
  if (e == null) return '';
  if (e.kind == ExpectationKind.paused) {
    return 'Coaching is paused — log if you like, nothing counts against you.';
  }
  if (e.kind == ExpectationKind.optional || e.kind == ExpectationKind.rest) {
    return e.note.isNotEmpty ? e.note : 'Logging is optional today.';
  }
  return '';
}
