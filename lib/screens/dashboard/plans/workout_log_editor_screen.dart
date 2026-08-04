import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../controllers/streak_controller.dart';
import '../../../core/domain/workout_history.dart';
import '../../../core/domain/workout_session.dart';
import '../../../core/services/workout_log_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/utils/lifestyle_math.dart' show dayKey;
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/serena/premium_states.dart';
import 'plan_segmented_control.dart';
import 'workout_set_edit_sheet.dart';

/// EDIT WORKOUT LOG — correcting what was recorded, without re-running it.
///
/// ── WHY THIS SCREEN EXISTS ────────────────────────────────────────────────
///
/// A finished workout used to be a dead end. The hero card's CTA became a
/// statement ("Workout complete") with `onCta: null`, and the only route back
/// into the numbers was to re-open the session PLAYER — a guided,
/// one-exercise-at-a-time flow built for performing a workout, which then
/// greeted the member with a dialog offering to start a second session. To fix
/// a mistyped rep count, a member had to navigate a screen designed for
/// training and decline an offer to train again.
///
/// So the editor is a LOG, not a player: every exercise and every set on one
/// page, tap the one that is wrong. That is exactly how the member already
/// corrects a meal (`FoodLogSection` → `FoodQuantitySheet`), which is what the
/// mission means by "editing must work exactly like Nutrition" — the same
/// gesture, the same sheet shape, the same immediate save, the same undoable
/// feel.
///
/// ── WHAT AN EDIT MAY AND MAY NOT TOUCH ────────────────────────────────────
///
/// **The workout stays completed. Only the logged data changes.** Every save
/// goes through [WorkoutLogService.saveEditedEntries], which writes `entries`
/// and `updatedAt` and NOTHING else — not `status`, not `date`, not
/// `startedAt`/`finishedAt`, not `durationSeconds`. Correcting a set can
/// therefore never re-open a finished session or move it in time, which is
/// precisely what routing this through the ordinary `saveSession` would have
/// risked.
///
/// **A corrected set is marked `edited`.** The coach sees the member's real
/// number and also sees that it was revised rather than logged live. That flag
/// is the same one the session player sets on a re-completed set, read by
/// TrainerHQ's `SessionSet.edited`, and it is why an honest correction does not
/// look like live data.
///
/// ── SYNCHRONISATION IS STRUCTURAL ─────────────────────────────────────────
///
/// The screen holds `List<ExerciseLog>` — the production model — and writes it
/// with `buildSessionEntries`, the one function that produces the wire shape.
/// There is no editor-specific model, no editor-specific document and no
/// second write path. TrainerHQ's `ClientWorkoutSessionModel.fromMap` parses
/// the result of an edit exactly as it parses the result of a live session,
/// because they are byte-identical shapes produced by the same code.
class WorkoutLogEditorScreen extends StatefulWidget {
  /// The session to edit. Deterministic (`ws_{clientId}_{yyyy-MM-dd}`).
  final String sessionId;

  /// The already-loaded log, when the caller has one. Passed to avoid a second
  /// read of a document the caller is already displaying — never as the source
  /// of truth: a save re-reads nothing, it writes what is on screen.
  final WorkoutDayLog? initial;

  /// Injectable so the whole edit path is drivable in a plain widget test.
  /// Null in production, where the screen builds the real service lazily.
  final WorkoutLogService? service;

  const WorkoutLogEditorScreen({
    super.key,
    required this.sessionId,
    this.initial,
    this.service,
  });

  @override
  State<WorkoutLogEditorScreen> createState() => _WorkoutLogEditorScreenState();
}

class _WorkoutLogEditorScreenState extends State<WorkoutLogEditorScreen> {
  WorkoutLogService? _resolved;
  WorkoutLogService get _log =>
      widget.service ?? (_resolved ??= WorkoutLogService());
  final TextEditingController _note = TextEditingController();

  WorkoutDayLog? _session;
  List<ExerciseLog> _exercises = const [];
  bool _loading = true;
  bool _loadFailed = false;
  bool _saving = false;

  /// The last save's outcome, so an offline correction says "saved on this
  /// device" rather than either lying about delivery or claiming a failure.
  WorkoutSaveResult? _lastSave;

  /// Whether the note differs from what was last written. The note is the one
  /// field with an explicit Save (it is free text — saving on every keystroke
  /// would be a write per character); the sets save immediately, like foods.
  bool _noteDirty = false;
  bool _savingNote = false;

  static const Color _accent = PlanSegmentedControl.workoutFill;
  static const Color _done = Color(0xFF2EBD59);
  static const Color _skip = Color(0xFFE0A106);

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final provided = widget.initial;
    if (provided != null) {
      _adopt(provided);
      return;
    }
    final doc = await _log.fetchSession(widget.sessionId);
    if (!mounted) return;
    final parsed =
        doc == null ? null : parseWorkoutDayLog(doc, widget.sessionId);
    if (parsed == null) {
      setState(() {
        _loading = false;
        _loadFailed = true;
      });
      return;
    }
    _adopt(parsed);
  }

  void _adopt(WorkoutDayLog session) {
    _session = session;
    _exercises = session.exercises;
    _note.text = session.memberNote;
    _noteDirty = false;
    if (mounted) {
      setState(() {
        _loading = false;
        _loadFailed = false;
      });
    } else {
      _loading = false;
      _loadFailed = false;
    }
  }

  SessionStats get _stats => computeSessionStats(_exercises);

  /// True when the session being edited is TODAY's.
  ///
  /// Editing yesterday must not touch the live "today" state that Home and My
  /// Plans render — the day guard in `StreakController` would refuse the stale
  /// stats anyway, but pushing them at all is the kind of thing that works
  /// until the guard is refactored.
  bool get _isToday {
    final s = _session;
    return s != null && s.dayKey == dayKey(DateTime.now());
  }

  // ── EDITING ───────────────────────────────────────────────────────────────

  Future<void> _editSet(int exerciseIndex, int setIndex) async {
    final ex = _exercises[exerciseIndex];
    final set = ex.sets[setIndex];
    final result = await showModalBottomSheet<SetEditResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => WorkoutSetEditSheet(
        setNumber: setIndex + 1,
        exerciseName: ex.name,
        set: set,
        accent: _accent,
      ),
    );
    if (result == null || !mounted) return;

    final unchanged = result.actualReps == set.actualReps &&
        result.actualWeight == set.actualWeight &&
        result.state == set.state;
    // Backing out of the sheet by saving an identical set must not stamp
    // `edited` on the coach's view, and must not spend a write.
    if (unchanged) return;

    // THE `edited` FLAG IS ABOUT PROVENANCE, NOT ABOUT CHANGE.
    //
    // It means "this number was revised after the fact rather than logged in
    // the moment". A set that was already resolved and is now different earns
    // it. A set the member had never answered (pending → completed) is being
    // logged for the first time, late — honest, and not a revision — but it is
    // still not live data, so it earns the flag too. The one case that does
    // NOT is a flag that is already set: it never comes back off.
    final wasAnswered = set.state != SetLogState.pending;
    set
      ..actualReps = result.actualReps
      ..actualWeight = result.actualWeight
      ..state = result.state
      ..edited = set.edited || wasAnswered || result.state != SetLogState.pending;

    setState(() {});
    await _persist();
  }

  Future<void> _toggleExerciseSkip(int index) async {
    final ex = _exercises[index];
    setState(() {
      ex.skipped = !ex.skipped;
      if (!ex.skipped) ex.skipReason = '';
    });
    await _persist();
  }

  Future<void> _persist() async {
    setState(() => _saving = true);
    final result = await _log.saveEditedEntries(
      sessionId: widget.sessionId,
      entries: buildSessionEntries(_exercises),
    );
    if (!mounted) return;
    setState(() {
      _saving = false;
      _lastSave = result;
    });

    if (result == WorkoutSaveResult.failed) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: Text('Could not save that correction — try again.'),
          behavior: SnackBarBehavior.floating,
        ));
      return;
    }

    // KEEP THE REST OF THE APP HONEST, IMMEDIATELY.
    //
    // Home's progress chip, My Plans' "Today's workout" and the streak all read
    // `StreakController`'s held session. Without this push, a member could
    // correct three sets, return to My Plans, and read the numbers they had
    // before the correction until the next cold start — which is exactly the
    // stale-duration defect this module has already been bitten by once.
    if (_isToday && Get.isRegistered<StreakController>()) {
      final stats = _stats;
      Get.find<StreakController>().markWorkoutToday(
        stats: stats,
        nextUp: nextUpFrom(_exercises),
        exercises: _exercises,
        // `trained` follows THE rule, in both directions: undoing the last
        // completed set of a session must take the day back out of the streak,
        // not leave it marked until a refetch disagrees.
        trained: hasCompletedWork(_exercises),
      );
    }
  }

  Future<void> _saveNote() async {
    final text = _note.text.trim();
    if (_savingNote) return;
    // CLEARING IS A REAL OUTCOME AND SAYS SO.
    //
    // Emptying the field and tapping Save used to report "Could not send that
    // note — try again", because the service refused an empty string. It is a
    // retraction, it now succeeds, and it must not be announced as though the
    // coach had just been sent a blank message.
    final removing = text.isEmpty;
    setState(() => _savingNote = true);
    final result = await _log.saveMemberNote(
      sessionId: widget.sessionId,
      note: text,
    );
    if (!mounted) return;
    setState(() {
      _savingNote = false;
      if (result != WorkoutSaveResult.failed) _noteDirty = false;
    });
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(
          result == WorkoutSaveResult.failed
              ? removing
                  ? 'Could not remove that note — try again.'
                  : 'Could not send that note — try again.'
              : result == WorkoutSaveResult.queued
                  ? 'Saved on this device — your coach sees it when you '
                      'reconnect.'
                  : removing
                      ? 'Note removed.'
                      : 'Note updated for your coach.',
        ),
        behavior: SnackBarBehavior.floating,
      ));
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Edit workout log',
            style: AppText.title(size: 20).copyWith(color: p.textPrimary)),
        iconTheme: IconThemeData(color: p.textPrimary),
        actions: [
          // A quiet, permanent statement of write state rather than a snackbar
          // per set: the member is making several corrections in a row and a
          // stack of toasts would cover the rows they are correcting.
          Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Center(child: _saveIndicator(p)),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: _loading
            ? _skeleton(p)
            : _loadFailed
                ? _error(p)
                : _body(p),
      ),
    );
  }

  Widget _saveIndicator(AppPalette p) {
    if (_saving) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.textMuted),
          ),
          const SizedBox(width: 6),
          Text('Saving',
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted)),
        ],
      );
    }
    final last = _lastSave;
    if (last == null) return const SizedBox.shrink();
    // A FAILED WRITE MUST NOT LEAVE "Saved" IN THE APP BAR.
    //
    // The snackbar that reports the failure is transient; this indicator is
    // not, so a member who missed the toast would be left with a persistent
    // green "Saved" over a correction that never reached Firestore. The
    // indicator says nothing when there is nothing true to say.
    if (last == WorkoutSaveResult.failed) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 14, color: p.error),
          const SizedBox(width: 5),
          Text('Not saved',
              style: AppText.body(size: 11.5).copyWith(color: p.error)),
        ],
      );
    }
    final queued = last == WorkoutSaveResult.queued;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(queued ? Icons.cloud_queue_rounded : Icons.check_rounded,
            size: 14, color: queued ? p.textMuted : _done),
        const SizedBox(width: 5),
        Text(
          // Queued is NOT an error and NOT a success — the write is in
          // Firestore's local queue and will sync. Saying "Saved" would be a
          // claim about the coach's screen the app cannot make yet.
          //
          // ⚠️ NOT "Saved offline". `queued` means only that the server did
          // not acknowledge within `ackTimeout` (4s) — it does NOT mean the
          // device is offline, and nothing on this path ever checks. Observed
          // on a fully-connected emulator during a cold start, where App Check
          // token retries pushed the first write past 4s: the member was told
          // they were offline while they were online, and the very next write
          // acked in under a second.
          //
          // "Saved on this device" is true in BOTH cases — the write is in the
          // local queue — and claims nothing about a network the app has not
          // measured. It is also the phrase Lifestyle already uses for exactly
          // this state, so one situation reads one way across the app.
          queued ? 'Saved on this device' : 'Saved',
          style: AppText.body(size: 11.5)
              .copyWith(color: queued ? p.textMuted : _done),
        ),
      ],
    );
  }

  Widget _body(AppPalette p) {
    final session = _session!;
    final stats = _stats;
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
      children: [
        _summary(p, session, stats),
        const SizedBox(height: 18),
        Text('EVERY SET, AS LOGGED',
            style: AppText.label(size: 11)
                .copyWith(color: p.textMuted, letterSpacing: 1.0)),
        const SizedBox(height: 4),
        Text(
          'Tap any set to correct what you recorded. The workout stays '
          'completed — only the numbers change.',
          style: AppText.body(size: 12).copyWith(color: p.textMuted),
        ),
        const SizedBox(height: 12),
        for (var i = 0; i < _exercises.length; i++) _exerciseCard(p, i),
        const SizedBox(height: 10),
        _noteCard(p),
      ],
    );
  }

  /// The session's own numbers, recomputed live from the edits above them.
  ///
  /// This is the feedback that makes an edit feel like it landed: change a set
  /// from skipped to completed and the percentage, the set count and the volume
  /// all move on the same frame, from the same engine the coach reads.
  Widget _summary(AppPalette p, WorkoutDayLog session, SessionStats stats) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: glassCard(p, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            session.planName.isEmpty ? 'Workout' : session.planName,
            style: AppText.cardTitle(size: 15).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 2),
          Text(
            DateFormat('EEEE, d MMMM').format(session.date),
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 20,
            runSpacing: 10,
            children: [
              _stat(p, 'Completion', '${stats.progressPercent}%'),
              _stat(p, 'Sets', '${stats.completedSets}/${stats.totalSets}'),
              if (stats.skippedSets > 0)
                _stat(p, 'Skipped', '${stats.skippedSets}'),
              if (stats.hasVolume)
                _stat(p, 'Volume', '${stats.volumeKg.round()} kg'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(AppPalette p, String label, String value) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: AppText.body(size: 10.5).copyWith(color: p.textMuted)),
          const SizedBox(height: 1),
          Text(value,
              style: AppText.cardTitle(size: 15).copyWith(color: p.textPrimary)),
        ],
      );

  Widget _exerciseCard(AppPalette p, int index) {
    final ex = _exercises[index];
    final done = ex.sets.where((s) => s.state == SetLogState.completed).length;
    final allDone = !ex.skipped && ex.sets.isNotEmpty && done == ex.sets.length;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: glassCard(p, radius: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  ex.skipped
                      ? Icons.remove_circle_outline_rounded
                      : allDone
                          ? Icons.check_circle_rounded
                          : Icons.radio_button_unchecked_rounded,
                  size: 17,
                  color: ex.skipped
                      ? _skip
                      : allDone
                          ? _done
                          : p.textMuted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    ex.name.isEmpty ? 'Exercise' : ex.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.cardTitle(size: 14)
                        .copyWith(color: p.textPrimary),
                  ),
                ),
                const SizedBox(width: 8),
                // Un-skipping a whole exercise is the one bulk correction worth
                // offering: a member who skipped an exercise by mistake would
                // otherwise have to re-answer every set inside it to undo one
                // tap.
                TextButton(
                  onPressed: _saving ? null : () => _toggleExerciseSkip(index),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: ex.skipped ? _accent : p.textMuted,
                  ),
                  child: Text(
                    ex.skipped ? 'Un-skip' : 'Skip',
                    style: AppText.label(size: 12),
                  ),
                ),
              ],
            ),
            if (ex.skipped && ex.skipReason.isNotEmpty) ...[
              const SizedBox(height: 6),
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Text(ex.skipReason,
                    style: AppText.body(size: 12).copyWith(color: p.textMuted)),
              ),
            ],
            if (ex.sets.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8, left: 26),
                child: Text('No sets were prescribed for this exercise.',
                    style: AppText.body(size: 12).copyWith(color: p.textMuted)),
              )
            else ...[
              const SizedBox(height: 10),
              for (var i = 0; i < ex.sets.length; i++)
                _setRow(p, index, i, ex.sets[i]),
            ],
          ],
        ),
      ),
    );
  }

  Widget _setRow(AppPalette p, int exerciseIndex, int setIndex, SetLog s) {
    final target = _pair(s.pReps, s.pWeight);
    final actual = _pair(s.actualReps, s.actualWeight);
    final color = switch (s.state) {
      SetLogState.completed => _done,
      SetLogState.skipped => _skip,
      SetLogState.pending => p.textMuted,
    };

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Semantics(
        button: true,
        label: 'Set ${setIndex + 1}, '
            '${switch (s.state) {
          SetLogState.completed =>
            actual.isEmpty ? 'completed' : 'completed, $actual',
          SetLogState.skipped => 'skipped',
          SetLogState.pending => 'not done',
        }}. Tap to edit.',
        container: true,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _saving ? null : () => _editSet(exerciseIndex, setIndex),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              decoration: BoxDecoration(
                color: p.isDark
                    ? Colors.white.withValues(alpha: 0.03)
                    : const Color(0xFFF7F8FA),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 44,
                    child: Text('Set ${setIndex + 1}',
                        style: AppText.body(size: 11.5)
                            .copyWith(color: p.textMuted)),
                  ),
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (target.isNotEmpty)
                          Text(target,
                              style: AppText.body(size: 12)
                                  .copyWith(color: p.textMuted)),
                        // A pending set shows its target and leaves the result
                        // EMPTY — a dash there reads as "recorded nothing" when
                        // the truth is "not reached".
                        if (s.state == SetLogState.completed &&
                            actual.isNotEmpty) ...[
                          Icon(Icons.arrow_right_alt_rounded,
                              size: 14, color: p.textMuted),
                          Text(actual,
                              style: AppText.label(size: 12.5)
                                  .copyWith(color: p.textPrimary)),
                        ],
                        if (s.edited)
                          Text('edited',
                              style: AppText.body(size: 10.5)
                                  .copyWith(color: p.textMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    switch (s.state) {
                      SetLogState.completed => Icons.check_rounded,
                      SetLogState.skipped => Icons.remove_rounded,
                      SetLogState.pending => Icons.circle_outlined,
                    },
                    size: 14,
                    color: color,
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.edit_outlined, size: 14, color: p.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The member's message to their coach, editable after the fact.
  ///
  /// It rides the SAME document as the sets (`memberNote`), so the coach reads
  /// it beside the work it refers to. It saves explicitly rather than on every
  /// keystroke — free text on an auto-save would be one write per character.
  Widget _noteCard(AppPalette p) => Container(
        padding: const EdgeInsets.all(16),
        decoration: glassCard(p, radius: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NOTE FOR YOUR COACH',
                style: AppText.label(size: 11)
                    .copyWith(color: p.textMuted, letterSpacing: 1.1)),
            const SizedBox(height: 8),
            TextField(
              controller: _note,
              maxLines: 3,
              maxLength: 300,
              textCapitalization: TextCapitalization.sentences,
              onChanged: (_) {
                if (!_noteDirty) setState(() => _noteDirty = true);
              },
              style: AppText.body(size: 13.5).copyWith(color: p.textPrimary),
              decoration: InputDecoration(
                hintText: 'Shoulder felt tight on the last set…',
                hintStyle:
                    AppText.body(size: 13).copyWith(color: p.textMuted),
                counterText: '',
                filled: true,
                fillColor: p.inputFill,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: p.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _accent, width: 1.4),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                // Only live once there is something to save — a Save that does
                // nothing teaches the member the button is decorative.
                onPressed: (!_noteDirty || _savingNote) ? null : _saveNote,
                icon: _savingNote
                    ? const SizedBox(
                        width: 13,
                        height: 13,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _accent),
                      )
                    : const Icon(Icons.send_rounded, size: 15),
                style: TextButton.styleFrom(foregroundColor: _accent),
                label: Text('Save note', style: AppText.label(size: 13)),
              ),
            ),
          ],
        ),
      );

  Widget _skeleton(AppPalette p) => ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: const [
          SerenaSkeleton(height: 120, radius: 16),
          SizedBox(height: 14),
          SerenaSkeleton(height: 150, radius: 14),
          SizedBox(height: 12),
          SerenaSkeleton(height: 150, radius: 14),
        ],
      );

  Widget _error(AppPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 28),
          child: SerenaEmptyState(
            glyph: '\u{1F4E1}',
            title: "Couldn't open this workout",
            // NEVER the empty state: an unreadable document is a claim about
            // the network, not about the member's training.
            body: 'This is a connection problem — every set you logged is '
                'still saved.',
            actionLabel: 'Try again',
            onAction: () {
              setState(() {
                _loading = true;
                _loadFailed = false;
              });
              _bootstrap();
            },
            boxed: false,
          ),
        ),
      );

  /// The app's one phrasing for a reps × weight pair.
  static String _pair(String reps, String weight) {
    final r = reps.trim();
    final w = weight.trim();
    final hasUnit = w.isEmpty || RegExp(r'[a-zA-Z]').hasMatch(w);
    return [
      if (r.isNotEmpty) '$r reps',
      if (w.isNotEmpty) hasUnit ? w : '$w kg',
    ].join(' × ');
  }
}
