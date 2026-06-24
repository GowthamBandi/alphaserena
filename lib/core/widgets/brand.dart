import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// AlphaSerena brand marks shared across the splash / auth / profile screens.
///
/// The signature is a bold faceted red "A" peak followed by the
/// "ALPHAS ARENA" wordmark (white + red).

/// The geometric red "A" mark — drawn (not an image) so it stays crisp at any
/// size. A darker maroon facet on the upper-left gives the folded-ribbon look.
class AlphaAMark extends StatelessWidget {
  final double size;
  const AlphaAMark({super.key, this.size = 56});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size * 0.92,
      height: size,
      child: CustomPaint(painter: _AMarkPainter()),
    );
  }
}

class _AMarkPainter extends CustomPainter {
  static const Color _red = Color(0xFFE10600);
  static const Color _redDark = Color(0xFF7A0C0C);

  @override
  void paint(Canvas canvas, Size s) {
    final w = s.width, h = s.height;
    Offset p(double x, double y) => Offset(x * w, y * h);

    // Two thick legs meeting at the apex (open at the bottom) → reads as "A".
    final aPath = Path()
      ..fillType = PathFillType.evenOdd
      ..moveTo(p(0.5, 0.0).dx, p(0.5, 0.0).dy)
      ..lineTo(p(0.0, 1.0).dx, p(0.0, 1.0).dy)
      ..lineTo(p(1.0, 1.0).dx, p(1.0, 1.0).dy)
      ..close()
      ..moveTo(p(0.5, 0.30).dx, p(0.5, 0.30).dy)
      ..lineTo(p(0.32, 1.0).dx, p(0.32, 1.0).dy)
      ..lineTo(p(0.68, 1.0).dx, p(0.68, 1.0).dy)
      ..close();

    canvas.drawPath(aPath, Paint()..color = _red);

    // Darker facet on the upper-left, clipped to the A silhouette.
    canvas.save();
    canvas.clipPath(aPath);
    final facet = Path()
      ..moveTo(p(0.5, 0.0).dx, p(0.5, 0.0).dy)
      ..lineTo(p(0.5, 0.34).dx, p(0.5, 0.34).dy)
      ..lineTo(p(0.20, 0.62).dx, p(0.20, 0.62).dy)
      ..close();
    canvas.drawPath(facet, Paint()..color = _redDark);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// "ALPHAS ARENA" — ALPHAS in white, ARENA in red. Heavy, letter-spaced.
class AlphasArenaWordmark extends StatelessWidget {
  final double fontSize;
  const AlphasArenaWordmark({super.key, this.fontSize = 26});

  @override
  Widget build(BuildContext context) {
    final style = GoogleFonts.poppins(
      fontSize: fontSize,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.5,
      height: 1,
    );
    return RichText(
      text: TextSpan(
        children: [
          TextSpan(text: 'ALPHAS ', style: style.copyWith(color: Colors.white)),
          TextSpan(
            text: 'ARENA',
            style: style.copyWith(color: const Color(0xFFE10600)),
          ),
        ],
      ),
    );
  }
}
