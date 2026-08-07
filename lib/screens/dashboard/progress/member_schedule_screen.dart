import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../../controllers/check_in_controller.dart';
import '../../../controllers/member_controller.dart';
import '../../../controllers/training_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/serena/premium_states.dart';
import '../weekly_report/weekly_report_screen.dart';
import 'progress_ui.dart';

/// THE MEMBER'S SCHEDULE.
///
/// ── AN HONEST NOTE ON WHAT THIS IS ────────────────────────────────────────
///
/// The audit looked for a member-side schedule module to reuse and found none.
/// What exists is:
///
///   • the COACH's review board (`CheckInsScreen` in TrainerHQ) — coach-only,
///     reading `client_checkins` and `client_review_events`, neither of which
///     the member app is permitted or wired to read;
///   • a single boolean on the member's side — `CheckInController.isDue`,
///     derived from `clients.nextCheckInAt`;
///   • the weekly training shape, served inside `getMyTraining` and rendered on
///     exactly one screen (My Plans).
///
/// So this composes the schedule signals the member ALREADY OWNS into one
/// place. It introduces NO new collection, NO new query, NO new Cloud Function
/// and NO new field. Every value below is already streamed by a controller the
/// dashboard has running.
///
/// What it deliberately does NOT do is invent a calendar. There is no
/// appointment booking, no session clock-time and no recurring event store
/// anywhere in this platform — `today_schedule_section.dart` in the coach app
/// says so in its own header — so a month grid here would be a grid of
/// nothing.
class MemberScheduleScreen extends StatelessWidget {
  const MemberScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final training = Get.find<TrainingController>();
    final member = Get.find<MemberController>();
    final checkIn = Get.isRegistered<CheckInController>()
        ? Get.find<CheckInController>()
        : null;

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Schedule',
          style: AppText.title(size: 19).copyWith(color: p.textPrimary),
        ),
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          color: p.accent,
          onRefresh: () async {
            await member.claim();
            await training.load();
          },
          child: Obx(() {
            // Touch the observables this build depends on BEFORE any early
            // return. A memoized/short-circuiting Obx that reads no Rx stays
            // subscribed to nothing and silently stops updating — a defect this
            // codebase has already shipped once.
            final loading = training.isLoading.value;
            final weekly = training.weeklyOverview;
            final restToday = training.isWeeklyRestDay;
            final nextDay = training.nextTrainingDay;
            final due = checkIn?.isDue ?? false;
            final nextReview = checkIn?.nextCheckInAt;
            final cadence = _cadenceOf(member.client.value);

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 32),
              children: [
                _reviewCard(context, p, due, nextReview, cadence),
                const SizedBox(height: 16),
                const ProgressSectionHeader(
                  title: 'Training week',
                  subtitle: 'The shape your coach set for this week',
                ),
                const SizedBox(height: 10),
                if (loading)
                  const SerenaSkeleton(height: 190)
                else
                  _weekCard(context, p, weekly, restToday, nextDay),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// `clients.checkInCadenceDays`, written by the coach's `CheckInService`.
  static int? _cadenceOf(Map<String, dynamic>? client) {
    final raw = client?['checkInCadenceDays'];
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  Widget _reviewCard(
    BuildContext context,
    AppPalette p,
    bool due,
    DateTime? next,
    int? cadence,
  ) {
    final String headline;
    final String detail;
    final Color tint;

    if (next == null) {
      // NO SCHEDULE IS NOT AN OVERDUE SCHEDULE. A member whose coach has not
      // set a cadence must not be shown a red badge for missing a date nobody
      // asked them to hit.
      headline = 'No review scheduled';
      detail =
          'Your coach has not set a check-in rhythm yet. You can still send '
          'one whenever you want them to look.';
      tint = p.textMuted;
    } else if (due) {
      final days = DateTime.now().difference(next).inDays;
      headline = days <= 0 ? 'Check-in due today' : 'Check-in due';
      detail = days <= 0
          ? 'Scheduled for ${DateFormat('EEEE d MMMM').format(next.toLocal())}.'
          : 'Was due ${DateFormat('EEEE d MMMM').format(next.toLocal())} · '
                '$days ${days == 1 ? 'day' : 'days'} ago.';
      tint = kProgressAmber;
    } else {
      final days = next.difference(DateTime.now()).inDays;
      headline = 'Next check-in';
      detail =
          '${DateFormat('EEEE d MMMM').format(next.toLocal())}'
          '${days <= 0 ? '' : ' · in $days ${days == 1 ? 'day' : 'days'}'}.';
      tint = kProgressGreen;
    }

    return ProgressCard(
      accent: due,
      onTap: () => Get.to(() => const WeeklyReportScreen()),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: tint.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.event_available_rounded, color: tint, size: 21),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  headline,
                  style: AppText.title(
                    size: 15.5,
                  ).copyWith(color: p.textPrimary),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  style: AppText.body(
                    size: 12,
                  ).copyWith(color: p.textMuted, height: 1.35),
                ),
                if (cadence != null && cadence > 0) ...[
                  const SizedBox(height: 5),
                  Text(
                    'Every $cadence ${cadence == 1 ? 'day' : 'days'}',
                    style: AppText.body(size: 11).copyWith(color: p.textMuted),
                  ),
                ],
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: p.textMuted, size: 20),
        ],
      ),
    );
  }

  Widget _weekCard(
    BuildContext context,
    AppPalette p,
    Map<String, dynamic>? weekly,
    bool restToday,
    Map<String, dynamic>? nextDay,
  ) {
    if (weekly == null) {
      // A single-plan assignment and NO assignment are different facts, and
      // neither is a weekly schedule. Saying "no schedule" for a member on a
      // single plan would be wrong; saying "rest day" would be worse.
      return const ProgressCard(
        child: ProgressUnavailable(
          title: 'No weekly schedule',
          reason:
              'Your coach has not mapped a day-by-day week. When they do, it '
              'appears here — including which days are rest days.',
        ),
      );
    }

    final rawDays = (weekly['days'] as List?) ?? const [];
    final mapped = <String, String>{};
    String? todayName;
    for (final raw in rawDays) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final day = (m['day'] ?? '').toString();
      if (day.isEmpty) continue;
      mapped[day] = (m['planName'] ?? '').toString();
      if (m['isToday'] == true) todayName = day;
    }

    const week = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday',
    ];

    return ProgressCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            (weekly['name'] ?? 'Weekly plan').toString(),
            style: AppText.title(size: 15.5).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 12),
          for (final day in week) ...[
            _dayRow(
              p,
              day: day,
              plan: mapped[day],
              isToday: day == todayName,
            ),
            if (day != week.last) const SizedBox(height: 8),
          ],
          if (restToday && nextDay != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: p.surfaceAlt,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Row(
                children: [
                  Icon(Icons.bedtime_outlined, size: 17, color: p.textMuted),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      'Rest day. Next up: '
                      '${(nextDay['planName'] ?? 'training').toString()} on '
                      '${(nextDay['day'] ?? '').toString()}.',
                      style: AppText.body(
                        size: 12,
                      ).copyWith(color: p.textSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dayRow(
    AppPalette p, {
    required String day,
    required String? plan,
    required bool isToday,
  }) {
    // An unmapped weekday IS a rest day — that is the serving contract
    // (`weekly_serving.ts resolveWeeklyDay`), not a guess made here.
    final rest = plan == null;
    return Semantics(
      container: true,
      label: isToday
          ? 'Today, $day: ${rest ? 'rest day' : plan}'
          : '$day: ${rest ? 'rest day' : plan}',
      excludeSemantics: true,
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              day.substring(0, 3),
              style: AppText.label(size: 11.5).copyWith(
                color: isToday ? p.accent : p.textMuted,
              ),
            ),
          ),
          Container(
            width: 7,
            height: 7,
            margin: const EdgeInsets.only(right: 11),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: rest ? p.border : (isToday ? p.accent : kProgressGreen),
            ),
          ),
          Expanded(
            child: Text(
              rest ? 'Rest day' : plan,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.body(size: 12.5).copyWith(
                color: rest ? p.textMuted : p.textPrimary,
              ),
            ),
          ),
          if (isToday)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                'Today',
                style: AppText.label(size: 10).copyWith(color: p.accent),
              ),
            ),
        ],
      ),
    );
  }
}
