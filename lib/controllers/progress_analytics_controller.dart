import 'dart:async';

import 'package:get/get.dart';

import '../core/analytics/analytics_adapters.dart';
import '../core/analytics/progress_analytics.dart';
import '../core/models/check_in_submission_model.dart';
import '../core/models/transformation_entry.dart';
import '../core/services/check_in_submission_service.dart';
import '../core/services/member_rollup_service.dart';
import '../core/services/nutrition_rollup_service.dart';
import '../core/services/workout_log_service.dart';
import 'member_controller.dart';
import 'progress_controller.dart';

/// The observation window a member chose.
///
/// A fixed set rather than a free date picker: every range here maps to a
/// bounded read (a whole number of monthly rollup documents), so no selection a
/// member can make turns into an unbounded query.
enum ProgressRange { week, month, quarter, year }

extension ProgressRangeX on ProgressRange {
  int get days => switch (this) {
    ProgressRange.week => 7,
    ProgressRange.month => 30,
    ProgressRange.quarter => 90,
    ProgressRange.year => 365,
  };

  String get label => switch (this) {
    ProgressRange.week => 'Week',
    ProgressRange.month => 'Month',
    ProgressRange.quarter => '3 Months',
    ProgressRange.year => 'Year',
  };

  /// The phrase used inside a sentence ("over the last 30 days").
  String get phrase => switch (this) {
    ProgressRange.week => 'last 7 days',
    ProgressRange.month => 'last 30 days',
    ProgressRange.quarter => 'last 3 months',
    ProgressRange.year => 'last 12 months',
  };

  /// How many monthly rollup documents this range needs.
  ///
  /// `+1` because a window always straddles a month boundary — 30 days ending
  /// on the 5th reaches back into the previous month, and reading only the
  /// current one would silently truncate the window at the 1st.
  int get months => switch (this) {
    ProgressRange.week => 2,
    ProgressRange.month => 2,
    ProgressRange.quarter => 4,
    ProgressRange.year => 13,
  };
}

/// How one source of Progress data is doing, tracked SEPARATELY.
///
/// A partial feed must never render as a complete one, and one healthy source
/// must never mask another's failure — the rule the coach app's
/// `ProgressController` already enforces, brought to the member's side because
/// this screen now has five sources instead of one.
enum SourceState { loading, ready, failed }

/// THE MEMBER'S PROGRESS INTELLIGENCE RUNTIME.
///
/// ── WHAT IT IS ─────────────────────────────────────────────────────────────
///
/// It owns the I/O for the Progress screen and NOTHING ELSE. Every number it
/// exposes is produced by `core/analytics/progress_analytics.dart` — the file
/// twinned with TrainerHQ — from sources adapted by `analytics_adapters.dart`.
/// There is no arithmetic in this class. If a calculation appears here, the two
/// apps have started deriving separately again.
///
/// ── WHAT IT DELIBERATELY DOES NOT DO ───────────────────────────────────────
///
///  • It does NOT open a second `client_progress` listener. The existing
///    [ProgressController] already streams the member's transformation history
///    for the Transformation surface; this reads that controller's list. One
///    collection, one listener, whatever else is on screen.
///  • It does NOT re-aggregate the consistency engine. Streaks against the
///    coach's PRESCRIPTION belong to `StreakController` / `PerformanceController`
///    and are shown by the Consistency surface; the streak here is the plain
///    calendar-day training streak the shared core computes, and it is labelled
///    as such.
///  • It does NOT load until the member actually opens Progress. The dashboard's
///    `IndexedStack` builds all four tabs at mount, so an eager load would make
///    every member pay for a screen they may never visit. [ensureLoaded] is
///    called the first time the tab becomes visible.
class ProgressAnalyticsController extends GetxController {
  ProgressAnalyticsController({
    WorkoutLogService? workoutLog,
    CheckInSubmissionService? checkIns,
    NutritionRollupService? nutritionRollups,
    MemberRollupService? lifestyleRollups,
    MemberController? member,
    ProgressController? transformation,
    DateTime Function()? clock,
  }) : _injectedWorkoutLog = workoutLog,
       _injectedCheckIns = checkIns,
       _injectedNutrition = nutritionRollups,
       _injectedLifestyle = lifestyleRollups,
       _injectedMember = member,
       _injectedTransformation = transformation,
       _clock = clock ?? DateTime.now;

  final WorkoutLogService? _injectedWorkoutLog;
  final CheckInSubmissionService? _injectedCheckIns;
  final NutritionRollupService? _injectedNutrition;
  final MemberRollupService? _injectedLifestyle;
  final MemberController? _injectedMember;
  final ProgressController? _injectedTransformation;
  final DateTime Function() _clock;

  // Every collaborator resolves LAZILY. Building a Firebase-backed service in a
  // field initializer is a recurring defect class in this codebase — it throws
  // at CONSTRUCTION even for a fake that overrides every method, and it is what
  // made four other services untestable.
  WorkoutLogService? _workoutLog;
  WorkoutLogService get workoutLog =>
      _injectedWorkoutLog ?? (_workoutLog ??= WorkoutLogService());

  CheckInSubmissionService? _checkInService;
  CheckInSubmissionService get checkInService =>
      _injectedCheckIns ?? (_checkInService ??= CheckInSubmissionService());

  NutritionRollupService? _nutritionService;
  NutritionRollupService get nutritionService =>
      _injectedNutrition ?? (_nutritionService ??= NutritionRollupService());

  MemberRollupService? _lifestyleService;
  MemberRollupService get lifestyleService =>
      _injectedLifestyle ??
      (_lifestyleService ??=
          (Get.isRegistered<MemberRollupService>()
              ? Get.find<MemberRollupService>()
              : MemberRollupService()));

  MemberController get member =>
      _injectedMember ??
      (Get.isRegistered<MemberController>()
          ? Get.find<MemberController>()
          : Get.put(MemberController()));

  /// The transformation stream's owner. Null when Progress is rendered without
  /// it (tests, previews) — the body sources then come from check-ins alone,
  /// which is a smaller truth, never a fabricated one.
  ProgressController? get transformation =>
      _injectedTransformation ??
      (Get.isRegistered<ProgressController>()
          ? Get.find<ProgressController>()
          : null);

  DateTime get now => _clock();

  // ── Selected range ────────────────────────────────────────────────────────

  final Rx<ProgressRange> range = ProgressRange.month.obs;

  /// Changes the window and re-subscribes the rollup streams if the new range
  /// needs more months than the current subscription covers.
  ///
  /// Widening re-subscribes; NARROWING DOES NOT — the data already in memory
  /// covers the smaller window, and tearing down live listeners to read less
  /// would cost reads to show a subset of what is already on the device.
  void setRange(ProgressRange next) {
    if (next == range.value) return;
    final needsMore = next.months > _subscribedMonths;
    range.value = next;
    if (needsMore && _loaded) _bindRollups();
  }

  // ── Sources ───────────────────────────────────────────────────────────────

  final RxList<AnalyticsSession> sessions = <AnalyticsSession>[].obs;
  final RxList<CheckInSubmissionModel> checkIns = <CheckInSubmissionModel>[].obs;
  final RxList<AnalyticsRatio> nutrition = <AnalyticsRatio>[].obs;
  final RxList<AnalyticsRatio> lifestyle = <AnalyticsRatio>[].obs;

  final Rx<SourceState> sessionState = SourceState.loading.obs;
  final Rx<SourceState> checkInState = SourceState.loading.obs;
  final Rx<SourceState> nutritionState = SourceState.loading.obs;
  final Rx<SourceState> lifestyleState = SourceState.loading.obs;

  /// Bumped on every source emission so `Obx` rebuilds derived views even when
  /// a change does not alter a headline number (a new photo, a corrected set).
  final RxInt revision = 0.obs;

  StreamSubscription? _checkInSub;
  StreamSubscription? _nutritionSub;
  StreamSubscription? _lifestyleSub;
  Worker? _linkWorker;
  Worker? _clientWorker;
  Worker? _transformationWorker;

  bool _loaded = false;
  int _subscribedMonths = 0;
  bool _closed = false;

  /// True until every source has produced a first event (data OR error).
  bool get isLoading =>
      !_loaded ||
      sessionState.value == SourceState.loading ||
      checkInState.value == SourceState.loading ||
      nutritionState.value == SourceState.loading ||
      lifestyleState.value == SourceState.loading;

  /// True when ANY source failed. The screen still renders what it has and says
  /// which part is missing — a partial view labelled as partial beats a blank
  /// one, and beats a complete-looking one that is quietly short a source.
  bool get hasPartialFailure =>
      sessionState.value == SourceState.failed ||
      checkInState.value == SourceState.failed ||
      nutritionState.value == SourceState.failed ||
      lifestyleState.value == SourceState.failed;

  /// Names the sources that failed, for an honest banner.
  List<String> get failedSources => [
    if (sessionState.value == SourceState.failed) 'Workouts',
    if (checkInState.value == SourceState.failed) 'Check-ins',
    if (nutritionState.value == SourceState.failed) 'Nutrition',
    if (lifestyleState.value == SourceState.failed) 'Lifestyle',
  ];

  /// True when every source SUCCEEDED and there is genuinely nothing recorded.
  ///
  /// 🔴 A FAILED SOURCE IS NOT AN EMPTY ACCOUNT. This getter used to test the
  /// lists alone, so a member whose reads failed — which is what a half-resolved
  /// link produces on a cold start — was shown "Your progress starts with one
  /// record" while they had months of training. That is the same "null is not
  /// zero" rule the rest of this module obeys, applied to the STATE of a source
  /// rather than the value of a metric: the screen may only offer the first-run
  /// invitation once it can prove there is nothing to show.
  bool get isEmpty =>
      !hasPartialFailure &&
      sessions.isEmpty &&
      checkIns.isEmpty &&
      nutrition.isEmpty &&
      lifestyle.isEmpty &&
      bodyPoints.isEmpty;

  /// The member identity the last bind actually ran against.
  ///
  /// Not a boolean, because "linked" and "readable" are different facts that
  /// resolve at different times — see [_rebindIfIdentityChanged].
  String _boundIdentity = '';

  /// ⚠️ `clientId` + `adminId` ONLY — deliberately NOT `uid`.
  ///
  /// Both of these read plain `Rx` values, whereas `member.uid` resolves
  /// `FirebaseAuth.instance`, and this getter runs from `ensureLoaded()` during
  /// the first build. Touching a Firebase singleton on a build path throws
  /// `[core/no-app]` wherever Firebase is not initialised — which is every
  /// widget test — and is the house rule this repo already learned the hard way
  /// ("never resolve a Firebase singleton in a field initializer; it has made
  /// four services untestable"). Nothing is lost: `uid` is fixed for the
  /// lifetime of a session, because a different member tears this controller
  /// down and builds a new one. The two ids below are the parts that actually
  /// arrive late, and they are the ones the reads wait for.
  String get _identity => '${member.clientId}|${member.adminId}';

  /// The coach-authored lifestyle goals the current [lifestyle] ratios were
  /// scored against.
  ///
  /// 🔴 THE DEFECT THIS CLOSES: a lifestyle ratio is `met / asked`, and the two
  /// halves come from DIFFERENT documents that change independently — the
  /// values from `coaching_rollups` (server-derived, changes when the member
  /// logs), the goals from `clients/{id}.lifestyleTargets` + `.supplementPlan`
  /// (coach-authored, changes when the COACH edits). The goals used to be read
  /// inside the rollup stream's listener, which pinned them to the instant a
  /// rollup happened to arrive. A coach edit lands on the live `clients`
  /// listener but does NOT write a rollup, so the new goal could not reach the
  /// member's score until they logged something else — and TrainerHQ scores the
  /// same member against the goals as they are NOW. Two apps, one member, one
  /// day, different Lifestyle numbers. Proven both ways in
  /// `test/progress_live_targets_test.dart`.
  ///
  /// `LifestyleHistoryController._signature()` already carried exactly this
  /// guard; Progress is the surface that missed it, so the shape is copied
  /// deliberately rather than reinvented.
  String _goalsSignature = '';

  static String _signatureOf(Map<String, dynamic>? client) {
    final stack = client?['supplementPlan'];
    return '${client?['lifestyleTargets']}|${stack is List ? stack.length : 0}';
  }

  /// The raw rollup days, kept so a goal change can be RE-SCORED in memory.
  ///
  /// Re-reading them would be the obvious fix and the wrong one: the values did
  /// not change, only the question asked of them, so a coach edit must cost
  /// zero Firestore reads. Pinned by the no-re-subscription test.
  final List<RollupDay> _lifestyleDays = [];

  void _rescoreLifestyle() {
    final goals = LifestyleGoals.fromClient(member.client.value);
    lifestyle.assignAll(lifestyleRatios(_lifestyleDays, goals));
  }

  /// Reacts to the live `clients` document: a new identity rebinds every read,
  /// a new GOAL re-scores lifestyle in memory, anything else costs nothing.
  void _onClientChanged() {
    if (_rebindIfIdentityChanged()) return;
    final signature = _signatureOf(member.client.value);
    if (signature == _goalsSignature) return;
    _goalsSignature = signature;
    // Only when the days are actually on the device. Mid-load the pending bind
    // will score against the new goals anyway.
    if (lifestyleState.value != SourceState.ready) return;
    _rescoreLifestyle();
    _bump();
  }

  /// Rebinds when the identity the READS require changes.
  ///
  /// 🔴 THE DEFECT THIS CLOSES: the rebind used to watch `member.isLinked`, which
  /// flips the moment `clientProfiles.linkedClientId` resolves. But every read
  /// here needs `adminId` too, and that arrives LATER, on the `clients` document
  /// stream. So on a cold start Progress bound twice — once with nothing, once
  /// with a clientId but no adminId — `canLog` was false both times, every read
  /// returned "unavailable", and because `isLinked` never changed a third time
  /// NOTHING EVER RETRIED. The member's own Progress screen stayed blank until
  /// they happened to pull-to-refresh. Proven on device:
  ///   `canLog=false docs=null linked=false clientId="" adminId=""`
  ///   `canLog=false docs=null linked=true  clientId="EkNg…" adminId=""`
  /// Watching the composite identity means the bind that succeeds is the one
  /// that runs when the link is actually usable, and a coach edit that does not
  /// change the identity costs no reads.
  /// Returns true when it consumed the change by rebinding.
  bool _rebindIfIdentityChanged() {
    if (_identity == _boundIdentity) return false;
    _boundIdentity = _identity;
    if (_loaded) _bindAll();
    return true;
  }

  @override
  void onInit() {
    super.onInit();
    // Rebind when the member's link resolves — a controller created before
    // `claim()` returns would otherwise stream nothing forever, the exact defect
    // that once left three member controllers permanently empty.
    _linkWorker = ever(member.isLinked, (_) => _rebindIfIdentityChanged());
    // …and again when the `clients` document lands, because that is what
    // carries `adminId`. Both workers funnel through the same identity guard,
    // so whichever resolves last triggers exactly one bind.
    _clientWorker = ever(member.client, (_) => _onClientChanged());
    final t = transformation;
    if (t != null) {
      // The transformation list is already streamed elsewhere; mirroring its
      // revisions is what keeps the body chart live without a second listener.
      _transformationWorker = ever(t.entries, (_) => _bump());
    }
  }

  /// Loads on first use. Safe to call on every build.
  void ensureLoaded() {
    if (_loaded) return;
    _loaded = true;
    _boundIdentity = _identity;
    _bindAll();
  }

  void _bindAll() {
    _bindSessions();
    _bindCheckIns();
    _bindRollups();
  }

  /// Re-attempts every source. Firestore snapshot streams are terminal on
  /// error, so recovery genuinely requires fresh subscriptions — this is the
  /// action the error surface's Retry offers, and it is also pull-to-refresh.
  Future<void> retry() async {
    if (!_loaded) {
      ensureLoaded();
      return;
    }
    _bindAll();
  }

  void _bump() {
    if (_closed) return;
    revision.value++;
  }

  // ── Workout sessions ──────────────────────────────────────────────────────

  /// Sessions are FETCHED, not streamed, and that is deliberate.
  ///
  /// `fetchSessionHistory` is the query `WorkoutHistoryController` already uses,
  /// so Progress adds no new query SHAPE and needs no new index. It is an
  /// equality-only read on `authorId` — auto-indexed, no composite required.
  ///
  /// ⚠️ IT IS UNBOUNDED. There is no `[authorId, date]` composite index, so a
  /// windowed server-side query is not available; the window is applied in
  /// memory by the shared core. For a member with years of history this grows.
  /// Recorded as a backend gap rather than worked around with a second read
  /// path that would double the cost for everyone to help nobody today.
  Future<void> _bindSessions() async {
    sessionState.value = SourceState.loading;
    final docs = await workoutLog.fetchSessionHistory();
    if (_closed) return;
    if (docs == null) {
      // NULL IS NOT EMPTY. `get()` answers from the local cache offline and does
      // not throw, so an unserved empty answer must read as "unavailable" — a
      // member with months of training being told they have never trained is
      // the exact defect this distinction exists to prevent.
      sessionState.value = SourceState.failed;
      _bump();
      return;
    }
    sessions.assignAll(analyticsSessions(docs));
    sessionState.value = SourceState.ready;
    _bump();
  }

  // ── Check-ins ─────────────────────────────────────────────────────────────

  void _bindCheckIns() {
    _checkInSub?.cancel();
    checkInState.value = SourceState.loading;
    _checkInSub = checkInService.watchMine().listen(
      (list) {
        if (_closed) return;
        checkIns.assignAll(list);
        checkInState.value = SourceState.ready;
        _bump();
      },
      onError: (_) {
        if (_closed) return;
        checkInState.value = SourceState.failed;
        _bump();
      },
    );
  }

  // ── Monthly rollups (nutrition + lifestyle) ───────────────────────────────

  void _bindRollups() {
    final months = range.value.months;
    _subscribedMonths = months;

    _nutritionSub?.cancel();
    nutritionState.value = SourceState.loading;
    _nutritionSub = nutritionService.watchDays(months: months, now: now).listen(
      (days) {
        if (_closed) return;
        nutrition.assignAll(nutritionRatios(days));
        nutritionState.value = SourceState.ready;
        _bump();
      },
      onError: (_) {
        if (_closed) return;
        nutritionState.value = SourceState.failed;
        _bump();
      },
    );

    _lifestyleSub?.cancel();
    lifestyleState.value = SourceState.loading;
    _lifestyleSub = lifestyleService.watchDays(months: months, now: now).listen(
      (days) {
        if (_closed) return;
        _lifestyleDays
          ..clear()
          ..addAll(days);
        _goalsSignature = _signatureOf(member.client.value);
        _rescoreLifestyle();
        lifestyleState.value = SourceState.ready;
        _bump();
      },
      onError: (_) {
        if (_closed) return;
        lifestyleState.value = SourceState.failed;
        _bump();
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // DERIVED — every value below is produced by the SHARED core. No math here.
  // ═══════════════════════════════════════════════════════════════════════

  int get windowDays => range.value.days;

  /// Body observations, RECONCILED across transformation checkpoints and weekly
  /// check-in packets — the two places a member records a weight.
  List<AnalyticsBodyPoint> get bodyPoints {
    final entries = transformation?.entries ?? const <TransformationEntry>[];
    return analyticsBodyPoints(entries);
  }

  List<TrendPoint> get weightSeries => reconciledWeightSeries(
    bodyPoints,
    checkInBodyPoints(checkIns),
  );

  /// The weight series clipped to the selected window. The FULL series stays
  /// available for the all-time net change, because a transformation is not a
  /// 30-day story and clipping it would understate the member's actual work.
  List<TrendPoint> get weightSeriesInRange {
    final start = now.subtract(Duration(days: windowDays));
    return [
      for (final p in weightSeries)
        if (!p.date.isBefore(start)) p,
    ];
  }

  List<String> get measurementKeys => presentMeasurementKeys(bodyPoints);

  List<TrendPoint> measurementFor(String key) =>
      measurementSeries(bodyPoints, key);

  List<TrendPoint> get workoutSeries =>
      workoutAdherenceSeries(sessions, now: now, windowDays: windowDays);

  List<TrendPoint> get nutritionSeries =>
      adherenceSeries(nutrition, now: now, windowDays: windowDays);

  List<TrendPoint> get lifestyleSeries =>
      adherenceSeries(lifestyle, now: now, windowDays: windowDays);

  List<TrendPoint> get volumeTrend =>
      volumeSeries(sessions, now: now, windowDays: windowDays);

  double get volume => totalVolume(sessions, now: now, windowDays: windowDays);

  int get exerciseVariety =>
      distinctExercises(sessions, now: now, windowDays: windowDays);

  int get trainingDays => activeDays(sessions, now: now, windowDays: windowDays);

  double get weeklyFrequency =>
      sessionsPerWeek(sessions, now: now, windowDays: windowDays);

  int get currentStreak => workoutStreak(sessions, now: now);

  int get bestStreak => longestWorkoutStreak(sessions);

  List<({String exercise, double weight, DateTime at})> get bests =>
      personalBests(sessions, limit: 5);

  List<({String key, String name, int sessions})> get strengthOptions =>
      weightedExercises(sessions);

  /// Which exercise the strength chart is showing. Null selects the
  /// most-logged weighted exercise, so the chart is never empty when a member
  /// has liftable history.
  final RxnString selectedExercise = RxnString();

  ({String key, String name})? get strengthExercise {
    final chosen = selectedExercise.value;
    if (chosen != null) {
      for (final o in strengthOptions) {
        if (o.key == chosen) return (key: o.key, name: o.name);
      }
    }
    return topWeightedExercise(sessions);
  }

  List<TrendPoint> get strengthTrend {
    final e = strengthExercise;
    if (e == null) return const [];
    return strengthSeries(sessions, e.key);
  }

  /// Distinct calendar days with ANY recorded activity, for momentum.
  List<DateTime> get activityDates => [
    for (final s in sessions) s.date,
    for (final r in nutrition) r.date,
    for (final r in lifestyle) r.date,
    for (final p in bodyPoints) p.date,
    for (final c in checkIns) ?c.submittedAt,
  ];

  /// Days since the member last recorded anything, or null when they never have.
  int? get daysSinceActive {
    final dates = activityDates;
    if (dates.isEmpty) return null;
    var latest = dates.first;
    for (final d in dates) {
      if (d.isAfter(latest)) latest = d;
    }
    final today = DateTime(now.year, now.month, now.day);
    final last = DateTime(latest.year, latest.month, latest.day);
    final diff = today.difference(last).inDays;
    // A future-dated record (device clock skew) must not read as negative days.
    return diff < 0 ? 0 : diff;
  }

  /// The scored dimensions behind the overview. A dimension with no scorable
  /// data in the window is ABSENT from this list — never present at 0%.
  List<ScoredDimension> get dimensions {
    final out = <ScoredDimension>[];

    final w = workoutAdherenceSummary(
      sessions,
      now: now,
      windowDays: windowDays,
    );
    if (w != null) {
      out.add(
        ScoredDimension(
          id: 'workout',
          label: 'Workout quality',
          value: w.value,
          direction: w.direction,
          sample: w.sample,
          confidence: w.confidence,
        ),
      );
    }

    final n = adherenceSummary(nutrition, now: now, windowDays: windowDays);
    if (n != null) {
      out.add(
        ScoredDimension(
          id: 'nutrition',
          label: 'Nutrition',
          value: n.value,
          direction: n.direction,
          sample: n.sample,
          confidence: n.confidence,
        ),
      );
    }

    final l = adherenceSummary(lifestyle, now: now, windowDays: windowDays);
    if (l != null) {
      out.add(
        ScoredDimension(
          id: 'lifestyle',
          label: 'Lifestyle',
          value: l.value,
          direction: l.direction,
          sample: l.sample,
          confidence: l.confidence,
        ),
      );
    }

    return out;
  }

  double? get score => overallScore(dimensions);

  ProgressDirection get direction => overallDirection(dimensions);

  ProgressVerdict get verdict => progressVerdict(
    score: score,
    overall: direction,
    daysSinceActive: daysSinceActive,
  );

  ({double recentRate, double priorRate, int recentDays, int halfWindow, ProgressDirection direction})?
  get momentumOf =>
      momentum(activityDates, now: now, windowDays: windowDays);

  /// How far back the training analytics can actually see.
  ///
  /// Sessions are fetched whole, so this is the member's real first logged day —
  /// which is what lets a "best streak" state its window honestly instead of
  /// implying it searched all of time.
  int get loadedHistoryDays {
    if (sessions.isEmpty) return 0;
    var earliest = sessions.first.date;
    for (final s in sessions) {
      if (s.date.isBefore(earliest)) earliest = s.date;
    }
    final d = now.difference(earliest).inDays;
    return d < 0 ? 0 : d;
  }

  List<ProgressInsight> get insights => buildInsights(
    dimensions: dimensions,
    windowDays: windowDays,
    currentStreak: currentStreak,
    longestStreak: bestStreak,
    streakWindowDays: loadedHistoryDays,
    bests: bests,
    weight: weightSeries,
    strengthExercise: strengthExercise,
    strength: strengthTrend,
  );

  @override
  void onClose() {
    _closed = true;
    _checkInSub?.cancel();
    _nutritionSub?.cancel();
    _lifestyleSub?.cancel();
    _linkWorker?.dispose();
    _clientWorker?.dispose();
    _transformationWorker?.dispose();
    super.onClose();
  }
}
