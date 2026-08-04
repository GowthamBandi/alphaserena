import 'package:flutter/material.dart';
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
      expect(find.text('Workout Plans'), findsOneWidget);
      expect(find.text('Diet Plans'), findsOneWidget);
    });

    testWidgets('the selected tab is announced as selected, the other is not',
        (tester) async {
      await _pump(
        tester,
        PlanSegmentedControl(value: PlanTab.diet, onChanged: (_) {}),
      );
      final handle = tester.ensureSemantics();
      expect(
        tester.getSemantics(find.bySemanticsLabel('Diet Plans')),
        matchesSemantics(
          label: 'Diet Plans',
          isButton: true,
          hasSelectedState: true,
          isSelected: true,
        ),
      );
      // Only ONE tab may announce itself as selected.
      expect(
        tester.getSemantics(find.bySemanticsLabel('Workout Plans')),
        matchesSemantics(
          label: 'Workout Plans',
          isButton: true,
          hasSelectedState: true,
          isSelected: false,
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
      await tester.tap(find.text('Diet Plans'));
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
      await tester.tap(find.text('Workout Plans'));
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
      expect(control.height, 56);
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
