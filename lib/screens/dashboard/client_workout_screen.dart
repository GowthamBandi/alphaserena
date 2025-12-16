import 'package:flutter/material.dart';

class ClientWorkoutScreen extends StatelessWidget {
  const ClientWorkoutScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Colors.white;

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            "Workouts",
            style: TextStyle(
              color: text,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),

          _workoutCard("Upper Body", "Completed"),
          _workoutCard("Leg Day", "Pending"),
          _workoutCard("Cardio", "Missed"),
        ],
      ),
    );
  }
}

Widget _workoutCard(String name, String status) {
  return _glassCard(
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(name, style: const TextStyle(color: Colors.white, fontSize: 16)),
        Chip(label: Text(status), backgroundColor: Colors.white12),
      ],
    ),
  );
}

Widget _glassCard({required Widget child}) {
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 8),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white12,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.white24),
    ),
    child: child,
  );
}
