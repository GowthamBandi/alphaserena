import 'package:flutter/material.dart';

/// Raw brand colors — theme-independent. AlphaSerena's signature is the deep red
/// (`#D50000`) flowing into orange for "arena / warrior" gradients.
class BrandColors {
  BrandColors._();

  static const Color accent = Color(0xFFD50000);
  static const Color accentSoft = Color(0xFFFF5252);
  static const Color gradientOrange = Color(0xFFFB8C00);
  static const Color gradientDeep = Color(0xFFFF6E40);
  static const Color success = Color(0xFF00C853);
  static const Color error = Color(0xFFFF5252);
  static const Color amber = Color(0xFFFFCA28);

  static const List<Color> heroGradient = [accent, gradientOrange];
  static const List<Color> selectedGradient = [accent, gradientDeep];
}

/// Theme-aware semantic palette ([ThemeExtension]); read via `context.palette`.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color background;
  final Color backgroundGradientEnd;
  final Color surface;
  final Color surfaceAlt;
  final Color inputFill;
  final Color border;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color accent;
  final Color success;
  final Color error;
  final bool isDark;

  const AppPalette({
    required this.background,
    required this.backgroundGradientEnd,
    required this.surface,
    required this.surfaceAlt,
    required this.inputFill,
    required this.border,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.accent,
    required this.success,
    required this.error,
    required this.isDark,
  });

  static const AppPalette light = AppPalette(
    background: Color(0xFFFFFFFF),
    backgroundGradientEnd: Color(0xFFF5F5F5),
    surface: Color(0xFFFFFFFF),
    surfaceAlt: Color(0xFFF2F3F5),
    inputFill: Color(0xFFF5F5F5),
    border: Color(0xFFE0E0E0),
    textPrimary: Color(0xFF000000),
    textSecondary: Color(0xFF616161),
    textMuted: Color(0xFF757575),
    accent: BrandColors.accent,
    success: BrandColors.success,
    error: BrandColors.error,
    isDark: false,
  );

  static const AppPalette dark = AppPalette(
    background: Color(0xFF0E0E0E),
    backgroundGradientEnd: Color(0xFF1A1A1A),
    surface: Color(0xFF161616),
    surfaceAlt: Color(0xFF1F1F1F),
    inputFill: Color(0xFF1C1C1C),
    border: Color(0xFF2A2A2A),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xB3FFFFFF),
    textMuted: Color(0xFF9E9E9E),
    accent: BrandColors.accent,
    success: BrandColors.success,
    error: BrandColors.error,
    isDark: true,
  );

  @override
  AppPalette copyWith({
    Color? background,
    Color? backgroundGradientEnd,
    Color? surface,
    Color? surfaceAlt,
    Color? inputFill,
    Color? border,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? accent,
    Color? success,
    Color? error,
    bool? isDark,
  }) {
    return AppPalette(
      background: background ?? this.background,
      backgroundGradientEnd:
          backgroundGradientEnd ?? this.backgroundGradientEnd,
      surface: surface ?? this.surface,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      inputFill: inputFill ?? this.inputFill,
      border: border ?? this.border,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      accent: accent ?? this.accent,
      success: success ?? this.success,
      error: error ?? this.error,
      isDark: isDark ?? this.isDark,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      background: Color.lerp(background, other.background, t)!,
      backgroundGradientEnd:
          Color.lerp(backgroundGradientEnd, other.backgroundGradientEnd, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      inputFill: Color.lerp(inputFill, other.inputFill, t)!,
      border: Color.lerp(border, other.border, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
      success: Color.lerp(success, other.success, t)!,
      error: Color.lerp(error, other.error, t)!,
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension AppPaletteX on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.dark;
}
