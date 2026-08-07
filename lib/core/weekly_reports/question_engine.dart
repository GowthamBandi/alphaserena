// ═══════════════════════════════════════════════════════════════════════════
// WEEKLY REPORTS — THE QUESTION ENGINE
//
// THIS FILE IS SHARED BYTE-FOR-BYTE BETWEEN alphaserena AND trainersHQ, and is
// twinned in TypeScript at
// `trainershq-backend/functions/src/lib/weekly_report_question.ts`.
//
//   • `test/weekly_report_engine_parity_test.dart` (both repos) pins the
//     SHA-256 of this file. Editing one copy without the other FAILS.
//   • `weekly_report_contract.json` is executed by BOTH the Dart suite and the
//     TS suite, pinning that the two validators agree case by case.
//
// WHY THIS DISCIPLINE. The rule this platform keeps relearning is *one rule, N
// copies, one drifts* — `lifestyle_math.dart` drifted, `progress_series.dart`
// re-implemented 13 rules the shared analytics core already owned, and a wrong
// number passed 1,982 tests. A weekly report is answered in one app, rendered
// in another and validated in a third; if "is this answer valid" is written
// three times, it will disagree three ways.
//
// PURE. No Flutter, no Firebase, no `DateTime.now()`. Every rule here is
// provable in a plain unit test, and nothing in it can read a device clock.
//
// WHAT IT OWNS
//   1. The question TYPE REGISTRY   — the 22 types and what each stores.
//   2. The wire MODEL               — QuestionDefinition and friends.
//   3. VALIDATION                   — one verdict, machine-coded, cross-language.
//   4. VISIBILITY + COMPLETION      — conditional questions and the submit gate.
//   5. The CANONICAL CONTENT STRING — what a template/snapshot hash is taken of.
//   6. The LEGACY PROJECTION map    — the Stage-A bridge to the old 7 keys.
//   7. The BUILT-IN LIBRARY         — and the default template blueprint.
//
// WHAT IT DELIBERATELY DOES NOT OWN
//   • Rendering. The UI dispatches through a registry keyed by `type`; there is
//     no switch on question type anywhere in either app.
//   • Persistence, ids, scheduling, timezones — all server-side concerns.
// ═══════════════════════════════════════════════════════════════════════════

import 'dart:convert';

/// Bump when the meaning of a stored question/answer shape changes.
const int kWeeklyReportSchema = 1;

// ───────────────────────────────────────────────────────────────────────────
// 1. THE TYPE REGISTRY
// ───────────────────────────────────────────────────────────────────────────

/// What actually lands in `answers.<questionId>.value`.
enum QuestionValueKind { integer, decimal, text, boolean, textList }

/// The immutable description of one question type.
///
/// A type is DATA, not a class. Adding a type is one row in [kQuestionTypes] +
/// one renderer registration + one contract-fixture case — never a new branch
/// in a screen.
class QuestionTypeSpec {
  final String id;
  final QuestionValueKind valueKind;

  /// Defaults applied when a question omits `validation` entirely.
  final QuestionValidation defaults;

  /// True when the type is meaningless without `options` (choice-like types).
  final bool requiresOptions;

  /// The analytics series this type feeds when the author does not name one.
  /// Null means "not trended by default".
  final String? defaultAnalyticsKey;

  const QuestionTypeSpec({
    required this.id,
    required this.valueKind,
    this.defaults = const QuestionValidation(),
    this.requiresOptions = false,
    this.defaultAnalyticsKey,
  });
}

/// A 1..5 scale — the shape most coaching questions want.
const QuestionValidation _scale1to5 =
    QuestionValidation(min: 1, max: 5, step: 1);

/// THE REGISTRY. Order is presentation order in the coach's type picker.
///
/// NOTE on the brief's `customText` / `customRating` / `customNumber`: they are
/// NOT types. A custom question is `text`/`rating`/`number` with no
/// `libraryId`. "Custom" is PROVENANCE, not type — modelling it as a type would
/// put one validation rule in two places, which is the defect this file exists
/// to prevent.
const List<QuestionTypeSpec> kQuestionTypes = <QuestionTypeSpec>[
  // ── generic ──────────────────────────────────────────────────────────────
  QuestionTypeSpec(
      id: 'rating', valueKind: QuestionValueKind.integer, defaults: _scale1to5),
  QuestionTypeSpec(
      id: 'emoji',
      valueKind: QuestionValueKind.text,
      requiresOptions: true),
  QuestionTypeSpec(
      id: 'slider',
      valueKind: QuestionValueKind.decimal,
      defaults: QuestionValidation(min: 0, max: 100, step: 1)),
  QuestionTypeSpec(
      id: 'number',
      valueKind: QuestionValueKind.decimal,
      defaults: QuestionValidation(decimals: 2)),
  QuestionTypeSpec(
      id: 'text',
      valueKind: QuestionValueKind.text,
      defaults: QuestionValidation(maxLength: 280)),
  QuestionTypeSpec(
      id: 'paragraph',
      valueKind: QuestionValueKind.text,
      defaults: QuestionValidation(maxLength: 4000)),
  QuestionTypeSpec(id: 'yesNo', valueKind: QuestionValueKind.boolean),
  QuestionTypeSpec(
      id: 'multipleChoice',
      valueKind: QuestionValueKind.textList,
      requiresOptions: true,
      defaults: QuestionValidation(minSelect: 0, maxSelect: 20)),
  QuestionTypeSpec(
      id: 'singleChoice',
      valueKind: QuestionValueKind.text,
      requiresOptions: true),

  // ── measured ─────────────────────────────────────────────────────────────
  QuestionTypeSpec(
      id: 'water',
      valueKind: QuestionValueKind.decimal,
      defaults: QuestionValidation(min: 0, max: 20000, decimals: 0),
      defaultAnalyticsKey: 'water'),
  QuestionTypeSpec(
      id: 'sleep',
      valueKind: QuestionValueKind.decimal,
      defaults: QuestionValidation(min: 0, max: 24, decimals: 1),
      defaultAnalyticsKey: 'sleep_hours'),
  QuestionTypeSpec(
      id: 'weight',
      valueKind: QuestionValueKind.decimal,
      // Bounds mirror the body-units guard the profile editor already enforces:
      // 3 cm / 9,999 kg were once projectable to a coach.
      defaults: QuestionValidation(min: 20, max: 400, decimals: 1),
      defaultAnalyticsKey: 'weight'),
  QuestionTypeSpec(
      id: 'photos',
      valueKind: QuestionValueKind.textList,
      defaults: QuestionValidation(maxPhotos: 8)),

  // ── coaching scales (rating presets with a trend series attached) ─────────
  QuestionTypeSpec(
      id: 'mood',
      valueKind: QuestionValueKind.integer,
      defaults: _scale1to5,
      defaultAnalyticsKey: 'mood'),
  QuestionTypeSpec(
      id: 'energy',
      valueKind: QuestionValueKind.integer,
      defaults: _scale1to5,
      defaultAnalyticsKey: 'energy'),
  QuestionTypeSpec(
      id: 'stress',
      valueKind: QuestionValueKind.integer,
      defaults: _scale1to5,
      defaultAnalyticsKey: 'stress'),
  QuestionTypeSpec(
      id: 'recovery',
      valueKind: QuestionValueKind.integer,
      defaults: _scale1to5,
      defaultAnalyticsKey: 'recovery'),
  QuestionTypeSpec(
      id: 'workoutSatisfaction',
      valueKind: QuestionValueKind.integer,
      defaults: _scale1to5,
      defaultAnalyticsKey: 'workout_satisfaction'),
  QuestionTypeSpec(
      id: 'dietSatisfaction',
      valueKind: QuestionValueKind.integer,
      defaults: _scale1to5,
      defaultAnalyticsKey: 'diet_satisfaction'),
  QuestionTypeSpec(
      id: 'supplementAdherence',
      valueKind: QuestionValueKind.integer,
      defaults: _scale1to5,
      defaultAnalyticsKey: 'supplement_adherence'),
  QuestionTypeSpec(
      id: 'pain',
      valueKind: QuestionValueKind.integer,
      defaults: _scale1to5,
      defaultAnalyticsKey: 'pain'),
  QuestionTypeSpec(
      id: 'digestion',
      valueKind: QuestionValueKind.integer,
      defaults: _scale1to5,
      defaultAnalyticsKey: 'digestion'),
];

final Map<String, QuestionTypeSpec> _typeById = <String, QuestionTypeSpec>{
  for (final t in kQuestionTypes) t.id: t,
};

/// The spec for [type], or null when this build does not know the type.
///
/// A null here is NOT a bug — it is an older app meeting a question type
/// shipped after it. See [validateAnswer] for how that degrades safely.
QuestionTypeSpec? questionTypeSpec(String type) => _typeById[type];

/// Every known type id, in registry order.
List<String> get kQuestionTypeIds =>
    kQuestionTypes.map((t) => t.id).toList(growable: false);

// ───────────────────────────────────────────────────────────────────────────
// 2. THE WIRE MODEL
// ───────────────────────────────────────────────────────────────────────────

num? _num(dynamic v) {
  if (v is num) return v;
  if (v is String) return num.tryParse(v.trim());
  return null;
}

int? _int(dynamic v) => _num(v)?.toInt();

String _str(dynamic v) => v == null ? '' : v.toString();

bool _bool(dynamic v, {bool fallback = false}) {
  if (v is bool) return v;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true') return true;
    if (s == 'false') return false;
  }
  return fallback;
}

/// One selectable answer on a choice-like question.
class QuestionOption {
  final String id;
  final String label;

  /// Optional numeric weight — what analytics trends when this option is
  /// picked. Null means the option is categorical and is not trended.
  final num? value;
  final String emoji;

  const QuestionOption({
    required this.id,
    required this.label,
    this.value,
    this.emoji = '',
  });

  factory QuestionOption.fromMap(Map<String, dynamic> m) => QuestionOption(
        id: _str(m['id']),
        label: _str(m['label']),
        value: _num(m['value']),
        emoji: _str(m['emoji']),
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'label': label,
        if (value != null) 'value': value,
        if (emoji.isNotEmpty) 'emoji': emoji,
      };
}

/// The bounds a question's answer must satisfy. Every field is optional; an
/// omitted field inherits the type's default (see [QuestionDefinition.bounds]).
class QuestionValidation {
  final num? min;
  final num? max;
  final num? step;
  final int? decimals;
  final int? minLength;
  final int? maxLength;
  final int? minSelect;
  final int? maxSelect;
  final int? maxPhotos;

  const QuestionValidation({
    this.min,
    this.max,
    this.step,
    this.decimals,
    this.minLength,
    this.maxLength,
    this.minSelect,
    this.maxSelect,
    this.maxPhotos,
  });

  factory QuestionValidation.fromMap(Map<String, dynamic> m) =>
      QuestionValidation(
        min: _num(m['min']),
        max: _num(m['max']),
        step: _num(m['step']),
        decimals: _int(m['decimals']),
        minLength: _int(m['minLength']),
        maxLength: _int(m['maxLength']),
        minSelect: _int(m['minSelect']),
        maxSelect: _int(m['maxSelect']),
        maxPhotos: _int(m['maxPhotos']),
      );

  /// [other] wins where it specifies a value; this object supplies the rest.
  QuestionValidation mergedUnder(QuestionValidation other) => QuestionValidation(
        min: other.min ?? min,
        max: other.max ?? max,
        step: other.step ?? step,
        decimals: other.decimals ?? decimals,
        minLength: other.minLength ?? minLength,
        maxLength: other.maxLength ?? maxLength,
        minSelect: other.minSelect ?? minSelect,
        maxSelect: other.maxSelect ?? maxSelect,
        maxPhotos: other.maxPhotos ?? maxPhotos,
      );

  bool get isEmpty =>
      min == null &&
      max == null &&
      step == null &&
      decimals == null &&
      minLength == null &&
      maxLength == null &&
      minSelect == null &&
      maxSelect == null &&
      maxPhotos == null;

  Map<String, dynamic> toMap() => <String, dynamic>{
        if (min != null) 'min': min,
        if (max != null) 'max': max,
        if (step != null) 'step': step,
        if (decimals != null) 'decimals': decimals,
        if (minLength != null) 'minLength': minLength,
        if (maxLength != null) 'maxLength': maxLength,
        if (minSelect != null) 'minSelect': minSelect,
        if (maxSelect != null) 'maxSelect': maxSelect,
        if (maxPhotos != null) 'maxPhotos': maxPhotos,
      };
}

/// The comparison operators a `showIf` rule may use.
class VisibilityOp {
  static const String eq = 'eq';
  static const String ne = 'ne';
  static const String gt = 'gt';
  static const String gte = 'gte';
  static const String lt = 'lt';
  static const String lte = 'lte';
  static const String contains = 'contains';
  static const String answered = 'answered';
  static const String notAnswered = 'notAnswered';

  static const List<String> all = <String>[
    eq, ne, gt, gte, lt, lte, contains, answered, notAnswered,
  ];
}

/// "Show this question only when another question was answered a certain way."
class QuestionVisibility {
  final String questionId;
  final String op;
  final dynamic value;

  const QuestionVisibility({
    required this.questionId,
    required this.op,
    this.value,
  });

  static QuestionVisibility? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final showIf = raw['showIf'];
    final m = showIf is Map ? showIf : raw;
    final qid = _str(m['questionId']);
    final op = _str(m['op']);
    if (qid.isEmpty || !VisibilityOp.all.contains(op)) return null;
    return QuestionVisibility(questionId: qid, op: op, value: m['value']);
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'showIf': <String, dynamic>{
          'questionId': questionId,
          'op': op,
          if (value != null) 'value': value,
        },
      };
}

/// One question, as authored and as frozen into a weekly snapshot.
class QuestionDefinition {
  /// Stable forever, never reused. This is the key an answer is stored under,
  /// so changing it orphans every historical answer.
  final String id;

  /// Which library question this came from; empty for an inline-authored one.
  /// PROVENANCE ONLY — it is never followed at render time, because a frozen
  /// snapshot must not depend on a mutable document.
  final String libraryId;

  final String type;
  final String title;
  final String description;
  final String sectionId;
  final int order;
  final bool required;
  final bool enabled;
  final dynamic defaultValue;
  final String unit;
  final QuestionValidation validation;
  final List<QuestionOption> options;
  final QuestionVisibility? visibility;

  /// The trend series this question feeds, e.g. `mood`. Empty = not trended.
  final String analyticsKey;

  const QuestionDefinition({
    required this.id,
    required this.type,
    required this.title,
    this.libraryId = '',
    this.description = '',
    this.sectionId = '',
    this.order = 0,
    this.required = false,
    this.enabled = true,
    this.defaultValue,
    this.unit = '',
    this.validation = const QuestionValidation(),
    this.options = const <QuestionOption>[],
    this.visibility,
    this.analyticsKey = '',
  });

  /// The type's defaults with the author's overrides applied on top.
  QuestionValidation get bounds {
    final spec = questionTypeSpec(type);
    if (spec == null) return validation;
    return spec.defaults.mergedUnder(validation);
  }

  /// The author's key, else the type's default, else empty.
  String get effectiveAnalyticsKey {
    if (analyticsKey.isNotEmpty) return analyticsKey;
    return questionTypeSpec(type)?.defaultAnalyticsKey ?? '';
  }

  QuestionDefinition copyWith({
    String? id,
    String? libraryId,
    String? type,
    String? title,
    String? description,
    String? sectionId,
    int? order,
    bool? required,
    bool? enabled,
    String? unit,
    QuestionValidation? validation,
    List<QuestionOption>? options,
    String? analyticsKey,
  }) =>
      QuestionDefinition(
        id: id ?? this.id,
        libraryId: libraryId ?? this.libraryId,
        type: type ?? this.type,
        title: title ?? this.title,
        description: description ?? this.description,
        sectionId: sectionId ?? this.sectionId,
        order: order ?? this.order,
        required: required ?? this.required,
        enabled: enabled ?? this.enabled,
        defaultValue: defaultValue,
        unit: unit ?? this.unit,
        validation: validation ?? this.validation,
        options: options ?? this.options,
        visibility: visibility,
        analyticsKey: analyticsKey ?? this.analyticsKey,
      );

  factory QuestionDefinition.fromMap(Map<String, dynamic> m) {
    final rawOptions = m['options'];
    return QuestionDefinition(
      id: _str(m['id']),
      libraryId: _str(m['libraryId']),
      type: _str(m['type']),
      title: _str(m['title']),
      description: _str(m['description']),
      sectionId: _str(m['sectionId']),
      order: _int(m['order']) ?? 0,
      required: _bool(m['required']),
      // A question with no `enabled` field is ENABLED. A missing field must
      // never silently remove a question from a member's report.
      enabled: _bool(m['enabled'], fallback: true),
      defaultValue: m['defaultValue'],
      unit: _str(m['unit']),
      validation: m['validation'] is Map
          ? QuestionValidation.fromMap(
              Map<String, dynamic>.from(m['validation'] as Map))
          : const QuestionValidation(),
      options: rawOptions is List
          ? rawOptions
              .whereType<Map>()
              .map((e) => QuestionOption.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const <QuestionOption>[],
      visibility: QuestionVisibility.fromMap(m['visibility']),
      analyticsKey: _str(m['analyticsKey']),
    );
  }

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        if (libraryId.isNotEmpty) 'libraryId': libraryId,
        'type': type,
        'title': title,
        if (description.isNotEmpty) 'description': description,
        if (sectionId.isNotEmpty) 'sectionId': sectionId,
        'order': order,
        'required': required,
        'enabled': enabled,
        if (defaultValue != null) 'defaultValue': defaultValue,
        if (unit.isNotEmpty) 'unit': unit,
        if (!validation.isEmpty) 'validation': validation.toMap(),
        if (options.isNotEmpty)
          'options': options.map((o) => o.toMap()).toList(growable: false),
        if (visibility != null) 'visibility': visibility!.toMap(),
        if (analyticsKey.isNotEmpty) 'analyticsKey': analyticsKey,
        'schema': kWeeklyReportSchema,
      };
}

/// A titled group of questions inside a template.
class ReportSection {
  final String id;
  final String title;
  final String description;
  final int order;

  const ReportSection({
    required this.id,
    required this.title,
    this.description = '',
    this.order = 0,
  });

  factory ReportSection.fromMap(Map<String, dynamic> m) => ReportSection(
        id: _str(m['id']),
        title: _str(m['title']),
        description: _str(m['description']),
        order: _int(m['order']) ?? 0,
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'title': title,
        if (description.isNotEmpty) 'description': description,
        'order': order,
      };
}

// ───────────────────────────────────────────────────────────────────────────
// 3. VALIDATION
// ───────────────────────────────────────────────────────────────────────────

/// Stable machine codes. These strings appear in `weekly_report_contract.json`
/// and are asserted by BOTH language suites — they are API, not debug text.
class AnswerIssue {
  static const String none = 'ok';
  static const String requiredMissing = 'required';
  static const String wrongType = 'type';
  static const String belowMin = 'min';
  static const String aboveMax = 'max';
  static const String badStep = 'step';
  static const String tooManyDecimals = 'decimals';
  static const String tooShort = 'minLength';
  static const String tooLong = 'maxLength';
  static const String tooFewSelected = 'minSelect';
  static const String tooManySelected = 'maxSelect';
  static const String unknownOption = 'unknownOption';
  static const String tooManyPhotos = 'maxPhotos';

  /// This build does not know the question's type. NOT a failure — see
  /// [validateAnswer].
  static const String unknownType = 'unknownType';
}

/// The outcome of validating one answer.
class AnswerVerdict {
  final bool ok;

  /// One of [AnswerIssue]. `ok` when there is nothing wrong.
  final String code;

  /// Member-facing text. Empty when [ok] and no note applies.
  final String message;

  /// The coerced, storable value — null when absent or unusable.
  final dynamic value;

  const AnswerVerdict({
    required this.ok,
    required this.code,
    this.message = '',
    this.value,
  });

  static const AnswerVerdict empty =
      AnswerVerdict(ok: true, code: AnswerIssue.none);
}

/// Whether [raw] counts as an answer at all (before any bounds are applied).
bool isAnswered(dynamic raw) {
  if (raw == null) return false;
  if (raw is String) return raw.trim().isNotEmpty;
  if (raw is Iterable) return raw.isNotEmpty;
  if (raw is Map) return raw.isNotEmpty;
  return true;
}

/// Coerces [raw] to the type's [QuestionValueKind], or null if it cannot be.
///
/// Deliberately narrow: a number answered to a `text` question is a client bug,
/// not something to paper over with `toString()`. Silent coercion across kinds
/// is how a "valid" entry ends up dropped by a stricter reader downstream.
dynamic coerceAnswer(QuestionValueKind kind, dynamic raw) {
  switch (kind) {
    case QuestionValueKind.integer:
      final n = _num(raw);
      if (n == null) return null;
      // 4.5 answered to a 1..5 rating is not "4" — it is wrong, and saying so
      // is more useful than rounding it away.
      if (n is double && n != n.roundToDouble()) return null;
      return n.toInt();
    case QuestionValueKind.decimal:
      return _num(raw)?.toDouble();
    case QuestionValueKind.text:
      return raw is String ? raw.trim() : null;
    case QuestionValueKind.boolean:
      if (raw is bool) return raw;
      if (raw is String) {
        final s = raw.trim().toLowerCase();
        if (s == 'true') return true;
        if (s == 'false') return false;
      }
      return null;
    case QuestionValueKind.textList:
      if (raw is! Iterable) return null;
      final out = <String>[];
      for (final e in raw) {
        if (e is! String) return null;
        final s = e.trim();
        if (s.isNotEmpty) out.add(s);
      }
      return out;
  }
}

/// THE validator. One implementation, two languages, one contract fixture.
///
/// UNKNOWN TYPES PASS. An app build that predates a question type cannot judge
/// it, and blocking would strand the member on a report they can never submit.
/// The verdict carries [AnswerIssue.unknownType] so the UI can render an honest
/// "needs an app update" card, and the SERVER — which always knows every type —
/// records the authoritative completion count on submit.
AnswerVerdict validateAnswer(QuestionDefinition q, dynamic raw) {
  final spec = questionTypeSpec(q.type);
  if (spec == null) {
    return AnswerVerdict(
      ok: true,
      code: AnswerIssue.unknownType,
      message: 'This question needs an app update.',
      value: raw,
    );
  }

  if (!isAnswered(raw)) {
    return q.required
        ? const AnswerVerdict(
            ok: false,
            code: AnswerIssue.requiredMissing,
            message: 'This one is required.')
        : AnswerVerdict.empty;
  }

  final value = coerceAnswer(spec.valueKind, raw);
  if (value == null) {
    return const AnswerVerdict(
        ok: false,
        code: AnswerIssue.wrongType,
        message: 'That answer isn\'t in the expected format.');
  }

  final b = q.bounds;

  if (value is num) {
    if (b.min != null && value < b.min!) {
      return AnswerVerdict(
          ok: false,
          code: AnswerIssue.belowMin,
          message: 'Enter ${_plain(b.min!)} or more.',
          value: value);
    }
    if (b.max != null && value > b.max!) {
      return AnswerVerdict(
          ok: false,
          code: AnswerIssue.aboveMax,
          message: 'Enter ${_plain(b.max!)} or less.',
          value: value);
    }
    if (b.step != null && b.step! > 0) {
      final origin = b.min ?? 0;
      final steps = (value - origin) / b.step!;
      if ((steps - steps.roundToDouble()).abs() > 1e-9) {
        return AnswerVerdict(
            ok: false,
            code: AnswerIssue.badStep,
            message: 'Use steps of ${_plain(b.step!)}.',
            value: value);
      }
    }
    if (b.decimals != null && value is double) {
      final factor = _pow10(b.decimals!);
      if (((value * factor) - (value * factor).roundToDouble()).abs() > 1e-9) {
        return AnswerVerdict(
            ok: false,
            code: AnswerIssue.tooManyDecimals,
            message: b.decimals == 0
                ? 'Enter a whole number.'
                : 'Use at most ${b.decimals} decimal places.',
            value: value);
      }
    }
  }

  if (value is String) {
    if (spec.requiresOptions) {
      final known = q.options.any((o) => o.id == value);
      if (!known) {
        return AnswerVerdict(
            ok: false,
            code: AnswerIssue.unknownOption,
            message: 'Pick one of the offered answers.',
            value: value);
      }
    } else {
      if (b.minLength != null && value.length < b.minLength!) {
        return AnswerVerdict(
            ok: false,
            code: AnswerIssue.tooShort,
            message: 'Write at least ${b.minLength} characters.',
            value: value);
      }
      if (b.maxLength != null && value.length > b.maxLength!) {
        return AnswerVerdict(
            ok: false,
            code: AnswerIssue.tooLong,
            message: 'Keep it under ${b.maxLength} characters.',
            value: value);
      }
    }
  }

  if (value is List<String>) {
    if (q.type == 'photos') {
      if (b.maxPhotos != null && value.length > b.maxPhotos!) {
        return AnswerVerdict(
            ok: false,
            code: AnswerIssue.tooManyPhotos,
            message: 'Up to ${b.maxPhotos} photos.',
            value: value);
      }
    } else {
      if (b.minSelect != null && value.length < b.minSelect!) {
        return AnswerVerdict(
            ok: false,
            code: AnswerIssue.tooFewSelected,
            message: 'Choose at least ${b.minSelect}.',
            value: value);
      }
      if (b.maxSelect != null && value.length > b.maxSelect!) {
        return AnswerVerdict(
            ok: false,
            code: AnswerIssue.tooManySelected,
            message: 'Choose at most ${b.maxSelect}.',
            value: value);
      }
      if (spec.requiresOptions) {
        final ids = q.options.map((o) => o.id).toSet();
        for (final v in value) {
          if (!ids.contains(v)) {
            return AnswerVerdict(
                ok: false,
                code: AnswerIssue.unknownOption,
                message: 'Pick from the offered answers.',
                value: value);
          }
        }
      }
    }
  }

  return AnswerVerdict(ok: true, code: AnswerIssue.none, value: value);
}

double _pow10(int n) {
  var out = 1.0;
  for (var i = 0; i < n; i++) {
    out *= 10;
  }
  return out;
}

/// Renders a bound without a trailing `.0`, so a message reads "1" not "1.0".
String _plain(num v) =>
    v is int || v == v.roundToDouble() ? v.toInt().toString() : v.toString();

// ───────────────────────────────────────────────────────────────────────────
// 4. VISIBILITY + COMPLETION
// ───────────────────────────────────────────────────────────────────────────

/// Reads `answers[questionId].value` from the stored answer map shape.
dynamic answerValue(Map<String, dynamic> answers, String questionId) {
  final entry = answers[questionId];
  if (entry is Map) return entry['value'];
  // Tolerate a bare value — older drafts and test fixtures write it that way.
  return entry;
}

bool _compare(String op, dynamic left, dynamic right) {
  switch (op) {
    case VisibilityOp.answered:
      return isAnswered(left);
    case VisibilityOp.notAnswered:
      return !isAnswered(left);
    case VisibilityOp.contains:
      if (left is Iterable) return left.contains(right);
      if (left is String) return left.contains(_str(right));
      return false;
  }

  final ln = _num(left);
  final rn = _num(right);
  if (ln != null && rn != null) {
    switch (op) {
      case VisibilityOp.eq:
        return ln == rn;
      case VisibilityOp.ne:
        return ln != rn;
      case VisibilityOp.gt:
        return ln > rn;
      case VisibilityOp.gte:
        return ln >= rn;
      case VisibilityOp.lt:
        return ln < rn;
      case VisibilityOp.lte:
        return ln <= rn;
    }
    return false;
  }

  // Non-numeric: only equality is meaningful. `gt` on two strings would be an
  // invented rule that the coach never asked for.
  if (op == VisibilityOp.eq) return _str(left) == _str(right);
  if (op == VisibilityOp.ne) return _str(left) != _str(right);
  if (left is bool && right is bool) return false;
  return false;
}

/// How deep a `showIf` chain may go before it is treated as a cycle.
const int _kVisibilityDepthLimit = 12;

bool _visible(
  QuestionDefinition q,
  Map<String, QuestionDefinition> byId,
  Map<String, dynamic> answers,
  Set<String> seen,
  int depth,
) {
  if (!q.enabled) return false;
  final rule = q.visibility;
  if (rule == null) return true;

  // A cycle (A shows-if B, B shows-if A) must not hang the screen. Showing the
  // question is the safe failure: a member can always over-answer, never
  // under-answer, and an invisible required question is unsubmittable.
  if (depth >= _kVisibilityDepthLimit || seen.contains(q.id)) return true;

  final controller = byId[rule.questionId];
  // A rule pointing at a question that is not in this snapshot is inert. The
  // snapshot is frozen, so this can only mean the coach deleted the controller
  // after authoring the rule — showing the dependent question is honest.
  if (controller == null) return true;

  if (!_visible(controller, byId, answers, {...seen, q.id}, depth + 1)) {
    return false;
  }
  return _compare(rule.op, answerValue(answers, rule.questionId), rule.value);
}

/// The questions a member should actually see, in author order.
///
/// Enabled + visible only, sorted by `order` then `id` so the sequence is
/// stable across devices (two questions with the same `order` must not swap
/// between renders).
List<QuestionDefinition> visibleQuestions(
  List<QuestionDefinition> questions,
  Map<String, dynamic> answers,
) {
  final byId = <String, QuestionDefinition>{for (final q in questions) q.id: q};
  final out = questions
      .where((q) => _visible(q, byId, answers, <String>{}, 0))
      .toList();
  out.sort((a, b) {
    final c = a.order.compareTo(b.order);
    return c != 0 ? c : a.id.compareTo(b.id);
  });
  return out;
}

/// The submit gate and the progress bar, from one computation.
class ReportCompletion {
  final int answered;
  final int total;
  final int requiredAnswered;
  final int requiredTotal;

  /// questionId → the failing verdict. Empty when everything entered is valid.
  final Map<String, AnswerVerdict> issues;

  const ReportCompletion({
    required this.answered,
    required this.total,
    required this.requiredAnswered,
    required this.requiredTotal,
    this.issues = const <String, AnswerVerdict>{},
  });

  /// THE GATE. Every required question answered, and nothing entered is
  /// invalid. Both halves matter: the old check-in asked only "has the member
  /// typed anything?", which was necessary but also, wrongly, sufficient.
  bool get canSubmit => requiredAnswered >= requiredTotal && issues.isEmpty;

  double get progress => total == 0 ? 0 : answered / total;
}

/// Scores [answers] against [questions]. Hidden and disabled questions are
/// excluded from BOTH numerator and denominator — a required question the
/// member cannot see must never block their submit.
ReportCompletion completionOf(
  List<QuestionDefinition> questions,
  Map<String, dynamic> answers,
) {
  final visible = visibleQuestions(questions, answers);
  var answeredCount = 0;
  var requiredTotal = 0;
  var requiredAnswered = 0;
  final issues = <String, AnswerVerdict>{};

  for (final q in visible) {
    final raw = answerValue(answers, q.id);
    final verdict = validateAnswer(q, raw);
    final has = isAnswered(raw);

    if (has) answeredCount++;

    // A required question whose TYPE this build does not know is excluded from
    // the gate entirely. It still renders (as an honest "needs an app update"
    // card) and still counts toward `total`, but counting it as required would
    // strand the member on a report they have no control able to answer — and
    // counting it as satisfied would be a lie the server's recount contradicts.
    final gateable = questionTypeSpec(q.type) != null;

    if (q.required && gateable) {
      requiredTotal++;
      if (has && verdict.ok) requiredAnswered++;
    }
    if (!verdict.ok) issues[q.id] = verdict;
  }

  return ReportCompletion(
    answered: answeredCount,
    total: visible.length,
    requiredAnswered: requiredAnswered,
    requiredTotal: requiredTotal,
    issues: issues,
  );
}

// ───────────────────────────────────────────────────────────────────────────
// 5. THE CANONICAL CONTENT STRING
// ───────────────────────────────────────────────────────────────────────────

/// A byte-stable serialization of a template's questions + sections. Hashing
/// this is what proves an assignment's snapshot never changed.
///
/// TWO RULES MAKE IT REPRODUCIBLE IN TYPESCRIPT:
///   1. Keys are emitted in a fixed order (both `jsonEncode` and
///      `JSON.stringify` preserve insertion order for string keys).
///   2. Integral doubles are emitted as integers. Dart renders `4.0` as "4.0"
///      and JS renders it as "4" — left alone, that alone would break every
///      cross-language hash comparison.
///
/// The engine does NOT hash. Callers apply SHA-256 to this string, so this file
/// stays dependency-free and unit-testable without `package:crypto`.
String canonicalContentString({
  required List<ReportSection> sections,
  required List<QuestionDefinition> questions,
}) {
  final s = [...sections]..sort((a, b) {
      final c = a.order.compareTo(b.order);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  final q = [...questions]..sort((a, b) {
      final c = a.order.compareTo(b.order);
      return c != 0 ? c : a.id.compareTo(b.id);
    });
  return jsonEncode(<String, dynamic>{
    'schema': kWeeklyReportSchema,
    'sections': s.map((e) => _canonJson(e.toMap())).toList(growable: false),
    'questions': q.map((e) => _canonJson(e.toMap())).toList(growable: false),
  });
}

dynamic _canonJson(dynamic v) {
  if (v is double) return v == v.roundToDouble() ? v.toInt() : v;
  if (v is Map) {
    final keys = v.keys.map((k) => k.toString()).toList()..sort();
    return <String, dynamic>{for (final k in keys) k: _canonJson(v[k])};
  }
  if (v is Iterable) return v.map(_canonJson).toList(growable: false);
  return v;
}

// ───────────────────────────────────────────────────────────────────────────
// 6. THE LEGACY PROJECTION (Stage-A bridge)
// ───────────────────────────────────────────────────────────────────────────

/// The seven fixed keys the retiring `client_check_in_submissions` carries, and
/// which weekly-report analytics key feeds each.
///
/// This map is THE bridge. 25 Dart files and 4 backend files still read those
/// seven keys — Attention, Missions, Action Centre, Timeline, Progress and
/// Engagement all score from them. Until every one of those consumers is
/// repointed (Stage C), a submitted weekly report is projected into the legacy
/// shape through this map, and nothing on the coach's side goes dark.
///
/// The two judgement calls, stated openly rather than buried: `cravings` feeds
/// the legacy `hunger` scale, and `mood` feeds the legacy `motivation` scale.
/// Neither is a synonym; each is the nearest surviving question, and the legacy
/// consumers score a trend rather than the word.
const Map<String, String> kLegacyRatingKeyByAnalyticsKey = <String, String>{
  'energy': 'energy',
  'sleep': 'sleep',
  'stress': 'stress',
  'cravings': 'hunger',
  'mood': 'motivation',
  'workout_satisfaction': 'training',
  'diet_adherence': 'diet',
};

/// Rescales an answer onto the legacy 1..5 integer scale.
///
/// A coach may set a 1..10 rating; the legacy consumers assume 1..5 and
/// `CheckInSubmissionModel._parseRatings` DROPS anything outside it — so an
/// un-rescaled 8 would vanish silently rather than read as 4.
int? projectToLegacyRating(num? value, {num min = 1, num max = 5}) {
  if (value == null) return null;
  if (max <= min) return null;
  final clamped = value < min ? min : (value > max ? max : value);
  final ratio = (clamped - min) / (max - min);
  final scaled = 1 + (ratio * 4);
  final rounded = scaled.round();
  return rounded < 1 ? 1 : (rounded > 5 ? 5 : rounded);
}

// ───────────────────────────────────────────────────────────────────────────
// 7. THE BUILT-IN LIBRARY + THE DEFAULT TEMPLATE
// ───────────────────────────────────────────────────────────────────────────

/// Section ids used by the default blueprint.
class DefaultSections {
  static const String general = 's_general';
  static const String recovery = 's_recovery';
  static const String training = 's_training';
  static const String nutrition = 's_nutrition';
  static const String body = 's_body';
  static const String notes = 's_notes';
}

QuestionDefinition _b(
  String id,
  String type,
  String title, {
  String section = DefaultSections.general,
  String description = '',
  bool required = false,
  String unit = '',
  QuestionValidation validation = const QuestionValidation(),
  String analyticsKey = '',
  List<QuestionOption> options = const <QuestionOption>[],
}) =>
    QuestionDefinition(
      id: id,
      // A built-in is its own library entry — provenance points at itself, so a
      // template can always tell "coach wrote this" from "shipped with the app".
      libraryId: id,
      type: type,
      title: title,
      description: description,
      sectionId: section,
      required: required,
      unit: unit,
      validation: validation,
      analyticsKey: analyticsKey,
      options: options,
    );

/// THE BUILT-IN QUESTION LIBRARY.
///
/// Deliberately CODE, not Firestore documents. They are identical for every
/// organization, cost zero reads, and a per-org document copy is exactly the
/// drift source this file exists to eliminate. `weekly_report_questions` holds
/// only what a coach authored.
final List<QuestionDefinition> kBuiltInQuestions = <QuestionDefinition>[
  _b('q_week_summary', 'paragraph', 'How was your week?',
      description: 'The headline — what went well, what got in the way.',
      required: true,
      validation: const QuestionValidation(maxLength: 2000)),
  _b('q_energy', 'energy', 'Energy',
      section: DefaultSections.recovery,
      description: '1 = drained, 5 = excellent',
      required: true),
  _b('q_stress', 'stress', 'Stress',
      section: DefaultSections.recovery,
      description: '1 = calm, 5 = overwhelmed',
      required: true),
  // SLEEP IS TWO QUESTIONS, NOT ONE. Quality is a 1..5 judgement; hours are a
  // measurement. Collapsing them — as the first draft of this library did —
  // fed HOURS into the legacy `sleep` RATING key, which is both semantically
  // wrong (7.5 hours is not "3 out of 5") and, because the analytics keys did
  // not meet, silently blank on every legacy coach surface. The default
  // template asks for quality (matching the retiring check-in it replaces);
  // hours are available in the library for coaches who want the measurement.
  _b('q_sleep_quality', 'rating', 'Sleep',
      section: DefaultSections.recovery,
      description: '1 = poor, 5 = excellent',
      required: true,
      analyticsKey: 'sleep'),
  _b('q_recovery', 'recovery', 'Recovery',
      section: DefaultSections.recovery,
      description: 'How well did your body bounce back?',
      required: true),
  _b('q_workout_difficulty', 'rating', 'Workout Difficulty',
      section: DefaultSections.training,
      description: '1 = too easy, 5 = too hard',
      required: true,
      analyticsKey: 'workout_difficulty'),
  _b('q_workout_enjoyment', 'workoutSatisfaction', 'Workout Enjoyment',
      section: DefaultSections.training,
      description: 'Did you enjoy training this week?',
      required: true),
  _b('q_diet_adherence', 'rating', 'Diet Adherence',
      section: DefaultSections.nutrition,
      description: 'How closely did you follow the plan?',
      required: true,
      analyticsKey: 'diet_adherence'),
  _b('q_diet_satisfaction', 'dietSatisfaction', 'Diet Satisfaction',
      section: DefaultSections.nutrition,
      description: 'Was the plan enjoyable and filling?',
      required: true),
  _b('q_water', 'water', 'Water Intake',
      section: DefaultSections.nutrition,
      description: 'Average per day',
      unit: 'ml',
      required: true,
      validation: const QuestionValidation(min: 0, max: 10000, decimals: 0)),
  _b('q_digestion', 'digestion', 'Digestion',
      section: DefaultSections.nutrition,
      description: '1 = poor, 5 = excellent',
      required: true),
  _b('q_cravings', 'rating', 'Cravings',
      section: DefaultSections.nutrition,
      description: '1 = none, 5 = constant',
      required: true,
      analyticsKey: 'cravings'),
  _b('q_mood', 'mood', 'Mood',
      section: DefaultSections.recovery,
      description: '1 = low, 5 = great',
      required: true),
  _b('q_progress_photos', 'photos', 'Progress Photos',
      section: DefaultSections.body,
      description: 'Front, side and back if you can.',
      validation: const QuestionValidation(maxPhotos: 6)),
  _b('q_weight', 'weight', 'Current Weight',
      section: DefaultSections.body,
      description: 'Measured first thing in the morning.',
      unit: 'kg',
      required: true),
  _b('q_coach_notes', 'paragraph', 'Notes for your coach',
      section: DefaultSections.notes,
      description: 'Anything you want them to know before they review.',
      validation: const QuestionValidation(maxLength: 2000)),
  _b('q_additional_comments', 'paragraph', 'Additional Comments',
      section: DefaultSections.notes,
      validation: const QuestionValidation(maxLength: 2000)),

  // ── library-only: available to add, not in the default template ──────────
  _b('q_sleep_hours', 'sleep', 'Average Sleep Hours',
      section: DefaultSections.recovery,
      description: 'Average hours per night this week',
      unit: 'hours',
      validation: const QuestionValidation(min: 0, max: 16, decimals: 1)),
  _b('q_pain', 'pain', 'Pain or niggles',
      section: DefaultSections.recovery,
      description: '1 = none, 5 = significant'),
  _b('q_supplements', 'supplementAdherence', 'Supplement Adherence',
      section: DefaultSections.nutrition,
      description: 'How consistently did you take your stack?'),
  _b('q_steps', 'number', 'Average Daily Steps',
      section: DefaultSections.training,
      unit: 'steps',
      validation: const QuestionValidation(min: 0, max: 100000, decimals: 0),
      analyticsKey: 'steps'),
  _b('q_missed_sessions', 'number', 'Sessions missed',
      section: DefaultSections.training,
      validation: const QuestionValidation(min: 0, max: 14, decimals: 0),
      analyticsKey: 'missed_sessions'),
  _b('q_alcohol', 'yesNo', 'Any alcohol this week?',
      section: DefaultSections.nutrition),
  _b('q_travel', 'yesNo', 'Were you travelling this week?',
      section: DefaultSections.general),
  _b('q_waist', 'number', 'Waist',
      section: DefaultSections.body,
      unit: 'cm',
      validation: const QuestionValidation(min: 30, max: 250, decimals: 1),
      analyticsKey: 'waist'),
];

final Map<String, QuestionDefinition> _builtInById =
    <String, QuestionDefinition>{for (final q in kBuiltInQuestions) q.id: q};

/// A built-in by id, or null.
QuestionDefinition? builtInQuestion(String id) => _builtInById[id];

/// The sections of the professional default template.
const List<ReportSection> kDefaultSections = <ReportSection>[
  ReportSection(id: DefaultSections.general, title: 'General', order: 0),
  ReportSection(
      id: DefaultSections.recovery, title: 'Recovery & Wellbeing', order: 1),
  ReportSection(id: DefaultSections.training, title: 'Training', order: 2),
  ReportSection(id: DefaultSections.nutrition, title: 'Nutrition', order: 3),
  ReportSection(id: DefaultSections.body, title: 'Body', order: 4),
  ReportSection(id: DefaultSections.notes, title: 'Notes', order: 5),
];

/// The 17 questions every new organization starts with (Phase 3), in order.
const List<String> kDefaultTemplateQuestionIds = <String>[
  'q_week_summary',
  'q_energy',
  'q_stress',
  'q_sleep_quality',
  'q_recovery',
  'q_workout_difficulty',
  'q_workout_enjoyment',
  'q_diet_adherence',
  'q_diet_satisfaction',
  'q_water',
  'q_digestion',
  'q_cravings',
  'q_mood',
  'q_progress_photos',
  'q_weight',
  'q_coach_notes',
  'q_additional_comments',
];

/// The default template's questions, `order` assigned from list position.
///
/// A BLUEPRINT, not a live pointer: an organization MATERIALIZES a copy of this
/// into its own template document. A later change here therefore reaches new
/// organizations only — it can never edit a template a coach has already
/// customised, and it can never reach a frozen weekly snapshot.
List<QuestionDefinition> defaultTemplateQuestions() {
  final out = <QuestionDefinition>[];
  for (var i = 0; i < kDefaultTemplateQuestionIds.length; i++) {
    final q = builtInQuestion(kDefaultTemplateQuestionIds[i]);
    if (q == null) continue;
    out.add(q.copyWith(order: i));
  }
  return out;
}
