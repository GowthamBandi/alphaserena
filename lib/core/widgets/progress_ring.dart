import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// A premium animated completion ring.
///
/// One arc, a sweep gradient, a soft bloom beneath it and whatever the caller
/// wants in the middle. It animates from wherever it was, so a value that
/// changes advances the arc rather than teleporting it.
///
/// ⏭️ `NutritionProgressCard` still carries its own private copy of this
/// painter. The two are visually identical by construction; migrate it here
/// the next time that card is opened, so there is one ring in the app.
class ProgressRing extends StatelessWidget {
  const ProgressRing({
    super.key,
    required this.value,
    required this.palette,
    required this.colors,
    this.diameter = 128,
    this.strokeFraction = 0.095,
    this.child,
    this.duration = const Duration(milliseconds: 700),
    this.semanticLabel,
  });

  /// 0..1. Values above 1 fill the ring rather than wrapping around it.
  final double value;

  final AppPalette palette;

  /// Start → end of the sweep.
  final List<Color> colors;

  final double diameter;
  final double strokeFraction;
  final Widget? child;
  final Duration duration;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final p = palette;
    final stroke = diameter * strokeFraction;
    final ring = SizedBox(
      width: diameter,
      height: diameter,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0.0, 1.0)),
        duration: duration,
        curve: Curves.easeOutCubic,
        builder: (context, t, inner) => CustomPaint(
          painter: _RingPainter(
            progress: t,
            stroke: stroke,
            track: p.isDark
                ? Colors.white.withValues(alpha: 0.07)
                : const Color(0xFFE8EBF0),
            colors: colors,
            // The bloom is a dark-mode effect: on a white card the same blur
            // reads as a smudge rather than as light.
            glow: p.isDark ? 6 : 2.5,
          ),
          child: inner,
        ),
        child: child == null
            ? null
            : Center(
                child: Padding(
                  padding: EdgeInsets.all(stroke + 6),
                  child: FittedBox(fit: BoxFit.scaleDown, child: child),
                ),
              ),
      ),
    );
    if (semanticLabel == null) return ring;
    return Semantics(
      label: semanticLabel,
      container: true,
      excludeSemantics: true,
      child: ring,
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({
    required this.progress,
    required this.stroke,
    required this.track,
    required this.colors,
    required this.glow,
  });

  final double progress;
  final double stroke;
  final Color track;
  final List<Color> colors;
  final double glow;

  @override
  void paint(Canvas canvas, Size size) {
    final centre = (Offset.zero & size).center;
    final radius = (math.min(size.width, size.height) - stroke) / 2;
    final arcRect = Rect.fromCircle(center: centre, radius: radius);

    canvas.drawCircle(
      centre,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = track,
    );

    if (progress <= 0) return;

    const start = -math.pi / 2;
    final sweep = 2 * math.pi * progress.clamp(0.0, 1.0);
    final shader = SweepGradient(
      startAngle: 0,
      endAngle: 2 * math.pi,
      colors: [...colors, colors.first],
      stops: const [0.0, 0.75, 1.0],
      transform: const GradientRotation(-math.pi / 2),
    ).createShader(arcRect);

    canvas.drawArc(
      arcRect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, glow),
    );
    canvas.drawArc(
      arcRect,
      start,
      sweep,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = shader,
    );
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.progress != progress ||
      old.stroke != stroke ||
      old.track != track ||
      old.glow != glow ||
      old.colors != colors;
}
