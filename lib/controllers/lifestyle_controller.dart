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
  /// Every collaborator is INJECTABLE.
  ///
  /// It was not: this controller built `LifestyleLogService()` and
  /// `LifestyleEventService()` in its field initialisers, both of which
  /// reached `FirebaseFirestore.instance` at construction. A controller that
  /// cannot be built without a live Firebase app cannot be unit-tested, and
  /// this one never was — not one test in the repository referenced
  /// `addGlass`, `setSteps`, `setSleep` or `toggleSupplement`. The entire
  /// surface a member touches every day was unproven, which is the reason the
  /// defects below survived.
  LifestyleController({
    LifestyleLogService? service,
    LifestyleEventService? events,
    MemberController? member,
  })  : _service = service ?? LifestyleLogService(),
        _events = events ?? LifestyleEventService(),
        _member = member ??
            (Get.isRegistered<MemberController>()
                ? Get.find<MemberController>()
                : Get.put(MemberController()));

  final LifestyleLogService _service;
  final LifestyleEventService _events;
  final MemberController _member;

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

  /// Whether the member is linked well enough for anything to be recorded.
  ///
  /// Touches the linkage observable BEFORE delegating, and that order is the
  /// whole point. Every lifestyle surface branches on this getter inside an
  /// `Obx`, while `_service.canLog` short-circuits on the first empty field —
  /// so leaving IT to register the dependency meant an unlinked member's
  /// closure observed nothing, GetX threw, and no rebuild ever arrived when
  /// their linkage landed.
  ///
  /// Reading `isLinked` here makes the reactive contract a property of the
  /// CONTROLLER rather than an accident of how the service happens to order
  /// its `&&`. Re-ordering that expression, or faking the service, can no
  /// longer take the subscription away.
  bool get canLog {
    _member.isLinked.value;
    return _service.canLog;
  }

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

  /// What the live listeners are currently bound to — `{clientId}|{dateKey}`,
  /// or null when nothing is bound.
  ///
  /// THE de-duplication key, and the reason a rebind is deterministic rather
  /// than incidental: binding is idempotent for the same member-day, and
  /// changes exactly when the member or the day changes.
  String? _boundKey;

  String get _bindKey => '${_member.clientId}|$dateKeyStr';

  @override
  void onInit() {
    super.onInit();
    // BIND ONLY WHEN EVERY PREREQUISITE EXISTS.
    //
    // `_subscribe()` used to run unconditionally here, synchronously, while
    // `canLog` was still false — so `watchDay` returned `Stream.value(const [])`
    // and NO Firestore listener was registered at all. The only rebind was
    // `ever(_member.isLinked)`, and `isLinked` flips on the clientProfiles
    // snapshot — strictly BEFORE `_listenClient` has even started the `clients`
    // listener that supplies `adminId`. So the rebind also saw `canLog == false`
    // and `isLinked` never changed again: the member's own day was never read
    // back, for the life of the process, while their writes all landed.
    //
    // The `clients` document is the LAST prerequisite to arrive (it carries
    // `adminId`, and `clientId` is set strictly before it), so it is the one
    // correct signal. No polling, no timer, no retry: one edge, one bind.
    _bindWhenReady();
    _linkWorker = ever(_member.client, (_) => _bindWhenReady());
  }

  /// Binds the day's listeners iff they can succeed and are not already bound.
  ///
  /// Never zero (it binds the moment the prerequisites land), never duplicated
  /// (the bind key short-circuits a repeat), never stale (the key carries the
  /// member AND the day, so switching either rebinds).
  void _bindWhenReady() {
    if (!canLog) return;
    if (_boundKey == _bindKey) return;
    _subscribe();
  }

  /// True while the selection is just the default "today" (the member hasn't
  /// deliberately browsed to another date).
  bool _followToday = true;

  /// Re-anchors the log to the current calendar day when the member was on
  /// "today" but the day rolled over (app left open past midnight / resumed the
  /// next morning) — otherwise writes would target yesterday's document.
  ///
  /// Called from the dashboard's `didChangeAppLifecycleState` (resume), from
  /// pull-to-refresh, AND — since LS-06 — immediately before every write.
  /// The lifecycle hook alone was not enough: it only fires when the app is
  /// BACKGROUNDED and brought back, so a member who simply keeps the app open
  /// across midnight (logging a last glass of water at 00:01, which is exactly
  /// when someone does that) went on writing into YESTERDAY's document. A
  /// re-anchor on the write path fixes the day a record lands on regardless of
  /// when the UI last refreshed, and it is a no-op on every ordinary tap
  /// because the day key has not changed.
  void ensureFreshDay() {
    if (!_followToday) return;
    final now = DateTime.now();
    if (dateKeyStr != dayKey(now)) {
      selectedDay.value = DateTime(now.year, now.month, now.day);
      // The bind key now carries a new day, so this rebinds — and only once.
      _bindWhenReady();
    }
  }

  void _subscribe() {
    _sub?.cancel();
    _eventSub?.cancel();
    // Stamped BEFORE the listeners are opened, so a re-entrant call during
    // binding cannot open a second pair.
    _boundKey = _bindKey;
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
    _bindWhenReady();
  }

  // ── Water: DERIVED from drink events; UI still works in glasses ────
  //
  // The stored total is gone. `totalWaterMl` sums the day's drinks, so a
  // coach changing their glass size can no longer requantise history and two
  // devices adding a glass no longer overwrite each other.
  int get waterMl => totalWaterMl(_live);

  int get waterGlasses => glassesFor(waterMl.toDouble(), targets.glassSizeMl);

  /// The coach's glass size — the ONLY source for the glasses↔ml conversion.
  /// Never hardcoded at a call site; `LifestyleTargets` already falls back to
  /// the platform default when the coach set none.
  double get glassSizeMl => targets.glassSizeMl;

  /// The coach's daily water goal in ml (their target, else the platform
  /// default). Shown beside the member's own total.
  double get waterTargetMl =>
      effectiveTarget(targets.waterTargetMl, LifestyleDefaults.waterMl);

  int get waterTargetGlasses => glassesToReach(waterTargetMl, glassSizeMl);

  /// True once the member has reached the goal — the ONE definition, so the
  /// ring, the counter, the + button and Home cannot disagree.
  bool get waterGoalReached =>
      waterTargetGlasses > 0 && waterGlasses >= waterTargetGlasses;

  /// WATER IS NEVER CAPPED. A goal is a goal, not a ceiling.
  ///
  /// `canAddGlass` used to refuse a tap once [waterGlasses] reached
  /// [waterTargetGlasses] — and since [waterTargetMl] falls back to the
  /// platform default, that target is NEVER <= 0, so the cap was always on. A
  /// member who drank more than their goal could not record it: their real
  /// intake was truncated in their own history and, permanently, in their
  /// coach's analytics. With no coach goal at all the cap enforced the
  /// SUGGESTED default — a number this app labels "suggested" on one screen
  /// and denies exists on another.
  ///
  /// Every other metric already accepts an over-target value and reports it as
  /// 115% / 140% rather than flattening it. Water is no longer the exception,
  /// and the `_pendingAdds` race guard retired with the cap it protected —
  /// there is no longer a threshold for two same-frame taps to straddle.
  ///
  /// The OTHER direction stays bounded, for a different reason: with no live
  /// drink left to withdraw, a "−" tap could only be a silent no-op.
  bool get canRemoveGlass => waterGlasses > 0 || lastDrink(_live) != null;

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

  /// Completion against the effective goal, or null when nothing is logged.
  ///
  /// 🔴 Counted MILLILITRES against the millilitre goal while every other
  /// water surface counted GLASSES against the glass goal, so Home and Today
  /// showed two different percentages for the same water and the ring
  /// disagreed with the counter drawn inside it. Glasses are what the member
  /// logs, so glasses are the unit — one ratio, everywhere.
  double? get waterCompletion => _completion(
      waterGlasses.toDouble(), waterTargetGlasses.toDouble(),
      logged: waterMl > 0);

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
  /// Reports the outcome into STATE, and nowhere else.
  ///
  /// This used to also fire `Get.snackbar`, which needs a live overlay: the
  /// controller therefore could not report a failed write outside a widget
  /// tree, and any test of the write path crashed on a null check inside GetX
  /// rather than on an assertion. A state class does not own the presentation
  /// of its errors — [hasError] and [isOffline] are rendered as a persistent
  /// banner by the only screen that writes, which outlives a snackbar anyway.
  void _reportWrite(EventWriteResult result) {
    hasError.value = result == EventWriteResult.failed;
    isOffline.value = result == EventWriteResult.queued;
  }

  /// Adds or withdraws EXACTLY one glass.
  ///
  /// Adding records a DRINK; withdrawing soft-deletes the most recent one. A
  /// correction is never a negative quantity, and the record keeps it.
  ///
  /// Adding is UNBOUNDED — a member's real intake is always recordable, even
  /// past their goal. Withdrawing stops at zero, because with no live drink
  /// left there is nothing a tap could withdraw.
  Future<void> addGlass(int delta) async {
    if (delta == 0) return;
    ensureFreshDay();
    if (delta > 0) {
      _reportWrite(await _events.logDrink(
          dateKey: dateKeyStr, ml: mlForGlasses(1, glassSizeMl).round()));
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
    ensureFreshDay();
    _reportWrite(
        await _events.logSteps(dateKey: dateKeyStr, count: steps.round()));
    return true;
  }

  /// Records sleep.
  ///
  /// [start]/[end] are preferred: the duration is then DERIVED and overlapping
  /// periods merge. When the member only reports hours, the stated duration is
  /// recorded as such — instants they never gave are never synthesised.
  ///
  /// [replacing] makes the write a CORRECTION rather than an addition.
  ///
  /// 🔴 Without it, editing sleep was impossible. `sleepMinutes` MERGES
  /// overlapping periods (so a nap and a night both count), so a member who
  /// saved 22:45→06:30 and then corrected it to 23:30→06:30 got the UNION of
  /// the two — 7h 45m, the original figure, unchanged by their correction and
  /// with no way to ever reduce it. The old bare-hours path had the mirror of
  /// the same problem in reverse (latest-stated wins), so the two entry modes
  /// disagreed about what a second save even means. An edit now withdraws the
  /// day's existing sleep events first: append-only, fully auditable, and the
  /// member's last word is what stands.
  Future<bool> setSleep(
    double hours, {
    DateTime? start,
    DateTime? end,
    bool replacing = false,
  }) async {
    if (validateSleepEntry(hours.toString()) != null) return false;
    ensureFreshDay();
    if (replacing) await _withdrawAll(LifestyleEventType.sleep);
    _reportWrite(await _events.logSleep(
      dateKey: dateKeyStr,
      start: start,
      end: end,
      minutes: (hours * 60).round(),
    ));
    return true;
  }

  /// Whether the day already holds a sleep record — the difference between a
  /// "Save" and an "Edit" affordance.
  bool get hasSleepRecord =>
      liveEventsOfType(_live, LifestyleEventType.sleep).isNotEmpty;

  bool get hasStepsRecord =>
      liveEventsOfType(_live, LifestyleEventType.stepsSample).isNotEmpty;

  /// The sleep PERIOD the member last recorded, when they gave one — what an
  /// Edit reloads into the pickers. Null when sleep was only ever stated as a
  /// duration (no instants were given, and none are invented here either).
  ({DateTime start, DateTime end})? get sleepPeriod {
    final events = liveEventsOfType(_live, LifestyleEventType.sleep);
    for (final e in events.reversed) {
      final start = e.payload['start'];
      final end = e.payload['end'];
      if (start is num && end is num && end > start) {
        return (
          start: DateTime.fromMillisecondsSinceEpoch(start.toInt()),
          end: DateTime.fromMillisecondsSinceEpoch(end.toInt()),
        );
      }
    }
    return null;
  }

  /// Withdraws every live event of one type on the selected day.
  ///
  /// The same pending-aware protocol a single withdrawal uses, so a correction
  /// issued during a burst cannot act on an event another tap already
  /// withdrew.
  Future<void> _withdrawAll(String type) async {
    final targets = liveEventsOfType(_live, type);
    if (targets.isEmpty) return;
    for (final e in targets) {
      _pendingWithdrawn.add(e.eventId);
    }
    events.refresh();
    for (final e in targets) {
      final result =
          await _events.withdraw(dateKey: dateKeyStr, eventId: e.eventId);
      if (result == EventWriteResult.failed) {
        _pendingWithdrawn.remove(e.eventId);
        _reportWrite(result);
      }
    }
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

  /// Items whose toggle is written but not yet reflected in the stream.
  ///
  /// 🔴 A TOGGLE THAT COULD NOT UN-TOGGLE. [toggleSupplement] picks its branch
  /// from `lastDoseOf`, which stays empty until the first write's snapshot
  /// returns — so two quick taps on the same checkbox BOTH took the "not taken
  /// yet" branch and recorded two doses of an item the member was trying to
  /// un-tick. Duplicate write, wrong end state, and a `×2` badge they never
  /// asked for. The water + and − paths already guarded this race; this is the
  /// same rule for the third one.
  ///
  /// Scoped to [toggleSupplement] ONLY: [addSupplementDose] is the deliberate
  /// "another dose" action, and a 3x/day protocol must still record three.
  final Set<String> _togglesInFlight = <String>{};

  /// Ticking records a dose; un-ticking withdraws the most recent one.
  Future<void> toggleSupplement(String id) async {
    ensureFreshDay();
    if (!_togglesInFlight.add(id)) return;
    try {
      await _toggleSupplement(id);
    } finally {
      _togglesInFlight.remove(id);
    }
  }

  Future<void> _toggleSupplement(String id) async {
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
    ensureFreshDay();
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
