import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/member_controller.dart';
import '../../controllers/training_controller.dart';
import '../../controllers/membership_controller.dart';
import '../../controllers/home_controller.dart';
import '../../controllers/progress_controller.dart';
import '../../core/responsive/breakpoints.dart';
import '../../core/theme/serena/serena_tokens.g.dart';
import 'client_progress_screen.dart';
import 'home/client_home_screen.dart';
import 'my_plans_screen.dart';
import 'profile/client_profile_screen.dart';

/// The member shell: 4 bottom-nav tabs over a kept-alive IndexedStack.
class ClientDashboard extends StatefulWidget {
  final int initialIndex;
  const ClientDashboard({super.key, this.initialIndex = 0});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  late int _index = widget.initialIndex;

  static const Color _nav = Color(0xFF121212);
  static const Color _muted = Color(0xFF8E8E8E);
  // M3: the active-tab red now consumes the SDS brand accent (#D50000),
  // replacing a drifted hardcoded #E10600 that mismatched the brand.
  static const Color _red = Color(SerenaColor.accentLight);

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<MemberController>()) Get.put(MemberController());
    if (!Get.isRegistered<TrainingController>()) Get.put(TrainingController());
    if (!Get.isRegistered<MembershipController>()) Get.put(MembershipController());
    if (!Get.isRegistered<HomeController>()) Get.put(HomeController());
    if (!Get.isRegistered<ProgressController>()) Get.put(ProgressController());
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
    final content = IndexedStack(index: _index, children: _pages);

    // R1 responsive shell. Wide (tablet / desktop / phone-landscape): a
    // navigation rail replaces the bottom bar and content is capped + centred so
    // it never stretches. Same 4 destinations, same IndexedStack, same logic.
    if (Breakpoints.isWide(context)) {
      return Scaffold(
        backgroundColor: const Color(0xFF0A0A0A),
        body: SafeArea(
          child: Row(
            children: [
              _rail(context),
              const VerticalDivider(
                  width: 1, thickness: 1, color: Color(0xFF1E1E1E)),
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
      backgroundColor: const Color(0xFF0A0A0A),
      body: content,
      bottomNavigationBar: _bottomNav(),
    );
  }

  Widget _bottomNav() {
    return Container(
      padding: const EdgeInsets.only(top: 8, bottom: 18),
      decoration: const BoxDecoration(
        color: _nav,
        border: Border(top: BorderSide(color: Color(0xFF1E1E1E))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          for (var i = 0; i < _dests.length; i++)
            _item(i, _dests[i].icon, _dests[i].label),
        ],
      ),
    );
  }

  Widget _rail(BuildContext context) {
    final extended = Breakpoints.isExpanded(context);
    final rail = NavigationRail(
      extended: extended,
      labelType: extended ? null : NavigationRailLabelType.all,
      backgroundColor: _nav,
      indicatorColor: _red.withValues(alpha: 0.16),
      selectedIndex: _index,
      onDestinationSelected: (i) => setState(() => _index = i),
      selectedIconTheme: const IconThemeData(color: _red),
      unselectedIconTheme: const IconThemeData(color: _muted),
      selectedLabelTextStyle: GoogleFonts.poppins(
          color: _red, fontWeight: FontWeight.w600, fontSize: 13),
      unselectedLabelTextStyle:
          GoogleFonts.poppins(color: _muted, fontSize: 13),
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

  Widget _item(int i, IconData icon, String label) {
    final active = _index == i;
    final color = active ? _red : _muted;
    // M3 a11y: expose each tab as a labeled, selected-state button (the member
    // nav had no screen-reader semantics at all).
    return Semantics(
      button: true,
      selected: active,
      label: '$label tab',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _index = i),
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
