import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';

import '../../../core/widgets/brand.dart';
import '../../../core/widgets/gradient_button.dart';
import '../dashboard_data.dart';

/// Home Dashboard — greeting, partner card, nutrition, progress, today's workout.
class ClientHomeScreen extends StatelessWidget {
  const ClientHomeScreen({super.key});

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);

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
            const SizedBox(height: 16),
            _partnerCard(),
            const SizedBox(height: 18),
            _nutrition(),
            const SizedBox(height: 18),
            _progressOverview(),
            const SizedBox(height: 18),
            _quote(),
            const SizedBox(height: 18),
            _todaysWorkout(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFF242424)),
          ),
          child: const Icon(Icons.grid_view_rounded, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('Good Morning, John!',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 17,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: 4),
                  const Text('👋', style: TextStyle(fontSize: 15)),
                ],
              ),
              const SizedBox(height: 2),
              Text('Ready to crush your goals today?',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 12)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _red.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _red.withValues(alpha: 0.5)),
          ),
          child: Row(
            children: [
              const Icon(Icons.local_fire_department, color: _red, size: 16),
              const SizedBox(width: 4),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('12',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 13,
                          height: 1,
                          fontWeight: FontWeight.w700)),
                  Text('Day Streak',
                      style:
                          GoogleFonts.poppins(color: _muted, fontSize: 8.5)),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _bell(),
      ],
    );
  }

  Widget _bell() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFF242424)),
          ),
          child: const Icon(Icons.notifications_none_rounded,
              color: Colors.white, size: 19),
        ),
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
            child: Text('2',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.w700)),
          ),
        ),
      ],
    );
  }

  Widget _partnerCard() {
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    alignment: Alignment.center,
                    child: const AlphaAMark(size: 22),
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
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w600)),
                            ),
                            const SizedBox(width: 3),
                            const Icon(Icons.verified, color: _red, size: 12),
                          ],
                        ),
                        Text('Your Transformation Partner',
                            style: GoogleFonts.poppins(
                                color: _muted, fontSize: 9.5)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          Container(width: 1, height: 50, color: const Color(0xFF1E1E1E)),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your Trainer',
                            style: GoogleFonts.poppins(
                                color: _red,
                                fontSize: 9,
                                fontWeight: FontWeight.w600)),
                        Text('Rahul Sharma',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600)),
                        Text('Strength & Performance Coach',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                                color: _muted, fontSize: 9)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ClipOval(
                    child: Image.asset('assets/images/trainer.png',
                        width: 38, height: 38, fit: BoxFit.cover),
                  ),
                  const Icon(Icons.chevron_right, color: _muted, size: 18),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _nutrition() {
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
              const Icon(Icons.restaurant, color: Color(0xFF2EBD59), size: 18),
              const SizedBox(width: 8),
              Text('Nutrition Today',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              const Spacer(),
              Row(
                children: [
                  const Icon(Icons.add, color: _red, size: 14),
                  const SizedBox(width: 3),
                  Text('Log Food',
                      style: GoogleFonts.poppins(
                          color: _red,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircularPercentIndicator(
                radius: 52,
                lineWidth: 9,
                percent: 0.64,
                backgroundColor: const Color(0xFF262626),
                progressColor: const Color(0xFF2EBD59),
                circularStrokeCap: CircularStrokeCap.round,
                center: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('860',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w800)),
                    Text('kcal left',
                        style: GoogleFonts.poppins(color: _muted, fontSize: 10)),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  children: [
                    Row(children: [
                      Expanded(child: _macro(kMacros[0])),
                      Expanded(child: _macro(kMacros[1])),
                    ]),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(child: _macro(kMacros[2])),
                      Expanded(child: _macro(kMacros[3])),
                    ]),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macro(Macro m) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(m.icon, color: m.color, size: 12),
              const SizedBox(width: 4),
              Text(m.name,
                  style: GoogleFonts.poppins(color: _muted, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 3),
          Text('${m.current} / ${m.goal}g',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 11,
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

  Widget _progressOverview() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.show_chart, color: Color(0xFF2EBD59), size: 18),
                const SizedBox(width: 8),
                Text('Progress Overview',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            Text('View All',
                style: GoogleFonts.poppins(
                    color: _red, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: kProgressStats
              .map((s) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: _statCard(s),
                    ),
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _statCard(ProgressStat s) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(s.icon, color: s.color, size: 16),
          const SizedBox(height: 8),
          Text(s.value,
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w700)),
          Text(s.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(color: _muted, fontSize: 8.5)),
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(s.up ? Icons.arrow_upward : Icons.arrow_downward,
                  color: const Color(0xFF2EBD59), size: 9),
              const SizedBox(width: 2),
              Flexible(
                child: Text(s.delta,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        color: const Color(0xFF2EBD59),
                        fontSize: 8.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          Text('vs last week',
              style: GoogleFonts.poppins(color: _muted, fontSize: 7.5)),
        ],
      ),
    );
  }

  Widget _quote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0E0E), Color(0xFF141414)],
        ),
        border: Border.all(color: const Color(0xFF2A1414)),
      ),
      child: Row(
        children: [
          const Text('"',
              style: TextStyle(
                  color: _red, fontSize: 40, fontWeight: FontWeight.w900)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Discipline today, defines your strength tomorrow.',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        height: 1.35)),
                const SizedBox(height: 4),
                Text('— Alpha Strength Co.',
                    style: GoogleFonts.poppins(color: _muted, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _todaysWorkout() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                const Icon(Icons.calendar_today_outlined,
                    color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Text("Today's Workout Plan",
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
              ],
            ),
            Text('25 May, 2024',
                style: GoogleFonts.poppins(color: _muted, fontSize: 11)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            gradient: const LinearGradient(
              colors: [Color(0xFFE10600), Color(0xFF8A0000)],
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fitness_center,
                    color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Upper Body Strength',
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    Text('5 Exercises • Est. 60 Min',
                        style: GoogleFonts.poppins(
                            color: Colors.white70, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text('Day 1 of 6',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 9.5,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        ...List.generate(
            kTodayExercises.length, (i) => _exerciseRow(i + 1, kTodayExercises[i])),
        const SizedBox(height: 8),
        GradientButton(
          label: 'View Workout Performance',
          showChevron: true,
          onPressed: () {},
        ),
      ],
    );
  }

  Widget _exerciseRow(int n, Exercise e) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Row(
        children: [
          Text('$n',
              style: GoogleFonts.poppins(
                  color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Image.asset(e.thumb, width: 42, height: 42, fit: BoxFit.cover),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                Text(e.muscle,
                    style: GoogleFonts.poppins(color: _muted, fontSize: 10)),
              ],
            ),
          ),
          _miniStat('${e.sets} Sets'),
          _miniStat(e.reps),
          _miniStat(e.weight),
          const SizedBox(width: 6),
          const Icon(Icons.radio_button_unchecked, color: _muted, size: 18),
        ],
      ),
    );
  }

  Widget _miniStat(String t) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(t,
            style: GoogleFonts.poppins(
                color: const Color(0xFFCFCFCF), fontSize: 9.5)),
      );
}
