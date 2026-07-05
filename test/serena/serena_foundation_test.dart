// SDS M1 foundation verification.
// (a) generated tokens + binding compile & bind to valid Flutter;
// (b) THE M0 CONTRAST EXIT GATE (AC-SDS-CONTRAST): real WCAG ratio over every semantic
//     {fill,on} pair, both themes, + error!=accentText + accent-on-console;
// (c) golden foundation (baseline via `flutter test --update-goldens`).
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/theme/serena/serena_palette.dart';
import 'package:alphaserena/core/theme/serena/serena_tokens.g.dart';

double _lin(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
double _lum(int argb) {
  final r = ((argb >> 16) & 0xFF) / 255.0, g = ((argb >> 8) & 0xFF) / 255.0, b = (argb & 0xFF) / 255.0;
  return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b);
}
double _contrast(int a, int b) {
  final la = _lum(a), lb = _lum(b);
  final hi = math.max(la, lb), lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('generated tokens carry the frozen SDS values', () {
    expect(SerenaColor.accentLight, 0xFFD50000);
    expect(SerenaColor.accentTextDark, 0xFFFF8A8A);
    expect(SerenaColor.errorFillDark, 0xFFF2555A);
    expect(SerenaRadius.card, 18.0);
    expect(SerenaMotion.instant.ms, 110);
    expect(SerenaDensity.compact.rowInset, SerenaSpace.sm); // density is reachable
  });

  test('M0 EXIT GATE — semantic on-fill contrast >= 3:1 (both themes) [AC-SDS-CONTRAST]', () {
    // name: [fillLight, fillDark, on]  — on-color must clear >=3:1 on BOTH fills.
    final semantic = <String, List<int>>{
      'success': [SerenaColor.successFillLight, SerenaColor.successFillDark, SerenaColor.successOn],
      'warning': [SerenaColor.warningFillLight, SerenaColor.warningFillDark, SerenaColor.warningOn],
      'error':   [SerenaColor.errorFillLight, SerenaColor.errorFillDark, SerenaColor.errorOn],
      'info':    [SerenaColor.infoFillLight, SerenaColor.infoFillDark, SerenaColor.infoOn],
    };
    semantic.forEach((name, v) {
      final cl = _contrast(v[0], v[2]), cd = _contrast(v[1], v[2]);
      expect(cl >= 3.0, isTrue, reason: '$name light on-fill = ${cl.toStringAsFixed(2)}:1 (<3:1)');
      expect(cd >= 3.0, isTrue, reason: '$name dark on-fill = ${cd.toStringAsFixed(2)}:1 (<3:1)');
    });
  });

  test('M0 EXIT GATE — accent/accentText/error separation & console legibility', () {
    // error stays distinct from accentText on dark (de-collision).
    expect(SerenaColor.errorFillDark != SerenaColor.accentTextDark, isTrue);
    // accent as text PASSES AA on the light console; the earlier draft claimed the opposite.
    expect(_contrast(SerenaColor.accentLight, SerenaColor.consoleBgLight) >= 4.5, isTrue);
    // accent as text FAILS on a dark surface -> must use accentText (which passes).
    expect(_contrast(SerenaColor.accentDark, SerenaColor.surfaceDark) < 4.5, isTrue);
    expect(_contrast(SerenaColor.accentTextDark, SerenaColor.surfaceDark) >= 4.5, isTrue);
  });

  test('palette binds light & dark (black canvas dark / white light)', () {
    expect(SerenaPalette.light().background, const Color(0xFFFFFFFF));
    expect(SerenaPalette.dark().background, const Color(0xFF000000));
    expect(SerenaAccents.macroAmber, const Color(0xFFFB8C00)); // secondary accents exposed
  });

  testWidgets('SDS swatch golden (light)', (tester) async {
    final p = SerenaPalette.light();
    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: p.background,
        body: Center(
          child: Container(
            width: 160,
            padding: const EdgeInsets.all(SerenaSpace.lg),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: SerenaRadii.card,
              boxShadow: SerenaShadows.card(false),
              border: Border.all(color: p.border),
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(height: 36, decoration: BoxDecoration(color: p.accent, borderRadius: SerenaRadii.sm)),
              const SizedBox(height: SerenaSpace.md),
              Text('SERENA', style: SerenaTextStyles.title.copyWith(color: p.textPrimary)),
            ]),
          ),
        ),
      ),
    ));
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/sds_swatch_light.png'));
  });
}
