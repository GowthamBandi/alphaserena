import 'dart:async';

import 'package:get/get.dart';

import '../core/services/member_rollup_service.dart';
import '../core/utils/lifestyle_math.dart';

/// Which habit a history view is showing.
enum HabitKind { water, steps, sleep, supplements }

extension HabitKindX on HabitKind {
  String get label => switch (this) {
        HabitKind.water => 'Water',
        HabitKind.steps => 'Steps',
        HabitKind.sleep => 'Sleep',
        HabitKind.supplements => 'Supplements',
      };
}

/// Everything a history view needs about ONE habit, all derived from the same
/// streamed rollup days. No habit computes its own window, streak or trend.
class HabitHistory {
  final HabitKind kind;

  /// Local day → the day's value. Days the member never logged are ABSENT,
  /// never present-as-zero: "did not log" and "logged none" are different.
  final Map<DateTime, double> dayValues;

  /// The coach's goal, or null when none is set.
  final double? target;

  final double? avg7;
  final double? avg30;
  final int currentStreak;
  final int bestStreak;

  /// 1 up · 0 flat · -1 down, last 7 days against the prior 7.
  final int trend;

  final MapEntry<DateTime, double>? bestDay;
  final MapEntry<DateTime, double>? worstDay;

  const HabitHistory({
    required this.kind,
    required this.dayValues,
    required this.target,
    required this.avg7,
    required this.avg30,
    required this.currentStreak,
    required this.bestStreak,
    required this.trend,
    this.bestDay,
    this.worstDay,
  });

  bool get hasTarget => target != null && target! > 0;
  bool get hasData => dayValues.isNotEmpty;

  /// Share of LOGGED days that met the goal, or null when there is no goal or
  /// nothing logged. The denominator is logged days, never the calendar — an
  /// unlogged day is not a miss.
  double? get goalHitRate {
    if (!hasTarget || dayValues.isEmpty) return null;
    final hits = dayValues.values.where((v) => v >= target!).length;
    return hits / dayValues.length;
  }
}

/// PHASE — the member's own Lifestyle history.
///
/// Reads `coaching_rollups`, the SAME server-derived read model TrainerHQ
/// reads, so a member and their coach can never disagree about a past day.
/// Every statistic below comes from `lifestyle_math`, whose functions are
/// twins of TrainerHQ's and are pinned against them by a contract test — the
/// alternative was two apps computing streaks from the same data with two
/// implementations, which is how they drift.
class LifestyleHistoryController extends GetxController {
  LifestyleHistoryController({
    MemberRollupService? rollups,
    Map<String, dynamic>? Function()? clientDoc,
    DateTime? now,
  })  : _rollups = rollups ?? MemberRollupService(),
        _clientDoc = clientDoc,
        _anchor = now;

  final MemberRollupService _rollups;
  final Map<String, dynamic>? Function()? _clientDoc;

  /// Injectable clock — history is anchored to the member's LOCAL day, and a
  /// test that could not fix "today" would be testing the machine's date.
  final DateTime? _anchor;

  final RxList<RollupDay> days = <RollupDay>[].obs;
  final RxBool isLoading = true.obs;

  /// The read FAILED, as distinct from "nothing logged". Claiming a member
  /// logged nothing for three months because a read failed is the worst thing
  /// this screen could say.
  final RxBool loadError = false.obs;

  final Rx<HabitKind> selected = HabitKind.water.obs;

  StreamSubscription<List<RollupDay>>? _sub;
  bool _closed = false;

  DateTime get _now => _anchor ?? DateTime.now();

  @override
  void onInit() {
    super.onInit();
    bind();
  }

  @override
  void onClose() {
    _closed = true;
    _sub?.cancel();
    super.onClose();
  }

  void bind() {
    _sub?.cancel();
    isLoading.value = true;
    loadError.value = false;
    _sub = _rollups.watchDays(now: _now).listen(
      (list) {
        if (_closed) return;
        days.assignAll(list);
        _cache.clear();
        isLoading.value = false;
        loadError.value = false;
      },
      onError: (_) {
        if (_closed) return;
        isLoading.value = false;
        loadError.value = true;
      },
    );
  }

  void retry() => bind();
  void select(HabitKind kind) => selected.value = kind;

  /// Memoized per habit, invalidated whenever the stream emits.
  ///
  /// Without this the screen re-derived every window, streak and trend on each
  /// rebuild — four habits × several passes over three months of days, inside
  /// an `Obx`, on every frame the member scrolled.
  final Map<HabitKind, HabitHistory> _cache = {};

  HabitHistory historyFor(HabitKind kind) {
    // Touch the observables BEFORE the cache check. A memoized getter that
    // short-circuits without reading an Rx leaves the enclosing `Obx`
    // subscribed to nothing — the UI then silently stops updating, and GetX
    // throws outright when nothing at all was read.
    days.length;
    isLoading.value;
    return _cache[kind] ??= _build(kind);
  }

  double? _targetFor(HabitKind kind) {
    final doc = _clientDoc?.call();
    final raw = doc?['lifestyleTargets'];
    final t = raw is Map<String, dynamic>
        ? raw
        : (raw is Map ? Map<String, dynamic>.from(raw) : null);
    double? n(Object? v) {
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
      return null;
    }

    return switch (kind) {
      // Millilitres, matching the unit the rollup stores.
      HabitKind.water => n(t?['waterTargetMl']),
      HabitKind.steps => n(t?['stepsTarget']),
      HabitKind.sleep => n(t?['sleepHoursTarget']),
      // The coach's PRESCRIBED STACK SIZE, because the value is the number of
      // items taken. A target of 1.0 against a count would have scored "took
      // any one supplement" as a perfect day.
      //
      // The rollup carries only what was TAKEN — the prescribed snapshot is
      // not part of the read model — so the current stack is the denominator.
      // That is an approximation only for days the stack has since been
      // resized, and it is the same one TrainerHQ's `_prescribedFor` makes;
      // the alternative was a zero denominator, which reads as "nothing
      // prescribed" for every day.
      HabitKind.supplements => _stackSize()?.toDouble(),
    };
  }

  /// How many supplements the coach currently prescribes, or null when none.
  int? _stackSize() {
    final raw = _clientDoc?.call()?['supplementPlan'];
    if (raw is! List || raw.isEmpty) return null;
    return raw.length;
  }

  double? _valueOf(HabitKind kind, RollupDay d) => switch (kind) {
        HabitKind.water => d.waterMl,
        HabitKind.steps => d.steps,
        HabitKind.sleep => d.sleepHours,
        // Items TAKEN that day, scored against the prescribed stack size.
        HabitKind.supplements => d.supplementItems?.toDouble(),
      };

  HabitHistory _build(HabitKind kind) {
    final now = _now;
    final today = DateTime(now.year, now.month, now.day);
    final target = _targetFor(kind);

    final dayValues = <DateTime, double>{};
    for (final d in days) {
      final v = _valueOf(kind, d);
      if (v == null) continue;
      final day = DateTime(d.date.year, d.date.month, d.date.day);
      // A FUTURE-dated day is corrupt — a wrong device clock, or a bad key.
      // It cannot be part of a streak, an average or a hit rate about days
      // that have happened.
      if (day.isAfter(today)) continue;
      dayValues.putIfAbsent(day, () => v);
    }

    List<double> window(int fromDaysAgo, int toDaysAgo) {
      final from = now.subtract(Duration(days: fromDaysAgo));
      final to = now.subtract(Duration(days: toDaysAgo));
      return [
        for (final e in dayValues.entries)
          if (e.key.isAfter(from) && !e.key.isAfter(to)) e.value,
      ];
    }

    double? avg(List<double> xs) =>
        xs.isEmpty ? null : xs.reduce((a, b) => a + b) / xs.length;

    final hits = <DateTime>{
      for (final e in dayValues.entries)
        if (target != null && target > 0 && e.value >= target) e.key,
    };
    final streaks = habitStreaks(hits, now);

    return HabitHistory(
      kind: kind,
      dayValues: dayValues,
      target: target,
      avg7: avg(window(7, 0)),
      avg30: avg(window(30, 0)),
      currentStreak: streaks.current,
      bestStreak: streaks.best,
      trend: trendDirection(avg(window(7, 0)), avg(window(14, 7))),
      bestDay: extremeDayFor(dayValues, best: true),
      worstDay: extremeDayFor(dayValues, best: false),
    );
  }
}
