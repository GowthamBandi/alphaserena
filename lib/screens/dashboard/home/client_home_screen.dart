import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

import '../../../controllers/home_controller.dart';
import '../../../controllers/diet_log_controller.dart';
import '../../../controllers/check_in_controller.dart';
import '../../../controllers/theme_controller.dart';
import '../../../core/constants/quotes.dart';
import '../../../core/services/coach_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../join/coach_storefront_screen.dart';
import '../../join/join_coach_screen.dart';
import '../../onboarding/onboarding_flow_screen.dart';
import '../../../core/models/app_notification.dart';
import '../../../core/services/notification_center_service.dart';
import '../check_in_screen.dart';
import '../client_chat_screen.dart';
import '../client_diet_screen.dart';
import '../lifestyle_today_screen.dart';
import '../membership_screen.dart';
import '../notification_center_screen.dart';
import '../workout_session_screen.dart';
import '../workout_player_screen.dart';

/// Home Dashboard — dynamic greeting, partner card, nutrition, progress, today's workout.
class ClientHomeScreen extends StatelessWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final h = Get.isRegistered<HomeController>()
        ? Get.find<HomeController>()
        : Get.put(HomeController());
    final dietLog = Get.isRegistered<DietLogController>()
        ? Get.find<DietLogController>()
        : Get.put(DietLogController());
    final checkIn = Get.isRegistered<CheckInController>()
        ? Get.find<CheckInController>()
        : Get.put(CheckInController());

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          if (h.isLoading) {
            return _skeletonLoader(p);
          }

          final linked = h.isLinked;
          final active = h.membershipController.isActive;
          final stage = h.stage;

          return RefreshIndicator(
            onRefresh: h.refreshAll,
            color: p.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                _header(h, p),
                const SizedBox(height: 16),
                
                // Expiry banner if expiring in <= 7 days
                if (linked && active && h.showExpiryBanner)
                  _expiryBanner(h, p),

                // Main Coach / Partner Card
                if (linked) _partnerCard(h, p) else _unlinkedCard(p),
                const SizedBox(height: 18),

                // If not linked or not active, display blockers and skip the private content
                if (!linked) ...[
                  const SizedBox(height: 12),
                  // Render a motivational quote since we don't have plans to show
                  _quote(p),
                ] else if (!active) ...[
                  _inactiveMembershipCard(h, p),
                  const SizedBox(height: 18),
                  _quote(p),
                ] else if (h.trainingController.error.value.isNotEmpty &&
                    !h.hasPlan) ...[
                  // A load FAILURE must not read as a lifecycle stage ("coach is
                  // preparing your plan") — show a distinct error + Retry.
                  _trainingErrorCard(h, p),
                  const SizedBox(height: 18),
                  _quote(p),
                ] else if (stage != ClientStage.ready) ...[
                  // Active member, but the coaching lifecycle isn't ready yet —
                  // guide them through onboarding → coach → plan instead of
                  // showing empty/placeholder plan content.
                  _gettingStartedCard(h, stage, p),
                  const SizedBox(height: 18),
                  _quote(p),
                ] else ...[
                  // Normal wired dashboard widgets for active subscribers
                  _nutrition(h, dietLog, p),
                  const SizedBox(height: 18),
                  _lifestyleTodayCard(p),
                  const SizedBox(height: 18),
                  _checkInCard(checkIn, p),
                  const SizedBox(height: 18),
                  _progressOverview(h, p),
                  const SizedBox(height: 18),
                  _quote(p),
                  const SizedBox(height: 18),
                  _todaysWorkout(h, p),
                ],
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _trainingErrorCard(HomeController h, AppPalette p) {
    return Container(
      decoration: glassCard(p),
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, color: p.accent, size: 34),
          const SizedBox(height: 10),
          Text("Couldn't load your plan",
              style: AppText.cardTitle(size: 15).copyWith(color: p.textPrimary)),
          const SizedBox(height: 4),
          Text('Check your connection and try again.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 12).copyWith(color: p.textMuted)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => h.trainingController.load(),
              style: ElevatedButton.styleFrom(backgroundColor: p.accent),
              icon: const Icon(Icons.refresh, size: 18, color: Colors.white),
              label: Text('Retry',
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _checkInCard(CheckInController c, AppPalette p) {
    return GestureDetector(
      onTap: () => Get.to(() => const CheckInScreen()),
      child: Container(
        decoration: glassCard(p),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.assignment_turned_in_outlined, color: p.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Obx(() {
                final due = c.isDue;
                final next = c.nextCheckInAt;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weekly check-in',
                      style: AppText.cardTitle(size: 14)
                          .copyWith(color: p.textPrimary),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      due
                          ? 'Due now — tell your coach how the week went'
                          : next != null
                              ? 'Next ${next.day}/${next.month} · submit anytime'
                              : 'Rate your week, weight & notes for your coach',
                      style: AppText.body(size: 12).copyWith(
                          color: due ? const Color(0xFFF59E0B) : p.textMuted),
                    ),
                  ],
                );
              }),
            ),
            Obx(() => c.isDue
                ? Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text('Due',
                        style: AppText.body(size: 10.5).copyWith(
                            color: const Color(0xFFF59E0B),
                            fontWeight: FontWeight.w700)),
                  )
                : Icon(Icons.chevron_right, color: p.textMuted)),
          ],
        ),
      ),
    );
  }

  Widget _lifestyleTodayCard(AppPalette p) {
    return GestureDetector(
      onTap: () => Get.to(() => const LifestyleTodayScreen()),
      child: Container(
        decoration: glassCard(p),
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(Icons.favorite_border, color: p.accent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Track today — water, steps, sleep, supplements',
                style:
                    AppText.cardTitle(size: 14).copyWith(color: p.textPrimary),
              ),
            ),
            Icon(Icons.chevron_right, color: p.textMuted),
          ],
        ),
      ),
    );
  }

  Widget _header(HomeController h, AppPalette p) {
    final hour = DateTime.now().hour;
    final String greetingPrefix;
    if (hour < 12) {
      greetingPrefix = 'Good Morning';
    } else if (hour < 17) {
      greetingPrefix = 'Good Afternoon';
    } else {
      greetingPrefix = 'Good Evening';
    }

    final streak = h.dailyStreak;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '$greetingPrefix, ${h.greetingName}!',
                    style: GoogleFonts.poppins(
                      color: p.textPrimary,
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Text('👋', style: TextStyle(fontSize: 15)),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'Ready to crush your goals today?',
                style: GoogleFonts.poppins(color: p.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
        if (streak > 0) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: p.accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: p.accent.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Icon(Icons.local_fire_department, color: p.accent, size: 16),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$streak',
                      style: GoogleFonts.poppins(
                        color: p.textPrimary,
                        fontSize: 13,
                        height: 1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'Day Streak',
                      style: GoogleFonts.poppins(color: p.textMuted, fontSize: 8.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
        ],
        _notificationBell(p),
        const SizedBox(width: 8),
        _themeToggle(p),
      ],
    );
  }

  /// Bell + live unread badge (streams the `notifications/{uid}` summary
  /// doc). Tap opens the notification center, which zeroes the counter.
  Widget _notificationBell(AppPalette p) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    if (uid.isEmpty) return const SizedBox.shrink();
    return StreamBuilder<NotificationSummary>(
      stream: NotificationCenterService().watchSummary(uid),
      builder: (context, snap) {
        final unread = snap.data?.unread ?? 0;
        return Semantics(
          button: true,
          label: unread > 0
              ? 'Notifications, $unread unread'
              : 'Notifications',
          excludeSemantics: true,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Get.to(() => const NotificationCenterScreen()),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: p.border),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(Icons.notifications_none_rounded,
                        color: p.textPrimary, size: 20),
                    if (unread > 0)
                      Positioned(
                        top: -5,
                        right: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1.5),
                          constraints: const BoxConstraints(minWidth: 15),
                          decoration: BoxDecoration(
                            color: p.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            unread > 99 ? '99+' : '$unread',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 8.5,
                              height: 1.2,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Dark/light toggle (mirrors trainersHQ) — sits in the header, same line as
  /// the greeting. Sun icon while dark (tap → light), moon while light.
  Widget _themeToggle(AppPalette p) {
    final theme = Get.find<ThemeController>();
    return Obx(() {
      final dark = theme.isDarkMode.value;
      return Semantics(
        button: true,
        label: dark ? 'Switch to light mode' : 'Switch to dark mode',
        excludeSemantics: true,
        child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: theme.toggleTheme,
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: p.border),
            ),
            child: Icon(
              dark ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
              color: dark ? BrandColors.amber : p.textPrimary,
              size: 19,
            ),
          ),
        ),
      ),
      );
    });
  }

  Widget _expiryBanner(HomeController h, AppPalette p) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: p.error.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: p.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: p.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              h.membershipExpiryText,
              style: AppText.body(size: 12).copyWith(color: p.error, fontWeight: FontWeight.w600),
            ),
          ),
          GestureDetector(
            onTap: () => Get.to(() => MembershipScreen()),
            child: Text(
              'Renew',
              style: AppText.label(size: 12).copyWith(color: p.accent, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  /// The coach card. Organization is ALWAYS shown (tap → storefront). The
  /// trainer side appears only once the coach has been assigned a trainer
  /// (`clients.trainerId`); before that we show the organization alone. When a
  /// trainer is assigned, their tile carries a message icon → chat.
  Widget _partnerCard(HomeController h, AppPalette p) {
    final hasTrainer = h.hasTrainer;
    return Container(
      decoration: glassCard(p, radius: 16),
      child: Row(
        children: [
          Expanded(child: _orgTile(h, p, showChevron: !hasTrainer)),
          if (hasTrainer) ...[
            Container(width: 1, height: 50, color: p.border),
            Expanded(child: _trainerTile(h, p)),
          ],
        ],
      ),
    );
  }

  Widget _orgTile(HomeController h, AppPalette p, {required bool showChevron}) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openStorefront(h),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: p.surfaceAlt,
                  borderRadius: BorderRadius.circular(9),
                ),
                alignment: Alignment.center,
                child: const AlphaAMark(size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            h.gymName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: p.textPrimary,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 3),
                        Icon(Icons.verified, color: p.accent, size: 12),
                      ],
                    ),
                    Text(
                      'View Storefront',
                      style: GoogleFonts.poppins(color: p.textMuted, fontSize: 9.5),
                    ),
                  ],
                ),
              ),
              if (showChevron)
                Icon(Icons.chevron_right, color: p.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _trainerTile(HomeController h, AppPalette p) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: const BorderRadius.only(
          topRight: Radius.circular(16),
          bottomRight: Radius.circular(16),
        ),
        onTap: () => Get.to(() => const ClientChatScreen()),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              ClipOval(
                child: Image.asset(
                  'assets/images/trainer.png',
                  width: 38,
                  height: 38,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    width: 38,
                    height: 38,
                    color: p.surfaceAlt,
                    alignment: Alignment.center,
                    child: Text(
                      h.coachName.isNotEmpty ? h.coachName[0].toUpperCase() : 'C',
                      style: AppText.title(size: 14).copyWith(color: p.accent),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your Coach',
                      style: GoogleFonts.poppins(
                        color: p.accent,
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      h.coachName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: p.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(Icons.chat_bubble_outline_rounded,
                    color: p.accent, size: 17),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Loads the member's own coach storefront (`organizationProfiles/{adminId}`)
  /// then opens it. Shows a brief loader; falls back to a snackbar on miss/error.
  Future<void> _openStorefront(HomeController h) async {
    final adminId = h.memberController.adminId;
    if (adminId.isEmpty) return;
    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );
    try {
      final org = await CoachService().byId(adminId);
      if (Get.isDialogOpen ?? false) Get.back();
      if (org != null) {
        Get.to(() => CoachStorefrontScreen(org: org));
      } else {
        Get.snackbar('Unavailable', 'Your coach\'s storefront isn\'t available right now.');
      }
    } catch (_) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar('Error', 'Could not open the storefront. Check your connection.');
    }
  }

  Widget _unlinkedCard(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: glassCard(p, radius: 16),
      child: Column(
        children: [
          Icon(Icons.link_off_rounded, color: p.accent, size: 36),
          const SizedBox(height: 12),
          Text(
            'Connect to a Coach',
            style: AppText.title(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'No coach linked yet. Find a coach or enter a handle to unlock your workout and nutrition plans.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () => Get.to(() => const JoinCoachScreen()),
            child: Text('Find a Coach', style: AppText.label(size: 13)),
          ),
        ],
      ),
    );
  }

  Widget _inactiveMembershipCard(HomeController h, AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: glassCard(p, radius: 16),
      child: Column(
        children: [
          Icon(Icons.lock_outline_rounded, color: p.accent, size: 36),
          const SizedBox(height: 12),
          Text(
            'Membership Inactive',
            style: AppText.title(size: 16).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            'Subscribe to a plan to unlock your daily training routines, diet charts, and chat with your trainer.',
            textAlign: TextAlign.center,
            style: AppText.body(size: 12).copyWith(color: p.textMuted),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: p.accent,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            onPressed: () => Get.to(() => MembershipScreen()),
            child: Text('View Membership Plans', style: AppText.label(size: 13)),
          ),
        ],
      ),
    );
  }

  // ── Coaching lifecycle: Getting Started tracker ─────────────────────
  Widget _gettingStartedCard(HomeController h, ClientStage stage, AppPalette p) {
    final String title;
    final String message;
    final bool showCta;
    switch (stage) {
      case ClientStage.onboarding:
        title = 'Complete your onboarding';
        message =
            'Answer a few questions from ${h.coachName} so your plan is built around you.';
        showCta = true;
        break;
      case ClientStage.awaitingTrainer:
        title = 'Coach being assigned';
        message =
            '${h.gymName} is assigning your coach. You\'ll be ready to train shortly.';
        showCta = false;
        break;
      case ClientStage.preparingPlan:
        title = 'Your plan is on the way';
        message =
            'Coach ${h.coachName} is preparing your workout & diet plan. Hang tight!';
        showCta = false;
        break;
      case ClientStage.ready:
        title = '';
        message = '';
        showCta = false;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: glassCard(p, radius: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.rocket_launch_rounded, color: p.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'Getting Started',
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          _stepTracker(stage, p),
          const SizedBox(height: 20),
          Text(
            title,
            style: AppText.title(size: 18).copyWith(color: p.textPrimary),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: AppText.body(size: 12.5).copyWith(color: p.textMuted, height: 1.4),
          ),
          if (showCta) ...[
            const SizedBox(height: 16),
            GradientButton(
              label: 'Complete Onboarding',
              showChevron: true,
              onPressed: () => Get.to(() => const OnboardingFlowScreen()),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stepTracker(ClientStage stage, AppPalette p) {
    const labels = ['Onboarding', 'Coach', 'Plan'];
    final children = <Widget>[];
    for (var i = 0; i < labels.length; i++) {
      final done = stage.index > i;
      final active = stage.index == i;
      children.add(_stepNode(labels[i], i + 1, done, active, p));
      if (i < labels.length - 1) {
        children.add(Expanded(
          child: Container(
            height: 2,
            margin: const EdgeInsets.only(bottom: 18),
            color: stage.index > i ? p.accent : p.border,
          ),
        ));
      }
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _stepNode(String label, int n, bool done, bool active, AppPalette p) {
    final Color ring = done || active ? p.accent : p.border;
    final Color fill = done
        ? p.accent
        : (active ? p.accent.withValues(alpha: 0.14) : p.surface);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: fill,
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 1.6),
          ),
          child: done
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
              : Text(
                  '$n',
                  style: GoogleFonts.poppins(
                    color: active ? p.accent : p.textMuted,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.poppins(
            color: done || active ? p.textPrimary : p.textMuted,
            fontSize: 10.5,
            fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _nutrition(HomeController h, DietLogController diet, AppPalette p) {
    final caloriesGoal = h.targetCalories > 0 ? h.targetCalories : 2000.0;
    final caloriesConsumed = diet.consumedCalories;
    final caloriesLeft = (caloriesGoal - caloriesConsumed).clamp(0.0, caloriesGoal);
    final nutritionPercent = (caloriesConsumed / caloriesGoal).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: glassCard(p, radius: 16),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant, color: Color(0xFF2EBD59), size: 18),
              const SizedBox(width: 8),
              Text(
                'Nutrition Today',
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              GestureDetector(
                onTap: () => Get.to(() => ClientDietScreen()),
                child: Row(
                  children: [
                    Icon(Icons.add, color: p.accent, size: 14),
                    const SizedBox(width: 3),
                    Text(
                      'Log Food',
                      style: GoogleFonts.poppins(
                        color: p.accent,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircularPercentIndicator(
                radius: 52,
                lineWidth: 9,
                percent: nutritionPercent,
                backgroundColor: p.isDark ? const Color(0xFF262626) : const Color(0xFFE0E0E0),
                progressColor: const Color(0xFF2EBD59),
                circularStrokeCap: CircularStrokeCap.round,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${caloriesLeft.round()}',
                      style: GoogleFonts.poppins(
                        color: p.textPrimary,
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'kcal left',
                      style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: _macro('Carbs', diet.consumedCarbs, h.targetCarbs, const Color(0xFF2EBD59), Icons.grain, p)),
                        Expanded(child: _macro('Protein', diet.consumedProtein, h.targetProtein, const Color(0xFF3B82F6), Icons.egg_alt, p)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(child: _macro('Fats', diet.consumedFat, h.targetFat, const Color(0xFFF59E0B), Icons.water_drop, p)),
                        Expanded(child: _macro('Fiber', diet.consumedFiber, h.targetFiber, const Color(0xFF9B5DE5), Icons.spa, p)),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macro(String name, double current, double goal, Color color, IconData icon, AppPalette p) {
    final finalGoal = goal > 0 ? goal : (name == 'Carbs' ? 300.0 : name == 'Protein' ? 150.0 : name == 'Fats' ? 70.0 : 35.0);
    final pct = (current / finalGoal).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 12),
              const SizedBox(width: 4),
              Text(
                name,
                style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Text(
            '${current.round()} / ${finalGoal.round()}g',
            style: GoogleFonts.poppins(
              color: p.textPrimary,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct,
              minHeight: 4,
              backgroundColor: p.isDark ? const Color(0xFF262626) : const Color(0xFFE0E0E0),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressOverview(HomeController h, AppPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart, color: Color(0xFF2EBD59), size: 18),
                const SizedBox(width: 8),
                Text(
                  'Progress Overview',
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _statCard(
                  '${h.latestWeight.toStringAsFixed(1)} kg',
                  'Weight',
                  h.hasWeightTrend ? h.weightDeltaText : null,
                  h.isWeightUp,
                  const Color(0xFF2EBD59),
                  Icons.monitor_weight_outlined,
                  p,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _statCard(
                  // 0 = never measured: show a placeholder, not a fake stat.
                  h.latestBodyFat > 0
                      ? '${h.latestBodyFat.toStringAsFixed(1)}%'
                      : '--',
                  'Body Fat',
                  null,
                  false,
                  const Color(0xFFF59E0B),
                  Icons.percent,
                  p,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: _statCard(
                  h.latestMuscleMass > 0
                      ? '${h.latestMuscleMass.toStringAsFixed(1)} kg'
                      : '--',
                  'Muscle Mass',
                  null,
                  false,
                  const Color(0xFF3B82F6),
                  Icons.fitness_center,
                  p,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard(
    String value,
    String label,
    String? delta, // null = no real trend yet; the delta row is hidden
    bool up,
    Color color,
    IconData icon,
    AppPalette p,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: glassCardSoft(p, radius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: p.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.poppins(color: p.textMuted, fontSize: 8.5),
          ),
          if (delta != null) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  up ? Icons.arrow_upward : Icons.arrow_downward,
                  color: up ? p.accent : const Color(0xFF2EBD59),
                  size: 9,
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    delta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: up ? p.accent : const Color(0xFF2EBD59),
                      fontSize: 8.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            Text('vs last entry',
                style: GoogleFonts.poppins(color: p.textMuted, fontSize: 7.5)),
          ],
        ],
      ),
    );
  }

  Widget _quote(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          colors: p.isDark
              ? [const Color(0xFF1A0E0E), const Color(0xFF141414)]
              : [const Color(0xFFFFF5F5), const Color(0xFFFFFFFF)],
        ),
        border: Border.all(color: p.isDark ? const Color(0xFF2A1414) : const Color(0xFFFFECEC)),
      ),
      child: Row(
        children: [
          Text(
            '"',
            style: TextStyle(
              color: p.accent,
              fontSize: 40,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Quotes.daily(),
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '— Alpha Serena',
                  style: GoogleFonts.poppins(color: p.textMuted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _todaysWorkout(HomeController h, AppPalette p) {
    final previewItems = h.workoutPreviewItems;
    final name = h.workoutName;
    final count = h.exerciseCount;

    if (previewItems.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: glassCard(p, radius: 16),
        child: Column(
          children: [
            Icon(Icons.fitness_center_rounded, color: p.textMuted, size: 40),
            const SizedBox(height: 12),
            Text(
              'Active Recovery / Rest Day',
              style: AppText.title(size: 16).copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: 6),
            Text(
              'No workout assigned for today. Take time to recover, stretch, and focus on your nutrition.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(Icons.calendar_today_outlined, color: p.textPrimary, size: 16),
                const SizedBox(width: 8),
                Text(
                  "Today's Workout Plan",
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            Text(
              'Today',
              style: GoogleFonts.poppins(color: p.textMuted, fontSize: 11),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFFD50000), Color(0xFF8A0000)],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fitness_center, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$count Exercises • Est. ${count * 10} Min',
                      style: GoogleFonts.poppins(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...previewItems.asMap().entries.map((e) => _exerciseRow(e.key + 1, e.value, p)),
        const SizedBox(height: 8),
        GradientButton(
          label: 'Start Full Workout',
          showChevron: true,
          onPressed: () => Get.to(() => const WorkoutSessionScreen()),
        ),
      ],
    );
  }

  Widget _exerciseRow(int n, Map<String, dynamic> ex, AppPalette p) {
    final sets = (ex['sets'] ?? 0).toString();
    final reps = (ex['reps'] ?? 0).toString();
    final weight = (ex['weight'] ?? '').toString();
    final muscle = (ex['muscleGroup'] ?? 'Target').toString();
    final name = ex['name']?.toString() ?? 'Exercise';

    return Semantics(
      button: true,
      label: '$name, $muscle, $sets sets, $reps reps',
      excludeSemantics: true,
      child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: glassCardSoft(p, radius: 12),
      child: InkWell(
        onTap: () => Get.to(() => WorkoutPlayerScreen(exercise: ex)),
        borderRadius: BorderRadius.circular(12),
        child: Row(
          children: [
            Text(
              '$n',
              style: GoogleFonts.poppins(
                color: p.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 10),
            _thumbnail(ex, p),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    ex['name']?.toString() ?? 'Exercise',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                      color: p.textPrimary,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    muscle,
                    style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10),
                  ),
                ],
              ),
            ),
            _miniStat('$sets Sets'),
            _miniStat(reps.contains('Reps') ? reps : '$reps Reps'),
            if (weight.isNotEmpty && weight != '0' && weight != '0.0')
              _miniStat(weight.contains('kg') || weight.contains('Kg') || weight.contains('lbs') ? weight : '$weight kg'),
            const SizedBox(width: 6),
            Icon(Icons.radio_button_unchecked, color: p.textMuted, size: 18),
          ],
        ),
      ),
      ),
    );
  }

  Widget _thumbnail(Map<String, dynamic> ex, AppPalette p) {
    final thumb = ex['thumbnail']?.toString() ?? '';
    if (thumb.startsWith('assets/images/')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: Image.asset(thumb, width: 42, height: 42, fit: BoxFit.cover),
      );
    }
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(9),
      ),
      child: Icon(Icons.fitness_center, color: p.accent, size: 20),
    );
  }

  Widget _miniStat(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(
          t,
          style: GoogleFonts.poppins(color: const Color(0xFFCFCFCF), fontSize: 9.5),
        ),
      );

  Widget _skeletonLoader(AppPalette p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                _skeletonBox(width: 40, height: 40, radius: 11, p: p),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _skeletonBox(width: 140, height: 16, radius: 4, p: p),
                    const SizedBox(height: 6),
                    _skeletonBox(width: 180, height: 12, radius: 4, p: p),
                  ],
                ),
              ],
            ),
            _skeletonBox(width: 40, height: 40, radius: 11, p: p),
          ],
        ),
        const SizedBox(height: 16),
        _skeletonBox(width: double.infinity, height: 80, radius: 16, p: p),
        const SizedBox(height: 18),
        _skeletonBox(width: double.infinity, height: 180, radius: 16, p: p),
        const SizedBox(height: 18),
        _skeletonBox(width: double.infinity, height: 120, radius: 16, p: p),
        const SizedBox(height: 18),
        _skeletonBox(width: double.infinity, height: 180, radius: 16, p: p),
      ],
    );
  }

  Widget _skeletonBox({
    required double width,
    required double height,
    required double radius,
    required AppPalette p,
  }) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
