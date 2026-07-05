// Serena Design System — theme-integration FOUNDATION (M1).
// The Flutter binding that consumes the generated raw token layer (serena_tokens.g.dart)
// and exposes it as a ThemeExtension + text/shadow helpers.
//
// M1 = FOUNDATION ONLY: this is registered ADDITIVELY alongside each repo's existing
// AppPalette (see theme-integration-foundation.md) — NO screen consumes it yet, NO font
// swap ships in M1. Fonts are deferred: SerenaText uses the SoR fontFamily names as
// literals (no google_fonts dependency), so this binding compiles with only the Flutter SDK.
//
// This file is drop-in-ready per repo (into lib/core/theme/serena/). It is hand-authored
// (stable), not generated; only serena_tokens.g.dart is generated + drift-guarded.

import 'package:flutter/material.dart';
import 'serena_tokens.g.dart';

/// SDS surface/role palette, resolved per theme. Read via `Theme.of(context).extension<SerenaPalette>()`.
@immutable
class SerenaPalette extends ThemeExtension<SerenaPalette> {
  final Brightness brightness;
  final Color background, backgroundAlt, surface, surfaceAlt, inputFill;
  final Color border, divider, textPrimary, textSecondary, textMuted;
  final Color glassTint, glassBorder, glassHighlight, consoleBg;
  final Color accent, accentSoft, accentDeep, accentText;
  final Color success, warning, error, info;
  final Color statusActive, statusPending, statusWarning, statusBlocked;

  const SerenaPalette({
    required this.brightness,
    required this.background, required this.backgroundAlt, required this.surface,
    required this.surfaceAlt, required this.inputFill, required this.border,
    required this.divider, required this.textPrimary, required this.textSecondary,
    required this.textMuted, required this.glassTint, required this.glassBorder,
    required this.glassHighlight, required this.consoleBg, required this.accent,
    required this.accentSoft, required this.accentDeep, required this.accentText,
    required this.success, required this.warning, required this.error, required this.info,
    required this.statusActive, required this.statusPending, required this.statusWarning,
    required this.statusBlocked,
  });

  factory SerenaPalette.light() => const SerenaPalette(
        brightness: Brightness.light,
        background: Color(SerenaColor.backgroundLight),
        backgroundAlt: Color(SerenaColor.backgroundAltLight),
        surface: Color(SerenaColor.surfaceLight),
        surfaceAlt: Color(SerenaColor.surfaceAltLight),
        inputFill: Color(SerenaColor.inputFillLight),
        border: Color(SerenaColor.borderLight),
        divider: Color(SerenaColor.dividerLight),
        textPrimary: Color(SerenaColor.textPrimaryLight),
        textSecondary: Color(SerenaColor.textSecondaryLight),
        textMuted: Color(SerenaColor.textMutedLight),
        glassTint: Color(SerenaColor.glassTintLight),
        glassBorder: Color(SerenaColor.glassBorderLight),
        glassHighlight: Color(SerenaColor.glassHighlightLight),
        consoleBg: Color(SerenaColor.consoleBgLight),
        accent: Color(SerenaColor.accentLight),
        accentSoft: Color(SerenaColor.accentSoftLight),
        accentDeep: Color(SerenaColor.accentDeepLight),
        accentText: Color(SerenaColor.accentTextLight),
        success: Color(SerenaColor.successFillLight),
        warning: Color(SerenaColor.warningFillLight),
        error: Color(SerenaColor.errorFillLight),
        info: Color(SerenaColor.infoFillLight),
        statusActive: Color(SerenaColor.statusActiveLight),
        statusPending: Color(SerenaColor.statusPendingLight),
        statusWarning: Color(SerenaColor.statusWarningLight),
        statusBlocked: Color(SerenaColor.statusBlockedLight),
      );

  factory SerenaPalette.dark() => const SerenaPalette(
        brightness: Brightness.dark,
        background: Color(SerenaColor.backgroundDark),
        backgroundAlt: Color(SerenaColor.backgroundAltDark),
        surface: Color(SerenaColor.surfaceDark),
        surfaceAlt: Color(SerenaColor.surfaceAltDark),
        inputFill: Color(SerenaColor.inputFillDark),
        border: Color(SerenaColor.borderDark),
        divider: Color(SerenaColor.dividerDark),
        textPrimary: Color(SerenaColor.textPrimaryDark),
        textSecondary: Color(SerenaColor.textSecondaryDark),
        textMuted: Color(SerenaColor.textMutedDark),
        glassTint: Color(SerenaColor.glassTintDark),
        glassBorder: Color(SerenaColor.glassBorderDark),
        glassHighlight: Color(SerenaColor.glassHighlightDark),
        consoleBg: Color(SerenaColor.consoleBgDark),
        accent: Color(SerenaColor.accentDark),
        accentSoft: Color(SerenaColor.accentSoftDark),
        accentDeep: Color(SerenaColor.accentDeepDark),
        accentText: Color(SerenaColor.accentTextDark),
        success: Color(SerenaColor.successFillDark),
        warning: Color(SerenaColor.warningFillDark),
        error: Color(SerenaColor.errorFillDark),
        info: Color(SerenaColor.infoFillDark),
        statusActive: Color(SerenaColor.statusActiveDark),
        statusPending: Color(SerenaColor.statusPendingDark),
        statusWarning: Color(SerenaColor.statusWarningDark),
        statusBlocked: Color(SerenaColor.statusBlockedDark),
      );

  @override
  SerenaPalette copyWith({Brightness? brightness}) => brightness == Brightness.dark
      ? SerenaPalette.dark()
      : SerenaPalette.light();

  @override
  SerenaPalette lerp(ThemeExtension<SerenaPalette>? other, double t) {
    if (other is! SerenaPalette) return this;
    return t < 0.5 ? this : other; // discrete theme switch (SDS themes don't tween)
  }
}

/// Brand gradient (red-depth). Solid-red `[accent, accent]` is equally on-brand (RFC-BRAND).
/// accent/accentDeep are theme-invariant (identical light/dark), so a single const list is correct.
const List<Color> serenaGradientBrand = [Color(SerenaColor.accentLight), Color(SerenaColor.accentDeepLight)];

/// Secondary semantic accents (theme-invariant single values; orange lives ONLY here per RFC-BRAND).
/// Exposed for data-viz/charts so consumers never reach for a raw hex.
class SerenaAccents {
  const SerenaAccents._();
  static const Color macroAmber = Color(SerenaColor.macroAmberLight);
  static const Color accentGold = Color(SerenaColor.accentGoldLight);
  static const Color nutritionGreen = Color(SerenaColor.nutritionGreenLight);
  static const Color macroBlue = Color(SerenaColor.macroBlueLight);
  static const Color accentPurple = Color(SerenaColor.accentPurpleLight);
}

/// SDS type scale → TextStyle. Fonts DEFERRED: fontFamily is the SoR name as a literal
/// (google_fonts wiring is a later migration step). Color is applied by the consuming widget.
class SerenaTextStyles {
  const SerenaTextStyles._();
  static TextStyle _of(SerenaTextToken t) => TextStyle(
        fontFamily: t.font,
        fontSize: t.size,
        fontWeight: FontWeight.values[(t.weight ~/ 100) - 1],
        letterSpacing: t.tracking,
        height: t.height,
        fontFeatures: t.tabular ? const [FontFeature.tabularFigures()] : null,
      );
  static TextStyle get display => _of(SerenaText.display);
  static TextStyle get title => _of(SerenaText.title);
  static TextStyle get cardTitle => _of(SerenaText.cardTitle);
  static TextStyle get label => _of(SerenaText.label);
  static TextStyle get body => _of(SerenaText.body);
  static TextStyle get bodyStrong => _of(SerenaText.bodyStrong);
  static TextStyle get feature => _of(SerenaText.feature);
  static TextStyle get caption => _of(SerenaText.caption);
  static TextStyle get mono => _of(SerenaText.mono);
  static TextStyle get wordmark => _of(SerenaText.wordmark);
}

/// Radii as BorderRadius helpers.
class SerenaRadii {
  const SerenaRadii._();
  static final BorderRadius sm = BorderRadius.circular(SerenaRadius.sm);
  static final BorderRadius md = BorderRadius.circular(SerenaRadius.md);
  static final BorderRadius card = BorderRadius.circular(SerenaRadius.card);
  static final BorderRadius nav = BorderRadius.circular(SerenaRadius.nav);
  static final BorderRadius lg = BorderRadius.circular(SerenaRadius.lg);
}

/// Elevation → BoxShadow lists (theme-aware).
class SerenaShadows {
  const SerenaShadows._();
  static List<BoxShadow> _layers(List<SerenaShadowLayer> ls, bool isDark) => ls
      .map((l) => BoxShadow(
            color: Color(isDark ? l.colorDark : l.colorLight),
            blurRadius: l.blur,
            spreadRadius: l.spread,
            offset: Offset(l.dx, l.dy),
          ))
      .toList();
  static List<BoxShadow> card(bool isDark) => _layers(SerenaElevation.card, isDark);
  static List<BoxShadow> softCard(bool isDark) => _layers(SerenaElevation.softCard, isDark);
  static List<BoxShadow> consoleCard(bool isDark) => _layers(SerenaElevation.consoleCard, isDark);
}

/// Motion → Duration + Curve.
class SerenaMotions {
  const SerenaMotions._();
  static Duration ms(SerenaMotionToken t) => Duration(milliseconds: t.ms);
  static Curve curve(SerenaMotionToken t) {
    switch (t.easing) {
      case 'easeOut': return Curves.easeOut;
      case 'easeOutCubic': return Curves.easeOutCubic;
      case 'easeInOutCubic': return Curves.easeInOutCubic;
      case 'ease': return Curves.ease;
      default: return Curves.easeInOut;
    }
  }
}
