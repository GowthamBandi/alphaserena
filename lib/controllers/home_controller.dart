import 'package:get/get.dart';

import 'member_controller.dart';
import 'membership_controller.dart';
import 'training_controller.dart';

/// The post-purchase coaching lifecycle, derived entirely from already-streamed
/// data (no new backend). Home reflects the real stage instead of jumping
/// straight to (empty) plan content.
enum ClientStage { onboarding, awaitingTrainer, preparingPlan, ready }

class HomeController extends GetxController {
  final MemberController memberController = Get.find<MemberController>();
  final TrainingController trainingController = Get.find<TrainingController>();
  final MembershipController membershipController = Get.find<MembershipController>();

  @override
  void onInit() {
    super.onInit();
    // `getMyTraining` is server-resolved (no realtime). When the member's
    // linked `clients` doc changes — e.g. the coach assigns a trainer or the
    // membership updates — re-pull training so a freshly-assigned plan surfaces
    // on Home without a manual refresh. Skipped while we already hold a plan to
    // avoid redundant calls; reloading sets `workout` only, so this never loops.
    _clientWorker = ever<Map<String, dynamic>?>(
        memberController.client, (_) => _maybeReloadTraining());
  }

  Worker? _clientWorker;
  bool _reloadQueued = false;

  /// Reload training when the client doc changes and no plan is held yet. A
  /// change arriving mid-load is QUEUED and re-run when the in-flight load
  /// finishes — a hard skip could swallow the very event that signaled the
  /// newly-assigned plan (getMyTraining is one-shot, not realtime).
  void _maybeReloadTraining() {
    if (hasPlan) return;
    if (trainingController.isLoading.value) {
      _reloadQueued = true;
      return;
    }
    _reloadQueued = false;
    trainingController.load().then((_) {
      if (_reloadQueued && !hasPlan) {
        _reloadQueued = false;
        trainingController.load();
      }
    });
  }

  @override
  void onClose() {
    _clientWorker?.dispose();
    super.onClose();
  }

  /// Plain getter (NOT an Rx) so an enclosing `Obx` tracks the THREE source
  /// observables it reads — wrapping them in a throwaway `.obs` (the old bug)
  /// meant the skeleton loader never reacted to the real loading state.
  bool get isLoading =>
      memberController.isLoading.value ||
      trainingController.isLoading.value ||
      membershipController.isLoading.value;

  // Real member data getters
  String get greetingName {
    final fullName = memberController.name;
    if (fullName.isEmpty) return 'Alpha';
    return fullName.split(' ').first;
  }

  String get coachName => memberController.trainerName.isNotEmpty
      ? memberController.trainerName
      : 'Your Coach';

  String get gymName => memberController.gymName.isNotEmpty
      ? memberController.gymName
      : 'Alpha Arena';

  bool get isLinked => memberController.isLinked.value;
  String get notice => memberController.notice.value;

  // ── Coaching lifecycle ──────────────────────────────────────────────
  /// The member completed onboarding for their CURRENT coach. Uses the
  /// member-owned flag `clientProfiles.coachOnboardingDoneFor` (= the adminId
  /// they onboarded for) so switching coaches re-triggers onboarding.
  bool get onboardingDone {
    final adminId = memberController.adminId;
    if (adminId.isEmpty) return false;
    final doneFor =
        (memberController.profile.value?['coachOnboardingDoneFor'] ?? '')
            .toString();
    return doneFor == adminId;
  }

  bool get hasTrainer =>
      (memberController.client.value?['trainerId'] ?? '').toString().isNotEmpty;

  bool get hasPlan =>
      trainingController.workout.value != null ||
      trainingController.diet.value != null;

  /// Derived stage for an active, linked member. (Caller gates on linked+active.)
  ///
  /// A delivered plan ALWAYS wins → `ready`: once the coach has assigned a
  /// workout/diet we never hide it behind the onboarding/trainer gates (the
  /// member may have skipped onboarding, and a solo coach may never set a
  /// separate `trainerId`). The earlier stages only apply BEFORE a plan exists.
  ClientStage get stage {
    if (hasPlan) return ClientStage.ready;
    if (!onboardingDone) return ClientStage.onboarding;
    if (!hasTrainer) return ClientStage.awaitingTrainer;
    return ClientStage.preparingPlan;
  }

  // Today's assigned diet calculations
  double get targetCalories => _sumDietField('calories');
  double get targetProtein => _sumDietField('protein');
  double get targetCarbs => _sumDietField('carbs');
  double get targetFat => _sumDietField('fat');
  double get targetFiber => _sumDietField('fiber');

  double _sumDietField(String key) {
    double total = 0;
    for (final item in trainingController.dietItems) {
      final value = item[key];
      if (value is num) {
        total += value.toDouble();
      } else if (value is String) {
        total += double.tryParse(value) ?? 0;
      }
    }
    return total;
  }

  // Today's workout details
  String get workoutName =>
      trainingController.workout.value?['name']?.toString() ?? 'Rest Day';

  List<Map<String, dynamic>> get workoutPreviewItems {
    final items = trainingController.workoutItems;
    if (items.length <= 3) return items;
    return items.sublist(0, 3);
  }

  int get exerciseCount => trainingController.workoutItems.length;

  // Membership expiry warning
  bool get showExpiryBanner => membershipController.isExpiringSoon;
  
  String get membershipExpiryText {
    final expiry = membershipController.expiry;
    if (expiry == null) return '';
    final remainingDays = expiry.difference(DateTime.now()).inDays;
    if (remainingDays <= 0) return 'Membership expires today!';
    return 'Membership expires in $remainingDays days (${expiry.day}/${expiry.month}/${expiry.year})';
  }

  // Weight & Progress Stats getters
  double get latestWeight {
    final log = memberController.profile.value?['weightLog'];
    if (log is List && log.isNotEmpty) {
      final last = log.last;
      if (last is Map) {
        final w = last['weight'];
        if (w is num) return w.toDouble();
      }
    }
    // Fallback to profile initial weight or 70.0
    final initialW = memberController.profile.value?['weight'];
    if (initialW is num) return initialW.toDouble();
    return 70.0;
  }

  String get weightDeltaText {
    final log = memberController.profile.value?['weightLog'];
    if (log is List && log.length >= 2) {
      final last = log[log.length - 1];
      final prev = log[log.length - 2];
      if (last is Map && prev is Map) {
        final lastW = last['weight'];
        final prevW = prev['weight'];
        if (lastW is num && prevW is num) {
          final diff = lastW.toDouble() - prevW.toDouble();
          if (diff == 0) return 'No change';
          return '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(1)} kg';
        }
      }
    }
    return '0.0 kg';
  }

  /// True only when two real entries exist — the delta row is hidden otherwise
  /// (never a fabricated "0.0 kg vs last entry").
  bool get hasWeightTrend {
    final log = memberController.profile.value?['weightLog'];
    return log is List && log.length >= 2;
  }

  bool get isWeightUp {
    final log = memberController.profile.value?['weightLog'];
    if (log is List && log.length >= 2) {
      final last = log[log.length - 1];
      final prev = log[log.length - 2];
      if (last is Map && prev is Map) {
        final lastW = last['weight'];
        final prevW = prev['weight'];
        if (lastW is num && prevW is num) {
          return lastW.toDouble() > prevW.toDouble();
        }
      }
    }
    return false;
  }

  /// 0 means "never measured" — the UI hides the tile rather than showing a
  /// fabricated default.
  double get latestBodyFat {
    final fat = memberController.profile.value?['bodyFat'];
    if (fat is num) return fat.toDouble();
    return 0.0;
  }

  double get latestMuscleMass {
    final muscle = memberController.profile.value?['muscleMass'];
    if (muscle is num) return muscle.toDouble();
    return 0.0;
  }

  int get dailyStreak => memberController.profile.value?['streak'] as int? ?? 0;

  Future<void> refreshAll() async {
    await memberController.claim();
    await trainingController.load();
  }
}
