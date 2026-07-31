import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
import '../domain/coaching_event.dart';
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

  /// Withdraws the most recently recorded drink.
  ///
  /// A "minus one glass" tap is a CORRECTION, not a negative quantity: it soft
  /// deletes the last drink so the record shows what happened, including that
  /// the member took it back.
  Future<EventWriteResult> undoLastDrink({
    required String dateKey,
    required List<CoachingEvent> events,
  }) {
    final last = lastDrink(events);
    if (last == null) return Future.value(EventWriteResult.synced);
    if (!canLog) return Future.value(EventWriteResult.failed);
    return _writer.softDeleteEvent(
      clientId: _member.clientId,
      dateKey: dateKey,
      eventId: last.eventId,
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

  /// Withdraws the most recent dose of one supplement (un-ticking it).
  Future<EventWriteResult> undoSupplementDose({
    required String dateKey,
    required List<CoachingEvent> events,
    required String itemId,
  }) {
    final last = lastDoseOf(events, itemId);
    if (last == null) return Future.value(EventWriteResult.synced);
    if (!canLog) return Future.value(EventWriteResult.failed);
    return _writer.softDeleteEvent(
      clientId: _member.clientId,
      dateKey: dateKey,
      eventId: last.eventId,
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
  }) async {
    if (!canLog) return;
    try {
      final water = totalWaterMl(events);
      await _legacy.setMetric(
          dateKey: dateKey, field: 'waterMl', value: water.toDouble());

      final sleep = sleepMinutes(events);
      if (sleep != null) {
        await _legacy.setMetric(
            dateKey: dateKey, field: 'sleepHours', value: sleep / 60.0);
      }
      final steps = totalSteps(events);
      if (steps != null) {
        await _legacy.setMetric(
            dateKey: dateKey, field: 'steps', value: steps.toDouble());
      }
    } catch (_) {
      // Never surfaced: the event is the record, this is only the bridge.
    }
  }
}
