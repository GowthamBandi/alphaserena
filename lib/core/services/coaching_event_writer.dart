import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/coaching_event.dart';

/// THE offline-safe writer for coaching events (WS-6).
///
/// WHY THIS EXISTS
/// ---------------
/// Three write paths had three different offline contracts:
///   • DietLogService  — 3-state result, 4s ack, orphan adoption. Correct.
///   • WorkoutLogService — 3-state result, 4s ack, NO orphan adoption, so a
///     late failure became an unhandled async error.
///   • LifestyleLogService — `await set()` with NO timeout at all. Offline the
///     Future NEVER resolves: the controller's documented "every write reports
///     failure" contract is false, and pending Futures accumulate for the
///     whole session while the member is told nothing.
///
/// This is one implementation of that contract, for every event domain.
///
/// THE FOUR GUARANTEES
/// -------------------
/// 1. NO INFINITE PENDING FUTURE. Firestore's `set`/`update` Future resolves
///    only on SERVER acknowledgement, so offline it never completes. Every
///    write is time-boxed; a timeout means QUEUED, not failed.
/// 2. NO SILENT LOSS. A queued write is still committed to Firestore's local
///    cache and replayed by the SDK on reconnect. The member is told it is
///    saved on-device, never that it failed.
/// 3. IDEMPOTENT REPLAY. The eventId is minted ONCE per member action and the
///    write targets `events.<eventId>`. Replaying the same queued write —
///    however many times the SDK retries — writes the same field with the same
///    value. Two taps are two events (two glasses); one tap retried is one.
/// 4. NO CLOBBERING. Writes are field-path scoped, so two devices editing
///    different events merge instead of overwriting each other's day. The
///    legacy path rewrites a whole array/total, which is how a concurrent
///    drink is lost.
enum EventWriteResult {
  /// The server acknowledged within [ackTimeout].
  synced,

  /// Committed locally and queued by the Firestore SDK; it replays on
  /// reconnect. NOT a failure.
  queued,

  /// Rejected (rules, validation) or an unrecoverable client error.
  failed,
}

/// Mints a collision-resistant, time-ordered event id.
///
/// Time-prefixed so ids sort chronologically in the stored map, with random
/// entropy so two devices — or two rapid taps — can never mint the same id.
/// Minted at ACTION time, which is what makes retries idempotent.
String newEventId([Random? rng]) {
  final r = rng ?? Random.secure();
  final ts = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final suffix = List.generate(8, (_) => _alphabet[r.nextInt(_alphabet.length)])
      .join();
  return '${ts}_$suffix';
}

const _alphabet = 'abcdefghijklmnopqrstuvwxyz0123456789';

class CoachingEventWriter {
  CoachingEventWriter({
    required this.collection,
    FirebaseFirestore? db,
    this.ackTimeout = const Duration(seconds: 4),
  }) : _db = db ?? FirebaseFirestore.instance;

  /// The day-document collection, e.g. `client_lifestyle_days`.
  final String collection;
  final FirebaseFirestore _db;

  /// How long to wait for a server acknowledgement before reporting `queued`.
  /// Matches the value the diet and workout paths already use, so the three
  /// domains behave identically to a member.
  final Duration ackTimeout;

  /// `{clientId}_{dateKey}` — deterministic, so an offline replay targets the
  /// same document and the security rules can pin the id to its contents.
  static String dayDocId(String clientId, String dateKey) =>
      '${clientId}_$dateKey';

  /// Live `events` map for one member-day.
  ///
  /// Serves from Firestore's local cache first, so the day renders — and the
  /// optimistic totals derive — while offline or before the server responds.
  Stream<Map<String, dynamic>> watchDay({
    required String clientId,
    required String dateKey,
  }) {
    return _db
        .collection(collection)
        .doc(dayDocId(clientId, dateKey))
        .snapshots()
        .map((s) {
      final raw = s.data()?['events'];
      return raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    });
  }

  /// Appends one event to a member-day.
  ///
  /// `SetOptions(merge: true)` with the event nested under its id both creates
  /// the day document (with its identity fields, which the rules require) and
  /// appends to an existing one — in a single write, with no read-before-write
  /// and therefore no lost update.
  Future<EventWriteResult> appendEvent({
    required String clientId,
    required String adminId,
    required String authorUid,
    required String dateKey,
    required CoachingEvent event,
  }) {
    return _write(
      clientId: clientId,
      dateKey: dateKey,
      data: {
        'schemaVersion': 1,
        'clientId': clientId,
        'adminId': adminId,
        'authorUid': authorUid,
        'dateKey': dateKey,
        'timezoneOffsetMin': DateTime.now().timeZoneOffset.inMinutes,
        'events': {event.eventId: event.toMap()},
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  /// Withdraws an event by SOFT delete.
  ///
  /// Events are append-only: a correction records that the member withdrew it,
  /// it never erases what was recorded. Targets one field path, so it cannot
  /// disturb any other event on the day.
  Future<EventWriteResult> softDeleteEvent({
    required String clientId,
    required String dateKey,
    required String eventId,
  }) {
    return _write(
      clientId: clientId,
      dateKey: dateKey,
      data: {
        'events': {
          eventId: {'deleted': true},
        },
        'updatedAt': FieldValue.serverTimestamp(),
      },
    );
  }

  Future<EventWriteResult> _write({
    required String clientId,
    required String dateKey,
    required Map<String, dynamic> data,
  }) async {
    final op = _db
        .collection(collection)
        .doc(dayDocId(clientId, dateKey))
        .set(data, SetOptions(merge: true));
    try {
      await op.timeout(ackTimeout);
      return EventWriteResult.synced;
    } on TimeoutException {
      // Offline (or a slow round trip). The write IS committed to the local
      // cache and the SDK will replay it. Adopt the orphaned Future so a late
      // failure cannot surface as an unhandled async error and take down the
      // isolate — the omission that still exists in WorkoutLogService.
      unawaited(op.catchError((Object _) {}));
      return EventWriteResult.queued;
    } catch (_) {
      return EventWriteResult.failed;
    }
  }
}
