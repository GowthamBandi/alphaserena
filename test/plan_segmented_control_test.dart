import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/plans/plan_hero_card.dart';
import 'package:alphaserena/screens/dashboard/plans/plan_segmented_control.dart';

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  Size size = const Size(390, 900),
  double textScale = 1.0,
  ThemeData? theme,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('the segmented control is exactly two tabs, and says which is live',
      () {
    testWidgets('both tabs are present and labelled', (tester) async {
      await _pump(
        tester,
        PlanSegmentedControl(value: PlanTab.workout, onChanged: (_) {}),
      );
      expect(find.text('Workout'), findsOneWidget);
      expect(find.text('Diet'), findsOneWidget);
    });

    testWidgets('a label is NEVER truncated — at any text size, on any phone',
        (tester) async {
      // "Workout Plans" ellipsized to "Workou…" at 2.0x on a 320dp phone: a
      // control painting a truncated version of its own name, and the member
      // who most needs to read it being the one who cannot. One word per half
      // was not enough on its own — measured, "Workout" wants 196px at 2.0x
      // and each half offers 127 — so the label scales down instead of being
      // cut. This asserts the OUTCOME (whole word) rather than the mechanism.
      for (final size in [const Size(320, 900), const Size(390, 900)]) {
        for (final scale in [1.0, 1.3, 2.0]) {
          await _pump(
            tester,
            PlanSegmentedControl(value: PlanTab.workout, onChanged: (_) {}),
            textScale: scale,
            size: size,
          );
          for (final label in ['Workout', 'Diet']) {
            final para = tester.renderObject<RenderParagraph>(find.text(label));
            expect(
              para.didExceedMaxLines,
              isFalse,
              reason: '"$label" was truncated at ${scale}x on ${size.width}dp',
            );
          }
        }
      }
    });

    testWidgets('the selected tab is announced as selected, the other is not',
        (tester) async {
      await _pump(
        tester,
        PlanSegmentedControl(value: PlanTab.diet, onChanged: (_) {}),
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Diet')),
        matchesSemantics(
          label: 'Diet',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      // Only ONE tab may announce itself as selected.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Workout')),
        matchesSemantics(
          label: 'Workout',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
          isInMutuallyExclusiveGroup: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('tapping the unselected half reports the new tab',
        (tester) async {
      PlanTab? got;
      await _pump(
        tester,
        PlanSegmentedControl(value: PlanTab.workout, onChanged: (t) => got = t),
      );
      await tester.tap(find.text('Diet'));
      await tester.pumpAndSettle();
      expect(got, PlanTab.diet);
    });

    testWidgets('tapping the ALREADY selected half fires nothing',
        (tester) async {
      // Re-emitting the current tab would rebuild the whole body and restart
      // the slider animation for no reason.
      var calls = 0;
      await _pump(
        tester,
        PlanSegmentedControl(value: PlanTab.workout, onChanged: (_) => calls++),
      );
      await tester.tap(find.text('Workout'));
      await tester.pumpAndSettle();
      expect(calls, 0);
    });

    testWidgets('each half is a large tap target, not a text-sized one',
        (tester) async {
      await _pump(
        tester,
        PlanSegmentedControl(value: PlanTab.workout, onChanged: (_) {}),
      );
      final control = tester.getSize(find.byType(PlanSegmentedControl));
      expect(control.height, PlanSegmentedControl.baseHeight);
      // The InkWell for each half spans (roughly) half the control.
      final inkWells = find.descendant(
        of: find.byType(PlanSegmentedControl),
        matching: find.byType(InkWell),
      );
      expect(inkWells, findsNWidgets(2));
      for (final w in tester.widgetList<InkWell>(inkWells)) {
        expect(w, isNotNull);
      }
    });

    testWidgets('the two tabs carry DIFFERENT accents', (tester) async {
      // Workout red / diet green is the colour language Home already uses; a
      // single shared accent would make the control decorative rather than
      // informative.
      expect(
        PlanSegmentedControl.fillFor(PlanTab.workout),
        isNot(PlanSegmentedControl.fillFor(PlanTab.diet)),
      );
    });

    testWidgets('survives 2.0x text without overflowing', (tester) async {
      await _pump(
        tester,
        PlanSegmentedControl(value: PlanTab.workout, onChanged: (_) {}),
        textScale: 2.0,
        size: const Size(320, 900),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('the track GROWS with the OS text scale, and stops growing',
        (tester) async {
      // A fixed height clipped its own label at accessibility sizes; an
      // unclamped one would eat a third of a 320dp screen.
      await _pump(
        tester,
        PlanSegmentedControl(value: PlanTab.workout, onChanged: (_) {}),
        textScale: 2.0,
        size: const Size(320, 900),
      );
      final tall = tester.getSize(find.byType(PlanSegmentedControl)).height;
      expect(tall, greaterThan(PlanSegmentedControl.baseHeight));
      expect(tall, PlanSegmentedControl.baseHeight * 1.35);
    });

    testWidgets('renders in light theme', (tester) async {
      await _pump(
        tester,
        PlanSegmentedControl(value: PlanTab.diet, onChanged: (_) {}),
        theme: AppTheme.light,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('the hero card never renders a fact it was not given', () {
    PlanHeroCard card({
      List<PlanFact> facts = const [],
      String? todayLine,
      bool completedToday = false,
      VoidCallback? onCta,
    }) =>
        PlanHeroCard(
          tab: PlanTab.workout,
          planName: 'Workout Plan 11',
          coachName: 'Coach Ada',
          orgName: 'Iron Temple',
          todayLine: todayLine,
          facts: facts,
          ctaLabel: completedToday ? 'Completed Today' : 'Start Workout',
          ctaIcon: Icons.play_arrow_rounded,
          onCta: onCta,
          completedToday: completedToday,
        );

    testWidgets('with no facts, no fact chips are drawn at all',
        (tester) async {
      // The old screen printed "Duration: Ongoing" — a hardcoded string, not a
      // backend value. An absent fact must produce NOTHING, never a filler row.
      await _pump(tester, card());
      expect(find.text('Duration'), findsNothing);
      expect(find.text('Ongoing'), findsNothing);
      expect(find.textContaining('Not set'), findsNothing);
    });

    testWidgets('only the facts supplied are rendered', (tester) async {
      await _pump(
        tester,
        card(facts: [
          (icon: Icons.repeat_rounded, label: 'Sets', value: '12'),
        ]),
      );
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Difficulty'), findsNothing);
    });

    testWidgets('plan name, coach and organization all appear',
        (tester) async {
      await _pump(tester, card());
      expect(find.text('Workout Plan 11'), findsOneWidget);
      expect(find.textContaining('Iron Temple'), findsOneWidget);
      expect(find.textContaining('Coach Ada'), findsOneWidget);
    });


    testWidgets('no status chip is rendered — status is not served at all',
        (tester) async {
      // getMyTraining serves ONLY active assignments, and prescriptionData
      // carries no status field. A chip here could only ever say "Active".
      await _pump(tester, card());
      expect(find.text('ACTIVE'), findsNothing);
      expect(find.text('PAUSED'), findsNothing);
      expect(find.text('ENDED'), findsNothing);
    });

    testWidgets('completed today replaces the CTA with a statement',
        (tester) async {
      await _pump(tester, card(completedToday: true, onCta: () {}));
      expect(find.text('Completed Today'), findsOneWidget);
      // No primary button to tap pointlessly.
      expect(find.byType(ElevatedButton), findsNothing);
    });

    testWidgets('a null CTA disables the button rather than hiding it',
        (tester) async {
      await _pump(tester, card(onCta: null));
      final btn = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(btn.onPressed, isNull);
    });

    testWidgets("today's line renders when supplied", (tester) async {
      await _pump(tester, card(todayLine: '3 exercises today'));
      expect(find.text('3 exercises today'), findsOneWidget);
    });

    testWidgets('survives 2.0x text at 320dp without overflowing',
        (tester) async {
      await _pump(
        tester,
        card(
          todayLine: 'Rest day · next: Push Day on Wednesday',
          facts: [
            (icon: Icons.repeat_rounded, label: 'Sets', value: '12'),
            (icon: Icons.list_alt_rounded, label: 'Exercises', value: '5'),
          ],
          onCta: () {},
        ),
        size: const Size(320, 1400),
        textScale: 2.0,
      );
      expect(tester.takeException(), isNull);
    });
  });
}
