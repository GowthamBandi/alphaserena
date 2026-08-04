import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../core/domain/food_portion_math.dart';
import '../core/models/member_food.dart';
import '../core/models/nutrition_day_model.dart';
import '../core/services/member_food_service.dart';
import '../core/services/nutrition_day_service.dart';
import 'member_controller.dart';

/// NIP PHASE 3A — the member's FOOD LOG for a day.
///
/// Owns `client_nutrition_days` reading and writing. Deliberately separate
/// from [DietLogController], which owns diet-plan ADHERENCE: the coach's
/// recommendation and the member's reality are two concepts, and one
/// controller owning both is how they start being averaged together.
///
/// NUTRITION TOTALS COME FROM LOGGED FOODS ONLY. The prescribed plan
/// contributes nothing to them — it is a recommendation, and counting it would
/// report calories nobody ate.
class FoodLogController extends GetxController {
  FoodLogController({
    NutritionDayService? service,
    MemberFoodService? foods,
    MemberController? member,
    String Function()? idFactory,
  })  : _service = service ?? NutritionDayService(),
        _foods = foods ?? MemberFoodService(),
        _injectedMember = member,
        _idFactory = idFactory;

  final NutritionDayService _service;
  final MemberFoodService _foods;
  final MemberController? _injectedMember;

  /// The entry-id source, injectable for the same reason every other
  /// collaborator here is: the default reaches `FirebaseFirestore.instance`, so
  /// without this seam NO test could call [logFood] at all — and none did,
  /// which is why the write path's interaction with a dead listener went
  /// unexercised until it became a production blocker.
  final String Function()? _idFactory;

  /// Resolved LAZILY: constructing a `MemberController` needs a live Firebase
  /// app, and doing it in the initializer list runs even for a subclass that
  /// overrides everything.
  MemberController get _member =>
      _injectedMember ??
      (Get.isRegistered<MemberController>()
          ? Get.find<MemberController>()
          : Get.put(MemberController()));

  final Rxn<NutritionDayModel> day = Rxn<NutritionDayModel>();
  final RxBool isLoading = true.obs;

  /// The last read FAILED, as distinct from "the member has logged nothing".
  /// Conflating them tells a member with a full day of food that they logged
  /// none of it.
  final RxBool loadError = false.obs;

  /// A write reached the local cache but not the server yet. Not an error:
  /// the entry is safe and will replay.
  final RxBool hasQueuedWrites = false.obs;

  /// Entry ids this device is currently writing — the re-entrancy guard behind
  /// duplicate taps.
  final RxSet<String> pendingIds = <String>{}.obs;

  StreamSubscription<NutritionDayModel?>? _sub;
  Worker? _linkWorker;
  bool _closed = false;

  /// The day this controller is bound to. Written only by [_bind].
  String _boundKey = '';
  String get dateKey => _boundKey.isEmpty ? todayKey() : _boundKey;

  /// The member's LOCAL calendar day. A food eaten at 23:50 belongs to the day
  /// the member lived, not to UTC.
  static String todayKey() => DateFormat('yyyy-MM-dd').format(DateTime.now());

  /// The adminId the day document was OPENED under.
  ///
  /// The rules pin `adminId` immutable on update, so a member who transfers
  /// gyms mid-day must keep writing the original org or every later write that
  /// day is denied. Null until the document exists, in which case the member's
  /// current org is correct — it is the first write.
  /// Read from the DAY DOCUMENT, never from the member's current org.
  ///
  /// This used to capture `MemberController.adminId` the first time a snapshot
  /// arrived. That is the member's org NOW, which is the right answer only
  /// while the app has been open since before a transfer — and there is no
  /// such memory after a relaunch. A member who transferred gyms mid-day and
  /// restarted therefore adopted their NEW org for a day created under the
  /// old one, and the immutability rule denied every write until midnight.
  ///
  /// Null when there is no document yet: the first write CREATES it, and
  /// create is the one moment the member's current org is correct — the
  /// service fills it in. Null too for a legacy day carrying no org, so a
  /// blank is never sent as an identity.
  String? get _dayAdminId {
    final admin = day.value?.adminId ?? '';
    return admin.isEmpty ? null : admin;
  }

  /// True while a REAL Firestore subscription is open (as opposed to the
  /// controller having given up because the member was not loggable yet).
  bool _liveBound = false;

  @override
  void onInit() {
    super.onInit();
    _bind();
    // REBIND ON WHAT `canLog` ACTUALLY DEPENDS ON.
    //
    // Logging needs THREE facts and they arrive on TWO different streams:
    // `clientId` from `clientProfiles`, `adminId` from the `clients` document,
    // and the auth uid. This used to watch `isLinked` alone — which flips true
    // when the PROFILE resolves, typically BEFORE the clients document lands.
    // `_bind()` therefore re-ran while `adminId` was still empty, took the
    // not-loggable branch, and subscribed to nothing; and when `adminId` did
    // arrive, `isLinked` never changed again, so nothing rebound. `ever` fires
    // on CHANGE, and the controller was watching the wrong fact.
    //
    // The write path never noticed, because `addEntry` re-checks `canLog` at
    // call time. Writes worked while reads were dead, so a member logged food
    // into a screen that then told them they had logged nothing — through a
    // full restart. Observed on device, with a real member, against real rules.
    //
    // Guarded on `_liveBound` so an already-live listener is not torn down and
    // reopened every time the coach edits the client document.
    _linkWorker = everAll([_member.isLinked, _member.client], (_) {
      if (!_liveBound) _bind();
    });
  }

  @override
  void onClose() {
    _closed = true;
    _sub?.cancel();
    _linkWorker?.dispose();
    super.onClose();
  }

  /// Re-anchors to the current calendar day if it rolled over while the app
  /// was open (left running overnight, or resumed the next morning).
  ///
  /// Without this the member would add breakfast to YESTERDAY's document and
  /// watch today's totals stay at zero. Called from the screens' build path,
  /// so it must never itself trigger a synchronous rebuild — [_bind] only
  /// touches Rx state from the stream callback.
  void ensureFreshDay() {
    if (_closed) return;
    if (_boundKey != todayKey()) _bind();
  }

  void _bind() {
    if (_closed) return;
    final key = todayKey();
    _sub?.cancel();
    _boundKey = key;
    if (!_service.canLog) {
      // Not loggable YET. Nothing is subscribed, so the link worker above must
      // keep watching for the moment it becomes loggable.
      _liveBound = false;
      isLoading.value = false;
      day.value = null;
      return;
    }
    _liveBound = true;
    isLoading.value = true;
    loadError.value = false;
    _sub = _service.watchDay(key).listen(
      (d) {
        if (_closed) return;
        day.value = d;
        isLoading.value = false;
        loadError.value = false;
        // Anything this device wrote has now come back down the stream.
        pendingIds.removeWhere((id) => d?.entries.containsKey(id) ?? false);
      },
      onError: (_) {
        if (_closed) return;
        isLoading.value = false;
        // An honest error, never the empty state. The empty state is a claim
        // about the member's behaviour; this is a claim about the network.
        loadError.value = true;
      },
    );
  }

  /// Re-subscribes after a failure — the Retry button.
  void retry() => _bind();

  /// SELF-HEALING AFTER A DEAD LISTENER.
  ///
  /// Firestore TERMINATES a listener on error and never retries it, and the
  /// only rebind path was [_bind] on a date rollover or a manual Retry. So a
  /// member whose listener failed — most commonly on a day document that does
  /// not exist yet — could log food perfectly well (the write path re-checks
  /// `canLog` and never touches `resource`), watch the write succeed, and go on
  /// staring at "Couldn't load today's food" with the food already stored. The
  /// documented escape hatch was "log blind, then tap Retry", which is not a
  /// state to leave a paying member in.
  ///
  /// A successful write proves the member is reachable and — for the missing-
  /// document case — that the document now EXISTS, so this is the exact moment
  /// a rebind can succeed. Guarded on [loadError] so the normal path never
  /// tears down a healthy subscription on every save.
  void _recoverIfErrored(DietSaveResult result) {
    if (result == DietSaveResult.failed) return;
    if (!loadError.value) return;
    _bind();
  }

  // ── READ MODEL ───────────────────────────────────────────────────────────

  /// Live entries for the bound day, newest first within each meal.
  List<FoodEntry> get liveEntries =>
      (day.value?.liveEntries.toList() ?? <FoodEntry>[])
        ..sort((a, b) {
          final m = mealSlotOrder(a.mealSlot).compareTo(mealSlotOrder(b.mealSlot));
          if (m != 0) return m;
          return (a.loggedAt ?? 0).compareTo(b.loggedAt ?? 0);
        });

  /// Entries grouped by meal, in canonical meal order, non-empty groups only.
  Map<String, List<FoodEntry>> get entriesByMeal {
    final out = <String, List<FoodEntry>>{};
    for (final e in liveEntries) {
      out.putIfAbsent(e.mealSlot, () => []).add(e);
    }
    return out;
  }

  int get entryCount => liveEntries.length;

  /// TODAY'S TOTALS, from logged foods only.
  ///
  /// Computed locally from the frozen `consumed` snapshots rather than read
  /// from the server's `computed` block, because the server's arrives one
  /// trigger round trip later — and offline it never arrives at all. The
  /// member must see their lunch counted the instant they log it.
  ///
  /// The arithmetic is the same operation the server performs
  /// (`computeDayTotals` = sum of live entries' `consumed`), over the same
  /// frozen snapshots, so the two cannot disagree once the trigger catches up.
  Map<String, double> get totals => sumMacros([
        for (final e in liveEntries)
          {
            'calories': e.consumed.calories,
            'protein': e.consumed.protein,
            'carbs': e.consumed.carbs,
            'fat': e.consumed.fat,
            'fiber': e.consumed.fiber,
            'sugar': e.consumed.sugar,
            'saturatedFat': e.consumed.saturatedFat,
          },
      ]);

  double get loggedCalories => totals['calories'] ?? 0;
  double get loggedProtein => totals['protein'] ?? 0;
  double get loggedCarbs => totals['carbs'] ?? 0;
  double get loggedFat => totals['fat'] ?? 0;
  double get loggedFiber => totals['fiber'] ?? 0;

  /// Totals for one meal — what the member ate at lunch, specifically.
  Map<String, double> totalsForMeal(String slot) => sumMacros([
        for (final e in liveEntries.where((e) => e.mealSlot == slot))
          {
            'calories': e.consumed.calories,
            'protein': e.consumed.protein,
            'carbs': e.consumed.carbs,
            'fat': e.consumed.fat,
            'fiber': e.consumed.fiber,
            'sugar': e.consumed.sugar,
            'saturatedFat': e.consumed.saturatedFat,
          },
      ]);

  bool get isFull => entryCount >= kMaxEntriesPerDay;

  // ── WRITES ───────────────────────────────────────────────────────────────

  /// A collision-free entry id that works OFFLINE.
  ///
  /// Firestore's own id generator is used rather than a timestamp: two rapid
  /// taps inside the same millisecond would collide on a timestamp and the
  /// second food would overwrite the first in the entries map — silently, and
  /// exactly in the "add three things quickly" flow this screen is built for.
  String newEntryId() =>
      (_idFactory ?? () => FirebaseFirestore.instance.collection('_ids').doc().id)();

  /// Logs one food.
  ///
  /// Returns the save outcome; [DietSaveResult.queued] is SUCCESS with no
  /// signal. Remembers the food in recents on any non-failure, because the
  /// member did choose it whether or not the server has heard yet.
  Future<DietSaveResult> logFood({
    required MemberFood food,
    required String mealSlot,
    required PortionSelection selection,
    String? note,
    DateTime? eatenAt,
  }) async {
    ensureFreshDay();
    if (!selection.isValid) return DietSaveResult.failed;

    final entryId = newEntryId();
    final consumed = scaleMacros(food.per100, selection.totalGrams);
    final entry = FoodEntry(
      entryId: entryId,
      source: FoodEntrySource.search,
      foodId: food.foodId,
      // SNAPSHOTTED. A food renamed, archived or removed from the org library
      // next month must not turn this day into a list of ids.
      foodName: food.name,
      foodTier: food.tier == MemberFoodTier.org ? FoodTier.org : FoodTier.global,
      mealSlot: canonicalMealSlot(mealSlot),
      quantity: selection.storedQuantity,
      unit: selection.storedUnit,
      // The MASS, stored alongside the human amount. "2 katori" is only 300 g
      // if you also know a katori is 150 g — and that lives in a food document
      // that may change later, so the mass is frozen here with the macros it
      // produced.
      grams: selection.totalGrams,
      consumed: ConsumedSnapshot(
        calories: consumed['calories'] ?? 0,
        protein: consumed['protein'] ?? 0,
        carbs: consumed['carbs'] ?? 0,
        fat: consumed['fat'] ?? 0,
        fiber: consumed['fiber'] ?? 0,
        sugar: consumed['sugar'] ?? 0,
        saturatedFat: consumed['saturatedFat'] ?? 0,
      ),
      loggedAt: (eatenAt ?? DateTime.now()).millisecondsSinceEpoch,
      note: (note != null && note.trim().isNotEmpty) ? note.trim() : null,
    );

    pendingIds.add(entryId);
    final result = await _service.addEntry(
      dateKey: dateKey,
      entry: entry,
      existingAdminId: _dayAdminId,
    );
    if (result == DietSaveResult.failed) {
      pendingIds.remove(entryId);
    } else {
      hasQueuedWrites.value =
          hasQueuedWrites.value || result == DietSaveResult.queued;
      unawaited(_foods.remember(food));
    }
    _recoverIfErrored(result);
    return result;
  }

  /// Changes an existing entry's amount (and optionally its meal).
  ///
  /// Rewrites the frozen `consumed` block, which is correct: the member is
  /// stating that the original amount was wrong, so the snapshot of what they
  /// ate should change. This is not the case the freeze protects against —
  /// that is a FOOD changing underneath a past entry, which still cannot
  /// happen because the new numbers are computed from [per100] supplied here.
  Future<DietSaveResult> editEntry({
    required FoodEntry entry,
    required Map<String, double> per100,
    required PortionSelection selection,
    String? mealSlot,
  }) async {
    if (!selection.isValid) return DietSaveResult.failed;
    final consumed = scaleMacros(per100, selection.totalGrams);
    pendingIds.add(entry.entryId);
    final result = await _service.writeEntry(
      dateKey: dateKey,
      entryId: entry.entryId,
      patch: {
        'quantity': selection.storedQuantity,
        'unit': selection.storedUnit,
        'grams': selection.totalGrams,
        'consumed': consumed,
        if (mealSlot != null) 'mealSlot': canonicalMealSlot(mealSlot),
      },
      existingAdminId: _dayAdminId,
    );
    if (result == DietSaveResult.failed) pendingIds.remove(entry.entryId);
    _recoverIfErrored(result);
    return result;
  }

  /// Soft-deletes an entry. The row stays, flagged; nothing is destroyed.
  Future<DietSaveResult> removeEntry(FoodEntry entry) async {
    pendingIds.add(entry.entryId);
    final result = await _service.softDelete(
      dateKey: dateKey,
      entryId: entry.entryId,
      existingAdminId: _dayAdminId,
    );
    if (result == DietSaveResult.failed) pendingIds.remove(entry.entryId);
    _recoverIfErrored(result);
    return result;
  }

  /// Undo for [removeEntry].
  Future<DietSaveResult> restoreEntry(FoodEntry entry) async {
    final result = await _service.restore(
      dateKey: dateKey,
      entryId: entry.entryId,
      existingAdminId: _dayAdminId,
    );
    _recoverIfErrored(result);
    return result;
  }
}
