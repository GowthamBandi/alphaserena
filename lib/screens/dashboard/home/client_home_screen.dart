import 'package:alphaserena/controllers/dashboard_controller.dart';
import 'package:alphaserena/screens/dashboard/workout_player_screen.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

class ClientHomeScreen extends StatelessWidget {
  const ClientHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final DashboardController ctrl = Get.find<DashboardController>();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark ? const Color(0xFF0E0E0E) : Colors.grey.shade100;
    final card = isDark ? Colors.white.withOpacity(.06) : Colors.white;
    final text = isDark ? Colors.white : Colors.black87;
    final sub = isDark ? Colors.white60 : Colors.black54;
    final accent = Colors.redAccent.shade700;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Obx(
          () => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              _trainerHeader(card, text, sub, accent),
              const SizedBox(height: 28),

              _calorieOverview(ctrl, card, accent, text, sub, isDark),
              const SizedBox(height: 32),

              _sectionTitle("Track Your Food", text),
              const SizedBox(height: 14),

              SizedBox(
                height: 170,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  itemCount: ctrl.mealCalories.length,
                  itemBuilder: (_, i) {
                    final meal = ctrl.mealCalories.keys.elementAt(i);
                    final kcal = ctrl.mealCalories[meal]!.value;
                    return _mealCard(meal, kcal, card, accent, text, sub);
                  },
                ),
              ),

              const SizedBox(height: 32),
              _sectionTitle("Today's Workout", text),
              const SizedBox(height: 14),

              _workoutTile(
                title: "Lower Body Blast",
                meta: "3 sets • 12 reps • 1 min rest",
                card: card,
                accent: accent,
                text: text,
                sub: sub,
              ),
              const SizedBox(height: 12),
              _workoutTile(
                title: "Upper Body Power",
                meta: "3 sets • 12 reps • 1 min rest",
                card: card,
                accent: accent,
                text: text,
                sub: sub,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _trainerHeader(Color card, Color text, Color sub, Color accent) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(.25)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: accent,
            child: const Text(
              "P",
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Your Trainer",
                  style: TextStyle(color: sub, fontSize: 12),
                ),
                Text(
                  "Prasad",
                  style: TextStyle(
                    color: text,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.messageCircle, color: text),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _calorieOverview(
    DashboardController ctrl,
    Color card,
    Color accent,
    Color text,
    Color sub,
    bool isDark,
  ) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: accent.withOpacity(.25)),
      ),
      child: Row(
        children: [
          CircularPercentIndicator(
            radius: 72,
            lineWidth: 12,
            percent: ctrl.calorieProgress,
            circularStrokeCap: CircularStrokeCap.round,
            progressColor: accent,
            backgroundColor: isDark ? Colors.white12 : Colors.black12,
            center: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  "${ctrl.dailyCalories.value.toInt()}",
                  style: TextStyle(
                    color: text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "/ ${ctrl.dailyGoal.value.toInt()} kcal",
                  style: TextStyle(color: sub, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              children: [
                _macro("Protein", ctrl.protein.value, accent, text),
                _macro("Carbs", ctrl.carbs.value, accent, text),
                _macro("Fats", ctrl.fats.value, accent, text),
                _macro("Fiber", ctrl.fiber.value, accent, text),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _macro(String label, double value, Color accent, Color text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            height: 6,
            width: 6,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            "$label: ${value.toStringAsFixed(1)}g",
            style: TextStyle(color: text, fontSize: 13),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _mealCard(
    String meal,
    double kcal,
    Color card,
    Color accent,
    Color text,
    Color sub,
  ) {
    return Container(
      width: 160,
      margin: const EdgeInsets.only(right: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            meal,
            style: TextStyle(color: text, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text("${kcal.toInt()} kcal", style: TextStyle(color: sub)),
          const Spacer(),
          Align(
            alignment: Alignment.bottomRight,
            child: CircleAvatar(
              radius: 18,
              backgroundColor: accent,
              child: const Icon(Icons.add, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _workoutTile({
    required String title,
    required String meta,
    required Color card,
    required Color accent,
    required Color text,
    required Color sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(.25)),
      ),
      child: Row(
        children: [
          Icon(LucideIcons.dumbbell, color: accent),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: text, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 4),
                Text(meta, style: TextStyle(color: sub, fontSize: 12)),
              ],
            ),
          ),
          GestureDetector(
            onTap: () => Get.to(() => WorkoutPlayerPage()),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text(
                "Start",
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _sectionTitle(String title, Color text) {
    return Text(
      title,
      style: TextStyle(color: text, fontSize: 18, fontWeight: FontWeight.bold),
    );
  }
}
