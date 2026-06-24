import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Progress — weekly overview, trend chart, body composition, measurements.
class ClientProgressScreen extends StatelessWidget {
  const ClientProgressScreen({super.key});

  static const Color _bg = Color(0xFF0A0A0A);
  static const Color _card = Color(0xFF141414);
  static const Color _muted = Color(0xFF8E8E8E);
  static const Color _red = Color(0xFFE10600);
  static const Color _green = Color(0xFF2EBD59);
  static const Color _blue = Color(0xFF3B82F6);
  static const Color _amber = Color(0xFFF59E0B);

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
            _tabs(),
            const SizedBox(height: 16),
            _zoneBanner(),
            const SizedBox(height: 18),
            _weekOverview(),
            const SizedBox(height: 16),
            _progressOverTime(),
            const SizedBox(height: 16),
            _bodyComposition(),
            const SizedBox(height: 18),
            _measurements(),
            const SizedBox(height: 18),
            _performance(),
            const SizedBox(height: 18),
            _ctaBanner(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Progress',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Track your journey. See your transformation.',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 12)),
            ],
          ),
        ),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFF242424)),
          ),
          child: const Icon(Icons.calendar_today_outlined,
              color: Colors.white, size: 17),
        ),
        const SizedBox(width: 10),
        Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFF242424)),
          ),
          child: Row(
            children: [
              Text('This Week',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w500)),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  color: _muted, size: 18),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tabs() {
    const tabs = ['Overview', 'Body Stats', 'Photos', 'Strength'];
    return Row(
      children: List.generate(tabs.length, (i) {
        final active = i == 0;
        return Expanded(
          child: Column(
            children: [
              Text(tabs[i],
                  style: GoogleFonts.poppins(
                      color: active ? _red : _muted,
                      fontSize: 12.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400)),
              const SizedBox(height: 8),
              Container(
                  height: active ? 2 : 1,
                  color: active ? _red : const Color(0xFF222222)),
            ],
          ),
        );
      }),
    );
  }

  Widget _zoneBanner() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Image.asset('assets/images/progress_banner.png',
                  fit: BoxFit.cover),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFF141414),
                    const Color(0xFF141414).withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text("You're in the zone!",
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    const Text('🔥', style: TextStyle(fontSize: 14)),
                  ],
                ),
                const SizedBox(height: 4),
                Text('Consistency is your\nsuperpower.',
                    style: GoogleFonts.poppins(
                        color: _muted, fontSize: 12, height: 1.35)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _weekOverview() {
    final stats = [
      (_red, Icons.fitness_center, '4 / 6', 'Workouts\nCompleted'),
      (_green, Icons.local_fire_department, '2,350', 'Calories\nBurned'),
      (_blue, Icons.timer_outlined, '5h 45m', 'Workout\nTime'),
      (_amber, Icons.trending_up, '98%', 'Plan\nAdherence'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('This Week Overview',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Row(
            children: stats
                .map((s) => Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(s.$2, color: s.$1, size: 16),
                          const SizedBox(height: 6),
                          Text(s.$3,
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700)),
                          Text(s.$4,
                              style: GoogleFonts.poppins(
                                  color: _muted, fontSize: 9, height: 1.2)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  Widget _progressOverTime() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Progress Over Time',
                  style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600)),
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1C),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    _segTab('Weekly', true),
                    _segTab('Monthly', false),
                    _segTab('Quarterly', false),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _legend(_red, 'Weight (kg)'),
              const SizedBox(width: 14),
              _legend(_blue, 'Body Fat (%)'),
              const SizedBox(width: 14),
              _legend(_green, 'Muscle Mass (kg)'),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(height: 150, child: _lineChart()),
          const SizedBox(height: 12),
          const Divider(color: Color(0xFF222222), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              _delta('1.3 kg', 'Weight', false),
              _delta('0.8 %', 'Body Fat', false),
              _delta('1.2 kg', 'Muscle Mass', true),
              _delta('320 kcal', 'Avg. Calories/Day', true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _segTab(String t, bool active) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: active ? _red : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(t,
            style: GoogleFonts.poppins(
                color: active ? Colors.white : _muted,
                fontSize: 10,
                fontWeight: FontWeight.w500)),
      );

  Widget _legend(Color c, String t) => Row(
        children: [
          Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(t, style: GoogleFonts.poppins(color: _muted, fontSize: 9.5)),
        ],
      );

  Widget _lineChart() {
    LineChartBarData bar(List<double> ys, Color c) => LineChartBarData(
          spots: [for (int i = 0; i < ys.length; i++) FlSpot(i.toDouble(), ys[i])],
          isCurved: true,
          color: c,
          barWidth: 2.4,
          dotData: FlDotData(show: true),
          belowBarData: BarAreaData(show: false),
        );

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: 6,
        minY: 10,
        maxY: 80,
        gridData: FlGridData(show: false),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(enabled: false),
        titlesData: FlTitlesData(
          topTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              interval: 20,
              getTitlesWidget: (v, meta) => Text(v.toInt().toString(),
                  style: GoogleFonts.poppins(color: _muted, fontSize: 8)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 20,
              interval: 1,
              getTitlesWidget: (v, meta) {
                const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
                final i = v.toInt();
                if (i < 0 || i >= days.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(days[i],
                      style: GoogleFonts.poppins(color: _muted, fontSize: 8)),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          bar([74, 73.6, 73.2, 73, 72.8, 72.6, 72.5], _red),
          bar([28, 26, 25, 24, 22, 21, 20], _blue),
          bar([60, 61, 61.5, 62, 63, 63.5, 64], _green),
        ],
      ),
    );
  }

  Widget _delta(String value, String label, bool up) {
    return Expanded(
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(up ? Icons.arrow_upward : Icons.arrow_downward,
                  color: _green, size: 10),
              const SizedBox(width: 2),
              Text(value,
                  style: GoogleFonts.poppins(
                      color: _green,
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: _muted, fontSize: 8.5)),
        ],
      ),
    );
  }

  Widget _bodyComposition() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E1E1E)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Body Composition',
              style: GoogleFonts.poppins(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          Row(
            children: [
              SizedBox(
                width: 92,
                height: 92,
                child: PieChart(
                  PieChartData(
                    sectionsSpace: 2,
                    centerSpaceRadius: 26,
                    sections: [
                      _slice(22.4, _blue),
                      _slice(11.3, _red),
                      _slice(3.1, _green),
                      _slice(35.7, _amber),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Current',
                      style: GoogleFonts.poppins(color: _muted, fontSize: 9.5)),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('72.5',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w800)),
                      Text(' kg',
                          style: GoogleFonts.poppins(
                              color: _muted, fontSize: 10)),
                    ],
                  ),
                  Text('Total Weight',
                      style: GoogleFonts.poppins(color: _muted, fontSize: 9)),
                  const SizedBox(height: 6),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      Text('15.6',
                          style: GoogleFonts.poppins(
                              color: Colors.white,
                              fontSize: 16,
                              fontWeight: FontWeight.w700)),
                      Text(' %',
                          style: GoogleFonts.poppins(
                              color: _muted, fontSize: 9)),
                    ],
                  ),
                  Text('Body Fat',
                      style: GoogleFonts.poppins(color: _muted, fontSize: 9)),
                ],
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _compLegend(_blue, 'Muscle Mass', '22.4 kg'),
                  _compLegend(_red, 'Body Fat', '11.3 kg'),
                  _compLegend(_green, 'Bone Mass', '3.1 kg'),
                  _compLegend(_amber, 'Water Weight', '35.7 kg'),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 42,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF242424)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('View Detailed Body Stats',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600)),
                const Icon(Icons.chevron_right, color: _muted, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }

  PieChartSectionData _slice(double v, Color c) => PieChartSectionData(
        value: v,
        color: c,
        radius: 18,
        showTitle: false,
      );

  Widget _compLegend(Color c, String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: c, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label,
                style: GoogleFonts.poppins(color: _muted, fontSize: 10)),
            const SizedBox(width: 10),
            Text(value,
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w600)),
          ],
        ),
      );

  Widget _measurements() {
    final m = [
      (Icons.favorite_border, 'Chest', '102 cm', '1.5 cm', true),
      (Icons.straighten, 'Waist', '78 cm', '2 cm', false),
      (Icons.fitness_center, 'Arms', '36 cm', '0.8 cm', true),
      (Icons.accessibility_new, 'Thighs', '56 cm', '0.6 cm', true),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Key Measurements',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            Text('View All',
                style: GoogleFonts.poppins(
                    color: _red, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E1E1E)),
          ),
          child: Row(
            children: m
                .map((e) => Expanded(
                      child: Column(
                        children: [
                          Icon(e.$1, color: _red, size: 16),
                          const SizedBox(height: 6),
                          Text(e.$3,
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700)),
                          Text(e.$2,
                              style: GoogleFonts.poppins(
                                  color: _muted, fontSize: 9.5)),
                          const SizedBox(height: 3),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                  e.$5
                                      ? Icons.arrow_upward
                                      : Icons.arrow_downward,
                                  color: _green,
                                  size: 9),
                              Text(e.$4,
                                  style: GoogleFonts.poppins(
                                      color: _green, fontSize: 8.5)),
                            ],
                          ),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _performance() {
    final p = [
      (Icons.fitness_center, _green, 'Strength', 'Good', 'Progressing'),
      (Icons.favorite, _red, 'Endurance', 'Excellent', 'Improving'),
      (Icons.self_improvement, _amber, 'Mobility', 'Good', 'Maintaining'),
      (Icons.bedtime_outlined, _blue, 'Recovery', 'Great', 'Well Rested'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Performance',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w700)),
            Text('View All',
                style: GoogleFonts.poppins(
                    color: _red, fontSize: 12, fontWeight: FontWeight.w600)),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF1E1E1E)),
          ),
          child: Row(
            children: p
                .map((e) => Expanded(
                      child: Column(
                        children: [
                          Icon(e.$1, color: e.$2, size: 18),
                          const SizedBox(height: 6),
                          Text(e.$3,
                              style: GoogleFonts.poppins(
                                  color: _muted, fontSize: 9.5)),
                          Text(e.$4,
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w700)),
                          Text(e.$5,
                              style: GoogleFonts.poppins(
                                  color: _muted, fontSize: 8.5)),
                        ],
                      ),
                    ))
                .toList(),
          ),
        ),
      ],
    );
  }

  Widget _ctaBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: const LinearGradient(
          colors: [Color(0xFF1A0E0E), Color(0xFF2A0E0E)],
        ),
        border: Border.all(color: _red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.emoji_events, color: _red, size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Small daily improvements lead to',
                    style: GoogleFonts.poppins(color: _muted, fontSize: 11)),
                Text('Big transformations.',
                    style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: _red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('Keep Pushing!',
                style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
