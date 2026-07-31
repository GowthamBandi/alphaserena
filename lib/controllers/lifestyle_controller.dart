import 'dart:async';

import 'package:get/get.dart';

import '../core/domain/coaching_event.dart';
import '../core/models/lifestyle_log_model.dart';
import '../core/models/lifestyle_targets.dart';
import '../core/services/coaching_event_writer.dart';
import '../core/services/lifestyle_event_service.dart';
import '../core/services/lifestyle_log_service.dart';
import '../core/utils/lifestyle_math.dart';
import 'member_controller.dart';

/// Drives the member's "Today" lifestyle surface: streams the selected day's log,
/// reads the coach's targets + supplement stack off the live client doc, and
/// writes metric/supplement updates. Selected day defaults to today.
class LifestyleController extends GetxController {
  final LifestyleLogService _service = LifestyleLogService();
  final LifestyleEventService _events = LifestyleEventService();
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  final Rxn<LifestyleLogModel> log = Rxn<LifestyleLogModel>();
  final Rx<DateTime> selectedDay = DateTime.now().obs;
  final RxBool isLoading = true.obs;

  /// WS-6: the member's EVENTS for the selected day. Totals are derived from
  /// these, never typed — so two devices adding a glass both count, and a
  /// correction withdraws the event rather than subtracting from a total.
  final RxList<CoachingEvent> events = <CoachingEvent>[].obs;

  /// A write failed (offline / permissions). Surfaced so a member's water,
  /// sleep or steps never vanish silently.
  final RxBool hasError = false.obs;

  /// A write is committed on THIS DEVICE and queued for replay. Distinct from
  /// [hasError]: queued is not a failure, and telling a member their log was
  /// lost when it was not is the defect this replaces.
  final RxBool isOffline = false.obs;

  StreamSubscription? _sub;
  StreamSubscription? _eventSub;
  Worker? _linkWorker;

  String get dateKeyStr => dayKey(selectedDay.value);
  bool get canLog => _service.canLog;

  LifestyleTargets get targets => LifestyleTargets.fromMap(
      _member.client.value?['lifestyleTargets'] is Map
          ? Map<String, dynamic>.from(_member.client.value!['lifestyleTargets'])
          : null);

  List<SupplementPlanItem> get stack {
    final raw = _member.client.value?['supplementPlan'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => SupplementPlanItem.fromMap(Map<String, dynamic>.from(e)))
        .where((s) => s.id.isNotEmpty && s.name.isNotEmpty)
        .toList();
  }

  @override
  void onInit() {
    super.onInit();
    _subscribe();
    // The dashboard creates this controller before the auth claim resolves:
    // canLog is false then, so watchDay latched onto a permanently-null stream
    // and every write silently no-op'd. Re-subscribe the moment linkage lands
    // (same rebind pattern as Diet/Progress/CheckIn).
    _linkWorker = ever(_member.isLinked, (_) => _subscribe());
  }

  /// True while the selection is just the default "today" (the member hasn't
  /// deliberately browsed to another date).
  bool _followToday = true;

  /// Re-anchors the log to the current calendar day when the member was on
  /// "today" but the day rolled over (app left open past midnight / resumed the
  /// next morning) — otherwise writes would target yesterday's document.
  void ensureFreshDay() {
    if (!_followToday) return;
    final now = DateTime.now();
    if (dateKeyStr != dayKey(now)) {
      selectedDay.value = DateTime(now.year, now.month, now.day);
      _subscribe();
    }
  }

  void _subscribe() {
    _sub?.cancel();
    _eventSub?.cancel();
    isLoading.value = true;
    _sub = _service.watchDay(dateKeyStr).listen((l) {
      log.value = l;
      isLoading.value = false;
    }, onError: (_) => isLoading.value = false);
    // The event stream is the source of truth for every total the UI shows.
    // The legacy stream above stays subscribed only until TrainerHQ reads
    // rollups, because the compatibility projection is written from it.
    _eventSub = _events.watchDay(dateKeyStr).listen((e) {
      events.assignAll(e);
      isLoading.value = false;
    }, onError: (_) => isLoading.value = false);
  }

  void selectDay(DateTime day) {
    selectedDay.value = DateTime(day.year, day.month, day.day);
    _followToday = dateKeyStr == dayKey(DateTime.now());
    _subscribe();
  }

  // ── Water: DERIVED from drink events; UI still works in glasses ────
  //
  // The stored total is gone. `totalWaterMl` sums the day's drinks, so a
  // coach changing their glass size can no longer requantise history and two
  // devices adding a glass no longer overwrite each other.
  int get waterMl => totalWaterMl(events);

  int get waterGlasses => glassesFor(waterMl.toDouble(), targets.glassSizeMl);

  int get waterTargetGlasses {
    final ml = effectiveTarget(targets.waterTargetMl, LifestyleDefaults.waterMl);
    return glassesFor(ml, targets.glassSizeMl);
  }

  /// Reports the outcome of an event write.
  ///
  /// THREE states, not two. The old contract had only ok/not-ok and, because
  /// the write was never time-boxed, offline it resolved NEITHER — the member
  /// was told nothing while pending Futures accumulated. `queued` is a
  /// success: the event is committed on the device and replays on reconnect.
  void _reportWrite(EventWriteResult result) {
    hasError.value = result == EventWriteResult.failed;
    isOffline.value = result == EventWriteResult.queued;
    if (result == EventWriteResult.failed) {
      Get.snackbar('Not saved',
          "That didn't save — check your connection and try again.");
    }
  }

  /// Mirrors the day's derived totals into the legacy document so TrainerHQ's
  /// existing lifestyle review keeps working. Best-effort and never surfaced —
  /// the event is the record; this is only the migration bridge.
  Future<void> _mirror() =>
      _events.mirrorLegacyTotals(dateKey: dateKeyStr, events: events);

  /// Adds or withdraws a glass.
  ///
  /// Adding records a DRINK; withdrawing soft-deletes the most recent one. A
  /// correction is never a negative quantity, and the record keeps it.
  Future<void> addGlass(int delta) async {
    if (delta == 0) return;
    final result = delta > 0
        ? await _events.logDrink(
            dateKey: dateKeyStr,
            ml: mlForGlasses(1, targets.glassSizeMl).round())
        : await _events.undoLastDrink(dateKey: dateKeyStr, events: events);
    _reportWrite(result);
    await _mirror();
  }

  /// Records a step reading. A manual entry is an ABSOLUTE daily figure, so
  /// the server takes the latest rather than summing — logging twice no longer
  /// requires the member to total in their head.
  Future<void> setSteps(double steps) async {
    _reportWrite(await _events.logSteps(
        dateKey: dateKeyStr, count: steps.round()));
    await _mirror();
  }

  /// Records sleep.
  ///
  /// [start]/[end] are preferred: the duration is then DERIVED and overlapping
  /// periods merge. When the member only reports hours, the stated duration is
  /// recorded as such — instants they never gave are never synthesised.
  Future<void> setSleep(double hours, {DateTime? start, DateTime? end}) async {
    _reportWrite(await _events.logSleep(
      dateKey: dateKeyStr,
      start: start,
      end: end,
      minutes: (hours * 60).round(),
    ));
    await _mirror();
  }

  /// Current supplement checklist merged over the coach stack.
  ///
  /// "Taken" is now derived from DOSE EVENTS rather than a stored boolean, so
  /// the record shows when each dose happened — the legacy model could hold
  /// only one flag per item per day, discarding the coach's `timing` entirely.
  List<SupplementIntake> get supplementChecklist {
    final taken = supplementItemsTaken(events);
    return stack
        .map((p) => SupplementIntake(
            id: p.id, name: p.name, dose: p.dose, taken: taken.contains(p.id)))
        .toList();
  }

  /// How many doses of [id] the member has recorded today.
  int dosesOf(String id) => liveEventsOfType(
          events, LifestyleEventType.supplementTaken)
      .where((e) => (e.payload['itemId'] ?? '').toString() == id)
      .length;

  /// Ticking records a dose; un-ticking withdraws the most recent one.
  Future<void> toggleSupplement(String id) async {
    final item = stack.firstWhereOrNull((s) => s.id == id);
    final already = supplementItemsTaken(events).contains(id);
    final result = already
        ? await _events.undoSupplementDose(
            dateKey: dateKeyStr, events: events, itemId: id)
        : await _events.logSupplementDose(
            dateKey: dateKeyStr,
            itemId: id,
            name: item?.name,
            dose: item?.dose);
    _reportWrite(result);
    await _mirror();
  }

  /// Records an ADDITIONAL dose of [id] — the 3x/day case the single daily
  /// boolean could never express.
  Future<void> addSupplementDose(String id) async {
    final item = stack.firstWhereOrNull((s) => s.id == id);
    _reportWrite(await _events.logSupplementDose(
        dateKey: dateKeyStr, itemId: id, name: item?.name, dose: item?.dose));
    await _mirror();
  }

  @override
  void onClose() {
    _sub?.cancel();
    _eventSub?.cancel();
    _linkWorker?.dispose();
    super.onClose();
  }
}
