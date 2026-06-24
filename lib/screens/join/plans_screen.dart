import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/widgets/brand.dart';
import 'discover_models.dart';
import 'plan_details_screen.dart';

/// Plans screen — the organization's membership plans.
class PlansScreen extends StatelessWidget {
  final DiscoverOrg org;
  const PlansScreen({super.key, required this.org});

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

  @override
  Widget build(BuildContext context) {
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
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            org.id == 'alpha'
                ? const AlphaAMark(size: 18)
                : Icon(org.logoIcon, color: org.logoColor, size: 18),
            const SizedBox(width: 8),
            Text(org.name,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
        children: [
          Center(
            child: Text('Available Plans',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text('Choose the plan that fits your fitness journey',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: _muted, fontSize: 12.5)),
          ),
          const SizedBox(height: 20),
          ...kPlans.map((p) => _planCard(context, p)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _red.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.workspace_premium, color: _red, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'All plans include access to our community & resources',
                    style: GoogleFonts.poppins(color: _muted, fontSize: 11.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _planCard(BuildContext context, MembershipPlan p) {
    final highlighted = p.popular;
    return GestureDetector(
      onTap: () => Get.to(() => PlanDetailsScreen(org: org, plan: p)),
      child: Container(
        margin: const EdgeInsets.only(bottom: 14),
        decoration: BoxDecoration(
          color: highlighted ? const Color(0xFF1A0E0E) : const Color(0xFF141414),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: highlighted ? _red : const Color(0xFF1E1E1E),
            width: highlighted ? 1.4 : 1,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (highlighted) const SizedBox(height: 8),
                        Text(p.name,
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                        const SizedBox(height: 2),
                        Text(p.program,
                            style: GoogleFonts.poppins(
                                color: _red,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w500)),
                        const SizedBox(height: 8),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.baseline,
                          textBaseline: TextBaseline.alphabetic,
                          children: [
                            Text('₹${inr(p.price)}',
                                style: GoogleFonts.poppins(
                                    color: Colors.white,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(width: 4),
                            Text('/ ${p.weeks} weeks',
                                style: GoogleFonts.poppins(
                                    color: _muted, fontSize: 12)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ...p.features.map(_feature),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 70,
                    child: Column(
                      children: [
                        const SizedBox(height: 40),
                        Text(p.clientsTransformed,
                            style: GoogleFonts.poppins(
                                color: _red,
                                fontSize: 14,
                                fontWeight: FontWeight.w700)),
                        Text('Clients\nTransformed',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.poppins(
                                color: _muted, fontSize: 9.5, height: 1.2)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (p.popular)
              Positioned(
                top: 0,
                left: 16,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: const BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.only(
                      bottomLeft: Radius.circular(8),
                      bottomRight: Radius.circular(8),
                    ),
                  ),
                  child: Text('MOST POPULAR',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _feature(String f) => Padding(
        padding: const EdgeInsets.only(bottom: 7),
        child: Row(
          children: [
            const Icon(Icons.check_circle, color: _red, size: 14),
            const SizedBox(width: 8),
            Text(f,
                style: GoogleFonts.poppins(
                    color: const Color(0xFFCFCFCF), fontSize: 12)),
          ],
        ),
      );

}
