// WEEKLY REPORTS AT SCALE — what a 100-, 250- and 1000-question report costs.
//
// The release checklist asks for render time, rebuild counts and scrolling on a
// large template. This measures the thing that decides all three: HOW MANY
// question widgets the form actually instantiates.
//
// Every Weekly Reports list is built with the EAGER `ListView(children: [...])`
// constructor (member form weekly_report_screen.dart:412, coach review
// weekly_report_review_screen.dart:173), not `ListView.builder`. The eager
// constructor materialises every child on every build; the lazy one materialises
// only what the viewport needs. On a 17-question template — the default, and the
// only size anyone has run — the difference is invisible. These tests state what
// it becomes when a coach builds the 100+ question template the checklist asks
// about, and pin the numbers so the trade-off is a decision rather than a
// surprise.

import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/core/weekly_reports/question_engine.dart';
import 'package:alphaserena/core/weekly_reports/question_renderers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

QuestionDefinition _q(int i) => QuestionDefinition(
      id: 'q_$i',
      type: 'rating',
      title: 'Question $i',
      description: 'How did this go over the week?',
      required: i.isEven,
      validation: const QuestionValidation(min: 1, max: 5, step: 1),
    );

Widget _card(QuestionDefinition q) => QuestionCard(
      key: ValueKey(q.id),
      ctx: QuestionRenderContext(
        question: q,
        value: null,
        onChanged: (_) {},
      ),
    );

/// The member form's own construction: `ListView(children: [...])`.
Widget _eager(List<QuestionDefinition> qs) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ListView(children: [for (final q in qs) _card(q)]),
      ),
    );

/// The lazy alternative, for the comparison the numbers are meaningless without.
Widget _lazy(List<QuestionDefinition> qs) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: ListView.builder(
          itemCount: qs.length,
          itemBuilder: (_, i) => _card(qs[i]),
        ),
      ),
    );

void main() {
  // A phone-sized viewport — the surface that decides how much is off-screen.
  Future<void> sized(WidgetTester tester, Widget w) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(w);
  }

  group('a large template renders at all', () {
    for (final n in [100, 250]) {
      testWidgets('$n questions render without throwing', (tester) async {
        final qs = [for (var i = 0; i < n; i++) _q(i)];
        await sized(tester, _eager(qs));
        expect(tester.takeException(), isNull);
        // Scrolling a long report must not throw either — the checklist asks
        // about scrolling, and a RenderFlex that only breaks at item 180 is
        // invisible to a test that never scrolls.
        await tester.drag(find.byType(ListView), const Offset(0, -4000));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('THE MEASUREMENT — and the assumption it disproved', () {
    // HYPOTHESIS (mine, from reading the source): `ListView(children: [...])`
    // is the EAGER constructor, so a 250-question report would inflate 250
    // question widgets on every rebuild, and the member form — which sits
    // inside an Obx and rebuilds on every answer — would degrade badly.
    //
    // MEASUREMENT: it inflates SIX. `SliverChildListDelegate` still only
    // mounts what the viewport needs; the `children` list holds 250 immutable
    // widget DESCRIPTIONS (cheap config objects), not 250 mounted elements.
    // The hypothesis was wrong and the number is the reason it was dropped
    // rather than argued.
    testWidgets('a 250-question report mounts a viewport-sized handful, '
        'not 250 — the eager constructor is NOT a scaling defect',
        (tester) async {
      final qs = [for (var i = 0; i < 250; i++) _q(i)];

      await sized(tester, _eager(qs));
      final eagerMounted = tester.widgetList(find.byType(QuestionCard)).length;

      await sized(tester, _lazy(qs));
      final lazyMounted = tester.widgetList(find.byType(QuestionCard)).length;

      expect(eagerMounted, lessThan(40),
          reason: 'a phone viewport must not mount the whole report');
      // Both constructions are viewport-bound. The remaining eager cost is the
      // per-rebuild allocation of N widget descriptions — real, but linear in
      // cheap objects, not in mounted element trees.
      expect((eagerMounted - lazyMounted).abs(), lessThan(40));

      // ignore: avoid_print
      print('SCALE 250 questions — eager mounts: $eagerMounted, '
          'lazy mounts: $lazyMounted');
    });

    testWidgets('mounted cost does NOT grow with the template — 100 vs 1000',
        (tester) async {
      final mounted = <int, int>{};
      for (final n in [100, 1000]) {
        final qs = [for (var i = 0; i < n; i++) _q(i)];
        await sized(tester, _eager(qs));
        mounted[n] = tester.widgetList(find.byType(QuestionCard)).length;
        expect(tester.takeException(), isNull);
      }
      // THE POINT: a 10x bigger template mounts the same handful. This is what
      // makes 1000 questions safe, and it is the number the release checklist
      // was asking for.
      expect(mounted[1000], lessThan(40));
      expect((mounted[1000]! - mounted[100]!).abs(), lessThan(20),
          reason: 'mounted cost must be viewport-bound, not template-bound');
      // ignore: avoid_print
      print('SCALE mounted cards — 100q: ${mounted[100]}, '
          '1000q: ${mounted[1000]}');
    });
  });

  group('answering stays responsive-shaped', () {
    testWidgets('a 250-question report still accepts a tap on question 1',
        (tester) async {
      // Not a frame-time benchmark — a machine-timing threshold that flips run
      // to run is the defect this repo already carries in progress_scale_bench.
      // This pins the SHAPE: the first question is reachable and interactive on
      // a large report, which is what a member actually does first.
      var changed = 0;
      final qs = [for (var i = 0; i < 250; i++) _q(i)];
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(
          body: ListView(children: [
            for (final q in qs)
              QuestionCard(
                key: ValueKey(q.id),
                ctx: QuestionRenderContext(
                  question: q,
                  value: null,
                  onChanged: (_) => changed++,
                ),
              ),
          ]),
        ),
      ));
      expect(tester.takeException(), isNull);

      final firstRating = find.text('3').first;
      await tester.tap(firstRating, warnIfMissed: false);
      await tester.pump();
      expect(changed, greaterThan(0),
          reason: 'the first question must be answerable on a 250-q report');
      expect(tester.takeException(), isNull);
    });
  });
}
