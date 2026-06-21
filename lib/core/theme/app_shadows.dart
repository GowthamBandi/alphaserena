import 'package:flutter/material.dart';
import 'app_colors.dart';

/// Elevation / shadow tokens.
class AppShadows {
  AppShadows._();

  static List<BoxShadow> card(bool isDark) => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.08),
          blurRadius: 12,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get navGlow => [
        BoxShadow(
          color: BrandColors.accent.withValues(alpha: 0.25),
          blurRadius: 18,
          offset: const Offset(0, 8),
        ),
      ];
}
