// lib/screens/client/client_profile_screen.dart

import 'package:alphaserena/controllers/theme_controller.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

class ClientProfileScreen extends StatelessWidget {
  const ClientProfileScreen({super.key});

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
          // iconTheme: IconThemeData(color: textColor),
          actions: [
            IconButton(
              onPressed: theme.toggleTheme, // ✅ FIXED
              icon: Icon(isDark ? Icons.light_mode : Icons.dark_mode),
            ),
          ],
          title: Text(
            "Profile",
            style: GoogleFonts.poppins(
              color: text,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _profileHeader(card, text, sub, accent),
            const SizedBox(height: 20),

            _actionsAndMetrics(card, text, sub, accent),
            const SizedBox(height: 24),

            _sectionTitle("Progress Snapshot", text),
            const SizedBox(height: 12),
            _progressCard(card, accent, text, sub),
            const SizedBox(height: 24),

            _sectionTitle("Assigned Trainer", text),
            const SizedBox(height: 12),
            _trainerCard(card, accent, text, sub),
          ],
        ),
      );
    });
  }

  // ---------------------------------------------------------------------------
  /// PROFILE HEADER (WITH EDIT + SUBSCRIPTION)
  Widget _profileHeader(Color card, Color text, Color sub, Color accent) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: accent.withOpacity(.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: accent,
                child: const Text(
                  "A",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Arjun Kumar",
                      style: GoogleFonts.poppins(
                        color: text,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Age 26 • Male",
                      style: GoogleFonts.poppins(color: sub, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(LucideIcons.edit, color: accent, size: 20),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: Colors.white12),

          // SUBSCRIPTION INFO
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _profileStat("Plan", "Premium", accent),
              _profileStat("Status", "Active", Colors.greenAccent),
              _profileStat("Expiry", "12 Dec 2025", sub),
            ],
          ),
        ],
      ),
    );
  }

  Widget _profileStat(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(color: Colors.white60, fontSize: 11),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GoogleFonts.poppins(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  /// ACTIONS + BODY METRICS (SINGLE CONTAINER)
  Widget _actionsAndMetrics(Color card, Color text, Color sub, Color accent) {
    return Container(
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: accent.withOpacity(.2)),
      ),
      child: Column(
        children: [
          _actionTile(LucideIcons.messageCircle, "Chat with Trainer", accent),
          _divider(),
          _actionTile(LucideIcons.apple, "View Diet Plan", accent),
          _divider(),
          _actionTile(LucideIcons.dumbbell, "Workout Program", accent),
          _divider(),

          // BODY METRICS
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Height", style: GoogleFonts.poppins(color: sub)),
                Text(
                  "175 cm",
                  style: GoogleFonts.poppins(
                    color: text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Weight", style: GoogleFonts.poppins(color: sub)),
                Text(
                  "74 kg",
                  style: GoogleFonts.poppins(
                    color: text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Body Fat", style: GoogleFonts.poppins(color: sub)),
                Text(
                  "18%",
                  style: GoogleFonts.poppins(
                    color: text,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionTile(IconData icon, String label, Color accent) {
    return ListTile(
      leading: Icon(icon, color: accent),
      title: Text(
        label,
        style: GoogleFonts.poppins(fontWeight: FontWeight.w600),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {},
    );
  }

  Widget _divider() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: const Divider(height: 1, thickness: .5),
  );

  // ---------------------------------------------------------------------------
  Widget _progressCard(Color card, Color accent, Color text, Color sub) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        children: [
          _progressRow("Workouts Completed", "42", accent, text),
          _progressRow("Diet Compliance", "86%", accent, text),
          _progressRow("Weekly Consistency", "5/7 days", accent, text),
        ],
      ),
    );
  }

  Widget _progressRow(String label, String value, Color accent, Color text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.poppins(color: text)),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: accent,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  Widget _trainerCard(Color card, Color accent, Color text, Color sub) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: accent,
            child: const Text("P", style: TextStyle(color: Colors.white)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Prasad",
                  style: GoogleFonts.poppins(
                    color: text,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  "Certified Strength Coach",
                  style: GoogleFonts.poppins(color: sub, fontSize: 12),
                ),
              ],
            ),
          ),
          Icon(LucideIcons.messageCircle, color: accent),
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
}
