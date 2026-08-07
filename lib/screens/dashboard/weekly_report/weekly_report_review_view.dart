import 'package:flutter/material.dart';

import '../../../core/models/weekly_report_models.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text.dart';

/// The coach's review, as the MEMBER sees it. Entirely read-only.
///
/// What is deliberately absent: the coach's PRIVATE notes. They live in a
/// `private/` subcollection with no member read rule, because Firestore
/// authorizes documents and not fields — a `privateNotes` field on this
/// document would be readable by the member through any direct SDK call
/// whatever this widget chose to draw.
class WeeklyReportReviewView extends StatelessWidget {
  final WeeklyReportReview review;

  const WeeklyReportReviewView({super.key, required this.review});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    // Goals and action items share one array and are told apart by `kind`. An
    // unknown kind reads as an action item, so a goal written by a newer coach
    // build is shown as a task rather than silently dropped.
    final items = review.actionItems.where((a) => !a.isGoal).toList();
    final goals = review.actionItems.where((a) => a.isGoal).toList();

    return Container(
      padding: const EdgeInsets.all(18),
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
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.rate_review_outlined,
                    size: 17, color: p.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.reviewerName.isEmpty
                          ? 'Coach feedback'
                          : review.reviewerName,
                      style: AppText.cardTitle(size: 15)
                          .copyWith(color: p.textPrimary),
                    ),
                    if (review.reviewedAt != null)
                      Text(
                        _dateLabel(review.reviewedAt!),
                        style: AppText.body(size: 11.5)
                            .copyWith(color: p.textMuted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (review.visibleNotes.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              review.visibleNotes,
              style: AppText.body(size: 14).copyWith(
                color: p.textPrimary,
                height: 1.5,
              ),
            ),
          ],
          if (items.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('ACTION ITEMS',
                style: AppText.label(size: 11)
                    .copyWith(color: p.textSecondary, letterSpacing: 1.1)),
            const SizedBox(height: 10),
            for (final a in items)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      a.done
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 17,
                      color: a.done ? p.accent : p.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        a.text,
                        style: AppText.body(size: 13.5).copyWith(
                          color: a.done ? p.textMuted : p.textPrimary,
                          decoration:
                              a.done ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (goals.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text('GOALS',
                style: AppText.label(size: 11)
                    .copyWith(color: p.textSecondary, letterSpacing: 1.1)),
            const SizedBox(height: 10),
            for (final g in goals)
              Padding(
                padding: const EdgeInsets.only(bottom: 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.flag_outlined, size: 17, color: p.accent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            g.text,
                            style: AppText.body(size: 13.5)
                                .copyWith(color: p.textPrimary),
                          ),
                          if (g.dueAt != null)
                            Text(
                              'By ${_dateLabel(g.dueAt!)}',
                              style: AppText.label(size: 11)
                                  .copyWith(color: p.accent),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (review.followUpAt != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: AppRadii.smR,
              ),
              child: Row(
                children: [
                  Icon(Icons.event_outlined, size: 16, color: p.textSecondary),
                  const SizedBox(width: 10),
                  Text(
                    'Follow-up on ${_dateLabel(review.followUpAt!)}',
                    style: AppText.body(size: 12.5)
                        .copyWith(color: p.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _dateLabel(DateTime d) {
    const m = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${m[d.month - 1]} ${d.year}';
  }
}
