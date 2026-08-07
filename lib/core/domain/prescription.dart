/// PRESCRIPTION ENGINE — Step 1: the domain.
///
/// Implements `PRESCRIPTION_ENGINE_FREEZE.md` exactly. No Flutter, no Firebase,
/// no I/O — so this file is copied **verbatim** into TrainerHQ and both apps
/// compute one answer from one rule set. That portability is the whole point:
/// the moment either app owns a private copy of this logic, the two products
/// can disagree about what a member was asked to do.
///
/// ── THE ONE RULE ──────────────────────────────────────────────────────────
/// Every number the platform shows must trace to a prescription a coach
/// actually wrote, or resolve to [ExpectationKind.unknown]. Nothing is ever
/// inferred to make a screen look complete. `unknown` is the honest answer for
/// every member today, and it is a first-class value — never an error, never a
/// silent default to "daily".
library;

// ═══════════════════════════════════════════════════════════════════════════
// RHYTHM — "on which days"  (freeze §3: exactly four, no more)
// ═══════════════════════════════════════════════════════════════════════════

enum RhythmType {
  /// ONE DAY ONLY — expected on the prescription's own `startDate` and never
  /// again. The DEFAULT for a workout: a coach handing a member today's
  /// session has said nothing about tomorrow, and the honest reading of
  /// silence is "nothing tomorrow", not "this, forever".
  ///
  /// It carries NO anchor of its own. The day it means is [Prescription
  /// .startDate], which every prescription already has — storing the date
  /// twice would let the two copies disagree about which day "one day" was.
  /// The window, not the rhythm, is what bounds it: see
  /// [Prescription.effectiveEndDate], which is why the day after resolves
  /// through the SAME `ended` path a 12-week block reaches on its last day.
  oneDay,

  /// Every day. The default for diet.
  daily,

  /// Fixed weekdays, e.g. {Mon, Tue, Thu, Sat}. Offline gyms, strength blocks.
  weekdays,

  /// "Any N per week" — the member picks the days.
  ///
  /// This is the rhythm a weekday bitmap cannot express and the reason the
  /// engine exists in this shape: it changes the UNIT of consistency from the
  /// day to the WEEK (see [ConsistencyUnit]).
  frequency,

  /// N on / M off. Alternate-day and 3-on-1-off splits, which drift across
  /// weekdays and are therefore not weekly-periodic.
  cycle,
}

/// What a prescription asks for, expressed in one of four shapes.
class Rhythm {
  final RhythmType type;

  /// [RhythmType.weekdays] only — `DateTime.monday`..`DateTime.sunday`.
  final Set<int> weekdays;

  /// [RhythmType.frequency] only — sessions per week.
  final int count;

  /// [RhythmType.cycle] only.
  final int onDays;
  final int offDays;

  /// [RhythmType.cycle] only — the day the cycle's first ON block begins.
  /// A cycle without an anchor cannot be resolved for any date.
  final DateTime? cycleStart;

  const Rhythm._({
    required this.type,
    this.weekdays = const {},
    this.count = 0,
    this.onDays = 0,
    this.offDays = 0,
    this.cycleStart,
  });

  const Rhythm.oneDay() : this._(type: RhythmType.oneDay);

  const Rhythm.daily() : this._(type: RhythmType.daily);

  const Rhythm.weekdays(Set<int> days)
    : this._(type: RhythmType.weekdays, weekdays: days);

  const Rhythm.frequency(int perWeek)
    : this._(type: RhythmType.frequency, count: perWeek);

  const Rhythm.cycle({
    required int on,
    required int off,
    required DateTime start,
  }) : this._(
         type: RhythmType.cycle,
         onDays: on,
         offDays: off,
         cycleStart: start,
       );

  /// Whether this rhythm is expressible at all.
  ///
  /// An INVALID rhythm is rejected at the write boundary rather than silently
  /// treated as "no days" — an empty weekday set would otherwise make every day
  /// a rest day and every member permanently perfect (freeze §9, case 21).
  bool get isValid {
    switch (type) {
      case RhythmType.oneDay:
      case RhythmType.daily:
        return true;
      case RhythmType.weekdays:
        return weekdays.isNotEmpty &&
            weekdays.every((d) => d >= DateTime.monday && d <= DateTime.sunday);
      case RhythmType.frequency:
        // 7 is the ceiling: "8 per week" is not a prescription, it is a typo.
        return count >= 1 && count <= 7;
      case RhythmType.cycle:
        return onDays >= 1 && offDays >= 0 && cycleStart != null;
    }
  }

  /// The unit consistency is measured in. Frequency is measured by WEEK because
  /// the member chooses the days — asking "did you train on Tuesday?" is
  /// meaningless when Tuesday was never specified.
  ConsistencyUnit get unit =>
      type == RhythmType.frequency ? ConsistencyUnit.week : ConsistencyUnit.day;

  /// Whether this rhythm asks for work on [date]. Frequency rhythms return
  /// false for every individual day — they are resolved per week, never per day.
  bool expectsOn(DateTime date) {
    switch (type) {
      // ONE DAY says yes to every day it is ASKED about, because the only day
      // it is ever asked about is its own: [expectationFor] resolves
      // `notYetStarted` before the start day and `ended` after it, so this
      // method is only ever reached ON the day. Encoding the bound here as
      // well would be a second copy of the window rule.
      case RhythmType.oneDay:
      case RhythmType.daily:
        return true;
      case RhythmType.weekdays:
        return weekdays.contains(date.weekday);
      case RhythmType.frequency:
        return false; // resolved weekly, never daily
      case RhythmType.cycle:
        final start = cycleStart;
        if (start == null) return false;
        final period = onDays + offDays;
        if (period <= 0) return false;
        final delta = _calendarDaysBetween(start, date);
        if (delta < 0) return false; // before the cycle began
        return (delta % period) < onDays;
    }
  }

  Map<String, dynamic> toMap() => {
    'type': type.name,
    if (type == RhythmType.weekdays) 'weekdays': weekdays.toList()..sort(),
    if (type == RhythmType.frequency) 'count': count,
    if (type == RhythmType.cycle) ...{
      'onDays': onDays,
      'offDays': offDays,
      'cycleStart': _iso(cycleStart),
    },
  };

  static Rhythm? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final t = _enumByName(RhythmType.values, m['type']);
    if (t == null) return null;
    switch (t) {
      case RhythmType.oneDay:
        return const Rhythm.oneDay();
      case RhythmType.daily:
        return const Rhythm.daily();
      case RhythmType.weekdays:
        final raw = m['weekdays'];
        final days = raw is List
            ? raw.whereType<num>().map((e) => e.toInt()).toSet()
            : <int>{};
        return Rhythm.weekdays(days);
      case RhythmType.frequency:
        return Rhythm.frequency(_int(m['count']));
      case RhythmType.cycle:
        final start = _date(m['cycleStart']);
        if (start == null) return null;
        return Rhythm.cycle(
          on: _int(m['onDays']),
          off: _int(m['offDays']),
          start: start,
        );
    }
  }
}

/// Whether a track's consistency is counted by day or by week (freeze §7.3).
enum ConsistencyUnit { day, week }

// ═══════════════════════════════════════════════════════════════════════════
// EXCEPTIONS — date-ranged overrides  (freeze §3)
// ═══════════════════════════════════════════════════════════════════════════

enum ExceptionType { pause, rest, travel, medical, deload, closure, custom }

/// A date-ranged override of the base rhythm.
///
/// `to == null` means OPEN-ENDED, which is the normal case for medical leave —
/// "I don't know when they're back" must be expressible without inventing a
/// return date.
class PrescriptionException {
  final DateTime from;
  final DateTime? to;
  final ExceptionType type;

  /// When present, the rhythm that REPLACES the base one for this range
  /// (a deload dropping 6 days to 2). When absent, the range is non-training.
  final Rhythm? replacementRhythm;

  final String note;

  const PrescriptionException({
    required this.from,
    required this.type,
    this.to,
    this.replacementRhythm,
    this.note = '',
  });

  bool covers(DateTime date) {
    final d = _midnight(date);
    if (d.isBefore(_midnight(from))) return false;
    final end = to;
    if (end == null) return true; // open-ended
    return !d.isAfter(_midnight(end));
  }

  /// A pause suspends coaching entirely; other types merely change what is
  /// asked. Only a pause freezes streaks.
  bool get isPause => type == ExceptionType.pause || type == ExceptionType.medical;

  Map<String, dynamic> toMap() => {
    'from': _iso(from),
    if (to != null) 'to': _iso(to),
    'type': type.name,
    if (replacementRhythm != null) 'replacementRhythm': replacementRhythm!.toMap(),
    if (note.isNotEmpty) 'note': note,
  };

  static PrescriptionException? fromMap(Map<String, dynamic> m) {
    final from = _date(m['from']);
    final type = _enumByName(ExceptionType.values, m['type']);
    if (from == null || type == null) return null;
    return PrescriptionException(
      from: from,
      to: _date(m['to']),
      type: type,
      replacementRhythm: Rhythm.fromMap(
        m['replacementRhythm'] is Map
            ? Map<String, dynamic>.from(m['replacementRhythm'] as Map)
            : null,
      ),
      note: (m['note'] ?? '').toString(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// PRESCRIPTION — immutable, versioned  (freeze §4)
// ═══════════════════════════════════════════════════════════════════════════

/// One immutable version of what a coach asks of one member on one track.
///
/// Edits never mutate: they write a NEW version with `effectiveFrom = today` and
/// move the prior one to history. Consistency for a past date resolves the
/// version effective THEN, so moving a member from 6 days to 4 can never
/// retroactively improve last month.
class Prescription {
  /// Monotonic. 1 is the first version.
  final int version;

  /// The date this version began to apply. Never back-dated by a client.
  final DateTime effectiveFrom;

  /// When the prescription itself starts/ends (a client joining Wednesday, a
  /// 12-week block). Distinct from [effectiveFrom], which is about VERSIONS.
  final DateTime startDate;
  final DateTime? endDate;

  final Rhythm rhythm;

  /// Ordered; LATER entries win, so a travel week can be layered on a deload
  /// without editing either.
  final List<PrescriptionException> exceptions;

  final String note;

  const Prescription({
    required this.version,
    required this.effectiveFrom,
    required this.startDate,
    required this.rhythm,
    this.endDate,
    this.exceptions = const [],
    this.note = '',
  });

  /// The last day this prescription asks for anything — the ONE place the
  /// schedule window is decided.
  ///
  /// For [RhythmType.oneDay] it is the EARLIER of [startDate] and [endDate]:
  /// One Day can be ENDED EARLY but never STRETCHED.
  ///
  /// • Never stretched — a coach switching a running 12-week block to One Day
  ///   leaves the old `endDate` on the document; honouring it would keep the
  ///   plan they just shortened demanding work for 12 more weeks.
  /// • Ended early — a version whose assignment was replaced carries a clamped
  ///   `endDate` (the day it left service). A One Day plan booked for next
  ///   Friday and replaced on Tuesday must resolve `ended` on that Friday, not
  ///   `required`: fabricating a required day for a plan that no longer exists
  ///   is exactly the failure this engine is built to make impossible.
  ///
  /// Every other rhythm is bounded by [endDate] exactly as before, so this
  /// getter is a no-op for every prescription written to date.
  DateTime? get effectiveEndDate {
    if (rhythm.type != RhythmType.oneDay) return endDate;
    final e = endDate;
    if (e == null) return startDate;
    return e.isBefore(startDate) ? e : startDate;
  }

  /// Validity at the write boundary. A prescription that fails this must be
  /// REJECTED, never stored and silently reinterpreted.
  bool get isValid {
    if (version < 1) return false;
    if (!rhythm.isValid) return false;
    final end = endDate;
    if (end != null && end.isBefore(startDate)) return false;
    for (final e in exceptions) {
      final to = e.to;
      if (to != null && to.isBefore(e.from)) return false;
      final replacement = e.replacementRhythm;
      if (replacement != null && !replacement.isValid) return false;
      // ONE DAY CANNOT REPLACE A RANGE. An exception says "for these dates,
      // do this instead"; "one day" names no day inside that range, and it has
      // no anchor of its own to name one with. Silently treating it as `daily`
      // (which is what an unguarded `expectsOn` would do) would turn a travel
      // week into a week of required sessions — the exact inversion of what
      // the coach asked for.
      if (replacement != null && replacement.type == RhythmType.oneDay) {
        return false;
      }
    }
    return true;
  }

  Map<String, dynamic> toMap() => {
    'version': version,
    'effectiveFrom': _iso(effectiveFrom),
    'startDate': _iso(startDate),
    if (endDate != null) 'endDate': _iso(endDate),
    'rhythm': rhythm.toMap(),
    if (exceptions.isNotEmpty)
      'exceptions': exceptions.map((e) => e.toMap()).toList(),
    if (note.isNotEmpty) 'note': note,
  };

  /// Null when the map is absent or unreadable — which resolves to
  /// [ExpectationKind.unknown] downstream, never to a fabricated default.
  static Prescription? fromMap(Map<String, dynamic>? m) {
    if (m == null) return null;
    final rhythm = Rhythm.fromMap(
      m['rhythm'] is Map ? Map<String, dynamic>.from(m['rhythm'] as Map) : null,
    );
    final effectiveFrom = _date(m['effectiveFrom']);
    final startDate = _date(m['startDate']);
    if (rhythm == null || effectiveFrom == null || startDate == null) {
      return null;
    }
    final rawEx = m['exceptions'];
    final exceptions = <PrescriptionException>[];
    if (rawEx is List) {
      for (final e in rawEx) {
        if (e is Map) {
          final parsed = PrescriptionException.fromMap(
            Map<String, dynamic>.from(e),
          );
          if (parsed != null) exceptions.add(parsed);
        }
      }
    }
    return Prescription(
      version: _int(m['version'], fallback: 1),
      effectiveFrom: effectiveFrom,
      startDate: startDate,
      endDate: _date(m['endDate']),
      rhythm: rhythm,
      exceptions: exceptions,
      note: (m['note'] ?? '').toString(),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// EXPECTATION & OUTCOME — two separate axes  (freeze §2, ▲3)
// ═══════════════════════════════════════════════════════════════════════════

/// What the coach ASKED for on a given date.
enum ExpectationKind {
  /// Expected, and counts both ways.
  required,

  /// Offered — helps if done, never hurts if not (refeed, extra cardio).
  optional,

  /// The coach prescribed no work. The ABSENCE of expectation, not a failure.
  rest,

  /// Coaching suspended. Streaks freeze; they do not break.
  paused,

  /// Before `startDate`.
  notYetStarted,

  /// After `endDate`.
  ended,

  /// NO PRESCRIPTION EXISTS. Today's state for every member on the platform.
  /// The UI must disclose this, never assume daily.
  unknown,
}

/// What actually HAPPENED. Never something a coach prescribes.
enum OutcomeKind {
  done,

  /// Today, still open. Never a miss until the day ends.
  open,

  missed,

  /// The coach cancelled this day after the fact. Protects a member's record
  /// without corrupting history by retro-editing the prescription.
  excusedByCoach,

  /// Outside any scoring: rest, paused, optional-not-done, unknown, out of
  /// validity. Absent from BOTH sides of every ratio.
  excluded,
}

/// One resolved day: what was asked, and what happened.
class DayVerdict {
  final DateTime date;
  final ExpectationKind expectation;
  final OutcomeKind outcome;
  final String reason;

  const DayVerdict({
    required this.date,
    required this.expectation,
    required this.outcome,
    this.reason = '',
  });

  bool get isHit => outcome == OutcomeKind.done;

  /// Counts against the member. Only a REQUIRED day that ended unlogged does.
  bool get isMiss => outcome == OutcomeKind.missed;

  /// In neither numerator nor denominator.
  bool get isExcluded =>
      outcome == OutcomeKind.excluded ||
      outcome == OutcomeKind.open ||
      outcome == OutcomeKind.excusedByCoach;
}

/// The expectation for one date, before any log is consulted.
class Expectation {
  final ExpectationKind kind;
  final String reason;
  final String note;

  const Expectation(this.kind, {this.reason = '', this.note = ''});

  static const Expectation unknown = Expectation(ExpectationKind.unknown);

  bool get isRequired => kind == ExpectationKind.required;
  bool get countsAgainstMember => kind == ExpectationKind.required;
}

// ═══════════════════════════════════════════════════════════════════════════
// THE ENGINE
// ═══════════════════════════════════════════════════════════════════════════

/// Resolves what was asked of a member on [date].
///
/// [versions] is the full version history, any order. The version whose
/// `effectiveFrom` is the latest one not after [date] wins — which is what makes
/// history immutable: a past date always resolves the prescription that was
/// actually in force then.
///
/// [coachingPause] is the CLIENT-level pause (medical leave, exams). It
/// outranks everything, because a coach pausing a member must not have to pause
/// three tracks separately.
Expectation expectationFor(
  List<Prescription> versions,
  DateTime date, {
  PrescriptionException? coachingPause,
}) {
  final d = _midnight(date);

  // Client-level pause wins over every prescription (freeze §15).
  if (coachingPause != null && coachingPause.covers(d)) {
    return Expectation(
      ExpectationKind.paused,
      reason: coachingPause.type.name,
      note: coachingPause.note,
    );
  }

  final p = versionEffectiveOn(versions, d);
  if (p == null) return Expectation.unknown;

  if (d.isBefore(_midnight(p.startDate))) {
    return const Expectation(ExpectationKind.notYetStarted);
  }
  // `effectiveEndDate`, not `endDate`: a ONE DAY rhythm ends on its start day,
  // so the day after reaches `ended` through the SAME path a 12-week block
  // reaches on its last day. That reuse is the whole point — every consumer
  // already renders `ended` as "Plan finished", excludes it from adherence and
  // never scores it as a miss, so One Day needed no new expectation kind and
  // no consumer had to learn a new word.
  final end = p.effectiveEndDate;
  if (end != null && d.isAfter(_midnight(end))) {
    return const Expectation(ExpectationKind.ended);
  }

  // Exceptions: LATER entries win, so the last covering one is authoritative.
  PrescriptionException? active;
  for (final e in p.exceptions) {
    if (e.covers(d)) active = e;
  }

  if (active != null) {
    if (active.isPause) {
      return Expectation(
        ExpectationKind.paused,
        reason: active.type.name,
        note: active.note,
      );
    }
    final replacement = active.replacementRhythm;
    if (replacement == null) {
      // A non-pause exception with no replacement means "no work this range" —
      // travel, closure, a prescribed rest block.
      return Expectation(
        ExpectationKind.rest,
        reason: active.type.name,
        note: active.note,
      );
    }
    return _fromRhythm(replacement, d, active.type.name, active.note);
  }

  return _fromRhythm(p.rhythm, d, 'rhythm', p.note);
}

Expectation _fromRhythm(Rhythm r, DateTime d, String reason, String note) {
  // A frequency rhythm asks for no SPECIFIC day, so no day is required and no
  // day is a miss. Every day is an opportunity; the week is scored (§7.3).
  if (r.type == RhythmType.frequency) {
    return Expectation(ExpectationKind.optional, reason: 'frequency', note: note);
  }
  return r.expectsOn(d)
      ? Expectation(ExpectationKind.required, reason: reason, note: note)
      : Expectation(ExpectationKind.rest, reason: reason, note: note);
}

/// The version in force on [date] — the latest whose `effectiveFrom` is not
/// after it. Null when the member had no prescription then.
Prescription? versionEffectiveOn(List<Prescription> versions, DateTime date) {
  final d = _midnight(date);

  // A VERSION WHOSE WINDOW HAS CLOSED MUST NOT MASK ONE THAT IS STILL OPEN.
  //
  // Selection was on `effectiveFrom` alone and never consulted the end of the
  // window, so a finished block with a later start outranked a live one and
  // [expectationFor] then answered `ended` — the member's plan read "finished"
  // while a current plan was serving them. The server has been end-clamping
  // superseded versions for exactly this purpose since WS-3, and nothing
  // selected on it.
  //
  // Two passes rather than one comparison, because the fallback matters: when
  // NOTHING is still open the honest answer is still the most recent closed
  // version (which resolves `ended`), not `unknown`. A closed version is only
  // ever beaten by an open one, never dropped.
  final open = <Prescription>[];
  final closed = <Prescription>[];
  for (final p in versions) {
    if (_midnight(p.effectiveFrom).isAfter(d)) continue;
    final end = p.effectiveEndDate;
    if (end != null && d.isAfter(_midnight(end))) {
      closed.add(p);
    } else {
      open.add(p);
    }
  }
  final candidates = open.isNotEmpty ? open : closed;

  Prescription? best;
  for (final p in candidates) {
    if (best == null ||
        _midnight(p.effectiveFrom).isAfter(_midnight(best.effectiveFrom)) ||
        (_midnight(p.effectiveFrom) == _midnight(best.effectiveFrom) &&
            p.version > best.version)) {
      best = p;
    }
  }
  return best;
}

/// Resolves one day fully: expectation + what happened.
///
/// [logged] — a qualifying log exists for that date.
/// [excused] — the coach cancelled this specific day.
DayVerdict verdictFor(
  List<Prescription> versions,
  DateTime date, {
  required bool logged,
  required DateTime today,
  bool excused = false,
  PrescriptionException? coachingPause,
}) {
  final d = _midnight(date);
  final t = _midnight(today);
  final e = expectationFor(versions, d, coachingPause: coachingPause);

  OutcomeKind outcome;
  switch (e.kind) {
    case ExpectationKind.required:
      if (logged) {
        outcome = OutcomeKind.done;
      } else if (excused) {
        outcome = OutcomeKind.excusedByCoach;
      } else if (!d.isBefore(t)) {
        // Today (or, defensively, the future) is never a miss.
        outcome = OutcomeKind.open;
      } else {
        outcome = OutcomeKind.missed;
      }
    case ExpectationKind.optional:
    case ExpectationKind.rest:
      // Logging on a rest or optional day is a genuine hit and can only help.
      // Not logging is never a miss.
      outcome = logged ? OutcomeKind.done : OutcomeKind.excluded;
    case ExpectationKind.paused:
    case ExpectationKind.notYetStarted:
    case ExpectationKind.ended:
    case ExpectationKind.unknown:
      // A DAY THE MEMBER TRAINED IS A DAY THE MEMBER TRAINED.
      //
      // This branch used to return `excluded` without ever consulting
      // [logged], which collapsed the two axes this engine exists to keep
      // apart: a coach's paperwork (or its absence) decided whether a real
      // session had happened. `unknown` is — by this file's own words — "every
      // member on the platform today", so for most of the platform EVERY
      // logged day resolved to `excluded`: the week rail drew empty circles on
      // days the member trained, the 30-day calendar drew them faint, and
      // "Total workouts" and "Adherence" both read "—" beside a streak that
      // said 5. The same erasure hit sessions logged before a plan started,
      // after it ended, and through a medical pause.
      //
      // `excluded` still applies when NOTHING was logged, so scoring is
      // untouched: `isMiss` remains gated on `required`, an unlogged paused
      // day still freezes rather than breaks a streak, and the ratios that
      // quote "days your coach asked for" count required days only.
      outcome = logged ? OutcomeKind.done : OutcomeKind.excluded;
  }

  return DayVerdict(
    date: d,
    expectation: e.kind,
    outcome: outcome,
    reason: e.reason,
  );
}

/// Whether a WEEK satisfied a frequency prescription (freeze §7.3).
///
/// Frequency is scored by week because the member chooses the days. A partial
/// CURRENT week is open, never a miss — judging Wednesday on a 4-per-week
/// target would punish a member who simply has not finished the week.
WeekVerdict weekVerdict(
  Rhythm rhythm,
  DateTime weekStart, {
  required int loggedInWeek,
  required DateTime today,
}) {
  final start = _midnight(weekStart);
  final end = start.add(const Duration(days: 6));
  final isCurrent = !_midnight(today).isAfter(end);
  if (rhythm.type != RhythmType.frequency) {
    return WeekVerdict(start, loggedInWeek, 0, WeekOutcome.notApplicable);
  }
  if (loggedInWeek >= rhythm.count) {
    return WeekVerdict(start, loggedInWeek, rhythm.count, WeekOutcome.hit);
  }
  return WeekVerdict(
    start,
    loggedInWeek,
    rhythm.count,
    isCurrent ? WeekOutcome.open : WeekOutcome.missed,
  );
}

enum WeekOutcome { hit, missed, open, notApplicable }

class WeekVerdict {
  final DateTime weekStart;
  final int logged;
  final int required;
  final WeekOutcome outcome;
  const WeekVerdict(this.weekStart, this.logged, this.required, this.outcome);
}

// ═══════════════════════════════════════════════════════════════════════════
// CADENCE & TARGET — the other two kinds of expectation  (freeze §2, ▲1)
// ═══════════════════════════════════════════════════════════════════════════

/// "How often", not "on which days" — check-in, weight, photo, measurements.
///
/// A cadence item is never "missed": it is DUE or OVERDUE. Putting a
/// fortnightly check-in into a daily streak would be meaningless.
enum CadenceState { notDue, due, overdue, never }

/// [intervalDays] is the coach's cadence (`clients.checkInCadenceDays` already
/// exists and is exactly this). [lastDone] null → never done.
CadenceState cadenceState({
  required int? intervalDays,
  required DateTime? lastDone,
  required DateTime today,
}) {
  if (intervalDays == null || intervalDays <= 0) return CadenceState.never;
  if (lastDone == null) return CadenceState.due;
  final elapsed = _calendarDaysBetween(lastDone, today);
  if (elapsed < intervalDays) return CadenceState.notDue;
  // One full interval late before it escalates — a coach does not want an alert
  // the moment a member is an hour past due.
  return elapsed >= intervalDays * 2
      ? CadenceState.overdue
      : CadenceState.due;
}

/// "How much, every day" — water, sleep, steps, supplements.
///
/// A target is never "missed" and never has a rest day. It is MET or not, and
/// it is only scored when the COACH set it — a platform default must never
/// masquerade as a prescription.
enum TargetState { met, notMet, noTargetSet }

TargetState targetState({required num? target, required num? actual}) {
  if (target == null || target <= 0) return TargetState.noTargetSet;
  if (actual == null) return TargetState.notMet;
  return actual >= target ? TargetState.met : TargetState.notMet;
}

// ═══════════════════════════════════════════════════════════════════════════
// SERVING GLUE — THE ONE ASSIGNMENT RESOLUTION RULE
// ═══════════════════════════════════════════════════════════════════════════
//
// Ported from `trainershq-backend/functions/src/lib/prescription.ts`, which
// remains the source of truth. It lives here because its ABSENCE is what let
// three separate client-side copies of "which assignment wins" grow — one in
// each app and one on the server's own serving path — and they had already
// drifted: the coach workspace broke createdAt ties the opposite way from the
// server, and never consulted `excusedDays` at all.
//
// A day key is a `yyyy-MM-dd` LOCAL date, matching `excusedDays`' stored keys.

/// The slice of an assignment document the resolver needs.
///
/// Deliberately not `PlanAssignmentModel`: this engine is twinned across both
/// apps and the server, and must not know either app's model layer.
class AssignmentSlice {
  /// The assignment document's id, so a caller can map the winning slice back
  /// to the document it came from. Mirrors the server's `ServingSlice.id`,
  /// which exists for exactly the same reason.
  final String id;

  /// Raw stored status. Empty/unknown reads as active — legacy documents were
  /// written before the lifecycle existed and are genuinely active.
  final String status;

  /// Assignment creation time, in millis. The tie-break for "latest wins".
  final int createdAtMillis;

  final Prescription? prescription;

  /// Day keys the coach excused on THIS assignment.
  final Set<String> excusedDays;

  /// The day the assignment was created, when known. Only consulted by a
  /// DATE-SCOPED pick: an assignment cannot have applied before it existed.
  final DateTime? createdOn;

  /// The day the assignment stopped serving, when known. Only meaningful once
  /// it is no longer active, and an approximation (`updatedAt` moves on any
  /// write) — the same one the member's timeline already clamps versions with.
  final DateTime? leftServiceOn;

  const AssignmentSlice({
    this.id = '',
    required this.status,
    required this.createdAtMillis,
    this.prescription,
    this.excusedDays = const {},
    this.createdOn,
    this.leftServiceOn,
  });

  /// Unknown/empty → `active`, matching the server's `status || "active"`.
  String get normalizedStatus {
    if (status == 'paused' || status == 'ended') return status;
    return 'active';
  }
}

/// Whether an assignment was IN SERVICE on [day].
///
/// Deliberately narrow: it answers only what the stored document can PROVE,
/// and never guesses what an assignment's status was in the past. An
/// assignment paused or ended TODAY may well have been running on the day
/// asked about, so it stays a candidate.
bool sliceInServiceOn(AssignmentSlice a, DateTime day) {
  final d = _midnight(day);
  final created = a.createdOn;
  if (created != null && d.isBefore(_midnight(created))) return false;
  final left = a.leftServiceOn;
  if (a.normalizedStatus == 'ended' &&
      left != null &&
      _midnight(left).isBefore(d)) {
    return false;
  }
  return true;
}

/// The winning assignment, plus the kind to fall back to when none wins.
class AssignmentPick {
  final AssignmentSlice? slice;

  /// Meaningful only when [slice] is null: `paused`, `ended` or `unknown`.
  final ExpectationKind fallback;

  const AssignmentPick(this.slice, this.fallback);
}

/// Picks the assignment whose state answers "what is expected" for one track.
///
/// Latest ACTIVE wins; a missing status counts as active. When nothing is
/// active the most recent paused resolves `paused`, else the most recent ended
/// resolves `ended`, else `unknown`.
///
/// The `>=` tie-break is load-bearing and matches the server exactly: two
/// assignments written in one batch share a serverTimestamp, and picking the
/// FIRST of them (a strict `>`) makes the coach's answer disagree with the
/// member's about which plan is live.
///
/// [onDay] makes the pick DATE-SCOPED — resolve the assignment as it stood on
/// that day rather than as it stands now. Off by default, and that default is
/// load-bearing: a plan the coach ended TODAY has left service today, so a
/// date-scoped pick would re-label it running and keep serving a member the
/// plan their coach just removed.
AssignmentPick pickAssignmentForExpectation(
  List<AssignmentSlice> assignments, {
  DateTime? onDay,
}) {
  var scoped = assignments;
  if (onDay != null) {
    final inService =
        assignments.where((a) => sliceInServiceOn(a, onDay)).toList();
    // NEVER ANSWER FROM AN EMPTY SET WHEN THE UNSCOPED SET IS NOT EMPTY.
    // A fabricated absence is worse than a stale identity, and
    // `leftServiceOn` is only an approximation.
    if (inService.isNotEmpty) scoped = inService;
  }

  // The slice's status ON THE DAY ASKED ABOUT. `status` describes NOW, so a
  // plan the coach has since ended was bucketed `ended` for a day it was
  // demonstrably still running. `paused` is deliberately NOT re-labelled: a
  // pause carries no date stamp to reason from, and unknowable stays unknown.
  String statusOn(AssignmentSlice a) {
    final raw = a.normalizedStatus;
    if (onDay == null || raw != 'ended') return raw;
    return sliceInServiceOn(a, onDay) ? 'active' : raw;
  }

  AssignmentSlice? active;
  AssignmentSlice? paused;
  AssignmentSlice? ended;
  for (final a in scoped) {
    switch (statusOn(a)) {
      case 'paused':
        if (paused == null || a.createdAtMillis >= paused.createdAtMillis) {
          paused = a;
        }
      case 'ended':
        if (ended == null || a.createdAtMillis >= ended.createdAtMillis) {
          ended = a;
        }
      default:
        if (active == null || a.createdAtMillis >= active.createdAtMillis) {
          active = a;
        }
    }
  }
  if (active != null) return AssignmentPick(active, ExpectationKind.unknown);
  if (paused != null) return const AssignmentPick(null, ExpectationKind.paused);
  if (ended != null) return const AssignmentPick(null, ExpectationKind.ended);
  return const AssignmentPick(null, ExpectationKind.unknown);
}

/// One track's resolved expectation for a day, with the provenance a caller
/// needs to phrase it without re-deriving anything.
class TrackExpectation {
  final ExpectationKind kind;
  final String reason;
  final String note;

  /// Whether a coach-authored prescription exists for the serving assignment.
  final bool prescribed;

  /// Prescription version the expectation came from (0 = none).
  final int version;

  /// Rhythm summary for UI copy; null when not prescribed.
  final Rhythm? rhythm;

  /// The coach excused this specific day, on ANY of the member's assignments.
  final bool excusedToday;

  /// The expectation cannot be resolved from the CURRENT prescription block
  /// alone (its `effectiveFrom` is in the future) and the caller must supply
  /// [resolveTrackExpectation]'s `historyVersions` and re-resolve.
  final bool needsHistory;

  const TrackExpectation({
    this.kind = ExpectationKind.unknown,
    this.reason = '',
    this.note = '',
    this.prescribed = false,
    this.version = 0,
    this.rhythm,
    this.excusedToday = false,
    this.needsHistory = false,
  });

  static const TrackExpectation unknown = TrackExpectation();

  /// The one definition of "the coach asked for work on this day". A day the
  /// coach excused is not asked for, however the rhythm reads.
  bool get isRequired =>
      kind == ExpectationKind.required && !excusedToday;
}

/// Resolves one track's expectation for [day] from its assignment set.
///
/// THE canonical entry point. Every consumer that answers "what does this
/// member owe on this day" delegates here rather than selecting an assignment
/// and calling [expectationFor] itself — doing the latter is what produced
/// three answers to one question.
///
/// [historyVersions] is consulted only for the queued-future-block case; pass
/// nothing on the first call and re-call with the fetched history when the
/// result reports [TrackExpectation.needsHistory] (keeps the hot path at zero
/// extra reads).
TrackExpectation resolveTrackExpectation(
  List<AssignmentSlice> assignments,
  DateTime day, {
  PrescriptionException? coachingPause,
  List<Prescription> historyVersions = const [],
  bool asOfDay = false,
}) {
  final d = _midnight(day);

  // Client-level pause outranks everything, including "no assignment".
  if (coachingPause != null && coachingPause.covers(d)) {
    return TrackExpectation(
      kind: ExpectationKind.paused,
      reason: coachingPause.type.name,
      note: coachingPause.note,
    );
  }

  final pick = pickAssignmentForExpectation(
    assignments,
    onDay: asOfDay ? d : null,
  );
  final slice = pick.slice;
  if (slice == null) {
    if (pick.fallback == ExpectationKind.paused) {
      return const TrackExpectation(
        kind: ExpectationKind.paused,
        reason: 'coachPause',
      );
    }
    if (pick.fallback == ExpectationKind.ended) {
      return const TrackExpectation(kind: ExpectationKind.ended);
    }
    return TrackExpectation.unknown;
  }

  final current = slice.prescription;
  if (current == null) return TrackExpectation.unknown; // disclosed unknown

  // EXCUSES ARE READ FROM THE MERGED SET, ACROSS EVERY ASSIGNMENT.
  //
  // `excuseDay` targets an arbitrary assignment id and only proves org
  // ownership, so an excuse landing on a non-picked assignment is a normal
  // outcome. Resolved toward the merged set deliberately: an excuse is a coach
  // saying "this one is on me", and being too generous with it is not a
  // failure a member experiences as unfair.
  final key = _dayKeyOf(d);
  final excusedToday = assignments.any((a) => a.excusedDays.contains(key));

  // Queued future block: the current version is not yet in force and history
  // has not been supplied — the caller must fetch it and re-resolve.
  if (_midnight(current.effectiveFrom).isAfter(d) && historyVersions.isEmpty) {
    return TrackExpectation(
      prescribed: true,
      excusedToday: excusedToday,
      needsHistory: true,
    );
  }

  final versions = <Prescription>[current, ...historyVersions];
  final e = expectationFor(versions, d);
  final effective = versionEffectiveOn(versions, d);
  return TrackExpectation(
    kind: e.kind,
    reason: e.reason,
    note: e.note,
    prescribed: true,
    version: effective?.version ?? 0,
    rhythm: effective?.rhythm,
    excusedToday: excusedToday,
  );
}

// ═══════════════════════════════════════════════════════════════════════════
// helpers
// ═══════════════════════════════════════════════════════════════════════════

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

/// `yyyy-MM-dd` for a LOCAL date — the shape `excusedDays` is keyed by.
///
/// Defined here rather than imported so the engine stays free of any app's
/// utility layer and the two twins can remain byte-identical.
String _dayKeyOf(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

/// WHOLE CALENDAR DAYS from [from] to [to] — DST-safe.
///
/// `_midnight(a).difference(_midnight(b)).inDays` is NOT this. Local midnights
/// are wall-clock instants, so a day containing a DST transition is 23 or 25
/// hours long, and `inDays` TRUNCATES: across a spring-forward the difference
/// between 1 March and 15 March measures 13 days, not 14. The backend computes
/// the same span from UTC-anchored day keys and gets 14, so from the first DST
/// transition onward the member's own app and the server disagreed about which
/// days a cycle asked for — and about how long a cadence had been running.
/// Proven with `TZ=America/New_York`: `expectsOn(15 Mar)` returned false for a
/// 1-on/1-off cycle whose 14th day is an ON day.
///
/// Re-anchoring the two midnights in UTC keeps the CALENDAR fields the caller
/// meant while removing the only thing that made them elastic. UTC has no DST,
/// so every day is exactly 24 hours and the subtraction is exact.
int _calendarDaysBetween(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

String _iso(DateTime? d) => d == null
    ? ''
    : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is DateTime) return _midnight(v);
  if (v is String) {
    final p = DateTime.tryParse(v);
    return p == null ? null : _midnight(p);
  }
  // Firestore Timestamp, without importing cloud_firestore.
  try {
    final d = (v as dynamic).toDate();
    if (d is DateTime) return _midnight(d);
  } catch (_) {
    /* not a Timestamp */
  }
  if (v is int) return _midnight(DateTime.fromMillisecondsSinceEpoch(v));
  return null;
}

int _int(dynamic v, {int fallback = 0}) {
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

T? _enumByName<T extends Enum>(List<T> values, dynamic name) {
  final s = (name ?? '').toString();
  for (final v in values) {
    if (v.name == s) return v;
  }
  return null;
}
