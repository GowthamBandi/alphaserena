import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/member_controller.dart';
import '../../controllers/training_controller.dart';
import '../../controllers/membership_controller.dart';
import '../../controllers/home_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../controllers/food_log_controller.dart';
import '../../controllers/check_in_controller.dart';
import '../../controllers/lifestyle_controller.dart';
import '../../controllers/streak_controller.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/serena/serena_tokens.g.dart';
import 'client_progress_screen.dart';
import 'home/client_home_screen.dart';
import 'plans/my_plans_screen.dart';
import 'profile/client_profile_screen.dart';

/// A request to show one of the shell's tabs, from outside the shell.
///
/// Deep links used to do `Get.to(() => const MyPlansScreen())`, which PUSHES a
/// second, rootless copy of the screen on top of the dashboard: no bottom
/// navigation, no way to reach Home except the system back gesture, and two
/// live instances of the same screen in the tree. Tapping a "your coach
/// assigned you a new plan" notification landed the member exactly there.
///
/// A tab is not a page you push — it is a page you SELECT. Sticky on purpose:
/// a notification tapped from a cold start is handled before the shell exists,
/// so the shell reads and clears the request when it mounts.
final RxnInt dashboardTabRequest = RxnInt();

/// Index of the My Plans tab in the shell.
const int kMyPlansTab = 1;

/// Shows My Plans as a TAB — popping back to the shell if a detail route is
/// open — rather than stacking another copy of it.
void openMyPlansTab() {
  dashboardTabRequest.value = kMyPlansTab;
  if (Get.key.currentState?.canPop() ?? false) {
    Get.until((r) => r.isFirst);
  }
}

/// The member shell: 4 bottom-nav tabs over a kept-alive IndexedStack.
class ClientDashboard extends StatefulWidget {
  final int initialIndex;
  const ClientDashboard({super.key, this.initialIndex = 0});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard>
    with WidgetsBindingObserver {
  late int _index = widget.initialIndex;

  // M3: the active-tab red now consumes the SDS brand accent (#D50000),
  // replacing a drifted hardcoded #E10600 that mismatched the brand.
  static const Color _red = Color(SerenaColor.accentLight);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!Get.isRegistered<MemberController>()) Get.put(MemberController());
    if (!Get.isRegistered<TrainingController>()) Get.put(TrainingController());
    if (!Get.isRegistered<MembershipController>()) Get.put(MembershipController());
    if (!Get.isRegistered<HomeController>()) Get.put(HomeController());
    if (!Get.isRegistered<ProgressController>()) Get.put(ProgressController());
    // DietLogController is NOT created here any more.
    //
    // It drives plan-ADHERENCE marking on `ClientDietScreen`, which became
    // unreachable when coach recommendations went read-only — so this bound a
    // Firestore listener on every dashboard load, for every member, on behalf
    // of a screen nobody can open. `FoodLogController` owns nutrition now and
    // is created by the screens that use it.
    if (!Get.isRegistered<FoodLogController>()) Get.put(FoodLogController());
    if (!Get.isRegistered<CheckInController>()) Get.put(CheckInController());
    if (!Get.isRegistered<StreakController>()) Get.put(StreakController());

    // A deep link handled BEFORE this shell existed (a notification tapped
    // from a cold start) left its request waiting here.
    final pending = dashboardTabRequest.value;
    if (pending != null && pending >= 0 && pending < _dests.length) {
      _index = pending;
      dashboardTabRequest.value = null;
    }
    // And one that arrives while the shell is already up.
    _tabWorker = ever(dashboardTabRequest, (int? i) {
      if (i == null || !mounted) return;
      if (i < 0 || i >= _dests.length) return;
      dashboardTabRequest.value = null;
      _select(i);
    });
  }

  Worker? _tabWorker;

  @override
  void dispose() {
    _tabWorker?.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    // Day-rollover guard: a phone left overnight resumes with the daily loggers
    // still pinned to yesterday — re-anchor them to the new calendar day so a
    // morning log never lands on (or copies from) yesterday's document.
    // Day-rollover guard for the FOOD LOG, which is what a member now writes.
    if (Get.isRegistered<FoodLogController>()) {
      Get.find<FoodLogController>().ensureFreshDay();
    }
    if (Get.isRegistered<LifestyleController>()) {
      Get.find<LifestyleController>().ensureFreshDay();
    }
    // PRESCRIPTION ENGINE: yesterday's served expectation is stale after a
    // rollover — a "rest day" banner on a training morning would be a lie.
    if (Get.isRegistered<TrainingController>()) {
      final training = Get.find<TrainingController>();
      training.ensureFreshDay();
      // AND re-pull the plan itself, not just the day.
      //
      // `ensureFreshDay` only reloads when the DAY changed, so a coach who
      // assigned, replaced, paused or removed a plan while the member had the
      // app backgrounded reached them only on a manual pull-to-refresh or a
      // restart. Resuming the app is the member looking at it again, which is
      // exactly when the plan should be current. Rate-limited inside
      // `refreshIfStale`.
      training.refreshIfStale();
    }
    // HOME FINAL: today's workout-progress stats are day-stamped; re-anchor
    // them too, or the hero would claim yesterday's "42% done" this morning.
    if (Get.isRegistered<StreakController>()) {
      Get.find<StreakController>().ensureFreshDay();
    }
  }

  /// Switches tab, and re-pulls the plan when the member enters My Plans.
  ///
  /// The screen lives in a kept-alive `IndexedStack`, so navigating to it does
  /// NOT rebuild it from scratch and nothing in it would otherwise notice that
  /// the coach changed something. Entering the tab is the member asking "what
  /// am I assigned?" — the one moment the answer must not be stale.
  void _select(int i) {
    setState(() => _index = i);
    if (i == kMyPlansTab && Get.isRegistered<TrainingController>()) {
      Get.find<TrainingController>().refreshIfStale();
    }
  }

  late final List<Widget> _pages = [
    const ClientHomeScreen(),
    const MyPlansScreen(),
    const ClientProgressScreen(),
    const ClientProfileScreen(),
  ];

  static const List<_Dest> _dests = [
    _Dest(Icons.home_rounded, 'Home'),
    _Dest(Icons.assignment_outlined, 'My Plans'),
    _Dest(Icons.show_chart_rounded, 'Progress'),
    _Dest(Icons.person_outline, 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final content = IndexedStack(index: _index, children: _pages);

    // R1 responsive shell. Wide (tablet / desktop / phone-landscape): a
    // navigation rail replaces the bottom bar and content is capped + centred so
    // it never stretches. Same 4 destinations, same IndexedStack, same logic.
    if (Breakpoints.isWide(context)) {
      return Scaffold(
        backgroundColor: p.background,
        body: SafeArea(
          child: Row(
            children: [
              _rail(context, p),
              VerticalDivider(width: 1, thickness: 1, color: p.border),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints:
                        const BoxConstraints(maxWidth: Breakpoints.maxContent),
                    child: content,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Compact (phone portrait): the original bottom navigation.
    return Scaffold(
      backgroundColor: p.background,
      body: content,
      bottomNavigationBar: _bottomNav(context, p),
    );
  }

  Widget _bottomNav(BuildContext context, AppPalette p) {
    // Respect the gesture-bar inset instead of a fixed guess.
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.only(
          top: 8, bottom: bottomInset > 10 ? bottomInset + 4 : 18),
      decoration: BoxDecoration(
        color: p.surface,
        border: Border(top: BorderSide(color: p.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < _dests.length; i++)
            _item(i, _dests[i].icon, _dests[i].label, p),
        ],
      ),
    );
  }

  Widget _rail(BuildContext context, AppPalette p) {
    final extended = Breakpoints.isExpanded(context);
    final rail = NavigationRail(
      extended: extended,
      labelType: extended ? null : NavigationRailLabelType.all,
      backgroundColor: p.surface,
      indicatorColor: _red.withValues(alpha: 0.16),
      selectedIndex: _index,
      onDestinationSelected: _select,
      selectedIconTheme: const IconThemeData(color: _red),
      unselectedIconTheme: IconThemeData(color: p.textMuted),
      selectedLabelTextStyle: GoogleFonts.poppins(
          color: _red, fontWeight: FontWeight.w600, fontSize: 13),
      unselectedLabelTextStyle:
          GoogleFonts.poppins(color: p.textMuted, fontSize: 13),
      destinations: [
        for (final d in _dests)
          NavigationRailDestination(icon: Icon(d.icon), label: Text(d.label)),
      ],
    );
    // Scroll-safe: on short viewports (phone landscape) the rail scrolls
    // instead of overflowing; still fills the height when there's room.
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: rail),
        ),
      ),
    );
  }

  Widget _item(int i, IconData icon, String label, AppPalette p) {
    final active = _index == i;
    final color = active ? _red : p.textMuted;
    // M3 a11y: expose each tab as a labeled, selected-state button (the member
    // nav had no screen-reader semantics at all).
    return Semantics(
      button: true,
      selected: active,
      label: '$label tab',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(i),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 23),
            const SizedBox(height: 4),
            Text(label,
                style: GoogleFonts.poppins(
                    color: color,
                    fontSize: 11,
                    fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
          ],
        ),
      ),
    );
  }
}

/// A navigation destination shared by the bottom bar (compact) and the rail (wide).
class _Dest {
  final IconData icon;
  final String label;
  const _Dest(this.icon, this.label);
}
