import 'package:flutter/material.dart';

/// Sample content for the member dashboard screens — mirrors the design mockups.
/// (Replace with live Firestore data when the plan pipeline is wired.)

class Exercise {
  final String name;
  final String muscle;
  final int sets;
  final String reps;
  final String weight;
  final String thumb;
  const Exercise(
      this.name, this.muscle, this.sets, this.reps, this.weight, this.thumb);
}

const List<Exercise> kTodayExercises = [
  Exercise('Barbell Bench Press', 'Chest', 4, '8-10 Reps', '60 Kg',
      'assets/images/ex1.png'),
  Exercise('Pull Ups', 'Back', 4, '8-12 Reps', 'Body W.',
      'assets/images/ex2.png'),
  Exercise('Dumbbell Shoulder Press', 'Shoulders', 3, '10-12 Reps', '16 Kg',
      'assets/images/ex3.png'),
  Exercise('Seated Cable Row', 'Back', 3, '10-12 Reps', '45 Kg',
      'assets/images/ex4.png'),
  Exercise('Tricep Pushdown', 'Triceps', 3, '12-15 Reps', '25 Kg',
      'assets/images/ex5.png'),
];

class Meal {
  final String type;
  final String name;
  final int kcal;
  final String image;
  const Meal(this.type, this.name, this.kcal, this.image);
}

const List<Meal> kMeals = [
  Meal('Breakfast', 'Oats with Protein Shake', 450, 'assets/images/meal1.png'),
  Meal('Lunch', 'Grilled Chicken with Quinoa', 650, 'assets/images/meal2.png'),
  Meal('Evening Snack', 'Greek Yogurt with Nuts', 200,
      'assets/images/meal3.png'),
  Meal('Dinner', 'Salmon with Steamed Veggies', 650, 'assets/images/meal4.png'),
];

class Macro {
  final String name;
  final int current;
  final int goal;
  final Color color;
  final IconData icon;
  const Macro(this.name, this.current, this.goal, this.color, this.icon);
  double get pct => (current / goal).clamp(0, 1).toDouble();
}

const List<Macro> kMacros = [
  Macro('Carbs', 210, 300, Color(0xFF2EBD59), Icons.grain),
  Macro('Protein', 85, 150, Color(0xFF3B82F6), Icons.egg_alt),
  Macro('Fats', 45, 70, Color(0xFFF59E0B), Icons.water_drop),
  Macro('Fiber', 18, 35, Color(0xFF9B5DE5), Icons.spa),
];

class ProgressStat {
  final String value;
  final String label;
  final String delta;
  final bool up;
  final Color color;
  final IconData icon;
  const ProgressStat(
      this.value, this.label, this.delta, this.up, this.color, this.icon);
}

const List<ProgressStat> kProgressStats = [
  ProgressStat('72.5 kg', 'Weight', '1.2 kg', false, Color(0xFF2EBD59),
      Icons.monitor_weight_outlined),
  ProgressStat('15.6%', 'Body Fat', '0.8%', false, Color(0xFFF59E0B),
      Icons.percent),
  ProgressStat('22.4 kg', 'Muscle Mass', '1.2 kg', true, Color(0xFF3B82F6),
      Icons.fitness_center),
  ProgressStat('2,350', 'Calories Burned', '320', true, Color(0xFFE10600),
      Icons.local_fire_department),
];
