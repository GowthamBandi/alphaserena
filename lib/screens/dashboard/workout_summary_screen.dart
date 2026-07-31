import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../core/domain/workout_session.dart';
import '../../core/services/workout_log_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/glass_card.dart';
import '../../core/widgets/gradient_button.dart';
import 'consistency_detail_screen.dart';

/// THE FINISH — the moment the product has never used.
///
/// A workout used to end with a snackbar. It now ends with what the member
/// actually did, stated plainly, and one chance to say something to their
/// coach. Celebration WITHOUT infantilising: no confetti, no trophies, no
/// "You're a legend!" — a clear record of real work, which is what an adult
/// paying for coaching wants to see.
///
/// Every number comes from [SessionStats] — the same arithmetic the coach's
/// app runs on the same document, so member and coach can never see
/// different figures for one session.
class WorkoutSummaryScreen extends StatefulWidget {
  final String sessionId;
  final String planName;
  final SessionStats stats;
  final int? durationSeconds;

  /// The finish write was held in the offline queue rather than acknowledged.
  final bool queued;

  const WorkoutSummaryScreen({
    super.key,
    required this.sessionId,
    required this.planName,
    required this.stats,
    this.durationSeconds,
    this.queued = false,
  });

  @override
  State<WorkoutSummaryScreen> createState() => _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends State<WorkoutSummaryScreen> {
  final TextEditingController _note = TextEditingController();
  final WorkoutLogService _log = WorkoutLogService();
  bool _sending = false;
  bool _sent = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  /// The member's message rides the SAME document as the session — the coach
  /// reads it beside the sets it refers to, not in a separate inbox.
  Future<void> _sendNote() async {
    final text = _note.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    // A dedicated two-field write: the logged sets and the session's own
    // timestamp are never touched by adding a note.
    final result = await _log.saveMemberNote(
      sessionId: widget.sessionId,
      note: text,
    );
    if (!mounted) return;
    setState(() {
      _sending = false;
      _sent = result != WorkoutSaveResult.failed;
    });
    if (!_sent) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send — try again.')),
      );
    }
  }

  String get _durationLabel {
    final s = widget.durationSeconds;
    if (s == null || s <= 0) return '—';
    final mins = (s / 60).round();
    if (mins < 1) return '<1 min';
    if (mins < 60) return '$mins min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final s = widget.stats;
    // ONE completion authority. This screen used to re-derive "complete"
    // locally; the engine (SessionStats.isComplete) now owns the rule, so the
    // summary, Home's progress chip and any coach surface agree by
    // construction. (isComplete requires every prescribed set done — skipped
    // exercises have skipped sets, so the old skippedExercises clause is
    // subsumed.)
    final complete = s.isComplete;

    return PopScope(
      // The session is already saved; leaving here is always safe, and the
      // hardware back button must behave exactly like "Done".
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Get.back();
      },
      child: Scaffold(
        backgroundColor: p.background,
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 28, 22, 20),
                  children: [
                    Icon(
                      complete
                          ? Icons.check_circle_rounded
                          : Icons.flag_rounded,
                      size: 54,
                      color: complete ? p.success : p.accent,
                    ),
                    const SizedBox(height: 14),
                    Text(
                      // Truthful headline: a partial finish states its real
                      // fraction instead of a congratulation it didn't earn.
                      complete
                          ? 'Workout complete'
                          : 'Workout finished — ${s.progressPercent}% done',
                      textAlign: TextAlign.center,
                      style: AppText.title(size: 26)
                          .copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.planName,
                      textAlign: TextAlign.center,
                      style:
                          AppText.body(size: 14).copyWith(color: p.textMuted),
                    ),
                    const SizedBox(height: 22),
                    _statGrid(p, s),
                    const SizedBox(height: 14),
                    _coachLine(p),
                    const SizedBox(height: 18),
                    _noteBox(p),
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

  Widget _statGrid(AppPalette p, SessionStats s) {
    final tiles = <({String value, String label})>[
      (value: _durationLabel, label: 'duration'),
      (
        value: '${s.completedSets}/${s.totalSets}',
        label: 'sets completed'
      ),
      // Skips are shown only when they happened — a zero would turn an
      // honest option into an accusation.
      if (s.skippedSets > 0)
        (value: '${s.skippedSets}', label: 'sets skipped'),
      // Volume is a LOAD metric: absent for bodyweight work rather than
      // faked as zero effort.
      if (s.hasVolume)
        (value: '${s.volumeKg.round()} kg', label: 'total volume'),
      if (s.targetHitPct != null)
        (
          value: '${(s.targetHitPct! * 100).round()}%',
          label: 'on target'
        ),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: glassCard(p, radius: 16),
      child: Wrap(
        children: [
          for (final t in tiles)
            SizedBox(
              width: MediaQuery.of(context).size.width / 2 - 24,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  children: [
                    Text(t.value,
                        textAlign: TextAlign.center,
                        style: AppText.title(size: 20)
                            .copyWith(color: p.textPrimary)),
                    const SizedBox(height: 2),
                    Text(t.label,
                        textAlign: TextAlign.center,
                        style: AppText.body(size: 11)
                            .copyWith(color: p.textMuted)),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// What happens next, stated honestly — including the offline case, which
  /// must never be dressed up as delivered.
  Widget _coachLine(AppPalette p) {
    return Row(
      children: [
        Icon(
          widget.queued ? Icons.cloud_queue_rounded : Icons.visibility_outlined,
          size: 15,
          color: p.textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            widget.queued
                ? 'Saved on this device — your coach will see it once you\'re '
                    'back online.'
                : 'Your coach can now see this session.',
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
        ),
      ],
    );
  }

  Widget _noteBox(AppPalette p) {
    if (_sent) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: AppRadii.cardR,
          color: p.success.withValues(alpha: 0.10),
          border: Border.all(color: p.success.withValues(alpha: 0.4)),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_rounded, size: 17, color: p.success),
            const SizedBox(width: 10),
            Expanded(
              child: Text('Sent to your coach with this session.',
                  style: AppText.body(size: 12.5)
                      .copyWith(color: p.textPrimary)),
            ),
          ],
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('ANYTHING TO TELL YOUR COACH?',
            style: AppText.label(size: 11)
                .copyWith(color: p.textMuted, letterSpacing: 1.4)),
        const SizedBox(height: 8),
        TextField(
          controller: _note,
          maxLines: 3,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          style: TextStyle(color: p.textPrimary),
          decoration: InputDecoration(
            hintText: 'Shoulder felt tight on the last set…',
            hintStyle: AppText.body(size: 13).copyWith(color: p.textMuted),
            counterText: '',
            filled: true,
            fillColor: p.inputFill,
            border: OutlineInputBorder(
                borderRadius: AppRadii.smR,
                borderSide: BorderSide(color: p.border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.smR,
                borderSide: BorderSide(color: p.border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: AppRadii.smR,
                borderSide: BorderSide(color: p.accent, width: 1.4)),
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _sending ? null : _sendNote,
            icon: _sending
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: p.accent),
                  )
                : Icon(Icons.send_rounded, size: 15, color: p.accent),
            label: Text('Send to coach',
                style: AppText.label(size: 13).copyWith(color: p.accent)),
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(AppPalette p) {
    return Container(
      padding: EdgeInsets.fromLTRB(
          22, 12, 22, 12 + MediaQuery.of(context).padding.bottom),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GradientButton(
            label: 'Done',
            onPressed: () => Get.back(),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: () {
              Get.back();
              Get.to(() => const ConsistencyDetailScreen(isWorkout: true));
            },
            child: Text('View my history',
                style: AppText.label(size: 13).copyWith(color: p.textMuted)),
          ),
        ],
      ),
    );
  }
}
