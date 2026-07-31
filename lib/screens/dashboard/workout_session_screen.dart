import 'dart:async';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/streak_controller.dart';
import '../../controllers/training_controller.dart';
import '../../core/domain/today_expectation.dart' show localDayKey;
import '../../core/domain/workout_memory.dart';
import '../../core/domain/workout_session.dart';
import '../../core/services/workout_draft_store.dart';
import '../../core/services/workout_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/gradient_button.dart';
import 'workout_player_screen.dart';
import 'workout_rest_overlay.dart';
import 'workout_summary_screen.dart';

// ── In-session state (UI wrapper over the pure SetLog) ────────────────
class _SetState {
  final SetLog log;
  final TextEditingController reps;
  final TextEditingController weight;

  _SetState(this.log)
      : reps = TextEditingController(text: log.actualReps),
        weight = TextEditingController(text: log.actualWeight);

  void syncIntoLog() {
    log.actualReps = reps.text.trim();
    log.actualWeight = weight.text.trim();
  }

  bool get completed => log.state == SetLogState.completed;
  bool get skipped => log.state == SetLogState.skipped;

  void dispose() {
    reps.dispose();
    weight.dispose();
  }
}

class _ExState {
  final ExerciseLog log;
  final String muscle;
  final List<_SetState> sets;
  int activeSet;

  _ExState({
    required this.log,
    required this.muscle,
    required this.sets,
  }) : activeSet = firstOpenIndex(sets.map((s) => s.log).toList());

  String get name => log.name;
  int get completedCount => sets.where((s) => s.completed).length;
  int get resolvedCount =>
      sets.where((s) => s.log.state != SetLogState.pending).length;
  bool get done =>
      sets.isNotEmpty && sets.every((s) => s.log.state != SetLogState.pending);
}

/// Index of the first set still awaiting a decision.
int firstOpenIndex(List<SetLog> sets) {
  for (var i = 0; i < sets.length; i++) {
    if (sets[i].state == SetLogState.pending) return i;
  }
  return sets.length;
}

/// THE GUIDED SESSION — one exercise, one set, one decision at a time.
///
/// Phase 2 (guided experience) on top of Phase 1 (integrity, unchanged):
/// lazy session creation, deterministic identity, draft autosave, resume,
/// skip/undo and the back-guard are all preserved exactly — this rework
/// changes what the member SEES, never what the app records.
///
/// Design rules, from watching how a trainer actually runs a floor session:
///  • The screen answers "what now?" in one glance: the current set, its
///    target, two inputs, one big button. Everything else is secondary.
///  • Position is always visible — exercise N of M, set N of M, and a
///    session-wide progress bar — so nobody is ever lost mid-workout.
///  • Targets PREFILL the inputs. The coach already said "10 × 40"; making
///    the member retype it is data entry, not coaching. The values are
///    visible and editable before the affirmative Complete tap.
///  • "Last time" appears when real history exists, and stays silent when
///    it does not.
class WorkoutSessionScreen extends StatefulWidget {
  const WorkoutSessionScreen({super.key});

  @override
  State<WorkoutSessionScreen> createState() => _WorkoutSessionScreenState();
}

class _WorkoutSessionScreenState extends State<WorkoutSessionScreen> {
  final TrainingController _training = Get.isRegistered<TrainingController>()
      ? Get.find<TrainingController>()
      : Get.put(TrainingController());
  final WorkoutLogService _log = WorkoutLogService();
  final WorkoutDraftStore _drafts = WorkoutDraftStore();

  List<_ExState> _exercises = [];
  late final String _planName;
  final DateTime _sessionDate = DateTime.now();
  String _sessionId = '';
  int? _startedAtMillis;
  int? _finishedAtMillis;
  bool _savedOnce = false;
  bool _finishedRemotely = false;

  /// Real per-exercise history ("last time"), loaded best-effort.
  Map<String, ExerciseMemory> _memory = const {};

  /// Sets reopened for correction this session — a re-complete marks the set
  /// `edited` so the coach knows the number was revised, not logged live.
  final Set<String> _reopened = {};

  WorkoutSaveResult? _lastSave;
  bool _booting = true;
  bool _finishing = false;

  /// Wall-clock stamp of the last set completion. When a set has no
  /// prescribed rest there is no overlay barrier after Complete, so a fast
  /// accidental double-tap landed on the NEXT set's freshly-prefilled button
  /// and logged work that never happened. A deliberate second tap — read the
  /// new set, decide, tap — takes well over this window.
  int _lastCompleteMillis = 0;
  int _current = 0;
  Timer? _draftDebounce;

  @override
  void initState() {
    super.initState();
    _planName = _training.workout.value?['name']?.toString() ?? 'Workout';
    _bootstrap();
  }

  // ── Bootstrap: draft → remote same-day doc → fresh (in that order) ───
  Future<void> _bootstrap() async {
    final dayKey = localDayKey(_sessionDate);
    final baseId = workoutSessionIdFor(_log.clientId, _sessionDate);

    final draft = await _drafts.load();
    if (draft != null && draft.dayKey == dayKey && draft.exercises.isNotEmpty) {
      _restoreFrom(
        draft.exercises,
        sessionId: draft.sessionId,
        startedAt: draft.startedAtMillis,
        current: draft.currentExercise,
        savedOnce: hasMeaningfulActivity(draft.exercises),
      );
      _loadMemory();
      return;
    }

    if (_log.clientId.isNotEmpty) {
      final doc = await _log.fetchSession(baseId);
      if (doc != null) {
        final logs = exercisesFromEntries(doc['entries']);
        if (logs.isNotEmpty) {
          final finished = (doc['status'] ?? '') == kSessionCompleted;
          _restoreFrom(
            logs,
            sessionId: baseId,
            startedAt: _millisOf(doc['startedAt']),
            current: 0,
            savedOnce: true,
            finished: finished,
          );
          _loadMemory();
          if (finished) _offerFinishedChoice();
          return;
        }
      }
    }

    // Fresh. NOTE: no doc is written here — the session does not exist until
    // the first completed/skipped set (Phase 1 integrity gate).
    _restoreFrom(
      exercisesFromServedItems(_training.workoutItems),
      sessionId: baseId,
      startedAt: null,
      current: 0,
      savedOnce: false,
    );
    _loadMemory();
  }

  /// Best-effort: memory enriches the session but must never delay or block
  /// it, and an unreadable history stays silent rather than guessing.
  Future<void> _loadMemory() async {
    final sessions = await _log.fetchRecentSessions();
    if (!mounted || sessions.isEmpty) return;
    setState(() {
      _memory = buildExerciseMemory(sessions, excludeId: _sessionId);
    });
  }

  void _restoreFrom(
    List<ExerciseLog> logs, {
    required String sessionId,
    required int? startedAt,
    required int current,
    required bool savedOnce,
    bool finished = false,
  }) {
    final served = _training.workoutItems;
    // A second restore ("Start another" after a finished day) replaces the
    // whole list — the outgoing TextEditingControllers must be released, not
    // abandoned. No-op on first boot when the list is empty.
    for (final ex in _exercises) {
      for (final st in ex.sets) {
        st.dispose();
      }
    }
    _exercises = [
      for (var i = 0; i < logs.length; i++)
        _ExState(
          log: logs[i],
          muscle: i < served.length
              ? (served[i]['muscleGroup'] ?? '').toString()
              : '',
          sets: logs[i].sets.map(_SetState.new).toList(),
        ),
    ];
    _sessionId = sessionId;
    _startedAtMillis = startedAt;
    _savedOnce = savedOnce;
    _finishedRemotely = finished;
    _current = current.clamp(0, _exercises.isEmpty ? 0 : _exercises.length - 1);
    for (final ex in _exercises) {
      for (final s in ex.sets) {
        s.reps.addListener(_onFieldChanged);
        s.weight.addListener(_onFieldChanged);
      }
    }
    _booting = false;
    _prefillActive();
    if (mounted) setState(() {});
  }

  /// The coach already prescribed the numbers; the member confirms or edits
  /// them. Only ever fills EMPTY fields on a pending set — a typed value is
  /// never overwritten.
  void _prefillActive() {
    if (_current >= _exercises.length) return;
    final ex = _exercises[_current];
    if (ex.activeSet >= ex.sets.length) return;
    final s = ex.sets[ex.activeSet];
    if (s.log.state != SetLogState.pending) return;
    if (s.reps.text.isEmpty && s.log.pReps.isNotEmpty) {
      s.reps.text = s.log.pReps;
    }
    if (s.weight.text.isEmpty && s.log.pWeight.isNotEmpty) {
      s.weight.text = s.log.pWeight;
    }
  }

  Future<void> _offerFinishedChoice() async {
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    final startNew = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Today's workout is finished"),
        content: const Text(
          'You can review and correct it, or deliberately start a second '
          'session for today.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Review & edit'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Start another'),
          ),
        ],
      ),
    );
    if (startNew == true && mounted) {
      // FIRST FREE RUN SLOT — not a hardcoded run 2. When run 2 already
      // exists (the member finished a second session, cleared the draft, and
      // reopened), starting "another" at run 2 would merge-write a fresh
      // entries array over the finished doc and destroy its logged sets.
      // Probe upward (cache-first fetch, so this works offline for docs the
      // device has seen) and take the first id that holds no entries.
      var run = 2;
      while (run < 10) {
        final existing = await _log.fetchSession(
          workoutSessionIdFor(_log.clientId, _sessionDate, run: run),
        );
        final hasEntries =
            existing != null && (existing['entries'] as List?)?.isNotEmpty == true;
        if (!hasEntries) break;
        run++;
      }
      if (!mounted) return;
      _restoreFrom(
        exercisesFromServedItems(_training.workoutItems),
        sessionId: workoutSessionIdFor(_log.clientId, _sessionDate, run: run),
        startedAt: null,
        current: 0,
        savedOnce: false,
      );
    }
  }

  int? _millisOf(dynamic v) {
    try {
      final d = (v as dynamic).toDate();
      if (d is DateTime) return d.millisecondsSinceEpoch;
    } catch (_) {}
    return null;
  }

  // ── Draft autosave ───────────────────────────────────────────────────
  void _onFieldChanged() {
    _draftDebounce?.cancel();
    _draftDebounce = Timer(const Duration(milliseconds: 500), _saveDraft);
  }

  Future<void> _saveDraft() async {
    for (final ex in _exercises) {
      for (final s in ex.sets) {
        s.syncIntoLog();
      }
    }
    await _drafts.save(WorkoutDraft(
      sessionId: _sessionId,
      dayKey: localDayKey(_sessionDate),
      planName: _planName,
      startedAtMillis: _startedAtMillis,
      currentExercise: _current,
      exercises: _exercises.map((e) => e.log).toList(),
    ));
  }

  @override
  void dispose() {
    _draftDebounce?.cancel();
    for (final ex in _exercises) {
      for (final s in ex.sets) {
        s.dispose();
      }
    }
    super.dispose();
  }

  // ── Navigation between exercises ─────────────────────────────────────
  void _goTo(int index) {
    if (index < 0 || index >= _exercises.length) return;
    setState(() => _current = index);
    _prefillActive();
    _saveDraft();
  }

  int _parseRest(String s) {
    final m = RegExp(r'\d+').firstMatch(s);
    return m != null ? int.parse(m.group(0)!) : 0;
  }

  bool get _meaningful =>
      hasMeaningfulActivity(_exercises.map((e) => e.log).toList());

  String _key(int exIndex, int setIndex) => '$exIndex:$setIndex';

  // ── Set actions: complete · skip · undo ──────────────────────────────
  Future<void> _completeSet(_ExState ex, int setIndex) async {
    if (_finishing) return; // spam guard
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (nowMs - _lastCompleteMillis < 400) return; // double-tap guard
    _lastCompleteMillis = nowMs;
    setState(() {
      ex.sets[setIndex].syncIntoLog();
      if (_reopened.remove(_key(_current, setIndex))) {
        ex.sets[setIndex].log.edited = true;
      }
      ex.sets[setIndex].log.state = SetLogState.completed;
      ex.activeSet = firstOpenIndex(ex.sets.map((s) => s.log).toList());
    });
    _prefillActive();

    // THE REST-TIMER DELAY, root-caused. This used to `await _persist()`
    // BEFORE showing the overlay — and _persist's remote save waits up to
    // `WorkoutLogService.ackTimeout` (4s) for a server ack on a slow network,
    // the full 4s offline. The member finished a set and stared at a frozen
    // screen while their rest clock silently ran. Rest is a WALL-CLOCK fact
    // that starts the moment the set ends; persistence is bookkeeping.
    //
    // The overlay now opens immediately and the save runs alongside it.
    // Ordering is safe: the logs were already mutated above, _saveRemote
    // serializes the FULL entries array (last write wins, no partial merge),
    // and the save result still surfaces through `_lastSave`'s banners the
    // moment it lands. Errors cannot be lost — _persist reports through
    // state, not through the return value.
    final persisted = _persist();

    final next = ex.activeSet;
    if (next < ex.sets.length && next == setIndex + 1) {
      final rest = _parseRest(ex.sets[setIndex].log.pRest);
      if (rest > 0 && mounted) {
        await _showRest(rest, next + 1);
      }
    }
    await persisted;
  }

  Future<void> _skipSet(_ExState ex, int setIndex) async {
    setState(() {
      ex.sets[setIndex].log.state = SetLogState.skipped;
      ex.activeSet = firstOpenIndex(ex.sets.map((s) => s.log).toList());
    });
    _prefillActive();
    await _persist();
  }

  Future<void> _reopenSet(_ExState ex, int setIndex) async {
    setState(() {
      _reopened.add(_key(_current, setIndex));
      ex.sets[setIndex].log.state = SetLogState.pending;
      ex.activeSet = setIndex;
    });
    await _persist();
  }

  Future<void> _skipExercise(_ExState ex) async {
    final reason = await _pickSkipReason();
    if (reason == null || !mounted) return;
    setState(() {
      ex.log.skipped = true;
      ex.log.skipReason = reason;
      for (final s in ex.sets) {
        if (s.log.state == SetLogState.pending) {
          s.log.state = SetLogState.skipped;
        }
      }
      ex.activeSet = ex.sets.length;
    });
    await _persist();
    if (!mounted) return;
    if (_current < _exercises.length - 1) _goTo(_current + 1);
  }

  Future<void> _unskipExercise(_ExState ex) async {
    setState(() {
      ex.log.skipped = false;
      ex.log.skipReason = '';
      // Reopen EVERY skipped set — completed sets keep their numbers.
      //
      // This used to guard on "actuals still empty", trying to preserve sets
      // the member had skipped individually before skipping the exercise.
      // That heuristic was never true in practice: prefill writes the coach's
      // targets into the input fields, the field listeners debounce a draft
      // save, and _saveDraft syncs EVERY field into its log — so a pending
      // set's actuals are already populated the moment it has been LOOKED at.
      // Undo then un-flagged the exercise while every set stayed skipped:
      // the member pressed Undo and nothing visibly reopened. A bulk skip
      // deserves a bulk undo; re-skipping one set is a single tap.
      for (final s in ex.sets) {
        if (s.log.state == SetLogState.skipped) {
          s.log.state = SetLogState.pending;
        }
      }
      ex.activeSet = firstOpenIndex(ex.sets.map((s) => s.log).toList());
    });
    _prefillActive();
    await _persist();
  }

  Future<String?> _pickSkipReason() {
    final p = context.palette;
    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Skip this exercise?',
                  style:
                      AppText.title(size: 16).copyWith(color: p.textPrimary)),
              const SizedBox(height: 4),
              Text(
                'Your coach sees the reason — skipping honestly is always '
                'better than a silent gap.',
                style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 14),
              for (final r in kSkipReasons)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading:
                      Icon(Icons.block_rounded, size: 18, color: p.textMuted),
                  title: Text(r,
                      style: AppText.body(size: 13.5)
                          .copyWith(color: p.textPrimary)),
                  onTap: () => Navigator.of(ctx).pop(r),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showRest(int seconds, int nextSetNumber) {
    final p = context.palette;
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'rest',
      barrierColor: Colors.black.withValues(alpha: 0.88),
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, _, _) => RestOverlay(
        seconds: seconds,
        nextSetNumber: nextSetNumber,
        accent: p.accent,
        reminder: restReminderFor(nextSetNumber),
      ),
    );
  }

  // ── Persistence ──────────────────────────────────────────────────────
  Future<void> _persist() async {
    await _saveDraft();
    if (!_meaningful) return;
    _startedAtMillis ??= DateTime.now().millisecondsSinceEpoch;
    await _saveRemote(status: kSessionInProgress);
  }

  Future<void> _saveRemote({required String status}) async {
    for (final ex in _exercises) {
      for (final s in ex.sets) {
        s.syncIntoLog();
      }
    }
    final result = await _log.saveSession(
      sessionId: _sessionId,
      planName: _planName,
      date: _sessionDate,
      entries: buildSessionEntries(_exercises.map((e) => e.log).toList()),
      status: status,
      startedAt: _startedAtMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(_startedAtMillis!)
          : null,
      finishedAt: _finishedAtMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(_finishedAtMillis!)
          : null,
      durationSeconds:
          sessionDurationSeconds(_startedAtMillis, _finishedAtMillis),
      markCreated: !_savedOnce,
    );
    if (!mounted) return;
    setState(() => _lastSave = result);
    if (result != WorkoutSaveResult.failed) {
      _savedOnce = true;
      final logs = _exercises.map((e) => e.log).toList();
      if (hasCompletedWork(logs) && Get.isRegistered<StreakController>()) {
        // Live progress rides along so Home's completion chip shows the REAL
        // fraction ("42% done"), not a binary flip at the first saved set —
        // and the resume POINT travels with it, so leaving mid-session lands
        // the member on a Home card that names the exact next set.
        Get.find<StreakController>().markWorkoutToday(
          stats: computeSessionStats(logs),
          nextUp: nextUpFrom(logs),
        );
      }
    }
  }

  Future<void> _finish() async {
    if (_finishing) return; // double-tap guard
    setState(() => _finishing = true);
    if (!_meaningful) {
      await _drafts.clear();
      if (mounted) Get.back();
      return;
    }
    _finishedAtMillis = DateTime.now().millisecondsSinceEpoch;
    await _saveRemote(status: kSessionCompleted);
    if (!mounted) return;
    if (_lastSave == WorkoutSaveResult.failed) {
      setState(() {
        _finishedAtMillis = null;
        _finishing = false;
      });
      return;
    }
    await _drafts.clear();
    if (!mounted) return;
    final stats = computeSessionStats(_exercises.map((e) => e.log).toList());
    // Replace the session with the summary: the workout is over, so there is
    // nothing to come back to — and no dead end either (Done → Home).
    Get.off(
      () => WorkoutSummaryScreen(
        sessionId: _sessionId,
        planName: _planName,
        stats: stats,
        durationSeconds:
            sessionDurationSeconds(_startedAtMillis, _finishedAtMillis),
        queued: _lastSave == WorkoutSaveResult.queued,
      ),
    );
  }

  // ── Back protection ──────────────────────────────────────────────────
  Future<void> _onPopAttempt() async {
    if (!_meaningful || _finishedRemotely) {
      if (!_meaningful) await _drafts.clear();
      if (mounted) Get.back();
      return;
    }
    final p = context.palette;
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave workout?'),
        content: Text(
          'Your progress is saved — you can resume exactly where you '
          'stopped, today.',
          style: AppText.body(size: 13).copyWith(color: p.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('stay'),
            child: const Text('Keep training'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop('leave'),
            child: const Text('Save & leave'),
          ),
        ],
      ),
    );
    if (choice == 'leave' && mounted) {
      await _saveDraft();
      if (mounted) Get.back();
    }
  }

  // ── Session-wide progress ────────────────────────────────────────────
  ({int done, int total}) get _sessionProgress {
    var done = 0;
    var total = 0;
    for (final ex in _exercises) {
      total += ex.sets.length;
      done += ex.resolvedCount;
    }
    return (done: done, total: total);
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    if (_booting) {
      return Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          backgroundColor: p.background,
          elevation: 0,
          iconTheme: IconThemeData(color: p.textPrimary),
        ),
        body: Center(
          child: CircularProgressIndicator(strokeWidth: 2.4, color: p.accent),
        ),
      );
    }
    if (_exercises.isEmpty) return _noWorkout(p);

    final ex = _exercises[_current];
    final progress = _sessionProgress;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _onPopAttempt();
      },
      child: Scaffold(
        backgroundColor: p.background,
        appBar: AppBar(
          backgroundColor: p.background,
          elevation: 0,
          iconTheme: IconThemeData(color: p.textPrimary),
          title: Text('Exercise ${_current + 1} of ${_exercises.length}',
              style:
                  AppText.cardTitle(size: 15).copyWith(color: p.textPrimary)),
          actions: [
            if (!ex.log.skipped && !ex.done)
              TextButton(
                onPressed: () => _skipExercise(ex),
                child: Text('Skip',
                    style:
                        AppText.label(size: 13).copyWith(color: p.textMuted)),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(3),
            child: LinearProgressIndicator(
              value: progress.total == 0 ? 0 : progress.done / progress.total,
              minHeight: 3,
              backgroundColor: p.surfaceAlt,
              valueColor: AlwaysStoppedAnimation(p.accent),
            ),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                  children: [
                    _exerciseHeader(p, ex),
                    const SizedBox(height: 14),
                    if (ex.log.skipped) ...[
                      _skippedBanner(p, ex),
                      const SizedBox(height: 14),
                    ],
                    if (ex.sets.isEmpty)
                      _noSetsNote(p)
                    else if (ex.done)
                      _exerciseDoneCard(p, ex)
                    else
                      _setFocus(p, ex),
                    const SizedBox(height: 14),
                    _setsStrip(p, ex),
                    if (_lastSave == WorkoutSaveResult.failed) ...[
                      const SizedBox(height: 14),
                      _saveErrorBanner(p),
                    ] else if (_lastSave == WorkoutSaveResult.queued) ...[
                      const SizedBox(height: 14),
                      _queuedBanner(p),
                    ],
                  ],
                ),
              ),
              _bottomBar(p),
            ],
          ),
        ),
      ),
    );
  }

  /// The SERVED item backing [ex] — by exerciseId first (survives reorders),
  /// then by name (freehand items), then by index. Null when the served plan
  /// no longer contains it (e.g. the coach edited the plan mid-session).
  Map<String, dynamic>? _servedItemFor(_ExState ex, int index) {
    final served = _training.workoutItems;
    final id = ex.log.exerciseId;
    if (id.isNotEmpty) {
      for (final it in served) {
        if ((it['exerciseId'] ?? '').toString() == id) return it;
      }
    }
    for (final it in served) {
      if ((it['name'] ?? '').toString() == ex.name) return it;
    }
    return index < served.length ? served[index] : null;
  }

  Widget _exerciseHeader(AppPalette p, _ExState ex) {
    final mem = _memory[exerciseMemoryKey(ex.log.exerciseId, ex.name)];
    // MEDIA + INSTRUCTIONS, finally reachable from the floor. The backend
    // serves videoUrl/instructions/equipment/difficulty per item and the
    // detail screen has always rendered them — but the SESSION, the one place
    // a member actually needs "how do I do this", had no route to it. The
    // coach's authored guidance was one navigation away from the only moment
    // it matters. One header action closes that; nothing is redesigned.
    final servedItem = _servedItemFor(ex, _current);
    final hasGuidance = servedItem != null &&
        (((servedItem['videoUrl'] ?? '').toString().isNotEmpty) ||
            ((servedItem['instructions'] ?? '').toString().isNotEmpty));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Text(ex.name,
                  style: AppText.title(size: 26).copyWith(color: p.textPrimary)),
            ),
            if (hasGuidance)
              Semantics(
                button: true,
                label: 'How to do ${ex.name}',
                excludeSemantics: true,
                child: TextButton.icon(
                  onPressed: () =>
                      Get.to(() => WorkoutPlayerScreen(exercise: servedItem)),
                  style: TextButton.styleFrom(
                    foregroundColor: p.accent,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 8),
                  ),
                  icon: const Icon(Icons.play_circle_outline, size: 18),
                  label: Text('How to',
                      style: AppText.label(size: 12.5)),
                ),
              ),
          ],
        ),
        if (ex.muscle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(ex.muscle,
                style: AppText.body(size: 13).copyWith(color: p.textMuted)),
          ),
        // EXERCISE MEMORY — real logged history only; silent when there is
        // none. Never a prediction, never a target.
        if (mem != null)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Row(
              children: [
                Icon(Icons.history_rounded, size: 15, color: p.accent),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    'Last time ${mem.ago(DateTime.now())}: ${mem.summary}',
                    style: AppText.body(size: 12.5)
                        .copyWith(color: p.textSecondary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// THE FOCUS — the current set, its target, two inputs, one big button.
  Widget _setFocus(AppPalette p, _ExState ex) {
    final i = ex.activeSet;
    final s = ex.sets[i];
    final target = [
      if (s.log.pReps.isNotEmpty) '${s.log.pReps} reps',
      if (s.log.pWeight.isNotEmpty) '${s.log.pWeight} kg',
    ].join('  ×  ');

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.accent, width: 1.4),
        boxShadow: [
          BoxShadow(
            color: p.accent.withValues(alpha: 0.14),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('SET ${i + 1} OF ${ex.sets.length}',
                  style: AppText.label(size: 12.5)
                      .copyWith(color: p.accent, letterSpacing: 1.6)),
              const Spacer(),
              if (s.log.pRest.isNotEmpty && _parseRest(s.log.pRest) > 0)
                Text('rest ${_parseRest(s.log.pRest)}s',
                    style:
                        AppText.body(size: 11.5).copyWith(color: p.textMuted)),
            ],
          ),
          if (target.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(target,
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 30,
                  height: 1.1,
                  fontWeight: FontWeight.w800,
                )),
            const SizedBox(height: 2),
            Text('your coach\'s target for this set',
                style: AppText.body(size: 11.5).copyWith(color: p.textMuted)),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _input(p, s.reps, 'Reps done', '')),
              const SizedBox(width: 12),
              Expanded(child: _input(p, s.weight, 'Weight', 'kg')),
            ],
          ),
          const SizedBox(height: 16),
          GradientButton(
            label: 'Complete Set ${i + 1}',
            showChevron: true,
            onPressed: () => _completeSet(ex, i),
          ),
          const SizedBox(height: 2),
          Center(
            child: TextButton(
              onPressed: () => _skipSet(ex, i),
              child: Text('Skip this set',
                  style: AppText.label(size: 12).copyWith(color: p.textMuted)),
            ),
          ),
        ],
      ),
    );
  }

  /// Every set resolved — the exercise is done, and the next action is the
  /// only thing on screen. No dead end, no hunting for a button.
  Widget _exerciseDoneCard(AppPalette p, _ExState ex) {
    final isLast = _current == _exercises.length - 1;
    final skipped = ex.sets.where((s) => s.skipped).length;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: p.success.withValues(alpha: 0.08),
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.success.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          Icon(Icons.check_circle_rounded, color: p.success, size: 38),
          const SizedBox(height: 10),
          Text(
            ex.log.skipped ? 'Exercise skipped' : '${ex.name} done',
            textAlign: TextAlign.center,
            style: AppText.title(size: 17).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            skipped > 0
                ? '${ex.completedCount} completed · $skipped skipped'
                : '${ex.completedCount} of ${ex.sets.length} sets completed',
            style: AppText.body(size: 12.5).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 14),
          GradientButton(
            label: isLast ? 'Finish Workout' : 'Next Exercise',
            showChevron: true,
            onPressed: isLast ? _finish : () => _goTo(_current + 1),
          ),
        ],
      ),
    );
  }

  /// Compact record of the exercise's sets — tap any resolved one to correct
  /// it (undo is one tap, never a menu).
  Widget _setsStrip(AppPalette p, _ExState ex) {
    if (ex.sets.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('THIS EXERCISE',
            style: AppText.label(size: 11)
                .copyWith(color: p.textMuted, letterSpacing: 1.4)),
        const SizedBox(height: 8),
        for (var i = 0; i < ex.sets.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: _setRow(p, ex, i),
          ),
      ],
    );
  }

  Widget _setRow(AppPalette p, _ExState ex, int i) {
    final s = ex.sets[i];
    final isActive = !ex.done && i == ex.activeSet;
    final resolved = s.completed || s.skipped;
    final done = s.completed
        ? [
            if (s.reps.text.trim().isNotEmpty) s.reps.text.trim(),
            if (s.weight.text.trim().isNotEmpty) '${s.weight.text.trim()}kg',
          ].join(' × ')
        : '';

    return Semantics(
      button: resolved,
      label: resolved
          ? 'Set ${i + 1}, ${s.completed ? 'completed $done' : 'skipped'}. '
              'Tap to correct'
          : 'Set ${i + 1}, ${isActive ? 'current' : 'upcoming'}',
      excludeSemantics: true,
      child: InkWell(
        borderRadius: AppRadii.smR,
        onTap: resolved ? () => _reopenSet(ex, i) : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: s.completed
                ? p.success.withValues(alpha: 0.08)
                : isActive
                    ? p.accent.withValues(alpha: 0.06)
                    : p.surface,
            borderRadius: AppRadii.smR,
            border: Border.all(
              color: s.completed
                  ? p.success.withValues(alpha: 0.35)
                  : isActive
                      ? p.accent.withValues(alpha: 0.5)
                      : p.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                s.completed
                    ? Icons.check_circle
                    : s.skipped
                        ? Icons.remove_circle_outline
                        : isActive
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                size: 17,
                color: s.completed
                    ? p.success
                    : isActive
                        ? p.accent
                        : p.textMuted,
              ),
              const SizedBox(width: 10),
              Text('Set ${i + 1}',
                  style: AppText.label(size: 12.5)
                      .copyWith(color: p.textPrimary)),
              const Spacer(),
              Text(
                s.completed
                    ? (done.isEmpty ? 'done' : done)
                    : s.skipped
                        ? 'skipped'
                        : [
                            if (s.log.pReps.isNotEmpty) s.log.pReps,
                            if (s.log.pWeight.isNotEmpty) '${s.log.pWeight}kg',
                          ].join(' × '),
                style: AppText.body(size: 12).copyWith(
                  color: s.completed ? p.textSecondary : p.textMuted,
                ),
              ),
              if (s.log.edited) ...[
                const SizedBox(width: 6),
                Text('edited',
                    style: AppText.body(size: 10)
                        .copyWith(color: p.textMuted)),
              ],
              if (resolved) ...[
                const SizedBox(width: 6),
                Icon(Icons.edit_outlined, size: 13, color: p.textMuted),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _skippedBanner(AppPalette p, _ExState ex) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: AppRadii.smR,
        color: p.surfaceAlt.withValues(alpha: 0.6),
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.block_rounded, size: 16, color: p.textMuted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Skipped — ${ex.log.skipReason.isEmpty ? 'no reason given' : ex.log.skipReason}',
              style: AppText.body(size: 12).copyWith(color: p.textSecondary),
            ),
          ),
          TextButton(
            onPressed: () => _unskipExercise(ex),
            child: Text('Undo',
                style: AppText.label(size: 12).copyWith(color: p.accent)),
          ),
        ],
      ),
    );
  }

  Widget _input(
      AppPalette p, TextEditingController ctrl, String label, String suffix) {
    return TextField(
      controller: ctrl,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      cursorColor: p.accent,
      style: TextStyle(
        color: p.textPrimary,
        fontWeight: FontWeight.w700,
        fontSize: 18,
      ),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: p.textMuted, fontSize: 13),
        suffixText: suffix.isEmpty ? null : suffix,
        filled: true,
        fillColor: p.inputFill,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
        enabledBorder: OutlineInputBorder(
            borderRadius: AppRadii.smR, borderSide: BorderSide(color: p.border)),
        focusedBorder: OutlineInputBorder(
            borderRadius: AppRadii.smR,
            borderSide: BorderSide(color: p.accent, width: 1.4)),
      ),
    );
  }

  // ── Bottom bar (prev / next / finish) ────────────────────────────────
  Widget _bottomBar(AppPalette p) {
    final isLast = _current == _exercises.length - 1;
    final ex = _exercises[_current];
    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 10, 16, 10 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Row(
        children: [
          if (_current > 0)
            _navBtn(p, Icons.arrow_back_rounded, 'Prev',
                () => _goTo(_current - 1)),
          if (_current > 0) const SizedBox(width: 12),
          Expanded(
            child: isLast
                ? _navBtnWide(
                    p,
                    _finishing ? 'Finishing…' : 'Finish Workout',
                    Icons.flag_rounded,
                    _finishing ? null : _finish,
                  )
                : _navBtnWide(
                    p,
                    ex.done ? 'Next Exercise' : 'Skip to next',
                    Icons.arrow_forward_rounded,
                    () => _goTo(_current + 1),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _navBtn(AppPalette p, IconData icon, String label, VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: p.textPrimary,
        side: BorderSide(color: p.border),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.smR),
      ),
      icon: Icon(icon, size: 18),
      label: Text(label, style: AppText.label(size: 13)),
    );
  }

  Widget _navBtnWide(
      AppPalette p, String label, IconData icon, VoidCallback? onTap) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: p.accent,
        side: BorderSide(color: p.accent),
        padding: const EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.smR),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(size: 14)),
          ),
          const SizedBox(width: 6),
          Icon(icon, size: 18),
        ],
      ),
    );
  }

  // ── Misc states ──────────────────────────────────────────────────────
  Widget _saveErrorBanner(AppPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: p.error.withValues(alpha: 0.1),
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.error.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, color: p.error, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Couldn\'t save your last set. Your work is kept on this '
              'device — retry when you can.',
              style: AppText.body(size: 12).copyWith(color: p.error),
            ),
          ),
          TextButton(
            onPressed: _persist,
            child: Text('Retry',
                style: AppText.label(size: 12).copyWith(color: p.accent)),
          ),
        ],
      ),
    );
  }

  Widget _queuedBanner(AppPalette p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: p.surfaceAlt.withValues(alpha: 0.5),
        borderRadius: AppRadii.smR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_queue_rounded, color: p.textMuted, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Saved on this device — syncs when you\'re back online.',
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noSetsNote(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Text('No sets prescribed for this exercise.',
          style: AppText.body(size: 13).copyWith(color: p.textMuted)),
    );
  }

  Widget _noWorkout(AppPalette p) {
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.fitness_center_rounded, color: p.textMuted, size: 44),
              const SizedBox(height: 14),
              Text('No workout to start',
                  style: AppText.title(size: 19).copyWith(color: p.textPrimary)),
              const SizedBox(height: 6),
              Text('Your coach hasn\'t assigned a workout yet.',
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 13).copyWith(color: p.textMuted)),
            ],
          ),
        ),
      ),
    );
  }
}
