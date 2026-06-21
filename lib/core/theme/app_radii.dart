import 'package:flutter/widgets.dart';

/// Corner-radius tokens.
class AppRadii {
  AppRadii._();

  static const double sm = 14;
  static const double md = 16;
  static const double card = 18;
  static const double nav = 20;
  static const double lg = 22;

  static const BorderRadius smR = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius mdR = BorderRadius.all(Radius.circular(md));
  static const BorderRadius cardR = BorderRadius.all(Radius.circular(card));
  static const BorderRadius navR = BorderRadius.all(Radius.circular(nav));
  static const BorderRadius lgR = BorderRadius.all(Radius.circular(lg));
}
