// lib/screens/client/client_progress_screen.dart

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../controllers/theme_controller.dart';

class ClientProgressScreen extends StatelessWidget {
  const ClientProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Get.find<ThemeController>();

    return Obx(() {
      final isDark = theme.isDarkMode.value;

      final bg = isDark ? const Color(0xFF0E0E0E) : Colors.grey.shade100;
      final card = isDark ? Colors.white.withOpacity(.06) : Colors.white;
      final text = isDark ? Colors.white : Colors.black87;
      final sub = isDark ? Colors.white60 : Colors.black54;
      final accent = Colors.redAccent.shade700;

      return Scaffold(
        backgroundColor: bg,
        appBar: AppBar(
          backgroundColor: bg,
          elevation: 0,
          title: Text(
            "Your Progress",
            style: GoogleFonts.poppins(
              color: text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            _streakCard(card, accent, text, sub),
            const SizedBox(height: 24),

            _sectionTitle("Today’s Completion", text),
            const SizedBox(height: 12),
            _ringsRow(card, accent, text, sub),
            const SizedBox(height: 26),

            _sectionTitle("Body Metrics", text),
            const SizedBox(height: 12),
            _metricsCard(card, text, sub, accent),
            const SizedBox(height: 26),

            _sectionTitle("Progress Timeline", text),
            const SizedBox(height: 12),
            _timeline(card, accent, text, sub),
          ],
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  /// 🔥 STREAK CARD (SNAPCHAT STYLE)
  Widget _streakCard(Color card, Color accent, Color text, Color sub) {
    return _glass(
      child: Row(
        children: [
          Container(
            height: 56,
            width: 56,
            decoration: BoxDecoration(
              color: accent.withOpacity(.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.local_fire_department, color: accent, size: 34),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "7 Day Streak 🔥",
                  style: GoogleFonts.poppins(
                    color: text,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Log activity today to keep it alive",
                  style: GoogleFonts.poppins(color: sub, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  /// ⭕ COMPLETION RINGS (VISUAL DOPAMINE)
  Widget _ringsRow(Color card, Color accent, Color text, Color sub) {
    return Row(
      children: [
        _ring(card, accent, text, sub, "Workout", 0.8),
        const SizedBox(width: 12),
        _ring(card, Colors.orange, text, sub, "Diet", 0.65),
        const SizedBox(width: 12),
        _ring(card, Colors.green, text, sub, "Steps", 0.9),
      ],
    );
  }

  Widget _ring(
    Color card,
    Color color,
    Color text,
    Color sub,
    String label,
    double progress,
  ) {
    return Expanded(
      child: _glass(
        child: Column(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  height: 72,
                  width: 72,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 7,
                    backgroundColor: Colors.white12,
                    color: color,
                  ),
                ),
                Text(
                  "${(progress * 100).toInt()}%",
                  style: GoogleFonts.poppins(
                    color: text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(label, style: GoogleFonts.poppins(color: sub, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  /// 📊 BODY METRICS
  Widget _metricsCard(Color card, Color text, Color sub, Color accent) {
    return _glass(
      child: Column(
        children: [
          _metricRow("Weight", "72.4 kg", "+0.4 kg", accent, text, sub),
          _metricRow("Body Fat", "18%", "-0.8%", Colors.greenAccent, text, sub),
          _metricRow("Waist", "32 in", "-1 in", Colors.greenAccent, text, sub),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: Text(
              "Last updated • Today",
              style: GoogleFonts.poppins(color: sub, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricRow(
    String label,
    String value,
    String delta,
    Color deltaColor,
    Color text,
    Color sub,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(color: sub)),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                value,
                style: GoogleFonts.poppins(
                  color: text,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                delta,
                style: GoogleFonts.poppins(color: deltaColor, fontSize: 12),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  /// 🧭 TIMELINE (STORY-LIKE)
  Widget _timeline(Color card, Color accent, Color text, Color sub) {
    return Column(
      children: [
        _timelineCard(
          card,
          accent,
          text,
          sub,
          "This Week",
          "5 workouts completed",
        ),
        _timelineCard(
          card,
          Colors.greenAccent,
          text,
          sub,
          "Milestone",
          "Lost 3 kg in 30 days 🎉",
        ),
        _timelineCard(
          card,
          Colors.orange,
          text,
          sub,
          "Consistency",
          "Diet followed 6/7 days",
        ),
      ],
    );
  }

  Widget _timelineCard(
    Color card,
    Color accent,
    Color text,
    Color sub,
    String title,
    String desc,
  ) {
    return _glass(
      child: Row(
        children: [
          Container(
            height: 10,
            width: 10,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.poppins(
                    color: text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  desc,
                  style: GoogleFonts.poppins(color: sub, fontSize: 13),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _sectionTitle(String title, Color text) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: text,
      ),
    );
  }

  Widget _glass({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(.08)),
      ),
      child: child,
    );
  }
}
