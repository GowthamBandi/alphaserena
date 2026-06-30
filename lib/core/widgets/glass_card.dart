import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A premium "glass" surface decoration used across cards. Gives light mode a
/// soft elevation + subtle gradient (so white cards lift off the background)
/// and dark mode a faint top-light gradient with depth for a frosted look.
///
/// Usage: `decoration: glassCard(context.palette, radius: 16)`.
BoxDecoration glassCard(AppPalette p, {double radius = 16}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: p.isDark
          ? const [Color(0xFF1D1D20), Color(0xFF151517)]
          : const [Colors.white, Color(0xFFF6F8FB)],
    ),
    border: Border.all(
      color: p.isDark
          ? Colors.white.withValues(alpha: 0.06)
          : const Color(0xFFEAEDF1),
    ),
    boxShadow: [
      BoxShadow(
        color: p.isDark
            ? Colors.black.withValues(alpha: 0.5)
            : const Color(0xFF8A94A6).withValues(alpha: 0.16),
        blurRadius: 22,
        spreadRadius: -6,
        offset: const Offset(0, 12),
      ),
    ],
  );
}

/// A lighter glass treatment for small/inner cards (e.g. stat tiles) — same
/// gradient + border but a softer shadow.
BoxDecoration glassCardSoft(AppPalette p, {double radius = 12}) {
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: p.isDark
          ? const [Color(0xFF1C1C1F), Color(0xFF161618)]
          : const [Colors.white, Color(0xFFF7F9FC)],
    ),
    border: Border.all(
      color: p.isDark
          ? Colors.white.withValues(alpha: 0.05)
          : const Color(0xFFEAEDF1),
    ),
    boxShadow: [
      BoxShadow(
        color: p.isDark
            ? Colors.black.withValues(alpha: 0.35)
            : const Color(0xFF8A94A6).withValues(alpha: 0.12),
        blurRadius: 14,
        spreadRadius: -6,
        offset: const Offset(0, 6),
      ),
    ],
  );
}
