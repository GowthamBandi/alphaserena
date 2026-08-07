import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/weekly_report_controller.dart';
import '../../../core/models/weekly_report_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/weekly_reports/question_engine.dart';
import '../../../core/weekly_reports/question_renderers.dart';
import 'weekly_report_review_view.dart';

/// Every weekly report the member has ever been issued, newest first.
///
/// IMMUTABLE BY CONSTRUCTION, not by discipline: each row renders its own
/// FROZEN snapshot, so a 2025 report shows the questions asked in 2025 even
/// after the coach has rewritten the template five times. Nothing on this screen
/// can write.
class WeeklyReportHistoryScreen extends StatelessWidget {
  const WeeklyReportHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final c = Get.isRegistered<WeeklyReportController>()
        ? Get.find<WeeklyReportController>()
        : Get.put(WeeklyReportController());

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        title: Text('Report history',
            style: AppText.title(size: 19).copyWith(color: p.textPrimary)),
      ),
      body: Obx(() {
        final list = c.history;
        if (c.isLoading.value) {
          return const Center(child: CircularProgressIndicator());
        }
        if (list.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No reports yet. Your history builds up one week at a time.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 13.5).copyWith(color: p.textMuted),
              ),
            ),
          );
        }

        final rollup = c.rollup.value;
        final keys = rollup.trendableKeys;

        return ListView(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
          children: [
            if (keys.isNotEmpty) ...[
              Text('TRENDS',
                  style: AppText.label(size: 12)
                      .copyWith(color: p.textSecondary, letterSpacing: 1.1)),
              const SizedBox(height: 12),
              for (final k in keys)
                _TrendCard(analyticsKey: k, points: rollup.seriesFor(k)),
              const SizedBox(height: 22),
            ],
            Text('WEEK BY WEEK',
                style: AppText.label(size: 12)
                    .copyWith(color: p.textSecondary, letterSpacing: 1.1)),
            const SizedBox(height: 12),
            for (final s in list)
              _HistoryTile(
                snapshot: s,
                submission: c.submissionFor(s.id),
                review: c.reviewFor(s.id),
              ),
          ],
        );
      }),
    );
  }
}

/// One expandable week.
class _HistoryTile extends StatelessWidget {
  final WeeklyReportSnapshot snapshot;
  final WeeklyReportSubmission? submission;
  final WeeklyReportReview? review;

  const _HistoryTile({
    required this.snapshot,
    required this.submission,
    required this.review,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final answers = submission?.answers ?? const <String, dynamic>{};
    final visible = visibleQuestions(snapshot.questions, answers);
    final status = historyStatusOf(snapshot, submission, review, p);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Theme(
        // The default divider makes an expansion tile look like a table row.
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          title: Text(
            snapshot.periodLabel,
            style: AppText.cardTitle(size: 14.5).copyWith(color: p.textPrimary),
          ),
          subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child: Text(
              snapshot.periodKey,
              style: AppText.body(size: 11.5).copyWith(color: p.textMuted),
            ),
          ),
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: status.$2.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              status.$1,
              style: AppText.label(size: 10.5).copyWith(color: status.$2),
            ),
          ),
          children: [
            if (submission == null || !submission!.hasContent)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  snapshot.isMissed
                      ? 'This report was not submitted.'
                      : 'No answers recorded for this week.',
                  style: AppText.body(size: 13).copyWith(color: p.textMuted),
                ),
              )
            else ...[
              if (review != null && review!.hasFeedback) ...[
                WeeklyReportReviewView(review: review!),
                const SizedBox(height: 16),
              ],
              for (final q in visible) ...[
                QuestionCard(
                  key: ValueKey('${snapshot.id}_${q.id}'),
                  ctx: QuestionRenderContext(
                    question: q,
                    value: answerValue(answers, q.id),
                    readOnly: true,
                    onChanged: (_) {},
                  ),
                ),
                // The coach's comment on THIS answer, kept beside it here as
                // well — history that drops half the conversation is not the
                // record it claims to be. Gated on a COMPLETED review for the
                // same reason the live screen is: a saved draft is not a
                // message.
                if (review?.isCompleted == true &&
                    (review!.questionComments[q.id] ?? '').trim().isNotEmpty)
                  _Comment(text: review!.questionComments[q.id]!),
              ],
            ],
          ],
        ),
      ),
    );
  }

}

/// (label, colour) for one week in the history timeline.
///
/// Pure and public so the rule is provable without rendering the screen — the
/// same shape as the coach app's `bucketFor`.
///
/// A missed week reads as missed: softening it would make the record less
/// useful to the member than to nobody.
///
/// ⚠️ A REVIEWED week must not read the same as one the coach has not opened.
/// This label used to ignore the review entirely — which the row already held,
/// and already rendered below — so every week the coach had answered still said
/// "Sent", and the timeline could not tell the member which weeks carried
/// feedback without expanding each one. The report screen said "Your coach has
/// reviewed it" at the same moment: two surfaces, one fact, two answers.
(String, Color) historyStatusOf(
  WeeklyReportSnapshot s,
  WeeklyReportSubmission? sub,
  WeeklyReportReview? review,
  AppPalette p,
) {
  if (s.isSubmitted) {
    return review?.isCompleted == true
        ? ('Reviewed', p.success)
        : ('Sent', p.accent);
  }
  if (s.isMissed) return ('Missed', p.error);
  if (s.isCancelled) return ('Cancelled', p.textMuted);
  if (sub?.hasContent == true) return ('Draft', p.textSecondary);
  return ('Open', p.textSecondary);
}

/// The coach's note against one answer, inside a history row.
class _Comment extends StatelessWidget {
  final String text;
  const _Comment({required this.text});

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
            child: Text(text,
                style: AppText.body(size: 13)
                    .copyWith(color: p.textPrimary, height: 1.45)),
          ),
        ],
      ),
    );
  }
}

/// A sparkline for one analytics series, drawn from the server rollup.
///
/// Only rendered for keys with ≥2 points — one point is not a trend, and drawing
/// it as a flat line invents a story the data does not tell.
class _TrendCard extends StatelessWidget {
  final String analyticsKey;
  final List<TrendPoint> points;

  const _TrendCard({required this.analyticsKey, required this.points});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final first = points.first.value;
    final last = points.last.value;
    final delta = last - first;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _humanize(analyticsKey),
                  style: AppText.cardTitle(size: 14)
                      .copyWith(color: p.textPrimary),
                ),
              ),
              Text(
                _plain(last),
                style: AppText.title(size: 17).copyWith(color: p.accent),
              ),
              if (delta != 0) ...[
                const SizedBox(width: 6),
                Icon(
                  delta > 0 ? Icons.trending_up : Icons.trending_down,
                  size: 15,
                  // NO good/bad colouring. Whether "stress up" is good depends
                  // on the question, and this widget does not know which
                  // question it is drawing.
                  color: p.textMuted,
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: CustomPaint(
              size: Size.infinite,
              painter: _SparklinePainter(
                values: points.map((e) => e.value).toList(),
                color: p.accent,
                baseline: p.border,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${points.length} weeks · ${points.first.periodKey} → ${points.last.periodKey}',
            style: AppText.body(size: 11).copyWith(color: p.textMuted),
          ),
        ],
      ),
    );
  }

  static String _plain(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);

  /// `workout_satisfaction` → `Workout satisfaction`. The engine names series in
  /// snake_case; nothing stores a display label, so deriving one beats
  /// inventing a second vocabulary that would drift from the first.
  static String _humanize(String key) {
    final words = key.split('_').where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return key;
    return words
        .asMap()
        .entries
        .map((e) => e.key == 0
            ? '${e.value[0].toUpperCase()}${e.value.substring(1)}'
            : e.value)
        .join(' ');
  }
}

class _SparklinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  final Color baseline;

  _SparklinePainter({
    required this.values,
    required this.color,
    required this.baseline,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var min = values.first;
    var max = values.first;
    for (final v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    // A flat series must draw a flat line through the middle, not divide by a
    // zero range.
    final span = (max - min).abs() < 1e-9 ? 1.0 : (max - min);
    final dx = size.width / (values.length - 1);

    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = dx * i;
      final y = size.height - ((values[i] - min) / span) * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawLine(
      Offset(0, size.height),
      Offset(size.width, size.height),
      Paint()
        ..color = baseline
        ..strokeWidth = 1,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    // The latest point, marked — it is the number the member came to read.
    final lastX = dx * (values.length - 1);
    final lastY =
        size.height - ((values.last - min) / span) * size.height;
    canvas.drawCircle(Offset(lastX, lastY), 3.2, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SparklinePainter old) =>
      old.values != values || old.color != color;
}
