import 'dart:ui';
import 'package:alphaserena/controllers/dashboard_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';
import 'package:google_fonts/google_fonts.dart';

class ActivityScreen extends StatefulWidget {
  const ActivityScreen({super.key});

  @override
  State<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends State<ActivityScreen> {
  DateTime currentMonth = DateTime.now();
  DateTime selectedDate = DateTime.now();

  final Map<String, dynamic> dummyData = {
    "2025-10-26": {
      "caloriesConsumed": 1800,
      "target": 2000,
      "meals": {"Breakfast": 400, "Lunch": 600, "Dinner": 700, "Snacks": 100},
      "exercises": [
        {"name": "Running", "time": "30 mins", "icon": Icons.directions_run},
        {"name": "Cycling", "time": "45 mins", "icon": Icons.directions_bike},
      ],
    },
    "2025-10-25": {
      "caloriesConsumed": 1600,
      "target": 2000,
      "meals": {"Breakfast": 350, "Lunch": 550, "Dinner": 600, "Snacks": 100},
      "exercises": [
        {"name": "Yoga", "time": "40 mins", "icon": Icons.self_improvement},
      ],
    },
  };

  List<DateTime> getDaysInMonth(DateTime date) {
    final lastDay = DateTime(date.year, date.month + 1, 0);
    return List.generate(
      lastDay.day,
      (i) => DateTime(date.year, date.month, i + 1),
    );
  }

  void goToPreviousMonth() {
    setState(() {
      currentMonth = DateTime(currentMonth.year, currentMonth.month - 1);
      selectedDate = DateTime(currentMonth.year, currentMonth.month, 1);
    });
  }

  void goToNextMonth() {
    setState(() {
      currentMonth = DateTime(currentMonth.year, currentMonth.month + 1);
      selectedDate = DateTime(currentMonth.year, currentMonth.month, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = Get.find<DashboardController>();
    final isDark = ctrl.isDarkMode.value;
    final accent = Colors.redAccent.shade700;

    final bg = isDark ? const Color(0xFF0E0E0E) : Colors.grey.shade100;
    final glass = isDark
        ? Colors.white.withOpacity(.06)
        : Colors.white.withOpacity(.8);
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white60 : Colors.black54;

    final days = getDaysInMonth(currentMonth);
    final dateKey = DateFormat('yyyy-MM-dd').format(selectedDate);
    final dayData = dummyData[dateKey];

    final caloriesConsumed = dayData?['caloriesConsumed'] ?? 0;
    final caloriesTarget = dayData?['target'] ?? 2000;
    final meals = dayData?['meals'] ?? {};
    final exercises = dayData?['exercises'] ?? [];

    final progress = (caloriesConsumed / caloriesTarget).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: bg,
        elevation: 0,
        centerTitle: true,
        title: Text(
          "Activity",
          style: GoogleFonts.poppins(color: text, fontWeight: FontWeight.w700),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        children: [
          // MONTH SELECTOR
          _glassCard(
            glass,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  onPressed: goToPreviousMonth,
                  icon: Icon(Icons.chevron_left, color: accent),
                ),
                Text(
                  DateFormat('MMMM yyyy').format(currentMonth),
                  style: TextStyle(
                    color: text,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  onPressed: goToNextMonth,
                  icon: Icon(Icons.chevron_right, color: accent),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // DAY SELECTOR
          SizedBox(
            height: 78,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: days.length,
              itemBuilder: (_, i) {
                final d = days[i];
                final selected = DateUtils.isSameDay(d, selectedDate);
                return GestureDetector(
                  onTap: () => setState(() => selectedDate = d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 10),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? accent : glass,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: selected
                            ? accent
                            : Colors.white.withOpacity(.08),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          DateFormat('E').format(d),
                          style: TextStyle(
                            color: selected ? Colors.white : sub,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          d.day.toString(),
                          style: TextStyle(
                            color: selected ? Colors.white : text,
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),

          const SizedBox(height: 20),

          // CALORIES CARD
          _glassCard(
            glass,
            child: Row(
              children: [
                SizedBox(
                  height: 90,
                  width: 90,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: progress,
                        strokeWidth: 8,
                        backgroundColor: isDark
                            ? Colors.white12
                            : Colors.black12,
                        color: accent,
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            caloriesConsumed.toString(),
                            style: TextStyle(
                              color: text,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                          Text(
                            "kcal",
                            style: TextStyle(color: sub, fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Calories Consumed", style: TextStyle(color: sub)),
                      const SizedBox(height: 10),
                      ...meals.entries.map(
                        (e) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(e.key, style: TextStyle(color: sub)),
                              Text(
                                "${e.value} kcal",
                                style: TextStyle(
                                  color: text,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // EXERCISES
          Text(
            "Exercises",
            style: TextStyle(
              color: text,
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),

          if (exercises.isEmpty)
            _glassCard(
              glass,
              child: Center(
                child: Text(
                  "No exercises logged",
                  style: TextStyle(color: sub),
                ),
              ),
            )
          else
            ...exercises.map(
              (e) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _glassCard(
                  glass,
                  child: Row(
                    children: [
                      Icon(e['icon'] as IconData, color: accent, size: 26),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          e['name'],
                          style: TextStyle(
                            color: text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(e['time'], style: TextStyle(color: sub)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _glassCard(Color color, {required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(.08)),
          ),
          child: child,
        ),
      ),
    );
  }
}
