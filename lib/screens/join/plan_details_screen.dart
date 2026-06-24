import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/widgets/gradient_button.dart';
import 'checkout_screen.dart';
import 'discover_models.dart';

/// Plan Details — full benefits of the chosen plan before checkout.
class PlanDetailsScreen extends StatelessWidget {
  final DiscoverOrg org;
  final MembershipPlan plan;
  const PlanDetailsScreen({super.key, required this.org, required this.plan});

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

  @override
  Widget build(BuildContext context) {
    final details = <(IconData, String, String)>[
      (Icons.fitness_center, 'Personalized Workout Plan',
          'Tailored workouts based on your goals and fitness level'),
      (Icons.restaurant_menu, 'Custom Nutrition Plan',
          'Meal plans designed to match your body type and goals'),
      (Icons.person_pin_circle_outlined, '1-on-1 Expert Coaching',
          'Direct access to certified trainers for guidance and support'),
      (Icons.show_chart, 'Progress Tracking',
          'Track your transformation with detailed weekly reports'),
      (Icons.support_agent, '24/7 Support',
          "We're here to help whenever you need us, any time of day"),
    ];

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new,
              color: Colors.white, size: 18),
          onPressed: () => Get.back(),
        ),
        title: Text('Plan Details',
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w600)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 20),
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A0E0E),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _red.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.asset(org.thumb,
                            width: 58, height: 58, fit: BoxFit.cover),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(plan.name,
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700)),
                            Text(plan.program,
                                style: GoogleFonts.poppins(
                                    color: _red, fontSize: 11.5)),
                            const SizedBox(height: 6),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text('₹${inr(plan.price)}',
                                    style: GoogleFonts.poppins(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800)),
                                const SizedBox(width: 4),
                                Text('/ ${plan.weeks} weeks',
                                    style: GoogleFonts.poppins(
                                        color: _muted, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  'A comprehensive ${plan.weeks}-week coaching program designed '
                  'to transform your body and lifestyle with expert guidance '
                  'every step of the way.',
                  style: GoogleFonts.poppins(
                      color: _muted, fontSize: 12.5, height: 1.5),
                ),
                const SizedBox(height: 18),
                Text("What's Included",
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 12),
                ...details.map((d) => _detailRow(d.$1, d.$2, d.$3)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFF1E1E1E)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.emoji_events, color: _red, size: 20),
                      const SizedBox(width: 12),
                      Text('${plan.clientsTransformed} Clients Transformed',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 20),
            child: GradientButton(
              label: 'Choose This Plan',
              onPressed: () =>
                  Get.to(() => CheckoutScreen(org: org, plan: plan)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailRow(IconData icon, String title, String sub) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: _red, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(sub,
                    style: GoogleFonts.poppins(
                        color: _muted, fontSize: 11.5, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
