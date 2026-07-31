import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/widgets/gradient_button.dart';
import 'checkout_screen.dart';
import 'discover_models.dart';

/// Plan Details — a premium, detailed view of the chosen plan before checkout.
/// Driven by the real [PlanVM] (price/duration/description/points).
class PlanDetailsScreen extends StatelessWidget {
  final DiscoverOrg org;
  final PlanVM plan;
  const PlanDetailsScreen({super.key, required this.org, required this.plan});

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

  static const List<IconData> _pointIcons = [
    Icons.fitness_center,
    Icons.restaurant_menu,
    Icons.person_pin_circle_outlined,
    Icons.show_chart,
    Icons.support_agent,
    Icons.verified_outlined,
  ];

  int get _perMonth =>
      plan.months > 0 ? (plan.price / plan.months).round() : plan.price;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new,
            color: Colors.white,
            size: 18,
          ),
          onPressed: () => Get.back(),
        ),
        title: Text(
          'Plan Details',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 6, 18, 20),
              children: [
                _heroCard(),
                const SizedBox(height: 16),
                _highlights(),
                if (plan.description.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionTitle('About this plan'),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: _cardDecoration(),
                    child: Text(
                      plan.description,
                      style: GoogleFonts.poppins(
                        color: const Color(0xFFCFCFCF),
                        fontSize: 12.5,
                        height: 1.55,
                      ),
                    ),
                  ),
                ],
                if (plan.points.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  _sectionTitle("What's Included"),
                  const SizedBox(height: 12),
                  ...List.generate(plan.points.length, (i) {
                    return _includedRow(
                      _pointIcons[i % _pointIcons.length],
                      plan.points[i],
                    );
                  }),
                ],
                const SizedBox(height: 18),
                _trustStrip(),
              ],
            ),
          ),
          _bottomBar(),
        ],
      ),
    );
  }

  // ── Hero plan card ──────────────────────────────────────────────────────
  Widget _heroCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1F0D0D), Color(0xFF120808)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _red.withValues(alpha: 0.55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Org row.
          Row(
            children: [
              OrgThumb(org: org, size: 40),
              const SizedBox(width: 10),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        org.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (org.verified) ...[
                      const SizedBox(width: 5),
                      const Icon(Icons.verified, color: _red, size: 14),
                    ],
                  ],
                ),
              ),
              if (plan.featured)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(
                    'MOST POPULAR',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 8.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            plan.name,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 23,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            plan.program,
            style: GoogleFonts.poppins(
              color: _red,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '₹${inr(plan.price)}',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  'one-time',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 12),
                ),
              ),
            ],
          ),
          if (plan.months > 1) ...[
            const SizedBox(height: 4),
            Text(
              '≈ ₹${inr(_perMonth)}/month · billed once for ${plan.months} months',
              style: GoogleFonts.poppins(color: _muted, fontSize: 11.5),
            ),
          ],
        ],
      ),
    );
  }

  // ── Highlights row ────────────────────────────────────────────────────────
  Widget _highlights() {
    final tiles = <(IconData, String, String)>[
      (Icons.calendar_month_outlined, plan.durationLabel, 'Duration'),
      if (plan.months > 1)
        (Icons.payments_outlined, '₹${inr(_perMonth)}', 'Per month'),
      if (plan.points.isNotEmpty)
        (Icons.workspace_premium_outlined, '${plan.points.length}', 'Benefits'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: _cardDecoration(),
      child: Row(
        children: tiles
            .map(
              (t) => Expanded(
                child: Column(
                  children: [
                    Icon(t.$1, color: _red, size: 20),
                    const SizedBox(height: 7),
                    Text(
                      t.$2,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      t.$3,
                      style: GoogleFonts.poppins(color: _muted, fontSize: 10),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }

  Widget _includedRow(IconData icon, String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: _cardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
            child: Text(
              title,
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.3,
              ),
            ),
          ),
          const Icon(Icons.check_circle, color: _red, size: 18),
        ],
      ),
    );
  }

  Widget _trustStrip() {
    Widget item(IconData icon, String t) => Expanded(
      child: Column(
        children: [
          Icon(icon, color: _muted, size: 18),
          const SizedBox(height: 6),
          Text(
            t,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: _muted,
              fontSize: 10,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
          decoration: _cardDecoration(),
          child: Row(
            children: [
              item(Icons.lock_outline, 'Secure\npayment'),
              item(Icons.flash_on_outlined, 'Instant\naccess'),
              // Only claim verification when the platform actually granted it.
              if (org.verified)
                item(Icons.verified_user_outlined, 'Verified\ncoach')
              else
                item(Icons.receipt_long_outlined, 'No hidden\nfees'),
            ],
          ),
        ),
        const SizedBox(height: 10),
        // Backed by the server's renewal math (renewalBaseMs): a purchase
        // extends from max(now, current expiry) — paid time is never lost.
        Text(
          'Already a member? A new purchase adds time on top of your '
          'current membership — no days are lost.',
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: _muted,
            fontSize: 10.5,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      decoration: const BoxDecoration(
        color: _bg,
        border: Border(top: BorderSide(color: Color(0xFF1A1A1A))),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Total',
                style: GoogleFonts.poppins(color: _muted, fontSize: 10.5),
              ),
              Text(
                '₹${inr(plan.price)}',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
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

  Widget _sectionTitle(String t) => Text(
    t,
    style: GoogleFonts.poppins(
      color: Colors.white,
      fontSize: 15,
      fontWeight: FontWeight.w700,
    ),
  );

  BoxDecoration _cardDecoration() => BoxDecoration(
    color: _card,
    borderRadius: BorderRadius.circular(14),
    border: Border.all(color: const Color(0xFF1E1E1E)),
  );
}
