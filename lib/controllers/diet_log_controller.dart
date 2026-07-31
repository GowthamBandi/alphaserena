import 'dart:async';

import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../core/models/client_diet_log_model.dart';
import '../core/services/nutrition_day_repository.dart';
import '../core/utils/diet_adherence.dart';
import '../core/utils/diet_log_restore.dart';
import 'member_controller.dart';
import 'streak_controller.dart';
import 'training_controller.dart';

/// Reactive per-food diet-adherence state for TODAY, over the coach-prescribed
/// diet (from [TrainingController.dietItems]). The member marks each prescribed
/// food eaten/partial/skipped; every change is persisted to `client_diet_logs`
/// via [NutritionDayRepository] so the coach sees compliance. Consumed macros
/// are derived (eaten = full, partial = half) — no free-form food entry,
/// matching the STEP-7 adherence model.
///
/// NIP Phase A: persistence goes through the [NutritionDayRepository] seam
/// (default: the legacy `client_diet_logs` adapter — behavior-identical) so
/// Phase B can swap the backing store without touching this controller.
class DietLogController extends GetxController {
  DietLogController({NutritionDayRepository? repository})
      : _service = repository ?? LegacyDietLogRepository();

  final TrainingController _training = Get.isRegistered<TrainingController>()
      ? Get.find<TrainingController>()
      : Get.put(TrainingController());
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());
  final NutritionDayRepository _service;

  /// prescribed-food index → status (eaten|partial|skipped).
  final RxMap<int, String> statuses = <int, String>{}.obs;
  final RxBool isSaving = false.obs;
  final RxBool hasError = false.obs;

  /// The last save reached the local cache but not the server yet.
  ///
  /// Held separately from [hasError] because it is not one: the member's marks
  /// are safe and will replay on reconnect. Conflating the two would tell an
  /// athlete logging lunch in a basement gym that their day was lost.
  final RxBool isOffline = false.obs;

  StreamSubscription<ClientDietLogModel?>? _sub;
  Worker? _linkWorker;
  Worker? _planWorker;
  ClientDietLogModel? _lastLog;
  bool _logArrived = false;
  bool _docExists = false;
  bool _restoredOnce = false;
  String _boundKey = '';

  /// The plan the current [statuses] INDICES describe.
  ///
  /// `statuses` is index-keyed, so it is only meaningful against a specific food
  /// list. Holding that list is what makes a mid-session plan change survivable:
  /// without it there is no way to know which food index 3 meant when it was
  /// marked, and therefore no way to move the mark with its food.
  List<PlanFood> _boundFoods = const [];

  String get dateKey => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// The coach-prescribed foods for today (stable order = the index space).
  List<Map<String, dynamic>> get foods => _training.dietItems;
  int get totalFoods => foods.length;
  int get loggedCount => statuses.length;
  bool get canLog => _service.canLog;
  String get planName => _training.diet.value?['name']?.toString() ?? '';

  double get adherence => dietAdherence(statuses, totalFoods);

  List<double> _perFood(String key) => foods.map((f) {
        final v = f[key];
        if (v is num) return v.toDouble();
        if (v is String) return double.tryParse(v) ?? 0.0;
        return 0.0;
      }).toList();

  double get consumedCalories => consumedMacro(_perFood('calories'), statuses);
  double get consumedProtein => consumedMacro(_perFood('protein'), statuses);
  double get consumedCarbs => consumedMacro(_perFood('carbs'), statuses);
  double get consumedFat => consumedMacro(_perFood('fat'), statuses);
  double get consumedFiber => consumedMacro(_perFood('fiber'), statuses);

  @override
  void onInit() {
    super.onInit();
    _bind();
    // Re-bind once the member links: on first init `canLog` may be false (claim()
    // unresolved) which would leave watchDay on a permanently-empty stream and a
    // failed restore of today's marks.
    _linkWorker = ever(_member.isLinked, (_) => _bind());
    // Identity restore needs the CURRENT plan (foodId + meal per food). The plan
    // arrives asynchronously from getMyTraining, often AFTER today's log snapshot
    // — retry the one-time restore whenever the plan changes so marks bind to
    // the right food regardless of load order.
    _planWorker = ever(_training.diet, (_) {
      // Order matters: remap FIRST so marks already made in this session follow
      // their food onto the new plan, then let the one-time restore run for the
      // case where nothing has been marked yet.
      _remapForNewPlan();
      _tryRestore();
    });
  }

  /// The current plan expressed as stable identities.
  List<PlanFood> get _planFoods => [
        for (final f in foods)
          (
            foodId: (f['foodId'] ?? '').toString(),
            meal: (f['meal'] ?? '').toString(),
          ),
      ];

  /// Moves marks the member already made onto a plan that changed underneath
  /// them — the case the one-time restore deliberately refuses to handle.
  ///
  /// [restoreAction] returns `noop` as soon as there are local marks, because
  /// re-running the full restore would clobber in-flight toggles with whatever
  /// the server last echoed. That is right for a re-bind, and wrong for a plan
  /// EDIT: the marks are still correct, but the indices they are keyed by now
  /// address different foods. So this remaps by identity instead of restoring,
  /// and persists only when the remap actually changed something (a food the
  /// coach deleted loses its mark, and the stored log must stop claiming it).
  void _remapForNewPlan() {
    if (statuses.isEmpty) {
      _boundFoods = _planFoods;
      return;
    }
    final next = _planFoods;
    if (next.isEmpty || !planFoodsDiffer(_boundFoods, next)) return;

    final remapped = remapStatusesOnPlanChange(
      Map<int, String>.from(statuses),
      _boundFoods,
      next,
    );
    _boundFoods = next;

    final changed =
        remapped.length != statuses.length ||
        remapped.entries.any((e) => statuses[e.key] != e.value);
    statuses.assignAll(remapped);
    statuses.refresh();
    if (changed) _persist();
  }

  /// Day-rollover guard: if the app lived past midnight (or resumed the next
  /// morning) the stream, restored marks and `_docExists` all describe
  /// YESTERDAY while `dateKey` already says today — a write would then stamp
  /// yesterday's marks onto today's document. Reset and rebind for the new day.
  void ensureFreshDay() {
    if (_boundKey.isEmpty || _boundKey == dateKey) return;
    statuses.clear();
    _boundFoods = const [];
    _docExists = false;
    _restoredOnce = false;
    _bind();
  }

  void _bind() {
    _sub?.cancel();
    _boundKey = dateKey;
    _logArrived = false; // new subscription — wait for its first snapshot
    // Only allow the one-time restore to run again if the member hasn't started
    // marking foods yet (avoid clobbering in-flight local toggles on re-bind).
    if (statuses.isEmpty) _restoredOnce = false;
    _sub = _service.watchDay(dateKey).listen((log) {
      _docExists = log != null;
      _lastLog = log;
      _logArrived = true;
      _tryRestore();
    });
  }

  /// Restores the day's marks from the persisted log ONCE, by STABLE IDENTITY
  /// (foodId + meal) against the current plan — so a coach reordering or editing
  /// the plan no longer reattaches a mark to a different food. Legacy marks
  /// (no foodId) fall back to their stored index.
  ///
  /// The decision is a pure state machine ([restoreAction]) so the load-order
  /// race between the plan and the log snapshot is provable: restore is deferred
  /// until BOTH the log snapshot and the plan have arrived, and is skipped once
  /// the member starts marking (local state is then authoritative — single
  /// device, later snapshots are just echoes of our own writes).
  void _tryRestore() {
    final action = restoreAction(
      alreadyRestored: _restoredOnce,
      hasLocalMarks: statuses.isNotEmpty,
      logArrived: _logArrived,
      logExists: _lastLog != null,
      planLoaded: foods.isNotEmpty,
    );
    switch (action) {
      case RestoreAction.noop:
      case RestoreAction.wait:
        return;
      case RestoreAction.restore:
        _restoredOnce = true;
        final current = foods;
        // The restored indices describe THIS plan; record it so a later edit
        // can remap them.
        _boundFoods = _planFoods;
        statuses.assignAll(restoreStatusesByIdentity(
          [
            for (final it in _lastLog!.items)
              (
                foodId: it.foodId,
                meal: it.meal,
                idx: it.idx,
                status: it.status,
              ),
          ],
          [
            for (final f in current)
              (
                foodId: (f['foodId'] ?? '').toString(),
                meal: (f['meal'] ?? '').toString(),
              ),
          ],
        ));
        return;
    }
  }

  String statusFor(int index) => statuses[index] ?? '';

  /// Sets (or toggles off, if the same status is tapped again) a food's status
  /// and persists the day. Returns nothing; surfaces failure via [hasError].
  Future<void> setStatus(int index, String status) async {
    // The FIRST mark of a session defines which plan these indices describe.
    if (statuses.isEmpty) _boundFoods = _planFoods;
    if (statuses[index] == status) {
      statuses.remove(index);
    } else {
      statuses[index] = status;
    }
    statuses.refresh();
    await _persist();
  }

  Future<void> _persist() async {
    if (!canLog) return;
    isSaving.value = true;
    hasError.value = false;
    final items = <Map<String, dynamic>>[];
    for (final e in statuses.entries) {
      final i = e.key;
      if (i < 0 || i >= foods.length) continue;
      // Freeze the served food as the log entry: V2A identity (foodId) + V2B
      // consumed-nutrition snapshot (7 macros), so history is recoverable and
      // immune to later food edits. Consumed = macro × status score (readers).
      // The mapping is pure + unit-tested (DietLogItem.fromServedFood).
      items.add(
        DietLogItem.fromServedFood(foods[i], idx: i, status: e.value).toMap(),
      );
    }
    final result = await _service.saveDay(
      dateKey: dateKey,
      planName: planName,
      items: items,
      adherencePct: adherence,
      markCreated: !_docExists,
    );
    isOffline.value = result == DietSaveResult.queued;
    if (result != DietSaveResult.failed) {
      // A queued write is already in the local cache and will replay, so the
      // document effectively exists — re-stamping `createdAt` on every later
      // mark would be wrong.
      _docExists = true;
      // Keep the Home streak's "today" contribution live (no refetch). Only a
      // day with at least one mark qualifies — matches the streak read rule.
      if (items.isNotEmpty && Get.isRegistered<StreakController>()) {
        Get.find<StreakController>().markDietToday();
      }
    } else {
      hasError.value = true;
    }
    isSaving.value = false;
  }

  @override
  void onClose() {
    _sub?.cancel();
    _linkWorker?.dispose();
    _planWorker?.dispose();
    super.onClose();
  }
}
