import 'package:cloud_firestore/cloud_firestore.dart';

import '../weekly_reports/question_engine.dart';

/// Wire models for Weekly Reports.
///
/// THESE CARRY NO RULES. Every question, bound, unit and option is read out of
/// the frozen snapshot through `question_engine.dart`; these classes only parse
/// Firestore's types defensively (`Timestamp | String | num`) and expose what
/// the server decided. In particular the member app NEVER computes whether a
/// report is open — it reads `status`, `opensAt` and `dueAt`, which the server
/// wrote in the organization's timezone.

DateTime? _date(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is String) return DateTime.tryParse(v);
  return null;
}

String _str(dynamic v) => v == null ? '' : v.toString();
int _int(dynamic v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

/// Server-owned lifecycle of one week's report.
class WeeklyReportStatus {
  static const String scheduled = 'scheduled';
  static const String open = 'open';
  static const String submitted = 'submitted';
  static const String missed = 'missed';
  static const String cancelled = 'cancelled';
}

/// THE FROZEN SNAPSHOT — one member, one week, immutable forever.
class WeeklyReportSnapshot {
  final String id;
  final String clientId;
  final String adminId;
  final String periodKey;
  final String periodStart;
  final String periodEnd;
  final String timezone;
  final String status;
  final DateTime? opensAt;
  final DateTime? dueAt;
  final String templateId;
  final int templateVersion;
  final String contentHash;
  final List<ReportSection> sections;
  final List<QuestionDefinition> questions;

  const WeeklyReportSnapshot({
    required this.id,
    this.clientId = '',
    this.adminId = '',
    this.periodKey = '',
    this.periodStart = '',
    this.periodEnd = '',
    this.timezone = '',
    this.status = WeeklyReportStatus.scheduled,
    this.opensAt,
    this.dueAt,
    this.templateId = '',
    this.templateVersion = 0,
    this.contentHash = '',
    this.sections = const [],
    this.questions = const [],
  });

  bool get isOpen => status == WeeklyReportStatus.open;
  bool get isSubmitted => status == WeeklyReportStatus.submitted;
  bool get isMissed => status == WeeklyReportStatus.missed;
  bool get isCancelled => status == WeeklyReportStatus.cancelled;

  /// Whether the member may still write. The SERVER's `status` decides; this is
  /// only the read of it. A missed report stays writable because the platform
  /// default allows late submission — and the rules, not this getter, are what
  /// actually enforce it.
  bool get acceptsAnswers => isOpen || isMissed;

  /// Human label for the week under review, e.g. "3 – 9 Aug".
  String get periodLabel {
    final a = DateTime.tryParse(periodStart);
    final b = DateTime.tryParse(periodEnd);
    if (a == null || b == null) return periodKey;
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final sameMonth = a.month == b.month;
    return sameMonth
        ? '${a.day} – ${b.day} ${m[b.month - 1]}'
        : '${a.day} ${m[a.month - 1]} – ${b.day} ${m[b.month - 1]}';
  }

  factory WeeklyReportSnapshot.fromMap(Map<String, dynamic> m, String id) {
    final snap = m['snapshot'];
    final raw = snap is Map ? Map<String, dynamic>.from(snap) : const {};
    final rawQ = raw['questions'];
    final rawS = raw['sections'];
    return WeeklyReportSnapshot(
      id: id,
      clientId: _str(m['clientId']),
      adminId: _str(m['adminId']),
      periodKey: _str(m['periodKey']),
      periodStart: _str(m['periodStart']),
      periodEnd: _str(m['periodEnd']),
      timezone: _str(m['timezone']),
      status: _str(m['status']).isEmpty
          ? WeeklyReportStatus.scheduled
          : _str(m['status']),
      opensAt: _date(m['opensAt']),
      dueAt: _date(m['dueAt']),
      templateId: _str(m['templateId']),
      templateVersion: _int(m['templateVersion']),
      contentHash: _str(raw['contentHash']),
      sections: rawS is List
          ? rawS
              .whereType<Map>()
              .map((e) => ReportSection.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const [],
      questions: rawQ is List
          ? rawQ
              .whereType<Map>()
              .map((e) =>
                  QuestionDefinition.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const [],
    );
  }
}

/// The member's answers. `draft` until submitted; immutable afterwards.
class WeeklyReportSubmission {
  final String id;
  final String status;
  final Map<String, dynamic> answers;
  final int completedRequired;
  final int totalRequired;
  final int revisionCount;
  final DateTime? submittedAt;
  final DateTime? lastSavedAt;

  const WeeklyReportSubmission({
    required this.id,
    this.status = 'draft',
    this.answers = const {},
    this.completedRequired = 0,
    this.totalRequired = 0,
    this.revisionCount = 0,
    this.submittedAt,
    this.lastSavedAt,
  });

  bool get isSubmitted => status == 'submitted';
  bool get isDraft => status == 'draft';

  /// True when the member has entered anything at all — what separates
  /// "not started" from "resume where you left off".
  bool get hasContent => answers.values.any((e) {
        final v = e is Map ? e['value'] : e;
        return isAnswered(v);
      });

  factory WeeklyReportSubmission.fromMap(Map<String, dynamic> m, String id) =>
      WeeklyReportSubmission(
        id: id,
        status: _str(m['status']).isEmpty ? 'draft' : _str(m['status']),
        answers: m['answers'] is Map
            ? Map<String, dynamic>.from(m['answers'] as Map)
            : const {},
        completedRequired: _int(m['completedRequired']),
        totalRequired: _int(m['totalRequired']),
        revisionCount: _int(m['revisionCount']),
        submittedAt: _date(m['submittedAt']),
        lastSavedAt: _date(m['lastSavedAt']),
      );
}

/// One action item the coach set. Member-visible, member-read-only.
class WeeklyReportActionItem {
  final String id;
  final String text;
  final bool done;

  /// `action` or `goal`.
  ///
  /// A GOAL AND AN ACTION ITEM ARE THE SAME DOCUMENT SHAPE ON PURPOSE. Goals
  /// have no collection anywhere on this platform, and inventing one for a UI
  /// mission would mean a new schema, new rules, a new index and a deploy — to
  /// store a sentence with a date. They live in the review the coach already
  /// writes and the member already reads, distinguished by this field.
  ///
  /// Unknown values read as `action`: an older build must degrade to showing a
  /// goal as a task, never to dropping it.
  final String kind;

  /// When a goal is meant to be reached. Null for an ordinary action item.
  final DateTime? dueAt;

  const WeeklyReportActionItem({
    required this.id,
    required this.text,
    this.done = false,
    this.kind = kActionKind,
    this.dueAt,
  });

  static const String kActionKind = 'action';
  static const String kGoalKind = 'goal';

  bool get isGoal => kind == kGoalKind;

  WeeklyReportActionItem copyWith({
    String? text,
    bool? done,
    String? kind,
    DateTime? dueAt,
    bool clearDueAt = false,
  }) =>
      WeeklyReportActionItem(
        id: id,
        text: text ?? this.text,
        done: done ?? this.done,
        kind: kind ?? this.kind,
        dueAt: clearDueAt ? null : (dueAt ?? this.dueAt),
      );

  factory WeeklyReportActionItem.fromMap(Map<String, dynamic> m) =>
      WeeklyReportActionItem(
        id: _str(m['id']),
        text: _str(m['text']),
        done: m['done'] == true,
        kind: _str(m['kind']) == kGoalKind ? kGoalKind : kActionKind,
        dueAt: _date(m['dueAt']),
      );

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'text': text,
        'done': done,
        'kind': kind,
        // Omitted rather than written null: a null in an array element is a
        // value some parsers keep and others drop, and this array round-trips
        // through two apps and a projection.
        if (dueAt != null) 'dueAt': Timestamp.fromDate(dueAt!),
      };
}

/// The coach's review. Private notes are NOT here — they live in a subcollection
/// the member has no read rule for, because Firestore authorizes documents and
/// not fields.
class WeeklyReportReview {
  final String id;
  final String status;
  final String reviewerName;
  final String visibleNotes;
  final Map<String, String> questionComments;
  final List<WeeklyReportActionItem> actionItems;
  final DateTime? followUpAt;
  final DateTime? reviewedAt;

  const WeeklyReportReview({
    required this.id,
    this.status = 'pending',
    this.reviewerName = '',
    this.visibleNotes = '',
    this.questionComments = const {},
    this.actionItems = const [],
    this.followUpAt,
    this.reviewedAt,
  });

  bool get isCompleted => status == 'completed';

  /// Whether there is anything for the member to read. A `pending` review with
  /// no notes must not render as "your coach replied".
  bool get hasFeedback =>
      isCompleted &&
      (visibleNotes.trim().isNotEmpty ||
          actionItems.isNotEmpty ||
          questionComments.isNotEmpty);

  factory WeeklyReportReview.fromMap(Map<String, dynamic> m, String id) {
    final comments = <String, String>{};
    final rawC = m['questionComments'];
    if (rawC is Map) {
      rawC.forEach((k, v) => comments[k.toString()] = _str(v));
    }
    final rawA = m['actionItems'];
    return WeeklyReportReview(
      id: id,
      status: _str(m['status']).isEmpty ? 'pending' : _str(m['status']),
      reviewerName: _str(m['reviewerName']),
      visibleNotes: _str(m['visibleNotes']),
      questionComments: comments,
      actionItems: rawA is List
          ? rawA
              .whereType<Map>()
              .map((e) =>
                  WeeklyReportActionItem.fromMap(Map<String, dynamic>.from(e)))
              .toList(growable: false)
          : const [],
      followUpAt: _date(m['followUpAt']),
      reviewedAt: _date(m['reviewedAt']),
    );
  }
}

/// One point on a trend line.
class TrendPoint {
  final String periodKey;
  final double value;
  const TrendPoint(this.periodKey, this.value);
}

/// Server-maintained trend series, keyed by the engine's `analyticsKey`.
///
/// ONE DOCUMENT for a 52-week chart. Reading 52 submissions to draw a line was
/// the alternative, and it is what makes a history screen slow enough that
/// members stop opening it.
class WeeklyReportRollup {
  final String clientId;
  final Map<String, List<TrendPoint>> series;

  const WeeklyReportRollup({this.clientId = '', this.series = const {}});

  List<TrendPoint> seriesFor(String analyticsKey) =>
      series[analyticsKey] ?? const [];

  /// Keys that carry at least two points — a single point is not a trend, and
  /// drawing one as a flat line invents a story the data does not tell.
  List<String> get trendableKeys => [
        for (final e in series.entries)
          if (e.value.length >= 2) e.key,
      ]..sort();

  factory WeeklyReportRollup.fromMap(Map<String, dynamic> m, String id) {
    final out = <String, List<TrendPoint>>{};
    final raw = m['series'];
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is! List) return;
        final pts = <TrendPoint>[];
        for (final e in v) {
          if (e is! Map) continue;
          final p = _str(e['p']);
          final n = e['v'];
          if (p.isEmpty || n is! num) continue;
          pts.add(TrendPoint(p, n.toDouble()));
        }
        if (pts.isNotEmpty) out[k.toString()] = pts;
      });
    }
    return WeeklyReportRollup(clientId: id, series: out);
  }
}
