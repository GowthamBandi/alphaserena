import 'dart:async';

import 'package:get/get.dart';

import '../core/models/lifestyle_log_model.dart';
import '../core/models/lifestyle_targets.dart';
import '../core/services/lifestyle_log_service.dart';
import '../core/utils/lifestyle_math.dart';
import 'member_controller.dart';

/// Drives the member's "Today" lifestyle surface: streams the selected day's log,
/// reads the coach's targets + supplement stack off the live client doc, and
/// writes metric/supplement updates. Selected day defaults to today.
class LifestyleController extends GetxController {
  final LifestyleLogService _service = LifestyleLogService();
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  final Rxn<LifestyleLogModel> log = Rxn<LifestyleLogModel>();
  final Rx<DateTime> selectedDay = DateTime.now().obs;
  final RxBool isLoading = true.obs;

  StreamSubscription? _sub;

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
  }

  void _subscribe() {
    _sub?.cancel();
    isLoading.value = true;
    _sub = _service.watchDay(dateKeyStr).listen((l) {
      log.value = l;
      isLoading.value = false;
    }, onError: (_) => isLoading.value = false);
  }

  void selectDay(DateTime day) {
    selectedDay.value = DateTime(day.year, day.month, day.day);
    _subscribe();
  }

  // ── Water: stored ml; UI works in glasses ──────────────────────────
  int get waterGlasses {
    final ml = log.value?.waterMl?.value ?? 0;
    return glassesFor(ml, targets.glassSizeMl);
  }

  int get waterTargetGlasses {
    final ml = effectiveTarget(targets.waterTargetMl, LifestyleDefaults.waterMl);
    return glassesFor(ml, targets.glassSizeMl);
  }

  Future<void> addGlass(int delta) async {
    final next = (waterGlasses + delta).clamp(0, 60);
    await _service.setMetric(
        dateKey: dateKeyStr,
        field: 'waterMl',
        value: mlForGlasses(next, targets.glassSizeMl));
  }

  Future<void> setSteps(double steps) =>
      _service.setMetric(dateKey: dateKeyStr, field: 'steps', value: steps);

  Future<void> setSleep(double hours, {int? quality}) => _service.setMetric(
      dateKey: dateKeyStr, field: 'sleepHours', value: hours, quality: quality);

  /// Current supplement checklist merged over the coach stack (so newly-added
  /// stack items appear unchecked, removed ones drop off).
  List<SupplementIntake> get supplementChecklist {
    final logged = {
      for (final s in (log.value?.supplements ?? <SupplementIntake>[]))
        s.id: s.taken
    };
    return stack
        .map((p) => SupplementIntake(
            id: p.id, name: p.name, dose: p.dose, taken: logged[p.id] ?? false))
        .toList();
  }

  Future<void> toggleSupplement(String id) async {
    final next = supplementChecklist
        .map((s) => s.id == id ? s.copyWith(taken: !s.taken) : s)
        .toList();
    await _service.setSupplements(dateKeyStr, next);
  }

  @override
  void onClose() {
    _sub?.cancel();
    super.onClose();
  }
}
