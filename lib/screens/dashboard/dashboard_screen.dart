// lib/screens/dashboard/client_dashboard.dart

import 'package:alphaserena/screens/dashboard/clients/client_trainer_schedule_screen.dart';
import 'package:alphaserena/screens/dashboard/profile/client_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/theme_controller.dart';
import 'home/client_home_screen.dart';
import 'activity/activity_screen.dart';
import 'client_progress_screen.dart';

class ClientDashboard extends StatefulWidget {
  const ClientDashboard({super.key});

  @override
  State<ClientDashboard> createState() => _ClientDashboardState();
}

class _ClientDashboardState extends State<ClientDashboard> {
  int index = 0;

  final pages = const [
    ClientHomeScreen(),
    ClientTrainerScheduleScreen(),
    ActivityScreen(),
    ClientProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode.value;
      final bg = isDark ? const Color(0xFF0E0E0E) : Colors.white;
      final accent = Colors.redAccent.shade700;

      return Scaffold(
        backgroundColor: bg,
        body: IndexedStack(index: index, children: pages),
        bottomNavigationBar: Container(
          decoration: BoxDecoration(
            color: bg,
            border: Border(
              top: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
            ),
          ),
          child: BottomNavigationBar(
            currentIndex: index,
            onTap: (i) => setState(() => index = i),
            backgroundColor: bg,
            selectedItemColor: accent,
            unselectedItemColor: isDark ? Colors.white54 : Colors.black54,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.home_rounded),
                label: "Home",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.calendar_today_rounded),
                label: "Activity",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.show_chart_rounded),
                label: "Progress",
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person_rounded),
                label: "Profile",
              ),
            ],
          ),
        ),
      );
    });
  }
}
