import 'package:flutter/material.dart';

class ClientDietScreen extends StatelessWidget {
  const ClientDietScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Colors.white;
    final sub = Colors.white60;

    return Scaffold(
      backgroundColor: const Color(0xFF0E0E0E),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              "Diet Plan",
              style: TextStyle(
                color: text,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            _mealCard(
              meal: "Breakfast",
              items: ["Oats", "Eggs"],
              calories: "420 kcal",
            ),

            _mealCard(
              meal: "Lunch",
              items: ["Chicken Rice"],
              calories: "680 kcal",
            ),

            _mealCard(meal: "Dinner", items: ["Paneer"], calories: "520 kcal"),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // MEAL CARD (GLASSY + PREMIUM)
  // ---------------------------------------------------------------------------
  Widget _mealCard({
    required String meal,
    required List<String> items,
    required String calories,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.08),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                meal,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                calories,
                style: const TextStyle(
                  color: Colors.redAccent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Items
          ...items.map(
            (i) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    size: 16,
                    color: Colors.greenAccent,
                  ),
                  const SizedBox(width: 8),
                  Text(i, style: const TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          ),

          const SizedBox(height: 12),

          // CTA
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () {},
              child: const Text(
                "View Details",
                style: TextStyle(color: Colors.redAccent),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
