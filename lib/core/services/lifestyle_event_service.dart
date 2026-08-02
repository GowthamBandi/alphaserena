import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
import '../domain/coaching_event.dart';
import '../models/lifestyle_log_model.dart';
import '../models/lifestyle_targets.dart';
import 'coaching_event_writer.dart';
import 'lifestyle_log_service.dart';

/// LIFESTYLE EVENT PRODUCER (WS-6).
///
/// Converts member actions into first-class coaching events, replacing the
/// mutable totals the app has always written:
///
///   a glass tapped      → drink {ml}                  (summed server-side)
///   a glass withdrawn   → soft-delete the last drink  (never a subtraction)
///   sleep reported      → sleep {minutes | start,end} (duration derived)
///   steps entered       → steps_sample {count}        (manual = absolute)
///   a supplement ticked → supplement_taken {itemId}   (one event per DOSE)
///
/// DUAL WRITE, DELIBERATELY
/// ------------------------
/// TrainerHQ's lifestyle review reads the legacy `client_lifestyle_logs`
/// totals. Producing events alone would leave every coach staring at a blank
/// screen, so this service ALSO maintains the legacy document until TrainerHQ
/// reads `coaching_rollups`. The legacy total is derived from the same events
/// (one calculation, not two independent ones) and is written best-effort: it
/// is a compatibility projection, so its failure must never make a member
/// believe their event was lost.
///
/// The event write is the one whose result the member sees.
class LifestyleEventService {
  LifestyleEventService({
    CoachingEventWriter? writer,
    LifestyleLogService? legacy,
    MemberController? member,
  })  : _writer = writer ??
            CoachingEventWriter(collection: FsCollections.clientLifestyleDays),
        _legacy = legacy ?? LifestyleLogService(),
        _member = member ??
            (Get.isRegistered<MemberController>()
                ? Get.find<MemberController>()
                : Get.put(MemberController()));

  final CoachingEventWriter _writer;
  final LifestyleLogService _legacy;
  final MemberController _member;

  bool get canLog =>
      _member.clientId.isNotEmpty &&
      _member.adminId.isNotEmpty &&
      _member.uid.isNotEmpty;

  Future<EventWriteResult> _append(String dateKey, CoachingEvent event) {
    if (!canLog) return Future.value(EventWriteResult.failed);
    return _writer.appendEvent(
      clientId: _member.clientId,
      adminId: _member.adminId,
      authorUid: _member.uid,
      dateKey: dateKey,
      event: event,
    );
  }

  /// Records one drink. Two devices tapping concurrently both count — the
  /// legacy path reads the streamed total, adds, and writes an absolute
  /// figure, so one device's glass silently overwrites the other's.
  Future<EventWriteResult> logDrink({
    required String dateKey,
    required int ml,
    String source = EventSource.manual,
    String? sourceKey,
  }) {
    return _append(
      dateKey,
      CoachingEvent(
        eventId: newEventId(),
        type: LifestyleEventType.drink,
        at: DateTime.now(),
        source: source,
        sourceKey: sourceKey,
        payload: {'ml': ml},
      ),
    );
  }

  /// Records sleep as a PERIOD when the member gave instants (preferred: the
  /// duration is then derived, and overlapping periods merge), or as a stated
  /// duration when they only reported hours. Instants are never synthesised —
  /// inventing a bedtime the member never gave would be fabrication, and in an
  /// append-only store it would be permanent.
  Future<EventWriteResult> logSleep({
    required String dateKey,
    DateTime? start,
    DateTime? end,
    int? minutes,
    String source = EventSource.manual,
    String? sourceKey,
  }) {
    final hasPeriod = start != null && end != null && end.isAfter(start);
    return _append(
      dateKey,
      CoachingEvent(
        eventId: newEventId(),
        type: LifestyleEventType.sleep,
        at: DateTime.now(),
        source: source,
        sourceKey: sourceKey,
        payload: hasPeriod
            ? {
                'start': start.millisecondsSinceEpoch,
                'end': end.millisecondsSinceEpoch,
              }
            : {'minutes': minutes ?? 0},
      ),
    );
  }

  /// Records a step reading. A manual entry is an absolute daily figure, so
  /// the server takes the latest rather than summing; a device sample carries
  /// a `sourceKey` and is summed after dedup.
  Future<EventWriteResult> logSteps({
    required String dateKey,
    required int count,
    String source = EventSource.manual,
    String? sourceKey,
  }) {
    return _append(
      dateKey,
      CoachingEvent(
        eventId: newEventId(),
        type: LifestyleEventType.stepsSample,
        at: DateTime.now(),
        source: source,
        sourceKey: sourceKey,
        payload: {'count': count},
      ),
    );
  }

  /// Records one DOSE. A 3x/day protocol produces three events, where the
  /// legacy model could only ever store a single daily boolean for the whole
  /// stack — discarding the coach's `timing` entirely.
  Future<EventWriteResult> logSupplementDose({
    required String dateKey,
    required String itemId,
    String? name,
    String? dose,
  }) {
    return _append(
      dateKey,
      CoachingEvent(
        eventId: newEventId(),
        type: LifestyleEventType.supplementTaken,
        at: DateTime.now(),
        source: EventSource.manual,
        payload: {
          'itemId': itemId,
          if (name != null && name.isNotEmpty) 'name': name,
          if (dose != null && dose.isNotEmpty) 'dose': dose,
        },
      ),
    );
  }

  /// Withdraws ONE named event.
  ///
  /// The `undoLast*` helpers pick their own target from the events they are
  /// handed, which is safe only if the caller's view is current. It is not
  /// during a burst of taps — a withdrawal is a write, and until its snapshot
  /// returns the event still reads as live — so the controller chooses the
  /// target itself, marks it withdrawn locally, and names it here.
  Future<EventWriteResult> withdraw({
    required String dateKey,
    required String eventId,
  }) {
    if (!canLog) return Future.value(EventWriteResult.failed);
    return _writer.softDeleteEvent(
      clientId: _member.clientId,
      dateKey: dateKey,
      eventId: eventId,
    );
  }

  /// Live events for one day.
  Stream<List<CoachingEvent>> watchDay(String dateKey) {
    if (!canLog) return Stream.value(const []);
    return _writer
        .watchDay(clientId: _member.clientId, dateKey: dateKey)
        .map(parseCoachingEvents);
  }

  /// COMPATIBILITY PROJECTION — keeps TrainerHQ's existing lifestyle review
  /// working during the migration window.
  ///
  /// Derived from the SAME events the server will derive from, so the two can
  /// never disagree about what the member did; the server's `computed` map
  /// remains authoritative. Best-effort by design: this is a bridge for a
  /// coach screen, and its failure must never be reported to a member as a
  /// lost log. Retires when TrainerHQ reads `coaching_rollups`.
  Future<void> mirrorLegacyTotals({
    required String dateKey,
    required List<CoachingEvent> events,
    List<SupplementPlanItem> stack = const [],
  }) async {
    if (!canLog) return;
    try {
      final sleep = sleepMinutes(events);
      final steps = totalSteps(events);
      await _legacy.mirrorDay(
        dateKey: dateKey,
        waterMl: totalWaterMl(events).toDouble(),
        sleepHours: sleep == null ? null : sleep / 60.0,
        steps: steps?.toDouble(),
        supplements: projectSupplements(events, stack),
      );
    } catch (_) {
      // Never surfaced: the event is the record, this is only the bridge.
    }
  }

  /// The day's supplement checklist in the LEGACY shape, projected from dose
  /// events over the coach's stack.
  ///
  /// The mirror never wrote supplements at all, so the coach's supplement
  /// adherence read 0% no matter how faithfully the member ticked their stack.
  /// Returns null when no stack is prescribed, so the mirror leaves the field
  /// untouched rather than writing an empty array over a legacy snapshot.
  static List<SupplementIntake>? projectSupplements(
    List<CoachingEvent> events,
    List<SupplementPlanItem> stack,
  ) {
    if (stack.isEmpty) return null;
    final taken = supplementItemsTaken(events);
    return [
      for (final s in stack)
        SupplementIntake(
            id: s.id, name: s.name, dose: s.dose, taken: taken.contains(s.id)),
    ];
  }

  /// A compact signature of everything the projection would write. The
  /// controller compares it against the legacy document already on the wire so
  /// the bridge writes only when it is genuinely behind — the mirror used to
  /// fire on every action regardless.
  static String legacySignature(
    List<CoachingEvent> events,
    List<SupplementPlanItem> stack,
  ) {
    final taken = supplementItemsTaken(events);
    final ticks = [
      for (final s in stack) '${s.id}:${taken.contains(s.id)}',
    ].join(',');
    return '${totalWaterMl(events)}|${sleepMinutes(events)}|'
        '${totalSteps(events)}|$ticks';
  }

  /// The same signature computed from the legacy document a coach would read.
  static String legacySignatureOf(
    LifestyleLogModel? log,
    List<SupplementPlanItem> stack,
  ) {
    if (log == null) return 'none';
    final water = log.waterMl?.value.round() ?? 0;
    final sleepMin = log.sleepHours == null
        ? null
        : (log.sleepHours!.value * 60).round();
    final steps = log.steps?.value.round();
    final takenIds = {
      for (final s in log.supplements)
        if (s.taken) s.id,
    };
    final ticks = [
      for (final s in stack) '${s.id}:${takenIds.contains(s.id)}',
    ].join(',');
    return '$water|$sleepMin|$steps|$ticks';
  }
}
