import 'dart:async';

import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../core/models/client_diet_log_model.dart';
import '../core/services/diet_log_service.dart';
import '../core/utils/diet_adherence.dart';
import '../core/utils/diet_log_restore.dart';
import 'member_controller.dart';
import 'training_controller.dart';

/// Reactive per-food diet-adherence state for TODAY, over the coach-prescribed
/// diet (from [TrainingController.dietItems]). The member marks each prescribed
/// food eaten/partial/skipped; every change is persisted to `client_diet_logs`
/// via [DietLogService] so the coach sees compliance. Consumed macros are
/// derived (eaten = full, partial = half) — no free-form food entry, matching
/// the STEP-7 adherence model.
class DietLogController extends GetxController {
  final TrainingController _training = Get.isRegistered<TrainingController>()
      ? Get.find<TrainingController>()
      : Get.put(TrainingController());
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());
  final DietLogService _service = DietLogService();

  /// prescribed-food index → status (eaten|partial|skipped).
  final RxMap<int, String> statuses = <int, String>{}.obs;
  final RxBool isSaving = false.obs;
  final RxBool hasError = false.obs;

  StreamSubscription<ClientDietLogModel?>? _sub;
  Worker? _linkWorker;
  Worker? _planWorker;
  ClientDietLogModel? _lastLog;
  bool _logArrived = false;
  bool _docExists = false;
  bool _restoredOnce = false;
  String _boundKey = '';

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
    _planWorker = ever(_training.diet, (_) => _tryRestore());
  }

  /// Day-rollover guard: if the app lived past midnight (or resumed the next
  /// morning) the stream, restored marks and `_docExists` all describe
  /// YESTERDAY while `dateKey` already says today — a write would then stamp
  /// yesterday's marks onto today's document. Reset and rebind for the new day.
  void ensureFreshDay() {
    if (_boundKey.isEmpty || _boundKey == dateKey) return;
    statuses.clear();
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
    final ok = await _service.saveDay(
      dateKey: dateKey,
      planName: planName,
      items: items,
      adherencePct: adherence,
      markCreated: !_docExists,
    );
    if (ok) {
      _docExists = true;
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
