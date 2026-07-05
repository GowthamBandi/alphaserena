// Serena Design System — member-experience UI kit (M3).
//
// Additive, accessibility-first primitives that CONSUME the SDS tokens
// (`SerenaPalette`). Nothing here changes business logic, Firebase integration,
// or the capability architecture — these are presentation components the member
// screens opt into so status reads the same everywhere (active=green,
// pending/warning=amber, blocked=red) and controls meet contrast / screen-reader
// needs.
//
// `SerenaPalette` is registered in ThemeData.extensions (see app_theme.dart),
// so `context.serena` always resolves. Mirrors the coach app's M2 kit so the two
// apps share one presentation vocabulary (Phase-2 consistency goal).

import 'package:flutter/material.dart';

import '../../theme/serena/serena_palette.dart';

/// SDS accessor: `context.serena.statusActive`, `context.serena.accent`, …
/// Falls back to the dark palette if the extension is (impossibly) absent, so
/// this never throws during hot-reload or in a bare test harness. AlphaSerena is
/// dark-first, hence the dark fallback.
extension SerenaX on BuildContext {
  SerenaPalette get serena =>
      Theme.of(this).extension<SerenaPalette>() ?? SerenaPalette.dark();
}

/// Semantic status kinds. Each maps to one SDS status/semantic token.
enum SerenaStatus { active, pending, warning, blocked, info, neutral }

/// Resolve a [SerenaStatus] to its SDS color for the current theme.
Color serenaStatusColor(BuildContext context, SerenaStatus s) {
  final p = context.serena;
  switch (s) {
    case SerenaStatus.active:
      return p.statusActive;
    case SerenaStatus.pending:
      return p.statusPending;
    case SerenaStatus.warning:
      return p.statusWarning;
    case SerenaStatus.blocked:
      return p.statusBlocked;
    case SerenaStatus.info:
      return p.info;
    case SerenaStatus.neutral:
      return p.textMuted;
  }
}

/// A compact, accessible status pill. The status HUE is carried by a color-coded
/// marker (a dot, or an optional icon) plus a tinted fill + hairline border,
/// while the LABEL renders in the high-contrast primary text color — so the pill
/// stays legible for every status on both themes (some SDS status hues, e.g.
/// amber, are intentionally too light for small colored text). Exposed to screen
/// readers as one labeled status.
class SerenaStatusPill extends StatelessWidget {
  final String label;
  final SerenaStatus status;
  final IconData? icon;

  const SerenaStatusPill({
    super.key,
    required this.label,
    this.status = SerenaStatus.neutral,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final color = serenaStatusColor(context, status);
    return Semantics(
      label: 'Status: $label',
      container: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.13),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null)
              Icon(icon, size: 13, color: color)
            else
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: context.serena.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 11.5,
                letterSpacing: 0.1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
