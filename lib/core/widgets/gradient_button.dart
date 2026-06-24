import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The app's signature red CTA — glossy red gradient with a soft red glow.
/// Label stays optically centered; an optional trailing chevron sits at the
/// far right (as in the "Send OTP" / "Verify & Continue" mockups).
class GradientButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final bool showChevron;
  final IconData? leadingIcon;
  final double height;
  final double fontSize;
  final double radius;

  const GradientButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.showChevron = false,
    this.leadingIcon,
    this.height = 56,
    this.fontSize = 16,
    this.radius = 14,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: isLoading ? null : onPressed,
          child: Ink(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(radius),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFEC1C1C), Color(0xFFC20000)],
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFE10600).withValues(alpha: 0.45),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (isLoading)
                  const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    ),
                  )
                else ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (leadingIcon != null) ...[
                        Icon(leadingIcon, color: Colors.white, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: fontSize,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                  if (showChevron)
                    const Positioned(
                      right: 18,
                      child: Icon(Icons.chevron_right_rounded,
                          color: Colors.white, size: 26),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
