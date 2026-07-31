import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';

import '../core/domain/today_expectation.dart';
import '../core/models/served_diet.dart';

/// Loads the member's assigned workout + diet content from the getMyTraining
/// Cloud Function (resolved server-side; no direct reads of gym collections).
class TrainingController extends GetxController {
  final FirebaseFunctions _functions = FirebaseFunctions.instance;

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
