import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show protected, visibleForTesting;
import 'package:get/get.dart';

import '../core/domain/today_expectation.dart';
import '../core/models/served_diet.dart';

/// Loads the member's assigned workout + diet content from the getMyTraining
/// Cloud Function (resolved server-side; no direct reads of gym collections).
class TrainingController extends GetxController {
  /// Resolved LAZILY, not in a field initializer.
  ///
  /// `FirebaseFunctions.instance` throws without a live Firebase app, and an
  /// eager field runs even for a subclass that overrides every method — which
  /// made this controller impossible to fake in a widget test without booting
  /// Firebase. Nothing here needs the instance until `load()` actually calls.
  FirebaseFunctions? _injectedFunctions;
  FirebaseFunctions get _functions =>
      _injectedFunctions ??= FirebaseFunctions.instance;

  final RxBool isLoading = true.obs;
  final RxString error = ''.obs;
  final Rxn<Map<String, dynamic>> workout = Rxn<Map<String, dynamic>>();
  final Rxn<Map<String, dynamic>> diet = Rxn<Map<String, dynamic>>();

  /// NIP Phase A — the SAME served diet as [diet], parsed once into a typed
  /// model (items with entryId/grams/portions, description, the additive
  /// `targets` map). Additive: every existing raw-map getter stays; screens
  /// migrate to this at their own pace. Always set/cleared in lockstep with
  /// [diet], so the two views can never disagree.
  final Rxn<ServedDiet> servedDiet = Rxn<ServedDiet>();

  /// `{id, name, photoUrl, assigned}` — the member's coach, resolved server-side
  /// on every call. Null until the first successful load; the member app then
  /// falls back to the `clientProfiles` mirror so a cold offline start still
  /// shows a name.
  /// `getMyTraining`'s top-level `nutritionTargets` — the member's daily goal
  /// resolved from `clients/{id}`, NOT from a plan.
  ///
  /// Kept separate from [diet] precisely because it must outlive it: a coach
  /// can prescribe targets without assigning a diet plan, and can pause or end
  /// an assigned one, both of which send [diet] null. Null here means an older
  /// backend or a member with no prescription at all.
  final Rxn<Map<String, dynamic>> servedTargets = Rxn<Map<String, dynamic>>();

  final Rxn<Map<String, dynamic>> coach = Rxn<Map<String, dynamic>>();

  /// PRESCRIPTION ENGINE (Phase 3): what the coach ASKED for today, resolved
  /// server-side so this app never computes an expectation locally. Null when
  /// the backend predates Phase 2 or the field is unreadable — the UI then
  /// renders its legacy self exactly (never a guess).
  final Rxn<TodayExpectations> expectations = Rxn<TodayExpectations>();

  /// PRESCRIPTION ENGINE (Phase 4): the raw prescription material for the
  /// performance timeline — versions, per-day excuses, client-level pause.
  /// Past days are resolved from this with the SAME certified engine both
  /// apps carry; today's expectation above stays server-resolved. Null on an
  /// older backend → the performance screen renders its presence-only legacy.
  final Rxn<Map<String, dynamic>> prescriptionData =
      Rxn<Map<String, dynamic>>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  /// When the last SUCCESSFUL load completed. Null until one has.
  DateTime? _loadedAt;

  /// Stamps the plan as freshly served. Called by [load] on its success path
  /// only; exposed so a test double that overrides [load] can reproduce the
  /// same contract instead of the freshness rule being untestable.
  @protected
  @visibleForTesting
  void markLoadedForTest() => _loadedAt = DateTime.now();

  /// How long a served plan is treated as fresh by [refreshIfStale].
  static const Duration freshness = Duration(seconds: 45);

  /// THE COACH'S CHANGES HAVE NO PUSH PATH — this is the pull.
  ///
  /// `getMyTraining` is a one-shot callable, and TrainerHQ's `AssignmentService`
  /// writes ONLY to `client_plan_assignments` — a collection the member app
  /// cannot read (plan resolution is deliberately server-side) and which does
  /// not touch the `clients` document the member DOES stream. So nothing in the
  /// member app observes an assignment change:
  ///
  ///   • assigned a first plan   → invisible
  ///   • replaced / edited       → invisible
  ///   • paused / removed        → invisible, and the member can still open and
  ///                               START a workout their coach has withdrawn
  ///
  /// until a pull-to-refresh, a day rollover, or an app restart. `HomeController`
  /// has a reload worker, but it is gated on `!hasPlan`, so it can only ever
  /// help a member who has no plan at all.
  ///
  /// This closes the gap for every moment the member actually LOOKS at the
  /// screen — app resume, and entering the My Plans tab — without inventing a
  /// listener the backend does not expose. [freshness] keeps it cheap: this
  /// callable fans out to several document reads, so a member flicking between
  /// tabs must not re-run it every time.
  ///
  /// Still NOT covered, and documented rather than pretended away: a coach
  /// changing the plan while the member sits on the screen. That needs a real
  /// push channel (see the report).
  Future<void> refreshIfStale({Duration? maxAge}) async {
    if (isLoading.value) return;
    final at = _loadedAt;
    if (at != null && DateTime.now().difference(at) < (maxAge ?? freshness)) {
      return;
    }
    await load();
  }

  Future<void> load() async {
    try {
      isLoading.value = true;
      error.value = '';
      // The member's LOCAL day: their day is the day they lived (the server
      // clamps drift to ±1 day). Without this an IST member at 11pm would be
      // served the UTC day's — i.e. tomorrow's — expectation.
      final res = await _functions.httpsCallable('getMyTraining').call(
        <String, dynamic>{'localDate': localDayKey(DateTime.now())},
      );
      final data = Map<String, dynamic>.from(res.data as Map);
      workout.value = data['workout'] != null
          ? Map<String, dynamic>.from(data['workout'])
          : null;
      diet.value =
          data['diet'] != null ? Map<String, dynamic>.from(data['diet']) : null;
      servedDiet.value =
          diet.value != null ? ServedDiet.fromMap(diet.value!) : null;
      // The member's own daily goal, served independently of any plan — so it
      // survives `diet` going null when a plan is absent, paused or ended.
      servedTargets.value = data['nutritionTargets'] is Map
          ? Map<String, dynamic>.from(data['nutritionTargets'] as Map)
          : null;
      // The LIVE coach identity. Unlike the `clientProfiles` mirror this is
      // re-resolved on every call — and this callable runs on app open, on
      // Home reload and on every pull-to-refresh — so a renamed coach, a new
      // photo, or an assignment made while the app was closed all land here
      // without depending on a claim ever running again.
      coach.value = data['coach'] != null
          ? Map<String, dynamic>.from(data['coach'])
          : null;
      expectations.value = TodayExpectations.fromResponse(data);
      prescriptionData.value = data['prescriptionData'] is Map
          ? Map<String, dynamic>.from(data['prescriptionData'] as Map)
          : null;
      // Stamped only on SUCCESS: a failed load must not mark the held plan
      // fresh, or `refreshIfStale` would sit out the whole freshness window
      // after exactly the failure that most needs retrying.
      markLoadedForTest();
    } catch (_) {
      error.value = 'Could not load your training. Tap retry.';
    } finally {
      isLoading.value = false;
    }
  }

  /// Re-fetches when the day the server resolved FOR is no longer the
  /// member's local day (midnight rollover, app resumed next morning) — a
  /// stale "rest day" banner on a training morning would be a lie. No-op
  /// while a load is already in flight or no expectation was ever served.
  Future<void> ensureFreshDay() async {
    final served = expectations.value?.date ?? '';
    if (served.isEmpty || isLoading.value) return;
    if (served != localDayKey(DateTime.now())) await load();
  }

  ServedExpectation? get workoutExpectation => expectations.value?.workout;
  ServedExpectation? get dietExpectation => expectations.value?.diet;

  List<Map<String, dynamic>> get workoutItems =>
      ((workout.value?['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

  // ── WEEKLY PRESCRIPTION — additive serving fields ─────────────────────────
  // Present only when the coach assigned a weekly schedule; every legacy
  // response leaves them absent (→ false/null), which is single-plan behaviour.

  /// True when today is an authored REST day of a weekly schedule: the track
  /// exists, today asks for nothing, and `workoutItems` is honestly empty.
  bool get isWeeklyRestDay => workout.value?['restDay'] == true;

  /// The weekly overview `{name, days:[{day, planName, isToday}]}`, or null.
  Map<String, dynamic>? get weeklyOverview {
    final w = workout.value?['weekly'];
    return w is Map ? Map<String, dynamic>.from(w) : null;
  }

  /// The next mapped training day `{day, planName}`, or null. Serves the
  /// rest-day card's "Next: Push Day on Wednesday" line.
  Map<String, dynamic>? get nextTrainingDay {
    final n = workout.value?['nextDay'];
    return n is Map ? Map<String, dynamic>.from(n) : null;
  }

  List<Map<String, dynamic>> get dietItems =>
      ((diet.value?['items'] as List?) ?? const [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
}
