import 'package:flutter/widgets.dart';

/// App-wide route observer. Lets screens react to being covered/revealed by
/// navigation (e.g. pause a playing cover video when another screen is pushed).
/// Registered in [GetMaterialApp.navigatorObservers].
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
