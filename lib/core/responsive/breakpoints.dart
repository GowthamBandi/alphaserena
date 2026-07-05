// Serena responsive breakpoints (Phase 2B.1 — Responsive Experience Foundation).
//
// Canonical across the TrainerHQ ecosystem (mirrored per-repo, Option-B). Layout
// only — no design tokens, no business logic. Navigation and layout adapt across
// these bands; capabilities and workflow are identical at every width.
//
//   compact   < 600      phone portrait          → bottom navigation
//   medium    600–1023   tablet / phone-landscape → navigation rail (collapsed)
//   expanded  >= 1024     desktop / web           → navigation rail (extended)
//
// Wide content is capped at [maxContent] and centered so it never stretches on
// large/ultrawide displays.

import 'package:flutter/widgets.dart';

class Breakpoints {
  Breakpoints._();

  static const double medium = 600;
  static const double expanded = 1024;
  static const double maxContent = 900;

  static double widthOf(BuildContext c) => MediaQuery.sizeOf(c).width;

  static bool isCompact(BuildContext c) => widthOf(c) < medium;
  static bool isMedium(BuildContext c) =>
      widthOf(c) >= medium && widthOf(c) < expanded;
  static bool isExpanded(BuildContext c) => widthOf(c) >= expanded;

  /// True at [medium] and above — i.e. a navigation rail replaces the bottom bar.
  static bool isWide(BuildContext c) => widthOf(c) >= medium;
}
