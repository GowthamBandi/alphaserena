/// UNIFIED COACHING EVENT — the client mirror of the WS-5 wire contract.
///
/// The member records EVENTS; the SERVER derives every metric. This file owns
/// the event shape and the *optimistic* derivations the UI needs while a write
/// is still in flight or the device is offline.
///
/// WHY THE DERIVATIONS ARE MIRRORED HERE
/// ------------------------------------
/// Offline, the app must still show a total the moment a member taps. The
/// server remains authoritative — its `computed` map overwrites what the UI
/// derived as soon as it lands — so this is a *display* mirror, not a second
/// source of truth. It follows the house pattern already used for diet totals
/// (`diet_trainerhq_parity_test.dart`): one pure implementation on each side,
/// pinned by tests against the same fixtures.
///
/// Every function here is pure. Nothing in this file touches Firebase.
library;

/// Where an event came from. Mirrors `EVENT_SOURCES` in
/// `trainershq-backend/functions/src/lib/coaching_events.ts`.
class EventSource {
  static const manual = 'manual';
  static const plan = 'plan';
  static const device = 'device';
  static const healthKit = 'healthkit';
  static const googleFit = 'googlefit';
  static const wearable = 'wearable';
  static const barcode = 'barcode';
  static const aiPhoto = 'ai_photo';
  static const aiText = 'ai_text';

  /// Readings a machine took, as opposed to a number a person stated.
  static const automated = {device, healthKit, googleFit, wearable};

  static bool isAutomated(String source) => automated.contains(source);
}

/// Lifestyle event types. Mirrors `LIFESTYLE_EVENT_TYPES` on the server.
class LifestyleEventType {
  static const drink = 'drink';
  static const sleep = 'sleep';
  static const supplementTaken = 'supplement_taken';
  static const stepsSample = 'steps_sample';
}

/// One recorded event.
class CoachingEvent {
  const CoachingEvent({
    required this.eventId,
    required this.type,
    required this.at,
    this.source = EventSource.manual,
    this.sourceKey,
    this.deleted = false,
    this.payload = const {},
  });

  final String eventId;
  final String type;
  final DateTime at;
  final String source;

  /// The external identity of this reading, when it has one. Two events
  /// sharing `(source, sourceKey)` are the SAME reading re-delivered — the
  /// dedup anchor for offline replay and for wearables that re-report windows.
  final String? sourceKey;

  /// Soft delete. Events are append-only; a correction never erases.
  final bool deleted;

  final Map<String, dynamic> payload;

  Map<String, dynamic> toMap() => {
        'type': type,
        'at': at.millisecondsSinceEpoch,
        'source': source,
        if (sourceKey != null && sourceKey!.isNotEmpty) 'sourceKey': sourceKey,
        if (deleted) 'deleted': true,
        ...payload,
      };

  static CoachingEvent? fromMap(String eventId, dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    final atMs = _millis(m['at']);
    return CoachingEvent(
      eventId: eventId,
      type: (m['type'] ?? '').toString(),
      at: DateTime.fromMillisecondsSinceEpoch(atMs),
      source: (m['source'] ?? EventSource.manual).toString(),
      sourceKey: m['sourceKey']?.toString(),
      deleted: m['deleted'] == true,
      payload: m,
    );
  }

  CoachingEvent copyWith({bool? deleted}) => CoachingEvent(
        eventId: eventId,
        type: type,
        at: at,
        source: source,
        sourceKey: sourceKey,
        deleted: deleted ?? this.deleted,
        payload: payload,
      );
}

int _millis(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is DateTime) return v.millisecondsSinceEpoch;
  // Firestore Timestamp exposes millisecondsSinceEpoch via toDate(); the
  // service layer converts before parsing, so a string is the only remainder.
  final parsed = DateTime.tryParse('${v ?? ''}');
  return parsed?.millisecondsSinceEpoch ?? 0;
}

double _num(dynamic v) {
  if (v is num) return v.toDouble();
  return double.tryParse('${v ?? ''}') ?? 0;
}

/// Parses the stored `events` map. Malformed entries are RETAINED where they
/// can be, never silently dropped — mirrors the server.
List<CoachingEvent> parseCoachingEvents(dynamic raw) {
  if (raw is! Map) return const [];
  final out = <CoachingEvent>[];
  raw.forEach((k, v) {
    final e = CoachingEvent.fromMap('$k', v);
    if (e != null) out.add(e);
  });
  out.sort((a, b) {
    final c = a.at.compareTo(b.at);
    return c != 0 ? c : a.eventId.compareTo(b.eventId);
  });
  return out;
}

/// Live events of one type, deduped by `(source, sourceKey)`.
List<CoachingEvent> liveEventsOfType(List<CoachingEvent> events, String type) {
  final seen = <String>{};
  final out = <CoachingEvent>[];
  for (final e in events) {
    if (e.deleted || e.type != type) continue;
    final key = e.sourceKey;
    if (key != null && key.isNotEmpty) {
      final composite = '${e.source}:$key';
      if (seen.contains(composite)) continue;
      seen.add(composite);
    }
    out.add(e);
  }
  return out;
}

const int maxDrinkMl = 5000;
const int maxSleepMinutes = 24 * 60;
const int maxStepsSample = 200000;

/// Total water for the day, summed from individual drinks.
int totalWaterMl(List<CoachingEvent> events) {
  var ml = 0.0;
  for (final e in liveEventsOfType(events, LifestyleEventType.drink)) {
    final v = _num(e.payload['ml']);
    if (v > 0 && v <= maxDrinkMl) ml += v;
  }
  return ml.round();
}

/// Sleep duration in minutes. Overlapping periods merge; a stated duration is
/// used only when no period was recorded. Null when nothing was recorded —
/// never 0, which would read as "slept no time at all".
int? sleepMinutes(List<CoachingEvent> events) {
  final spans = <List<int>>[];
  int? stated;
  var statedAt = -1;
  for (final e in liveEventsOfType(events, LifestyleEventType.sleep)) {
    final start = _millis(e.payload['start']);
    final end = _millis(e.payload['end']);
    if (start > 0 && end > start) {
      final minutes = (end - start) / 60000;
      if (minutes > maxSleepMinutes) continue;
      spans.add([start, end]);
      continue;
    }
    final m = _num(e.payload['minutes']);
    final atMs = e.at.millisecondsSinceEpoch;
    if (m > 0 && m <= maxSleepMinutes && atMs >= statedAt) {
      statedAt = atMs;
      stated = m.round();
    }
  }
  if (spans.isEmpty) return stated;
  spans.sort((a, b) => a[0].compareTo(b[0]));
  var total = 0;
  var curStart = spans.first[0];
  var curEnd = spans.first[1];
  for (final s in spans.skip(1)) {
    if (s[0] <= curEnd) {
      if (s[1] > curEnd) curEnd = s[1];
    } else {
      total += curEnd - curStart;
      curStart = s[0];
      curEnd = s[1];
    }
  }
  total += curEnd - curStart;
  return (total / 60000).round();
}

/// Steps: device samples sum after dedup; a manual entry is absolute and the
/// latest wins; automated readings take precedence over human estimates.
int? totalSteps(List<CoachingEvent> events) {
  final samples = liveEventsOfType(events, LifestyleEventType.stepsSample);
  if (samples.isEmpty) return null;
  var deviceTotal = 0.0;
  var hasDevice = false;
  int? latestManual;
  var latestManualAt = -1;
  for (final e in samples) {
    final count = _num(e.payload['count']);
    if (count < 0 || count > maxStepsSample) continue;
    if (EventSource.isAutomated(e.source)) {
      hasDevice = true;
      deviceTotal += count;
    } else {
      final atMs = e.at.millisecondsSinceEpoch;
      if (atMs >= latestManualAt) {
        latestManualAt = atMs;
        latestManual = count.round();
      }
    }
  }
  return hasDevice ? deviceTotal.round() : latestManual;
}

/// Distinct plan items the member took at least one dose of today.
Set<String> supplementItemsTaken(List<CoachingEvent> events) {
  final out = <String>{};
  for (final e in liveEventsOfType(events, LifestyleEventType.supplementTaken)) {
    final id = (e.payload['itemId'] ?? '').toString();
    if (id.isNotEmpty) out.add(id);
  }
  return out;
}

/// Total doses recorded today (a 3x/day protocol counts three).
int supplementDoses(List<CoachingEvent> events) =>
    liveEventsOfType(events, LifestyleEventType.supplementTaken).length;

/// The most recent live drink — what a "minus one glass" tap withdraws.
CoachingEvent? lastDrink(List<CoachingEvent> events) {
  final drinks = liveEventsOfType(events, LifestyleEventType.drink);
  return drinks.isEmpty ? null : drinks.last;
}

/// The most recent live dose of one supplement — what un-ticking withdraws.
CoachingEvent? lastDoseOf(List<CoachingEvent> events, String itemId) {
  final doses = liveEventsOfType(events, LifestyleEventType.supplementTaken)
      .where((e) => (e.payload['itemId'] ?? '').toString() == itemId)
      .toList();
  return doses.isEmpty ? null : doses.last;
}
