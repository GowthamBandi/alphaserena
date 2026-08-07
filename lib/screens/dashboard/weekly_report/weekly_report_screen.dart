import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import '../../../controllers/weekly_report_controller.dart';
import '../../../core/models/weekly_report_models.dart';
import '../../../core/services/weekly_report_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/weekly_reports/question_engine.dart';
import '../../../core/weekly_reports/question_renderers.dart';
import 'weekly_report_history_screen.dart';
import 'weekly_report_review_view.dart';

/// THE MEMBER'S WEEKLY REPORT.
///
/// Replaces the Weekly Check-in. Every state on this screen is driven by
/// `snapshot.status` — a value the SERVER wrote in the organization's timezone —
/// and never by the device clock. The countdown is the one place a clock is
/// read, and it is display only.
///
/// The questions come from the FROZEN SNAPSHOT: this screen has no idea what
/// "energy" or "sleep" are, and cannot be made to. It renders whatever the coach
/// froze, through the shared registry, which is the same code path their live
/// preview uses.
class WeeklyReportScreen extends StatefulWidget {
  const WeeklyReportScreen({super.key});

  @override
  State<WeeklyReportScreen> createState() => _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends State<WeeklyReportScreen> {
  final WeeklyReportController c = Get.isRegistered<WeeklyReportController>()
      ? Get.find<WeeklyReportController>()
      : Get.put(WeeklyReportController());

  @override
  void dispose() {
    // A draft owed to the server must not be dropped because the member
    // navigated away inside the autosave debounce window.
    c.flushDraft();
    super.dispose();
  }

  Future<List<String>> _pickPhotos(String periodKey) async {
    final picker = ImagePicker();
    final files = await picker.pickMultiImage(imageQuality: 82);
    if (files.isEmpty) return const [];
    final service = WeeklyReportService();
    final urls = <String>[];
    for (final f in files) {
      final url = await service.uploadPhoto(
        periodKey: periodKey,
        file: File(f.path),
        filename: f.name,
      );
      if (url != null) urls.add(url);
    }
    if (urls.isEmpty && mounted) {
      Get.snackbar('Photo not added', 'The upload did not complete.',
          snackPosition: SnackPosition.BOTTOM);
    }
    return urls;
  }

  Future<void> _submit(WeeklyReportSnapshot s) async {
    FocusScope.of(context).unfocus();
    final ok = await c.submitCurrent();
    if (!mounted) return;
    if (ok) {
      Get.snackbar(
        c.hasQueuedWrite.value ? 'Saved on this device' : 'Report sent',
        c.hasQueuedWrite.value
            ? 'It will reach your coach as soon as you reconnect.'
            : 'Your coach will review it soon.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } else {
      Get.snackbar(
        'Not sent yet',
        c.errorText.value.isNotEmpty
            ? c.errorText.value
            : 'Some required answers are still missing.',
        snackPosition: SnackPosition.BOTTOM,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        title: Text('Weekly Report',
            style: AppText.title(size: 19).copyWith(color: p.textPrimary)),
        actions: [
          IconButton(
            tooltip: 'History',
            icon: Icon(Icons.history, color: p.textSecondary),
            onPressed: () => Get.to(() => const WeeklyReportHistoryScreen()),
          ),
        ],
      ),
      body: Obx(() {
        // MUST be first, and must stay. `Obx` records only the Rx reads made
        // inside THIS callback; `_FormView` and `_SubmittedView` read the
        // controller in their own `build`, which runs outside that scope.
        // Without this the form does not react to the member's own typing.
        // See `WeeklyReportController.observeAll`.
        c.observeAll();
        if (c.isLoading.value) return const _ReportSkeleton();
        final s = c.current;
        // 🔴 A FAILED LOAD IS NOT AN EMPTY ONE. Without this branch a member
        // whose stream errored was told "No weekly report yet — your coach
        // sends one every week", which is a confident, wrong statement about
        // their coach made on the strength of a network failure. Same shape as
        // the lifestyle outage this platform already paid for.
        if (s == null && c.errorText.value.isNotEmpty) {
          return _LoadFailed(message: c.errorText.value, onRetry: c.retry);
        }
        // "Not linked yet" and "no report yet" are DIFFERENT FACTS. Saying the
        // second while the first is true is a claim about the coach the app has
        // no basis for.
        if (s == null && c.isUnlinked) return const _NotLinkedYet();
        if (s == null) return const _NoReportYet();
        if (s.isSubmitted) return _SubmittedView(snapshot: s, controller: c);
        if (s.status == WeeklyReportStatus.scheduled) {
          return _CountdownView(snapshot: s, controller: c);
        }
        if (s.isCancelled) return const _CancelledView();
        return _FormView(
          snapshot: s,
          controller: c,
          onPickPhotos: () => _pickPhotos(s.periodKey),
          onSubmit: () => _submit(s),
        );
      }),
    );
  }
}

// ───────────────────────────────────────────────────────────────────────────
// States
// ───────────────────────────────────────────────────────────────────────────

class _ReportSkeleton extends StatelessWidget {
  const _ReportSkeleton();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            height: 108,
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: AppRadii.cardR,
            ),
          ),
      ],
    );
  }
}

/// No report has ever been issued. Deliberately NOT phrased as an error — the
/// most common cause is a coach who has not turned Weekly Reports on yet.
class _NoReportYet extends StatelessWidget {
  const _NoReportYet();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.event_note_outlined, size: 56, color: p.textMuted),
            const SizedBox(height: 16),
            Text('No weekly report yet',
                style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'Your coach sends one every week. The first will appear here as '
              'soon as it is ready.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13.5).copyWith(color: p.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

/// The stream failed. Says so, and offers the way back — never a claim about
/// what the coach has or has not sent.
class _LoadFailed extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _LoadFailed({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 48, color: p.textMuted),
            const SizedBox(height: 16),
            Text('We could not load your reports',
                textAlign: TextAlign.center,
                style: AppText.title(size: 17).copyWith(color: p.textPrimary)),
            const SizedBox(height: 8),
            Text(
              '$message Your answers are safe — nothing has been lost.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13.5).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: onRetry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}

/// The member's account is not linked to a coach's client record yet, so this
/// app cannot read reports at all — a different statement from "none exist".
class _NotLinkedYet extends StatelessWidget {
  const _NotLinkedYet();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.link_off, size: 52, color: p.textMuted),
            const SizedBox(height: 16),
            Text('Connecting your account',
                textAlign: TextAlign.center,
                style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'Your weekly reports appear here as soon as your coach\'s record '
              'is linked to this account. It usually takes a moment.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13.5).copyWith(color: p.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _CancelledView extends StatelessWidget {
  const _CancelledView();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'This week\'s report was cancelled by your coach.',
          textAlign: TextAlign.center,
          style: AppText.body(size: 14).copyWith(color: p.textMuted),
        ),
      ),
    );
  }
}

/// The report exists but has not opened. Shows when it will.
class _CountdownView extends StatelessWidget {
  final WeeklyReportSnapshot snapshot;
  final WeeklyReportController controller;

  const _CountdownView({required this.snapshot, required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final left = controller.countdownTo(DateTime.now());
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 132,
              height: 132,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.accent.withValues(alpha: 0.10),
                border: Border.all(color: p.accent.withValues(alpha: 0.35)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    left == null ? '—' : _countdownValue(left),
                    style: AppText.display(size: 34).copyWith(color: p.accent),
                  ),
                  Text(
                    left == null ? '' : _countdownUnit(left),
                    style:
                        AppText.label(size: 12).copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            Text('Your next report opens soon',
                style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'It will cover ${snapshot.periodLabel}.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13.5).copyWith(color: p.textMuted),
            ),
          ],
        ),
      ),
    );
  }

  static String _countdownValue(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}';
    if (d.inHours >= 1) return '${d.inHours}';
    return '${d.inMinutes}';
  }

  static String _countdownUnit(Duration d) {
    if (d.inDays >= 1) return d.inDays == 1 ? 'day' : 'days';
    if (d.inHours >= 1) return d.inHours == 1 ? 'hour' : 'hours';
    return 'minutes';
  }
}

/// The answerable report.
class _FormView extends StatelessWidget {
  final WeeklyReportSnapshot snapshot;
  final WeeklyReportController controller;
  final Future<List<String>> Function() onPickPhotos;
  final VoidCallback onSubmit;

  const _FormView({
    required this.snapshot,
    required this.controller,
    required this.onPickPhotos,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final visible = c.visibleFor(snapshot);
    final completion = c.completion(snapshot);
    final remaining = c.remainingFor(snapshot, DateTime.now());

    // Group by the snapshot's own sections, preserving author order. A question
    // whose section was deleted from the template still renders — under the
    // trailing group — rather than vanishing from a report already issued.
    final bySection = <String, List<QuestionDefinition>>{};
    for (final q in visible) {
      bySection.putIfAbsent(q.sectionId, () => []).add(q);
    }
    final orderedSections = [
      ...snapshot.sections.where((s) => bySection.containsKey(s.id)),
      for (final key in bySection.keys)
        if (!snapshot.sections.any((s) => s.id == key))
          ReportSection(id: key, title: key.isEmpty ? 'More' : 'More'),
    ];

    return Column(
      children: [
        _FormHeader(
          snapshot: snapshot,
          completion: completion,
          remaining: remaining,
          isSaving: c.isSaving.value,
          queued: c.hasQueuedWrite.value,
          late: snapshot.isMissed,
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
            children: [
              for (final section in orderedSections) ...[
                ReportSectionHeader(
                  section: section,
                  answered: bySection[section.id]!
                      .where((q) => isAnswered(c.answerFor(q.id)))
                      .length,
                  total: bySection[section.id]!.length,
                ),
                for (final q in bySection[section.id]!)
                  QuestionCard(
                    key: ValueKey(q.id),
                    ctx: QuestionRenderContext(
                      question: q,
                      value: c.answerFor(q.id),
                      verdict: c.verdictFor(q),
                      onPickPhotos: onPickPhotos,
                      onChanged: (v) => c.setAnswer(q, v),
                    ),
                  ),
              ],
            ],
          ),
        ),
        _SubmitBar(
          enabled: completion.canSubmit,
          busy: c.isSubmitting.value,
          onSubmit: onSubmit,
          hint: completion.canSubmit
              ? null
              : '${completion.requiredTotal - completion.requiredAnswered} '
                  'required ${completion.requiredTotal - completion.requiredAnswered == 1 ? "answer" : "answers"} left',
        ),
      ],
    );
  }
}

class _FormHeader extends StatelessWidget {
  final WeeklyReportSnapshot snapshot;
  final ReportCompletion completion;
  final Duration? remaining;
  final bool isSaving;
  final bool queued;
  final bool late;

  const _FormHeader({
    required this.snapshot,
    required this.completion,
    required this.remaining,
    required this.isSaving,
    required this.queued,
    required this.late,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
      decoration: BoxDecoration(
        color: p.background,
        border: Border(bottom: BorderSide(color: p.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  snapshot.periodLabel,
                  style: AppText.cardTitle(size: 15)
                      .copyWith(color: p.textPrimary),
                ),
              ),
              if (late)
                _Pill(text: 'Late', color: p.error)
              else if (remaining != null)
                _Pill(
                  text: _remainingLabel(remaining!),
                  color: remaining!.inHours < 12 ? p.error : p.textMuted,
                ),
            ],
          ),
          const SizedBox(height: 10),
          ReportProgressBar(completion: completion),
          if (isSaving || queued) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  queued ? Icons.cloud_off : Icons.sync,
                  size: 13,
                  color: p.textMuted,
                ),
                const SizedBox(width: 6),
                Text(
                  // "Saved on this device" is NOT an error, and must never be
                  // presented as one — the answers are safe and will sync.
                  queued ? 'Saved on this device' : 'Saving…',
                  style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  static String _remainingLabel(Duration d) {
    if (d.inDays >= 1) return '${d.inDays}d left';
    if (d.inHours >= 1) return '${d.inHours}h left';
    return '${d.inMinutes}m left';
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;
  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: AppText.label(size: 11).copyWith(color: color),
        ),
      );
}

class _SubmitBar extends StatelessWidget {
  final bool enabled;
  final bool busy;
  final String? hint;
  final VoidCallback onSubmit;

  const _SubmitBar({
    required this.enabled,
    required this.busy,
    required this.hint,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      padding: EdgeInsets.fromLTRB(
        18,
        12,
        18,
        12 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hint != null) ...[
            Text(hint!,
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              // ALWAYS TAPPABLE. A dead button explains nothing; tapping an
              // incomplete report reveals every missing answer instead. This is
              // the same correction Edit Profile needed.
              onPressed: busy ? null : onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: enabled ? p.accent : p.surfaceAlt,
                foregroundColor: enabled ? Colors.white : p.textMuted,
                elevation: 0,
                shape: const RoundedRectangleBorder(
                    borderRadius: AppRadii.mdR),
              ),
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text('Send to coach',
                      style: AppText.label(size: 15).copyWith(
                        color: enabled ? Colors.white : p.textMuted,
                      )),
            ),
          ),
        ],
      ),
    );
  }
}

/// A submitted report — read-only forever, plus the coach's review when it
/// lands.
class _SubmittedView extends StatelessWidget {
  final WeeklyReportSnapshot snapshot;
  final WeeklyReportController controller;

  const _SubmittedView({required this.snapshot, required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final submission = controller.submissionFor(snapshot.id);
    final review = controller.reviewFor(snapshot.id);
    final answers = submission?.answers ?? const <String, dynamic>{};
    final visible = visibleQuestions(snapshot.questions, answers);

    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.accent.withValues(alpha: 0.08),
            borderRadius: AppRadii.cardR,
            border: Border.all(color: p.accent.withValues(alpha: 0.30)),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, color: p.accent, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Sent for ${snapshot.periodLabel}',
                        style: AppText.cardTitle(size: 14.5)
                            .copyWith(color: p.textPrimary)),
                    const SizedBox(height: 3),
                    Text(
                      review?.isCompleted == true
                          ? 'Your coach has reviewed it.'
                          : 'Waiting for your coach to review it.',
                      style: AppText.body(size: 12.5)
                          .copyWith(color: p.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        if (review != null && review.hasFeedback) ...[
          WeeklyReportReviewView(review: review),
          const SizedBox(height: 18),
        ],
        Text('YOUR ANSWERS',
            style: AppText.label(size: 12)
                .copyWith(color: p.textSecondary, letterSpacing: 1.1)),
        const SizedBox(height: 12),
        for (final q in visible) ...[
          QuestionCard(
            key: ValueKey(q.id),
            ctx: QuestionRenderContext(
              question: q,
              value: answerValue(answers, q.id),
              readOnly: true,
              onChanged: (_) {},
            ),
          ),
          // The coach's comment ON THIS ANSWER, beside the answer it is about.
          // `questionComments` has been written by the coach's review screen and
          // read by NOTHING until now — the unconnected-code failure this
          // platform keeps paying for. A comment shown in a list at the bottom
          // would be a sentence the member has to match up themselves.
          //
          // Gated on `isCompleted`, exactly as `hasFeedback` gates the review
          // card above it: "Save progress" is a coach's draft, not a message.
          // Showing a half-written comment the moment it is saved would make
          // the difference between saving and sending invisible.
          if (review?.isCompleted == true &&
              (review!.questionComments[q.id] ?? '').trim().isNotEmpty)
            _CoachComment(text: review.questionComments[q.id]!),
        ],
      ],
    );
  }
}

/// The coach's note against one answer.
class _CoachComment extends StatelessWidget {
  final String text;
  const _CoachComment({required this.text});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: p.accent.withValues(alpha: 0.07),
        borderRadius: AppRadii.smR,
        border: Border(
          left: BorderSide(color: p.accent.withValues(alpha: 0.55), width: 3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.format_quote, size: 15, color: p.accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: AppText.body(size: 13)
                  .copyWith(color: p.textPrimary, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
