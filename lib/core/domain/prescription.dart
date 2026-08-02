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
        final delta = _midnight(date).difference(_midnight(start)).inDays;
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
      if (e.replacementRhythm != null && !e.replacementRhythm!.isValid) {
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
  final end = p.endDate;
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
  Prescription? best;
  for (final p in versions) {
    if (_midnight(p.effectiveFrom).isAfter(d)) continue;
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
  final elapsed = _midnight(today).difference(_midnight(lastDone)).inDays;
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
// helpers
// ═══════════════════════════════════════════════════════════════════════════

DateTime _midnight(DateTime d) => DateTime(d.year, d.month, d.day);

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
