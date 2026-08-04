import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/plans/plan_segmented_control.dart';

/// THE SLIDER MUST SIT INSIDE ITS TRACK, ON BOTH SIDES.
///
/// The control is a `Container(padding: EdgeInsets.all(5), border: 1px)`
/// wrapping a `Stack`, so the Stack's coordinate space is inset **6px** from the
/// control's outer rect on every side. The slider's geometry was computed from
/// the OUTER width instead (`half = maxWidth / 2`, `left: 0 | half`,
/// `width: half - 5`).
///
/// MEASURED, before the fix, at a 354dp width:
///
///   workout pill:  left inset  = 6.0   ✓ (correct by luck)
///   diet pill:     right inset = **-1.0**  ✗ — one pixel PAST the outer edge
///
/// So on the Diet tab the 6px frame that surrounds the pill everywhere else
/// vanishes and the pill paints over, and beyond, the track's own border.
/// Asymmetric by construction: flawless on the first tab, wrong on the second.
///
/// Asymmetric by construction: it looks correct until the member touches the
/// second tab, which is exactly the kind of flaw that ships.
///
/// These tests measure the rendered rectangles rather than asserting on the
/// arithmetic, so they stay true through any future re-implementation.
Future<Rect> _sliderRect(
  WidgetTester tester,
  PlanTab value, {
  double width = 354, // 390dp page minus the screen's 18dp side padding
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: width,
            child: PlanSegmentedControl(value: value, onChanged: (_) {}),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  // The slider is the only AnimatedContainer in the control.
  final finder = find.descendant(
    of: find.byType(PlanSegmentedControl),
    matching: find.byType(AnimatedContainer),
  );
  expect(finder, findsOneWidget);
  return tester.getRect(finder);
}

Rect _trackRect(WidgetTester tester) => tester.getRect(
      find
          .descendant(
            of: find.byType(PlanSegmentedControl),
            matching: find.byType(Container),
          )
          .first,
    );

void main() {
  // 5px of Container padding PLUS the 1px border the decoration draws — the
  // real distance from the control's outer rect to the slider's box.
  const pad = 6.0;

  group('the pill is inset by exactly the track padding, on every edge', () {
    testWidgets('workout (left half)', (tester) async {
      final slider = await _sliderRect(tester, PlanTab.workout);
      final track = _trackRect(tester);

      expect(slider.left - track.left, closeTo(pad, 0.01));
      expect(slider.top - track.top, closeTo(pad, 0.01));
      expect(track.bottom - slider.bottom, closeTo(pad, 0.01));
      // The right edge stops at the track's midpoint — it must not spill into
      // the other half.
      expect(slider.right, lessThanOrEqualTo(track.center.dx + 0.01));
    });

    testWidgets('diet (right half) — the half that was broken', (tester) async {
      final slider = await _sliderRect(tester, PlanTab.diet);
      final track = _trackRect(tester);

      expect(
        track.right - slider.right,
        closeTo(pad, 0.01),
        reason: 'the pill must keep the same 5px inset it has on the left',
      );
      expect(slider.top - track.top, closeTo(pad, 0.01));
      expect(track.bottom - slider.bottom, closeTo(pad, 0.01));
      expect(slider.left, greaterThanOrEqualTo(track.center.dx - 0.01));
    });
  });

  testWidgets('both halves are the SAME size — a segmented control is symmetric',
      (tester) async {
    final workout = await _sliderRect(tester, PlanTab.workout);
    final diet = await _sliderRect(tester, PlanTab.diet);
    expect(diet.width, closeTo(workout.width, 0.01));
    expect(diet.height, closeTo(workout.height, 0.01));
  });

  testWidgets('the two positions mirror each other about the centre',
      (tester) async {
    final workout = await _sliderRect(tester, PlanTab.workout);
    final diet = await _sliderRect(tester, PlanTab.diet);
    final track = _trackRect(tester);
    // Distance from the track's left edge to the workout pill must equal the
    // distance from the track's right edge to the diet pill.
    expect(
      workout.left - track.left,
      closeTo(track.right - diet.right, 0.01),
    );
  });

  group('geometry holds at every width the app actually renders', () {
    for (final w in <double>[284, 354, 604, 988]) {
      // 320dp phone, 390dp phone, tablet column, expanded tablet
      testWidgets('width $w', (tester) async {
        final diet = await _sliderRect(tester, PlanTab.diet, width: w);
        final track = _trackRect(tester);
        expect(track.right - diet.right, closeTo(pad, 0.01));
        expect(diet.left - track.center.dx, closeTo(0, 0.01));
      });
    }
  });

  testWidgets('the pill never paints outside its track', (tester) async {
    for (final tab in PlanTab.values) {
      final slider = await _sliderRect(tester, tab);
      final track = _trackRect(tester);
      expect(track.contains(slider.topLeft), isTrue, reason: '$tab topLeft');
      expect(
        slider.right,
        lessThanOrEqualTo(track.right + 0.01),
        reason: '$tab right edge',
      );
    }
  });
}
