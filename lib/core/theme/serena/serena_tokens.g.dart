// GENERATED FILE — DO NOT EDIT BY HAND.
// Source of truth: serena.tokens.json (Serena Design System, Option B / RFC-DISTRIBUTION).
// Regenerate: dart run tools/generate_tokens.dart. Drift-guard CI asserts byte-parity.
// Flutter-free raw token layer; the theme-integration binding (SerenaPalette ThemeExtension)
// consumes these. Brand: black-&-red (RFC-BRAND); orange = secondary semantic only.

// ignore_for_file: constant_identifier_names

// SDS version: 1.0.0 · fontsDeferred: true

/// Raw ARGB color tokens (0xAARRGGBB). Light/Dark suffix.
class SerenaColor {
  const SerenaColor._();
  static const int accentLight = 0xFFD50000;
  static const int accentDark = 0xFFD50000;
  static const int accentSoftLight = 0xFFFF1744;
  static const int accentSoftDark = 0xFFFF1744;
  static const int accentDeepLight = 0xFF7A0000;
  static const int accentDeepDark = 0xFF7A0000;
  static const int accentTextLight = 0xFFD50000;
  static const int accentTextDark = 0xFFFF8A8A;
  static const int inkLight = 0xFF000000;
  static const int inkDark = 0xFF000000;
  static const int paperLight = 0xFFFFFFFF;
  static const int paperDark = 0xFFFFFFFF;
  static const int successFillLight = 0xFF00C853;
  static const int successFillDark = 0xFF00E676;
  static const int successOn = 0xFF000000;
  static const int successSubtleBgLight = 0x1400C853;
  static const int successSubtleBgDark = 0x2600E676;
  static const int warningFillLight = 0xFFF5A623;
  static const int warningFillDark = 0xFFFFB74D;
  static const int warningOn = 0xFF000000;
  static const int warningSubtleBgLight = 0x14F5A623;
  static const int warningSubtleBgDark = 0x26FFB74D;
  static const int errorFillLight = 0xFFE5484D;
  static const int errorFillDark = 0xFFF2555A;
  static const int errorOn = 0xFFFFFFFF;
  static const int errorSubtleBgLight = 0x14E5484D;
  static const int errorSubtleBgDark = 0x26F2555A;
  static const int infoFillLight = 0xFF3B82F6;
  static const int infoFillDark = 0xFF5C9EE5;
  static const int infoOn = 0xFF000000;
  static const int infoSubtleBgLight = 0x143B82F6;
  static const int infoSubtleBgDark = 0x265C9EE5;
  static const int statusActiveLight = 0xFF1D9E75;
  static const int statusActiveDark = 0xFF1D9E75;
  static const int statusPendingLight = 0xFFF5A623;
  static const int statusPendingDark = 0xFFF5A623;
  static const int statusWarningLight = 0xFFE0A100;
  static const int statusWarningDark = 0xFFE0A100;
  static const int statusBlockedLight = 0xFFE5484D;
  static const int statusBlockedDark = 0xFFE5484D;
  static const int macroAmberLight = 0xFFFB8C00;
  static const int macroAmberDark = 0xFFFB8C00;
  static const int accentGoldLight = 0xFFFFCA28;
  static const int accentGoldDark = 0xFFFFCA28;
  static const int nutritionGreenLight = 0xFF43A047;
  static const int nutritionGreenDark = 0xFF43A047;
  static const int macroBlueLight = 0xFF3B82F6;
  static const int macroBlueDark = 0xFF3B82F6;
  static const int accentPurpleLight = 0xFF6C5CE7;
  static const int accentPurpleDark = 0xFF6C5CE7;
  static const int backgroundLight = 0xFFFFFFFF;
  static const int backgroundDark = 0xFF000000;
  static const int backgroundAltLight = 0xFFF5F5F5;
  static const int backgroundAltDark = 0xFF121212;
  static const int surfaceLight = 0xFFFFFFFF;
  static const int surfaceDark = 0xFF1A1A1A;
  static const int surfaceAltLight = 0xFFEEEEEE;
  static const int surfaceAltDark = 0xFF212121;
  static const int inputFillLight = 0xFFF5F5F5;
  static const int inputFillDark = 0xFF212121;
  static const int borderLight = 0xFFE0E0E0;
  static const int borderDark = 0xFF616161;
  static const int dividerLight = 0xFFECECEC;
  static const int dividerDark = 0xFF2A2A2A;
  static const int textPrimaryLight = 0xFF000000;
  static const int textPrimaryDark = 0xFFFFFFFF;
  static const int textSecondaryLight = 0xFF616161;
  static const int textSecondaryDark = 0xB3FFFFFF;
  static const int textMutedLight = 0xFF757575;
  static const int textMutedDark = 0xFFBDBDBD;
  static const int glassTintLight = 0xCCFFFFFF;
  static const int glassTintDark = 0x14FFFFFF;
  static const int glassBorderLight = 0x33FFFFFF;
  static const int glassBorderDark = 0x26FFFFFF;
  static const int glassHighlightLight = 0xE6FFFFFF;
  static const int glassHighlightDark = 0x40FFFFFF;
  static const int consoleBgLight = 0xFFF4F6F8;
  static const int consoleBgDark = 0xFF0A0A0A;
}

/// Type token: font family name + metrics (no Flutter dep).
class SerenaTextToken {
  final String font; final double size; final int weight;
  final double tracking; final double height; final bool tabular;
  const SerenaTextToken(this.font, this.size, this.weight, this.tracking, this.height, {this.tabular = false});
}
class SerenaText {
  const SerenaText._();
  static const SerenaTextToken display = SerenaTextToken('SpaceGrotesk', 32.0, 700, -0.5, 1.05);
  static const SerenaTextToken title = SerenaTextToken('SpaceGrotesk', 20.0, 600, -0.2, 1.15);
  static const SerenaTextToken cardTitle = SerenaTextToken('Inter', 16.0, 600, -0.1, 1.25);
  static const SerenaTextToken label = SerenaTextToken('Inter', 15.0, 600, 0.1, 1.2);
  static const SerenaTextToken body = SerenaTextToken('Inter', 14.0, 400, 0.0, 1.45);
  static const SerenaTextToken bodyStrong = SerenaTextToken('Inter', 14.0, 600, 0.0, 1.45);
  static const SerenaTextToken feature = SerenaTextToken('Inter', 15.0, 500, -0.1, 1.3);
  static const SerenaTextToken caption = SerenaTextToken('Inter', 12.0, 500, 0.1, 1.3);
  static const SerenaTextToken mono = SerenaTextToken('Inter', 13.0, 500, 0.0, 1.3, tabular: true);
  static const SerenaTextToken wordmark = SerenaTextToken('SpaceGrotesk', 34.0, 700, -0.5, 1.0);
}

class SerenaSpace {
  const SerenaSpace._();
  static const double xs = 4.0;
  static const double sm = 8.0;
  static const double md = 12.0;
  static const double lg = 16.0;
  static const double xl = 24.0;
  static const double xxl = 32.0;
  static const double xxxl = 48.0;
}

class SerenaRadius {
  const SerenaRadius._();
  static const double sm = 14.0;
  static const double md = 16.0;
  static const double card = 18.0;
  static const double nav = 20.0;
  static const double lg = 22.0;
}

class SerenaIcon {
  const SerenaIcon._();
  static const double sm = 16.0;
  static const double md = 20.0;
  static const double lg = 24.0;
  static const double xl = 32.0;
}

/// Density token: vertical rhythm (references SerenaSpace).
class SerenaDensityToken { final double rowInset; final double gap; const SerenaDensityToken(this.rowInset, this.gap); }
class SerenaDensity {
  const SerenaDensity._();
  static const SerenaDensityToken compact = SerenaDensityToken(SerenaSpace.sm, SerenaSpace.md);
  static const SerenaDensityToken comfortable = SerenaDensityToken(SerenaSpace.md, SerenaSpace.lg);
}

/// Shadow layer descriptor (Flutter-free).
class SerenaShadowLayer {
  final int colorLight; final int colorDark; final double blur; final double spread; final double dx; final double dy;
  const SerenaShadowLayer(this.colorLight, this.colorDark, this.blur, this.spread, this.dx, this.dy);
}
class SerenaElevation {
  const SerenaElevation._();
  static const List<SerenaShadowLayer> card = [SerenaShadowLayer(0x14000000, 0x59000000, 12.0, 0.0, 0.0, 6.0)];
  static const List<SerenaShadowLayer> softCard = [SerenaShadowLayer(0x0F000000, 0x73000000, 6.0, 0.0, 0.0, 2.0), SerenaShadowLayer(0x12000000, 0x4D000000, 20.0, 0.0, 0.0, 10.0)];
  static const List<SerenaShadowLayer> consoleCard = [SerenaShadowLayer(0x0F000000, 0x66000000, 10.0, 0.0, 0.0, 4.0)];
}

/// Motion token: duration (ms) + easing name.
class SerenaMotionToken { final int ms; final String easing; const SerenaMotionToken(this.ms, this.easing); }
class SerenaMotion {
  const SerenaMotion._();
  static const SerenaMotionToken instant = SerenaMotionToken(110, 'easeOut');
  static const SerenaMotionToken quick = SerenaMotionToken(200, 'easeInOut');
  static const SerenaMotionToken standard = SerenaMotionToken(300, 'easeInOutCubic');
  static const SerenaMotionToken entrance = SerenaMotionToken(420, 'easeOutCubic');
  static const SerenaMotionToken deliberate = SerenaMotionToken(560, 'easeInOut');
  static const SerenaMotionToken skeleton = SerenaMotionToken(1000, 'ease');
}

class SerenaBorder {
  const SerenaBorder._();
  static const int focusRingColor = 0xFFD50000;
  static const double focusRingWidth = 2.0;
  static const double focusRingOffset = 2.0;
  static const int neonEdgeColor = 0xFFD50000;
  static const double neonEdgeWidth = 1.0;
}
