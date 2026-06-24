import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

import '../../core/widgets/brand.dart';
import 'dashboard_data.dart';

/// My Plans — partner, active plans, today's nutrition + meals, workout overview.
class MyPlansScreen extends StatelessWidget {
  const MyPlansScreen({super.key});

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);
  static const Color _green = Color(0xFF2EBD59);

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _bg,
      child: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          children: [
            _header(),
            const SizedBox(height: 18),
            _tabs(),
            const SizedBox(height: 16),
            _partnerCard(),
            const SizedBox(height: 20),
            _sectionTitle('Active Plans'),
            const SizedBox(height: 12),
            _activePlans(),
            const SizedBox(height: 16),
            _todaysNutrition(),
            const SizedBox(height: 16),
            _sectionTitle("Today's Meals"),
            const SizedBox(height: 12),
            _meals(),
            const SizedBox(height: 12),
            _logFoodButton(),
            const SizedBox(height: 20),
            _workoutOverview(),
            const SizedBox(height: 20),
            _planDetails(),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) => Text(t,
      style: GoogleFonts.poppins(
          color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700));

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('My Plans',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Your personalized plans, crafted for your goals.',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 12)),
            ],
          ),
        ),
        _iconBtn(Icons.calendar_today_outlined),
        const SizedBox(width: 10),
        _iconBtn(Icons.tune),
      ],
    );
  }

  Widget _iconBtn(IconData icon) => Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFF242424)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      );

  Widget _tabs() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  Text('Current Plans',
                      style: GoogleFonts.poppins(
                          color: _red,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Container(height: 2, color: _red),
                ],
              ),
            ),
            Expanded(
              child: Column(
                children: [
                  Text('Previous Plans',
                      style: GoogleFonts.poppins(
                          color: _muted, fontSize: 13.5)),
                  const SizedBox(height: 8),
                  Container(height: 1, color: const Color(0xFF222222)),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _partnerCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0E0E), Color(0xFF141414)],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF2A1414)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(11),
                ),
                alignment: Alignment.center,
                child: const AlphaAMark(size: 26),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text('Alpha Strength Co.',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600)),
                        ),
                        const SizedBox(width: 3),
                        const Icon(Icons.verified, color: _red, size: 12),
                      ],
                    ),
                    Text('Your Transformation Partner',
                        style: GoogleFonts.poppins(color: _muted, fontSize: 9.5)),
                  ],
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Your Trainer',
                              style: GoogleFonts.poppins(
                                  color: _red,
                                  fontSize: 8.5,
                                  fontWeight: FontWeight.w600)),
                          Text('Rahul Sharma',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600)),
                          Text('Strength & Performance Coach',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                  color: _muted, fontSize: 8)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    ClipOval(
                      child: Image.asset('assets/images/trainer.png',
                          width: 38, height: 38, fit: BoxFit.cover),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          const Divider(color: Color(0xFF2A1414), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _planStat(Icons.calendar_today_outlined, 'Plan Started',
                  '20 May 2024'),
              _planStat(Icons.refresh, 'Next Review', '20 Jun 2024'),
              _planStat(Icons.schedule, 'Plan Duration', '12 Weeks'),
              _planStat(Icons.flag_outlined, 'Goal', 'Muscle Gain'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _planStat(IconData icon, String label, String value) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _red, size: 14),
            const SizedBox(height: 5),
            Text(label,
                style: GoogleFonts.poppins(color: _muted, fontSize: 8.5)),
            Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _activePlans() {
    Widget card(IconData icon, Color color, String title, String sub) =>
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: color, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600)),
                      Text(sub,
                          style: GoogleFonts.poppins(
                              color: _muted, fontSize: 9, height: 1.2)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        card(Icons.restaurant_menu, _green, 'Nutrition Plan',
            'Daily meal plan & nutrition guide'),
        const SizedBox(width: 12),
        card(Icons.fitness_center, _red, 'Workout Plan',
            'Daily workouts & training guide'),
      ],
    );
  }

  Widget _todaysNutrition() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.restaurant, color: _green, size: 18),
              const SizedBox(width: 8),
              Text("Today's Nutrition",
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Row(
                children: [
                  Text('View Full Plan',
                      style: GoogleFonts.poppins(
                          color: _red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                  const Icon(Icons.chevron_right, color: _red, size: 16),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              CircularPercentIndicator(
                radius: 48,
                lineWidth: 8,
                percent: 0.64,
                backgroundColor: const Color(0xFF262626),
                linearGradient: const LinearGradient(
                    colors: [Color(0xFFE10600), Color(0xFF2EBD59)]),
                circularStrokeCap: CircularStrokeCap.round,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('860',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                    Text('kcal left',
                        style:
                            GoogleFonts.poppins(color: _muted, fontSize: 9)),
                    Text('/ 2,400 kcal',
                        style:
                            GoogleFonts.poppins(color: _muted, fontSize: 7.5)),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children:
                      kMacros.map((m) => Expanded(child: _macroV(m))).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macroV(Macro m) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: Column(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              color: m.color.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(m.icon, color: m.color, size: 13),
          ),
          const SizedBox(height: 5),
          Text(m.name,
              style: GoogleFonts.poppins(color: _muted, fontSize: 9)),
          Text('${m.current} / ${m.goal}g',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: m.pct,
              minHeight: 4,
              backgroundColor: const Color(0xFF262626),
              valueColor: AlwaysStoppedAnimation(m.color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _meals() {
    return SizedBox(
      height: 168,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: kMeals.length,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final m = kMeals[i];
          return Container(
            width: 150,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF1E1E1E)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.type,
                    style: GoogleFonts.poppins(color: _muted, fontSize: 10)),
                const SizedBox(height: 2),
                Text(m.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12,
                        height: 1.25,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.asset(m.image,
                      width: double.infinity, height: 58, fit: BoxFit.cover),
                ),
                const SizedBox(height: 6),
                Text('${m.kcal} kcal',
                    style: GoogleFonts.poppins(
                        color: _green,
                        fontSize: 11,
                        fontWeight: FontWeight.w600)),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _logFoodButton() {
    return Container(
      height: 48,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF242424)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('Log Your Food',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          const SizedBox(width: 8),
          Container(
            width: 22,
            height: 22,
            decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
            child: const Icon(Icons.add, color: Colors.white, size: 14),
          ),
        ],
      ),
    );
  }

  Widget _workoutOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.fitness_center, color: _red, size: 16),
                const SizedBox(width: 8),
                Text('Workout Plan Overview',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            Row(
              children: [
                Text('View Full Plan',
                    style: GoogleFonts.poppins(
                        color: _red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
                const Icon(Icons.chevron_right, color: _red, size: 16),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            children: [
              Image.asset('assets/images/ex1.png',
                  width: double.infinity, height: 120, fit: BoxFit.cover),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Colors.black.withValues(alpha: 0.85),
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _red,
                            borderRadius: BorderRadius.circular(7),
                          ),
                          child: Text('Day 2 of 6',
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600)),
                        ),
                        Text('Workouts Completed',
                            style: GoogleFonts.poppins(
                                color: Colors.white70, fontSize: 9.5)),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text('Upper Body Strength',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    Text("Today's Workout",
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 10.5)),
                    const SizedBox(height: 10),
                    Row(
                      children: List.generate(
                          6,
                          (i) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Icon(
                                  i < 3
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: i < 3 ? _green : Colors.white38,
                                  size: 16,
                                ),
                              )),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          height: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF242424)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.calendar_month_outlined,
                  color: Colors.white, size: 16),
              const SizedBox(width: 8),
              Text('View Workout Calendar',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _planDetails() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Plan Details'),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E1E1E)),
          ),
          child: Row(
            children: [
              _detail(Icons.flag_outlined, 'Plan Type', 'Muscle Gain'),
              _detail(Icons.schedule, 'Plan Duration', '12 Weeks'),
              _detail(Icons.local_fire_department, 'Daily Calories',
                  '2,400 kcal'),
              _detail(Icons.update, 'Last Updated', '24 May 2024'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _detail(IconData icon, String label, String value) => Expanded(
        child: Column(
          children: [
            Icon(icon, color: _red, size: 16),
            const SizedBox(height: 6),
            Text(label,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(color: _muted, fontSize: 8.5)),
            const SizedBox(height: 2),
            Text(value,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
