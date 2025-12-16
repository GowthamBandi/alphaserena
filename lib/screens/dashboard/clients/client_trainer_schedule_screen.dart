import 'package:alphaserena/controllers/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

class ClientTrainerScheduleScreen extends StatefulWidget {
  const ClientTrainerScheduleScreen({super.key});

  @override
  State<ClientTrainerScheduleScreen> createState() =>
      _ClientTrainerScheduleScreenState();
}

class _ClientTrainerScheduleScreenState
    extends State<ClientTrainerScheduleScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  bool workoutExpanded = false;
  bool dietExpanded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode.value;

      final bg = isDark ? const Color(0xFF0E0E0E) : Colors.grey.shade100;
      final card = isDark ? Colors.white.withOpacity(.06) : Colors.white;
      final text = isDark ? Colors.white : Colors.black87;
      final sub = isDark ? Colors.white60 : Colors.black54;
      final accent = Colors.redAccent.shade700;

      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          title: Text(
            "Trainer Plans",
            style: GoogleFonts.poppins(
              color: text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _trainerHeader(card, text, sub, accent),
            const SizedBox(height: 22),

            TabBar(
              controller: _tabController,
              indicatorColor: accent,
              labelColor: accent,
              unselectedLabelColor: sub,
              labelStyle: GoogleFonts.poppins(fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: "Workouts"),
                Tab(text: "Diet"),
              ],
            ),

            const SizedBox(height: 16),

            /// ✅ NO FIXED HEIGHT — prevents overflow
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.75,
              child: TabBarView(
                controller: _tabController,
                children: [
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 30),
                    child: _workoutTab(
                      card,
                      accent,
                      text,
                      sub,
                      expanded: workoutExpanded,
                      onToggle: () =>
                          setState(() => workoutExpanded = !workoutExpanded),
                    ),
                  ),
                  SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 30),
                    child: _dietTab(
                      card,
                      accent,
                      text,
                      sub,
                      expanded: dietExpanded,
                      onToggle: () =>
                          setState(() => dietExpanded = !dietExpanded),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    });
  }

  // ===========================================================================
  /// TRAINER HEADER
  Widget _trainerHeader(Color card, Color text, Color sub, Color accent) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(.25)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 36,
            backgroundColor: accent,
            child: const Text(
              "P",
              style: TextStyle(
                color: Colors.white,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            "Prasad",
            style: GoogleFonts.poppins(
              color: text,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            "Assigned Trainer",
            style: GoogleFonts.poppins(color: sub, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Text(
            "Target Calories : 2000 kcal",
            style: GoogleFonts.poppins(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  /// WORKOUT TAB
  Widget _workoutTab(
    Color card,
    Color accent,
    Color text,
    Color sub, {
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onToggle,
          child: _collapsibleHeader(
            title: "Weekly Workout Plan",
            subtitle: "Push / Pull / Legs • 6 days",
            expanded: expanded,
            accent: accent,
            text: text,
            sub: sub,
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 300),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: [
              _dayWorkout(
                "Monday",
                "Chest & Triceps",
                ["Bench Press", "Chest Fly", "Triceps Pushdown"],
                accent,
                text,
              ),
              _dayWorkout(
                "Tuesday",
                "Back & Biceps",
                ["Lat Pulldown", "Barbell Row", "Bicep Curl"],
                accent,
                text,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dayWorkout(
    String day,
    String focus,
    List<String> exercises,
    Color accent,
    Color text,
  ) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "$day • $focus",
            style: GoogleFonts.poppins(
              color: text,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
          ...exercises.map(
            (e) => Row(
              children: [
                Icon(Icons.fitness_center, color: accent, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(e, style: GoogleFonts.poppins(color: text)),
                ),
                TextButton(
                  onPressed: () {
                    // Navigate to WorkoutPlayerPage later
                  },
                  child: Text(
                    "Start",
                    style: GoogleFonts.poppins(
                      color: accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  /// DIET TAB
  Widget _dietTab(
    Color card,
    Color accent,
    Color text,
    Color sub, {
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    return Column(
      children: [
        GestureDetector(
          onTap: onToggle,
          child: _collapsibleHeader(
            title: "High Protein Diet",
            subtitle: "2100 kcal • P 160g • C 200g • F 60g",
            expanded: expanded,
            accent: accent,
            text: text,
            sub: sub,
          ),
        ),
        AnimatedCrossFade(
          duration: const Duration(milliseconds: 300),
          crossFadeState: expanded
              ? CrossFadeState.showSecond
              : CrossFadeState.showFirst,
          firstChild: const SizedBox.shrink(),
          secondChild: Column(
            children: [
              _dietMeal(
                meal: "Breakfast",
                calories: "520 kcal",
                items: const [
                  "Oats • 100g",
                  "Egg Whites • 4 pcs",
                  "Banana • 1 medium",
                ],
                accent: accent,
                text: text,
              ),
              _dietMeal(
                meal: "Lunch",
                calories: "720 kcal",
                items: const [
                  "Chicken Breast • 150g",
                  "Rice • 120g",
                  "Salad • 1 bowl",
                ],
                accent: accent,
                text: text,
              ),
              _dietMeal(
                meal: "Dinner",
                calories: "560 kcal",
                items: const ["Paneer • 120g", "Vegetables • 1 bowl"],
                accent: accent,
                text: text,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dietMeal({
    required String meal,
    required String calories,
    required List<String> items,
    required Color accent,
    required Color text,
  }) {
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.05),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                meal,
                style: GoogleFonts.poppins(
                  color: text,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                calories,
                style: GoogleFonts.poppins(
                  color: accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...items.map(
            (i) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Container(
                    height: 6,
                    width: 6,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      i,
                      style: GoogleFonts.poppins(color: text, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  Widget _collapsibleHeader({
    required String title,
    required String subtitle,
    required bool expanded,
    required Color accent,
    required Color text,
    required Color sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: Colors.white.withOpacity(.06),
        border: Border.all(color: accent.withOpacity(.25)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.poppins(color: sub, fontSize: 13),
                ),
              ],
            ),
          ),
          Icon(
            expanded
                ? Icons.keyboard_arrow_up_rounded
                : Icons.keyboard_arrow_down_rounded,
            color: accent,
            size: 26,
          ),
        ],
      ),
    );
  }
}
