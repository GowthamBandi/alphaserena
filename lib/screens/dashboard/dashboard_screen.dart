import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../../controllers/training_controller.dart';
import '../../core/theme/app_colors.dart';
import 'client_diet_screen.dart';
import 'client_progress_screen.dart';
import 'client_workout_screen.dart';
import 'home/client_home_screen.dart';
import 'profile/client_profile_screen.dart';

/// The member shell: bottom-nav tabs over a kept-alive IndexedStack.
class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    if (!Get.isRegistered<MemberController>()) Get.put(MemberController());
    if (!Get.isRegistered<TrainingController>()) Get.put(TrainingController());
  }

  late final List<Widget> _pages = [
    const ClientHomeScreen(),
    ClientWorkoutScreen(),
    ClientDietScreen(),
    ClientProgressScreen(),
    ClientProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: IndexedStack(index: _index, children: _pages),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: p.surface,
          border: Border(top: BorderSide(color: p.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _index,
          onTap: (i) => setState(() => _index = i),
          backgroundColor: p.surface,
          selectedItemColor: p.accent,
          unselectedItemColor: p.textMuted,
          type: BottomNavigationBarType.fixed,
          showUnselectedLabels: true,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded), label: 'Home'),
            BottomNavigationBarItem(
                icon: Icon(Icons.fitness_center), label: 'Workout'),
            BottomNavigationBarItem(
                icon: Icon(Icons.restaurant_menu), label: 'Diet'),
            BottomNavigationBarItem(
                icon: Icon(Icons.show_chart_rounded), label: 'Progress'),
            BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
