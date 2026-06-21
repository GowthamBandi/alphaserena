import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Typography tokens (apply colors from `context.palette`).
/// Teko = display/titles · Poppins = body/buttons · Inter = dense rows.
class AppText {
  AppText._();

  static TextStyle display({double size = 32}) =>
      GoogleFonts.teko(fontSize: size, fontWeight: FontWeight.w900, letterSpacing: 2);

  static TextStyle title({double size = 20}) =>
      GoogleFonts.teko(fontSize: size, fontWeight: FontWeight.bold);

  static TextStyle cardTitle({double size = 16}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: FontWeight.bold);

  static TextStyle label({double size = 15}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: FontWeight.w600);

  static TextStyle body({double size = 14}) =>
      GoogleFonts.poppins(fontSize: size, fontWeight: FontWeight.w400);

  static TextStyle feature({double size = 15}) =>
      GoogleFonts.inter(fontSize: size, fontWeight: FontWeight.w400);

  static TextStyle wordmark({double size = 34}) => GoogleFonts.poppins(
      fontSize: size, fontWeight: FontWeight.w900, letterSpacing: 2);
}
