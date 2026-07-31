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
    // Custom InkWell surface — declare the button role + label explicitly so
    // TalkBack/VoiceOver announce it like any stock Material button.
    return Semantics(
      button: true,
      enabled: !isLoading && onPressed != null,
      label: label,
      child: SizedBox(
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
                        // Flexible + scale-down so a long label at a large
                        // accessibility text scale shrinks to fit instead of
                        // overflowing the button (visible red-stripe error on
                        // narrow phones at 1.6×; caught by the hero's
                        // text-scale widget test).
                        Flexible(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: showChevron ? 34 : 12,
                            ),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                label,
                                style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: fontSize,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (showChevron)
                      const Positioned(
                        right: 18,
                        child: Icon(
                          Icons.chevron_right_rounded,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
