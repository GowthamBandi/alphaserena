import 'package:get/get.dart';

import '../core/domain/nutrition_targets.dart';
import '../core/services/member_identity_service.dart';
import 'member_controller.dart';
import 'membership_controller.dart';
import 'streak_controller.dart';
import 'training_controller.dart';

/// The post-purchase coaching lifecycle, derived entirely from already-streamed
/// data (no new backend). Home reflects the real stage instead of jumping
/// straight to (empty) plan content.
///
/// `identity` (UMHIPP P2) comes FIRST and runs once ever — it is the member's
/// permanent, org-independent identity. The coach questionnaire (`onboarding`)
/// stays per-organization exactly as before.
enum ClientStage { identity, onboarding, awaitingTrainer, preparingPlan, ready }

class HomeController extends GetxController {
  final MemberController memberController = Get.find<MemberController>();
  final TrainingController trainingController = Get.find<TrainingController>();
  final MembershipController membershipController =
      Get.find<MembershipController>();

  @override
  void onInit() {
    super.onInit();
    // `getMyTraining` is server-resolved (no realtime). When the member's
    // linked `clients` doc changes — e.g. the coach assigns a trainer or the
    // membership updates — re-pull training so a freshly-assigned plan surfaces
    // on Home without a manual refresh. Skipped while we already hold a plan to
    // avoid redundant calls; reloading sets `workout` only, so this never loops.
    // The org fetch is no longer triggered here: MemberController owns it and
    // fires it from its own `clients` listener, so it happens whether or not
    // Home is the screen the member opened.
    _clientWorker = ever<Map<String, dynamic>?>(
      memberController.client,
      (_) => _maybeReloadTraining(),
    );
  }

  // Organisation identity now lives on MemberController — ONE cache, ONE rule,
  // reachable from every screen. These delegate so the header (and its tests)
  // are untouched, while Profile reads the same values instead of the stale
  // `clientProfiles.gymName` mirror it used to read directly.

  /// The member's org logo. Null → the AlphaSerena mark renders as the neutral
  /// fallback (never a fake org identity).
  Rxn<String> get orgLogoUrl => memberController.orgLogoUrl;

  /// The platform-controlled `verified` flag. The badge renders ONLY when true.
  RxBool get orgVerified => memberController.orgVerified;

  /// True only while the storefront fetch is genuinely in flight, so the header
  /// can skeleton the org name instead of flashing a placeholder at a member who
  /// does have one.
  RxBool get orgLoading => memberController.orgLoading;

  /// Whether a real organization name is known from either source. False → the
  /// header shows a neutral placeholder rather than inventing an org identity.
  bool get hasOrgName => memberController.hasOrgName;

  /// The org row is only actionable when a storefront can actually be resolved
  /// (`organizationProfiles/{adminId}`). No adminId → no tap, no fake route.
  bool get canOpenStorefront => memberController.adminId.isNotEmpty;

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

  /// COLD START ONLY — nothing has ever resolved, so there is nothing to keep.
  ///
  /// The member and membership controllers are stream-backed: their
  /// `isLoading` goes false on the first snapshot and never returns to true,
  /// so they are first-load signals already. Training is the one that re-loads,
  /// and it now says which kind of load it is doing.
  bool get isFirstLoad =>
      memberController.isLoading.value ||
      trainingController.isFirstLoad ||
      membershipController.isLoading.value;

  /// A refresh is running under content that is already on screen. Home keeps
  /// every card exactly as it is and shows one quiet line.
  bool get isRefreshing =>
      trainingController.isRefreshing ||
      (Get.isRegistered<StreakController>() &&
          Get.find<StreakController>().isRefreshing.value);

  /// Whether the coach's REAL name is known (vs the 'Your Coach' fallback) —
  /// lets the UI avoid "Your Coach / Your Coach" duplication.
  bool get hasCoachName => memberController.trainerName.isNotEmpty;

  /// The coach's real name, or a lowercase ROLE phrase.
  ///
  /// The fallback used to be title-cased `'Your Coach'`, which reads as a proper
  /// name — and this getter is interpolated mid-sentence ("Answer a few
  /// questions from ${coachName}"), so an unassigned member was addressed as if
  /// "Your Coach" were the person's name. Lowercase makes it unambiguously a
  /// role. Callers needing a sentence-initial form branch on [hasCoachName],
  /// which is why that getter exists.
  String get coachName => memberController.trainerName.isNotEmpty
      ? memberController.trainerName
      : 'your coach';

  /// The coach's avatar, or '' → the header renders initials.
  String get coachPhotoUrl => memberController.trainerPhotoUrl;

  /// Live storefront name → stale `gymName` mirror → a generic label that can't
  /// be mistaken for data (the old 'Alpha Arena' fallback looked like a real
  /// gym).
  ///
  /// The precedence is now live-before-mirror, via `resolveOrgName`. It used to
  /// be the reverse, so an organisation that renamed itself kept showing its
  /// FORMER name here even after the current one had been fetched and was
  /// sitting in memory — the mirror is written once by `claimClientAccount` and
  /// is never re-derived on a rename.
  String get gymName =>
      memberController.hasOrgName ? memberController.orgName : 'Your Organization';

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
  /// UMHIPP identity setup completed (once, ever — org-independent).
  bool get identityDone =>
      MemberIdentityService.isComplete(memberController.profile.value);

  ClientStage get stage {
    if (hasPlan) return ClientStage.ready;
    if (!identityDone) return ClientStage.identity;
    if (!onboardingDone) return ClientStage.onboarding;
    if (!hasTrainer) return ClientStage.awaitingTrainer;
    return ClientStage.preparingPlan;
  }

  // ── Today's daily nutrition targets ────────────────────────────────────
  // Resolved through the one canonical rule (`core/domain/nutrition_targets.dart`)
  // so Home, My Plans and the Diet screen cannot disagree. These previously
  // summed the assigned items unconditionally, which ignored the coach's real
  // `clients.dietTargets` goal that `getMyTraining` serves.
  NutritionTarget dietTarget(String targetKey, String itemKey) =>
      resolveNutritionTarget(
        servedTargets: trainingController.servedTargets.value,
        diet: trainingController.diet.value,
        targetKey: targetKey,
        itemKey: itemKey,
        items: trainingController.dietItems,
      );

  NutritionTarget get calorieTarget => dietTarget('targetCalories', 'calories');
  NutritionTarget get proteinTarget => dietTarget('targetProtein', 'protein');
  NutritionTarget get carbsTarget => dietTarget('targetCarbs', 'carbs');
  NutritionTarget get fatTarget => dietTarget('targetFat', 'fat');
  NutritionTarget get fiberTarget => dietTarget('targetFiber', 'fiber');

  double get targetCalories => calorieTarget.value;
  double get targetProtein => proteinTarget.value;
  double get targetCarbs => carbsTarget.value;
  double get targetFat => fatTarget.value;
  double get targetFiber => fiberTarget.value;

  /// True only when the coach set a real daily calorie goal. Home's ring shows
  /// "kcal left" against a genuine goal, and plain "kcal eaten" otherwise —
  /// a prescription sum is not a target to burn down.
  bool get hasCoachCalorieGoal => calorieTarget.isCoachGoal;

  // Today's workout details
  //
  // PRESCRIPTION ENGINE (Phase 3): the old fallback here was 'Rest Day' — a
  // fabricated prescription (nobody prescribed rest; the plan was merely
  // null). Rest is now only ever shown when the SERVER says the coach
  // prescribed it; a missing plan is just a missing plan.
  String get workoutName =>
      trainingController.workout.value?['name']?.toString() ?? 'Workout';

  List<Map<String, dynamic>> get workoutPreviewItems {
    final items = trainingController.workoutItems;
    if (items.length <= 3) return items;
    return items.sublist(0, 3);
  }

  int get exerciseCount => trainingController.workoutItems.length;

  // Membership expiry warning
  bool get showExpiryBanner => membershipController.isExpiringSoon;

  /// Header status line under the org name — repository-derived, never
  /// decorative: 'Active member' / 'Expires in Nd' (inactive members see the
  /// dedicated blocker card instead of a header chip).
  String get membershipStatusLabel {
    if (!membershipController.isActive) return '';
    if (membershipController.isExpiringSoon) {
      final e = membershipController.expiry;
      if (e != null) {
        final d = e.difference(DateTime.now()).inDays;
        return d <= 0 ? 'Expires today' : 'Expires in ${d}d';
      }
    }
    return 'Active';
  }

  String get membershipExpiryText {
    final expiry = membershipController.expiry;
    if (expiry == null) return '';
    final remainingDays = expiry.difference(DateTime.now()).inDays;
    if (remainingDays <= 0) return 'Membership expires today!';
    return 'Membership expires in $remainingDays days (${expiry.day}/${expiry.month}/${expiry.year})';
  }

  // Weight & Progress Stats getters
  /// 0 means "never measured" — the UI shows '--' rather than a fabricated
  /// default (same contract as [latestBodyFat]/[latestMuscleMass]).
  double get latestWeight {
    final log = memberController.profile.value?['weightLog'];
    if (log is List && log.isNotEmpty) {
      final last = log.last;
      if (last is Map) {
        final w = last['weight'];
        if (w is num) return w.toDouble();
      }
    }
    final initialW = memberController.profile.value?['weight'];
    if (initialW is num) return initialW.toDouble();
    return 0.0;
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

  Future<void> refreshAll() async {
    await memberController.claim();
    await trainingController.load();
    if (Get.isRegistered<StreakController>()) {
      await Get.find<StreakController>().load();
    }
  }
}
