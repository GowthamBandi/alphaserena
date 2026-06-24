import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/widgets/brand.dart';
import 'discover_models.dart';
import 'plans_screen.dart';

/// Organization Profile — the storefront a member sees before subscribing.
class CoachStorefrontScreen extends StatelessWidget {
  final DiscoverOrg org;
  const CoachStorefrontScreen({super.key, required this.org});

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          _hero(context),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _headerBlock(),
                const SizedBox(height: 16),
                _statsPanel(),
                const SizedBox(height: 22),
                _about(),
                const SizedBox(height: 22),
                _transformations(),
                const SizedBox(height: 22),
                _whatWeOffer(),
                const SizedBox(height: 22),
                _whyChoose(),
                const SizedBox(height: 18),
                _footer(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hero(BuildContext context) {
    return Stack(
      children: [
        Image.asset('assets/images/op_hero.png',
            width: double.infinity, fit: BoxFit.cover),
        Positioned(
          top: MediaQuery.of(context).padding.top + 6,
          left: 12,
          right: 12,
          child: Row(
            children: [
              _heroIcon(Icons.arrow_back_ios_new, () => Get.back()),
              const Spacer(),
              _heroIcon(Icons.favorite_border, () {}),
              const SizedBox(width: 8),
              _heroIcon(Icons.ios_share, () {}),
            ],
          ),
        ),
      ],
    );
  }

  Widget _heroIcon(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 17),
      ),
    );
  }

  Widget _headerBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 86,
              height: 86,
              decoration: BoxDecoration(
                color: const Color(0xFF161616),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFF242424)),
              ),
              alignment: Alignment.center,
              child: org.id == 'alpha'
                  ? const AlphaAMark(size: 44)
                  : Icon(org.logoIcon, color: org.logoColor, size: 40),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.verified, color: _red, size: 13),
                      const SizedBox(width: 4),
                      Text('VERIFIED ORGANIZATION',
                          style: GoogleFonts.poppins(
                              color: _red,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.5)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(org.name,
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 21,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(org.tagline,
                      style: GoogleFonts.poppins(color: _muted, fontSize: 13)),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.location_on, color: _muted, size: 13),
                      const SizedBox(width: 4),
                      Text(org.location,
                          style:
                              GoogleFonts.poppins(color: _muted, fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    const Icon(Icons.star, color: Color(0xFFFFC107), size: 16),
                    const SizedBox(width: 3),
                    Text(org.rating.toStringAsFixed(1),
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                  ],
                ),
                Text('(320 Reviews)',
                    style: GoogleFonts.poppins(color: _muted, fontSize: 11)),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [...org.tags, 'Athletic Performance'].map(_chip).toList(),
        ),
      ],
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.circular(9),
          border: Border.all(color: const Color(0xFF262626)),
        ),
        child: Text(label,
            style: GoogleFonts.poppins(
                color: const Color(0xFFC0C0C0), fontSize: 11.5)),
      );

  Widget _statsPanel() {
    final stats = [
      (Icons.groups_outlined, '12.5K+', 'Clients Trained'),
      (Icons.calendar_today_outlined, '8+', 'Years Experience'),
      (Icons.emoji_events_outlined, '35+', 'Certified Trainers'),
      (Icons.shield_outlined, '2.1K+', 'Transformations'),
    ];
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Row(
        children: stats
            .map((s) => Expanded(
                  child: Column(
                    children: [
                      Icon(s.$1, color: _red, size: 22),
                      const SizedBox(height: 8),
                      Text(s.$2,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(s.$3,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                              color: _muted, fontSize: 10.5)),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

  Widget _about() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('About ${org.name}',
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'At ${org.name}, we don\'t just build bodies — we build '
                    'stronger, confident, and better versions of you. Our '
                    'science-backed training programs, personalized nutrition, '
                    'and expert coaching help you achieve real, sustainable '
                    'results.',
                    style: GoogleFonts.poppins(
                        color: _muted, fontSize: 12.5, height: 1.5),
                  ),
                  const SizedBox(height: 6),
                  Text('Read More',
                      style: GoogleFonts.poppins(
                          color: _red,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFF1E1E1E)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('"',
                        style: GoogleFonts.poppins(
                            color: _red,
                            fontSize: 34,
                            fontWeight: FontWeight.w800,
                            height: 1)),
                    Text(
                      'We believe fitness isn\'t just a goal, it\'s a way of life.',
                      style: GoogleFonts.poppins(
                          color: Colors.white, fontSize: 12.5, height: 1.4),
                    ),
                    const SizedBox(height: 6),
                    Text('— ${org.name}',
                        style:
                            GoogleFonts.poppins(color: _muted, fontSize: 11)),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _transformations() {
    final items = [
      ('assets/images/trans1.png', 'Raj Sharma', 'Fat Loss'),
      ('assets/images/trans2.png', 'Neha Verma', 'Muscle Gain'),
      ('assets/images/trans3.png', 'Amit Yadav', 'Body Transformation'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Client Transformations',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            Text('View All',
                style: GoogleFonts.poppins(
                    color: _red, fontSize: 12.5, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 188,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final it = items[i];
              return SizedBox(
                width: 230,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(it.$1,
                          width: 230, height: 134, fit: BoxFit.cover),
                    ),
                    const SizedBox(height: 8),
                    Text(it.$2,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600)),
                    Text(it.$3,
                        style:
                            GoogleFonts.poppins(color: _muted, fontSize: 11.5)),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _whatWeOffer() {
    final offers = [
      (Icons.fitness_center, 'Personalized\nWorkout Plans'),
      (Icons.restaurant_menu, 'Custom\nNutrition Plans'),
      (Icons.person_pin_circle_outlined, '1-on-1 Expert\nCoaching'),
      (Icons.show_chart, 'Progress\nTracking'),
      (Icons.support_agent, '24/7 Support\n& Guidance'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('What We Offer',
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 6),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF1E1E1E)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: offers
                .map((o) => Expanded(
                      child: Column(
                        children: [
                          Icon(o.$1, color: _red, size: 22),
                          const SizedBox(height: 8),
                          Text(o.$2,
                              textAlign: TextAlign.center,
                              style: GoogleFonts.poppins(
                                  color: const Color(0xFFCFCFCF),
                                  fontSize: 10,
                                  height: 1.25)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _whyChoose() {
    Widget check(String t) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.check_circle, color: _red, size: 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(t,
                    style: GoogleFonts.poppins(
                        color: const Color(0xFFCFCFCF),
                        fontSize: 11.5,
                        height: 1.3)),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Why Choose ${org.name}?',
            style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 5,
              child: Column(
                children: [
                  check('Science-backed training methods'),
                  check('Result-driven programs'),
                  check('Certified & experienced coaches'),
                  check('Holistic approach to fitness'),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(flex: 4, child: _ctaCard()),
          ],
        ),
      ],
    );
  }

  Widget _ctaCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFE10600), Color(0xFF8A0000)],
        ),
        boxShadow: [
          BoxShadow(
              color: _red.withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ready to Start Your Transformation?',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  height: 1.25)),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xFF111111),
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => Get.to(() => PlansScreen(org: org)),
              child: Text('Choose This Organization',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.poppins(
                      fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    Widget col(IconData icon, String title, List<String> lines) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: _red, size: 14),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(title,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ...lines.map((l) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(l,
                        style: GoogleFonts.poppins(
                            color: _muted, fontSize: 10.5, height: 1.3)),
                  )),
            ],
          ),
        );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          col(Icons.access_time, 'Operating Hours',
              ['Mon - Sat:', '5:00 AM - 10:00 PM', 'Sunday:', '6:00 AM - 2:00 PM']),
          const SizedBox(width: 10),
          col(Icons.call, 'Contact',
              ['+91 98765 43210', 'info@alphastrength.co']),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.favorite, color: _red, size: 14),
                    const SizedBox(width: 6),
                    Text('Follow Us',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    _social(Icons.camera_alt, const Color(0xFFE1306C)),
                    const SizedBox(width: 8),
                    _social(Icons.play_arrow, _red),
                    const SizedBox(width: 8),
                    _social(Icons.facebook, const Color(0xFF1877F2)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _social(IconData icon, Color color) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: Icon(icon, color: Colors.white, size: 16),
      );
}
