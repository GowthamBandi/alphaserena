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
      _mirrorIfStale();
    }, onError: (_) => isLoading.value = false);
    // The event stream is the source of truth for every total the UI shows.
    // The legacy stream above stays subscribed only until TrainerHQ reads
    // rollups, because the compatibility projection is written from it.
    _pendingWithdrawn.clear();
    _eventSub = _events.watchDay(dateKeyStr).listen((e) {
      events.assignAll(e);
      // Drop pending markers the server has now confirmed (or that no longer
      // exist), so the set cannot grow for the life of the session.
      _pendingWithdrawn.removeWhere((id) {
        final match = e.firstWhereOrNull((x) => x.eventId == id);
        return match == null || match.deleted;
      });
      isLoading.value = false;
      _mirrorIfStale();
    }, onError: (_) => isLoading.value = false);
  }

  /// Event ids this device has withdrawn but whose soft delete has not yet
  /// come back down the stream.
  ///
  /// A withdrawal is a Firestore write; until its snapshot arrives the event
  /// still reads as LIVE. Two quick "minus" taps therefore both found the same
  /// last drink and withdrew it twice — the member removed one glass for two
  /// taps, and the second write was a no-op they were never told about.
  final Set<String> _pendingWithdrawn = <String>{};

  /// The day's events with this device's un-acknowledged withdrawals applied.
  /// EVERY derivation reads this rather than [events], so what the member sees
  /// and what the next tap acts on agree.
  List<CoachingEvent> get _live =>
      withEventsWithdrawn(events, _pendingWithdrawn);

  /// Brings the legacy projection up to date when — and only when — it is
  /// actually behind the events.
  ///
  /// The mirror used to be awaited at the end of every action, computed from
  /// the events list as it stood BEFORE the stream had delivered the event
  /// just written. It therefore projected the previous state: the coach saw
  /// every member action exactly one action late, and the last action of a
  /// session never arrived at all. Driving it from the stream instead means it
  /// always projects what the member actually recorded, including after an
  /// offline replay, and the comparison against the document already on the
  /// wire keeps it from writing when there is nothing to say.
  ///
  /// It also coalesces a BURST of member actions into one projection write.
  ///
  /// Every event write produces a stream emission, so tapping ten glasses in a
  /// row would issue ten mirror writes for a document only the coach reads and
  /// only the final state of which matters. The projection settles a moment
  /// after the member stops tapping instead.
  ///
  /// Staleness is checked BEFORE scheduling, for two reasons. The mirror write
  /// itself changes the legacy document, which emits on the other stream — so
  /// scheduling unconditionally armed a pointless timer after every write.
  /// And a debounce that restarts on every emission can be starved: a second
  /// device logging steadily would keep pushing the deadline back forever.
  /// Only a genuinely stale projection now holds a timer, and [_mirrorDeadline]
  /// caps how long it can be deferred.
  void _mirrorIfStale() {
    if (!canLog) return;
    if (!_projectionIsStale()) {
      _mirrorDebounce?.cancel();
      _mirrorDebounce = null;
      _owedSince = null;
      return;
    }
    final owed = _owedSince ??= DateTime.now();
    if (DateTime.now().difference(owed) >= _mirrorDeadline) {
      _mirrorDebounce?.cancel();
      _flushMirror();
      return;
    }
    _mirrorDebounce?.cancel();
    _mirrorDebounce = Timer(_mirrorDelay, _flushMirror);
  }

  /// How long a burst may coalesce.
  static const Duration _mirrorDelay = Duration(milliseconds: 900);

  /// The longest the coach's projection may lag behind the member's events,
  /// however continuously those events arrive.
  static const Duration _mirrorDeadline = Duration(seconds: 5);

  Timer? _mirrorDebounce;
  DateTime? _owedSince;
  String? _mirroring;

  bool _projectionIsStale() {
    final live = _live;
    if (live.isEmpty) return false;
    return LifestyleEventService.legacySignature(live, stack) !=
        LifestyleEventService.legacySignatureOf(log.value, stack);
  }

  void _flushMirror() {
    _mirrorDebounce = null;
    _owedSince = null;
    final live = _live;
    if (!canLog || live.isEmpty) return;
    final desired = LifestyleEventService.legacySignature(live, stack);
    if (desired == LifestyleEventService.legacySignatureOf(log.value, stack)) {
      return;
    }
    if (desired == _mirroring) return; // a write for this state is in flight
    _mirroring = desired;
    unawaited(_events
        .mirrorLegacyTotals(dateKey: dateKeyStr, events: live, stack: stack)
        .whenComplete(() {
      if (_mirroring == desired) _mirroring = null;
    }));
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
  int get waterMl => totalWaterMl(_live);

  int get waterGlasses => glassesFor(waterMl.toDouble(), targets.glassSizeMl);

  int get waterTargetGlasses {
    final ml = effectiveTarget(targets.waterTargetMl, LifestyleDefaults.waterMl);
    return glassesFor(ml, targets.glassSizeMl);
  }

  // ── Steps + sleep: DERIVED, like water ─────────────────────────────────
  //
  // These were the one inconsistency left by the event migration. Water read
  // from the events; steps and sleep still read the LEGACY MIRROR document —
  // so a member's entry only appeared once the bridge write had round-tripped,
  // and if the bridge failed (offline, or the write the coach never needed) it
  // never appeared at all. One screen, one source of truth.

  /// Today's step count, or null when nothing was recorded (never 0, which
  /// would read as "walked nowhere").
  int? get steps => totalSteps(_live);

  double? get sleepHours {
    final minutes = sleepMinutes(_live);
    return minutes == null ? null : minutes / 60.0;
  }

  /// Completion against the effective goal (coach target, else the platform
  /// default), or null when nothing is logged. Clamped for ring rendering by
  /// the caller, not here — the raw ratio is what a "112%" label needs.
  double? get waterCompletion => _completion(
      waterMl.toDouble(),
      effectiveTarget(targets.waterTargetMl, LifestyleDefaults.waterMl),
      logged: events.isNotEmpty && waterMl > 0);

  double? get stepsCompletion => _completion(
      steps?.toDouble(),
      effectiveTarget(
          targets.stepsTarget?.toDouble(), LifestyleDefaults.steps.toDouble()),
      logged: steps != null);

  double? get sleepCompletion => _completion(sleepHours,
      effectiveTarget(targets.sleepHoursTarget, LifestyleDefaults.sleepHours),
      logged: sleepHours != null);

  double? _completion(double? value, double target, {required bool logged}) {
    if (!logged || value == null || target <= 0) return null;
    return value / target;
  }

  /// Supplement completion for the day (items taken / prescribed), null when
  /// the coach has prescribed nothing.
  double? get supplementCompletion {
    if (stack.isEmpty) return null;
    return supplementItemsTaken(_live).length / stack.length;
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

  /// Adds or withdraws a glass.
  ///
  /// Adding records a DRINK; withdrawing soft-deletes the most recent one. A
  /// correction is never a negative quantity, and the record keeps it.
  Future<void> addGlass(int delta) async {
    if (delta == 0) return;
    if (delta > 0) {
      // Two taps are two glasses — adding is deliberately unguarded.
      _reportWrite(await _events.logDrink(
          dateKey: dateKeyStr,
          ml: mlForGlasses(1, targets.glassSizeMl).round()));
      return;
    }
    // Withdrawing must act on a DIFFERENT event each time, so the target is
    // chosen from the pending-aware view and marked before the write.
    final target = lastDrink(_live);
    if (target == null) return;
    _pendingWithdrawn.add(target.eventId);
    events.refresh(); // the totals are derived — show the glass gone now
    final result =
        await _events.withdraw(dateKey: dateKeyStr, eventId: target.eventId);
    if (result == EventWriteResult.failed) _pendingWithdrawn.remove(target.eventId);
    _reportWrite(result);
  }

  /// Records a step reading. A manual entry is an ABSOLUTE daily figure, so
  /// the server takes the latest rather than summing — logging twice no longer
  /// requires the member to total in their head.
  ///
  /// Out-of-range readings are REFUSED rather than written: the derivation
  /// discards anything above [maxStepsSample] or below zero, so an unchecked
  /// entry was recorded as an event that every reader then ignored — the
  /// member saw their number vanish with no explanation.
  Future<bool> setSteps(double steps) async {
    if (validateStepsEntry(steps.toString()) != null) return false;
    _reportWrite(
        await _events.logSteps(dateKey: dateKeyStr, count: steps.round()));
    return true;
  }

  /// Records sleep.
  ///
  /// [start]/[end] are preferred: the duration is then DERIVED and overlapping
  /// periods merge. When the member only reports hours, the stated duration is
  /// recorded as such — instants they never gave are never synthesised.
  Future<bool> setSleep(double hours, {DateTime? start, DateTime? end}) async {
    if (validateSleepEntry(hours.toString()) != null) return false;
    _reportWrite(await _events.logSleep(
      dateKey: dateKeyStr,
      start: start,
      end: end,
      minutes: (hours * 60).round(),
    ));
    return true;
  }

  /// Current supplement checklist merged over the coach stack.
  ///
  /// "Taken" is now derived from DOSE EVENTS rather than a stored boolean, so
  /// the record shows when each dose happened — the legacy model could hold
  /// only one flag per item per day, discarding the coach's `timing` entirely.
  List<SupplementIntake> get supplementChecklist {
    final taken = supplementItemsTaken(_live);
    return stack
        .map((p) => SupplementIntake(
            id: p.id, name: p.name, dose: p.dose, taken: taken.contains(p.id)))
        .toList();
  }

  /// How many doses of [id] the member has recorded today.
  int dosesOf(String id) => liveEventsOfType(
          _live, LifestyleEventType.supplementTaken)
      .where((e) => (e.payload['itemId'] ?? '').toString() == id)
      .length;

  /// Ticking records a dose; un-ticking withdraws the most recent one.
  Future<void> toggleSupplement(String id) async {
    final item = stack.firstWhereOrNull((s) => s.id == id);
    final target = lastDoseOf(_live, id);
    if (target != null) {
      // Same withdrawal race as water: un-ticking twice quickly must not
      // withdraw one dose twice.
      _pendingWithdrawn.add(target.eventId);
      events.refresh();
      final result =
          await _events.withdraw(dateKey: dateKeyStr, eventId: target.eventId);
      if (result == EventWriteResult.failed) {
        _pendingWithdrawn.remove(target.eventId);
      }
      _reportWrite(result);
      return;
    }
    _reportWrite(await _events.logSupplementDose(
      dateKey: dateKeyStr,
      itemId: id,
      name: item?.name,
      dose: item?.dose,
    ));
  }

  /// Records an ADDITIONAL dose of [id] — the 3x/day case the single daily
  /// boolean could never express.
  Future<void> addSupplementDose(String id) async {
    final item = stack.firstWhereOrNull((s) => s.id == id);
    _reportWrite(await _events.logSupplementDose(
        dateKey: dateKeyStr, itemId: id, name: item?.name, dose: item?.dose));
  }

  @override
  void onClose() {
    // A debounced projection still owed to the coach must not be dropped
    // because the member navigated away inside the window.
    if (_mirrorDebounce != null) {
      _mirrorDebounce!.cancel();
      _flushMirror();
    }
    _sub?.cancel();
    _eventSub?.cancel();
    _linkWorker?.dispose();
    super.onClose();
  }
}
