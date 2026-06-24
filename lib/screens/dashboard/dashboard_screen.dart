import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../controllers/member_controller.dart';
import '../../controllers/training_controller.dart';
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
  static const Color _red = Color(0xFFE10600);

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<MemberController>()) Get.put(MemberController());
    if (!Get.isRegistered<TrainingController>()) Get.put(TrainingController());
  }

  late final List<Widget> _pages = [
    const ClientHomeScreen(),
    const MyPlansScreen(),
    const ClientProgressScreen(),
    const ClientProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.only(top: 8, bottom: 18),
        decoration: const BoxDecoration(
          color: _nav,
          border: Border(top: BorderSide(color: Color(0xFF1E1E1E))),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _item(0, Icons.home_rounded, 'Home'),
            _item(1, Icons.assignment_outlined, 'My Plans'),
            _item(2, Icons.show_chart_rounded, 'Progress'),
            _item(3, Icons.person_outline, 'Profile'),
          ],
        ),
      ),
    );
  }

  Widget _item(int i, IconData icon, String label) {
    final active = _index == i;
    final color = active ? _red : _muted;
    return GestureDetector(
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
    );
  }
}
