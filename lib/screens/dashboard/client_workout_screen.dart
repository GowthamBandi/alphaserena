import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../../controllers/membership_controller.dart';
import '../../controllers/training_controller.dart';
import '../../core/domain/prescription.dart' show ExpectationKind;
import '../../core/domain/today_expectation.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/gradient_title.dart';
import 'membership_screen.dart';
import 'workout_player_screen.dart';

class ClientWorkoutScreen extends StatelessWidget {
  ClientWorkoutScreen({super.key});

  final TrainingController c = Get.isRegistered<TrainingController>()
      ? Get.find<TrainingController>()
      : Get.put(TrainingController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          if (c.isLoading.value) {
            return Center(
                child:
                    CircularProgressIndicator(strokeWidth: 2.4, color: p.accent));
          }
          // A load FAILURE must not read as "no plan assigned" — show a distinct
          // error with a Retry action (the coach didn't remove anything).
          if (c.error.value.isNotEmpty && c.workout.value == null) {
            return _errorState(p, c.load);
          }
          // getMyTraining returns null for BOTH "no active plan" and
          // "membership lapsed" — disambiguate so an expired member is told to
          // renew instead of believing the coach abandoned them.
          if (c.workout.value == null && _membershipInactive) {
            return _renewState(p);
          }
          final items = c.workoutItems;
          return RefreshIndicator(
            onRefresh: c.load,
            color: p.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
              children: [
                const GradientTitle('YOUR WORKOUT',
                    size: 30, textAlign: TextAlign.start),
                const SizedBox(height: 4),
                Text(
                  c.workout.value?['name']?.toString() ?? 'No workout assigned yet',
                  style: AppText.body(size: 14).copyWith(color: p.textMuted),
                ),
                // PRESCRIPTION ENGINE: this screen shows the PLAN; one line
                // says what today asks of it, so it can never contradict Home.
                Builder(builder: (context) {
                  final line = _todayLine(c.workoutExpectation);
                  if (line.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(children: [
                      Icon(Icons.event_available_rounded,
                          size: 13, color: p.accent),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          line,
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textSecondary),
                        ),
                      ),
                    ]),
                  );
                }),
                const SizedBox(height: 20),
                if (items.isEmpty)
                  _empty(p)
                else
                  ...items.asMap().entries.map((e) => _exerciseCard(
                      context, p, e.key + 1, e.value)),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _exerciseCard(
      BuildContext context, AppPalette p, int n, Map<String, dynamic> ex) {
    final sets = (ex['sets'] ?? 0).toString();
    final reps = (ex['reps'] ?? 0).toString();
    final hasVideo = (ex['videoUrl'] ?? '').toString().isNotEmpty;
    final name = ex['name']?.toString() ?? 'Exercise';
    return Semantics(
      button: true,
      label: '$name, $sets sets of $reps reps'
          '${hasVideo ? ', has a demo video' : ''}',
      excludeSemantics: true,
      child: Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.cardR,
          onTap: () => Get.to(() => WorkoutPlayerScreen(exercise: ex)),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: p.accent.withValues(alpha: 0.12),
                      borderRadius: AppRadii.smR),
                  child: Text('$n',
                      style: AppText.title(size: 18).copyWith(color: p.accent)),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(ex['name']?.toString() ?? 'Exercise',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppText.label(size: 14)
                              .copyWith(color: p.textPrimary)),
                      const SizedBox(height: 2),
                      Text('$sets sets × $reps reps',
                          style: AppText.body(size: 12)
                              .copyWith(color: p.textMuted)),
                    ],
                  ),
                ),
                Icon(hasVideo ? Icons.play_circle_fill : Icons.chevron_right,
                    color: hasVideo ? p.accent : p.textMuted, size: 26),
              ],
            ),
          ),
        ),
      ),
      ),
    );
  }

  /// Linked to a coach but the membership is expired/frozen — the server now
  /// blanks training at the data layer for lapsed members.
  bool get _membershipInactive =>
      Get.isRegistered<MemberController>() &&
      Get.isRegistered<MembershipController>() &&
      Get.find<MemberController>().isLinked.value &&
      // The clients doc must have ARRIVED before we can call the membership
      // inactive — during cold load isLinked (from clientProfiles) resolves
      // before the clients stream, and a null doc would read as "inactive",
      // flashing the renew state at active members with no plan.
      Get.find<MemberController>().client.value != null &&
      !Get.find<MembershipController>().isActive;

  static Widget _renewState(AppPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.lock_outline_rounded, size: 44, color: p.accent),
            const SizedBox(height: 14),
            Text('Membership inactive',
                style: AppText.title(size: 16).copyWith(color: p.textPrimary)),
            const SizedBox(height: 6),
            Text(
              'Your plan is safe — renew your membership to unlock your workouts again.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 13).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 18),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              onPressed: () => Get.to(() => MembershipScreen()),
              child: Text('Renew Membership', style: AppText.label(size: 13)),
            ),
          ]),
        ),
      );

  Widget _empty(AppPalette p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 50),
        child: Column(children: [
          Icon(Icons.fitness_center, size: 40, color: p.textMuted),
          const SizedBox(height: 12),
          Text('No workout assigned yet',
              style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
          const SizedBox(height: 4),
          Text('Your trainer will assign one soon.',
              style: AppText.body(size: 13).copyWith(color: p.textMuted)),
        ]),
      );

  /// One line on what TODAY asks of this plan — served by the backend, never
  /// computed here. '' stays silent (required day, unknown, legacy backend).
  static String _todayLine(ServedExpectation? e) {
    if (e == null) return '';
    if (e.excusedToday) return 'Today is excused by your coach.';
    switch (e.kind) {
      case ExpectationKind.rest:
        return 'Rest day today — prescribed by your coach.';
      case ExpectationKind.paused:
        return 'Coaching is paused — nothing counts against you.';
      case ExpectationKind.optional:
        return e.reason == 'frequency' && e.frequencyCount > 0
            ? 'Flexible week — any ${e.frequencyCount} sessions, you pick '
                'the days.'
            : 'Training today is optional.';
      case ExpectationKind.notYetStarted:
        return 'This plan hasn\'t started yet.';
      case ExpectationKind.ended:
        return 'This plan has finished — ask your coach for the next block.';
      case ExpectationKind.required:
      case ExpectationKind.unknown:
        return '';
    }
  }

  /// Distinct from the empty state: the load FAILED (network/server), so offer a
  /// Retry rather than implying the coach hasn't assigned a plan.
  static Widget _errorState(AppPalette p, Future<void> Function() onRetry) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.cloud_off_rounded, size: 44, color: p.textMuted),
            const SizedBox(height: 14),
            Text("Couldn't load your training",
                style: AppText.label(size: 15).copyWith(color: p.textSecondary)),
            const SizedBox(height: 4),
            Text('Check your connection and try again.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 13).copyWith(color: p.textMuted)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(backgroundColor: p.accent),
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
              label: Text('Retry',
                  style: AppText.label(size: 14).copyWith(color: Colors.white)),
            ),
          ]),
        ),
      );
}
