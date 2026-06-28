// Smoke test: the brand wordmark renders without error.
//
// The default Flutter counter template test was removed — this app has no
// counter, and pumping `MyApp` needs Firebase + GetX setup. This pumps a
// dependency-free brand widget instead, giving the suite a real, green
// widget smoke test.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/widgets/brand.dart';

void main() {
  testWidgets('AlphaSerenaWordmark renders without error',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Center(child: AlphaSerenaWordmark())),
      ),
    );

    expect(find.byType(AlphaSerenaWordmark), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
