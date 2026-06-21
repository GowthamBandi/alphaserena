import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_text.dart';

/// Gradient (red → orange) display title via ShaderMask.
class GradientTitle extends StatelessWidget {
  final String text;
  final double size;
  final TextAlign textAlign;
  final List<Color> colors;

  const GradientTitle(
    this.text, {
    super.key,
    this.size = 32,
    this.textAlign = TextAlign.center,
    this.colors = BrandColors.heroGradient,
  });

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      shaderCallback: (bounds) =>
          LinearGradient(colors: colors).createShader(bounds),
      child: Text(
        text,
        textAlign: textAlign,
        style: AppText.display(size: size).copyWith(color: Colors.white),
      ),
    );
  }
}
