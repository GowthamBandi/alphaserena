// The renderer registry — the layer that makes "no switch on question type"
// true, and the layer where a type the engine accepts could silently reach a
// member as an "app update needed" card.

import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/core/weekly_reports/question_engine.dart';
import 'package:alphaserena/core/weekly_reports/question_renderers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

QuestionDefinition _q(
  String type, {
  String id = 'q1',
  String title = 'Question',
  bool required = false,
  QuestionValidation validation = const QuestionValidation(),
  List<QuestionOption> options = const [],
  String unit = '',
}) =>
    QuestionDefinition(
      id: id,
      type: type,
      title: title,
      required: required,
      validation: validation,
      options: options,
      unit: unit,
    );

void main() {
  group('THE COVERAGE GUARD', () {
    test('EVERY type the engine accepts has a renderer', () {
      // Without this, adding a type to the engine ships a member a card saying
      // their app needs updating — for a question their app could have drawn.
      final missing = kQuestionTypeIds
          .where((t) => !QuestionRendererRegistry.knows(t))
          .toList();
      expect(missing, isEmpty,
          reason: 'no renderer for: ${missing.join(", ")}');
    });

    test('the registry draws nothing the engine does not know', () {
      final extra = QuestionRendererRegistry.renderableTypes
          .where((t) => questionTypeSpec(t) == null)
          .toList();
      expect(extra, isEmpty,
          reason: 'renderer for unknown type: ${extra.join(", ")}');
    });

    test('dispatch is a MAP LOOKUP, and an unknown type resolves', () {
      // rendererFor must never return null — that is the whole reason it is a
      // lookup with a fallback rather than a switch with a default nobody wrote.
      expect(QuestionRendererRegistry.rendererFor('holographicScan'), isNotNull);
      expect(QuestionRendererRegistry.knows('holographicScan'), isFalse);
    });
  });

  group('every renderer mounts', () {
    for (final type in kQuestionTypeIds) {
      testWidgets(type, (tester) async {
        final needsOptions = questionTypeSpec(type)!.requiresOptions;
        await tester.pumpWidget(_host(QuestionCard(
          ctx: QuestionRenderContext(
            question: _q(
              type,
              title: 'A $type question',
              options: needsOptions
                  ? const [
                      QuestionOption(id: 'a', label: 'A', emoji: '🙂', value: 1),
                      QuestionOption(id: 'b', label: 'B', emoji: '🙁', value: 2),
                    ]
                  : const [],
            ),
            value: null,
            onChanged: (_) {},
          ),
        )));
        expect(tester.takeException(), isNull);
        expect(find.text('A $type question'), findsOneWidget);
      });
    }
  });

  group('the honest fallback', () {
    testWidgets('an unknown type renders the update card, not a crash',
        (tester) async {
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('holographicScan', title: 'Future question'),
          value: null,
          onChanged: (_) {},
        ),
      )));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('needs an app update'), findsOneWidget);
      // And it says the member can still finish, because the engine excludes
      // unknown types from the submit gate.
      expect(find.textContaining('submit the rest'), findsOneWidget);
    });
  });

  group('the scale renderer reads its bounds from the ENGINE', () {
    testWidgets('a default rating draws 1..5', (tester) async {
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('rating'),
          value: null,
          onChanged: (_) {},
        ),
      )));
      for (var i = 1; i <= 5; i++) {
        expect(find.text('$i'), findsOneWidget);
      }
      expect(find.text('6'), findsNothing);
    });

    testWidgets('a coach-widened 1..10 rating draws ten, with no code change',
        (tester) async {
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('rating',
              validation: const QuestionValidation(min: 1, max: 10, step: 1)),
          value: null,
          onChanged: (_) {},
        ),
      )));
      expect(find.text('10'), findsOneWidget);
    });

    testWidgets('tapping reports the value', (tester) async {
      dynamic got;
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('energy'),
          value: null,
          onChanged: (v) => got = v,
        ),
      )));
      await tester.tap(find.text('4'));
      expect(got, 4);
    });

    testWidgets('readOnly does not report changes', (tester) async {
      var called = false;
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('energy'),
          value: 3,
          readOnly: true,
          onChanged: (_) => called = true,
        ),
      )));
      await tester.tap(find.text('4'));
      expect(called, isFalse);
    });
  });

  group('choice renderers', () {
    testWidgets('single choice reports the OPTION ID, never the label',
        (tester) async {
      dynamic got;
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('singleChoice', options: const [
            QuestionOption(id: 'opt_a', label: 'Great'),
            QuestionOption(id: 'opt_b', label: 'Poor'),
          ]),
          value: null,
          onChanged: (v) => got = v,
        ),
      )));
      await tester.tap(find.text('Poor'));
      // Storing the label would orphan every historical answer the first time
      // a coach reworded an option.
      expect(got, 'opt_b');
    });

    testWidgets('multi choice returns AUTHOR order, not tap order',
        (tester) async {
      dynamic got;
      final q = _q('multipleChoice', options: const [
        QuestionOption(id: 'a', label: 'Alpha'),
        QuestionOption(id: 'b', label: 'Beta'),
        QuestionOption(id: 'c', label: 'Gamma'),
      ]);
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: q,
          value: const ['c'],
          onChanged: (v) => got = v,
        ),
      )));
      await tester.tap(find.text('Alpha'));
      // Tap order would make one answer serialize two ways, and every diff
      // between two identical reports would read as a change.
      expect(got, ['a', 'c']);
    });

    testWidgets('tapping a selected multi-choice option removes it',
        (tester) async {
      dynamic got;
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('multipleChoice', options: const [
            QuestionOption(id: 'a', label: 'Alpha'),
          ]),
          value: const ['a'],
          onChanged: (v) => got = v,
        ),
      )));
      await tester.tap(find.text('Alpha'));
      expect(got, isEmpty);
    });
  });

  group('yes / no', () {
    testWidgets('reports booleans, not strings', (tester) async {
      dynamic got;
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('yesNo'),
          value: null,
          onChanged: (v) => got = v,
        ),
      )));
      await tester.tap(find.text('No'));
      expect(got, false);
      await tester.tap(find.text('Yes'));
      expect(got, true);
    });
  });

  group('numeric renderers', () {
    testWidgets('the accepted range is stated up front', (tester) async {
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('weight', unit: 'kg'),
          value: null,
          onChanged: (_) {},
        ),
      )));
      // A member should not have to submit to discover a bound.
      expect(find.text('20–400'), findsOneWidget);
      expect(find.text('kg'), findsOneWidget);
    });

    testWidgets('typing reports a parsed number', (tester) async {
      dynamic got;
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('weight'),
          value: null,
          onChanged: (v) => got = v,
        ),
      )));
      await tester.enterText(find.byType(TextField), '78.4');
      expect(got, 78.4);
    });

    testWidgets('a partially typed decimal does not clobber the field',
        (tester) async {
      // "7." is not a number yet. If the parent re-seeded the box on every
      // keystroke the member could never type a decimal at all.
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('sleep'),
          value: null,
          onChanged: (_) {},
        ),
      )));
      await tester.enterText(find.byType(TextField), '7.');
      await tester.pump();
      expect(find.text('7.'), findsOneWidget);
    });
  });

  group('text renderers', () {
    testWidgets('a paragraph shows its character budget', (tester) async {
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('paragraph',
              validation: const QuestionValidation(maxLength: 100)),
          value: null,
          onChanged: (_) {},
        ),
      )));
      await tester.enterText(find.byType(TextField), 'hello');
      await tester.pump();
      expect(find.text('5 / 100'), findsOneWidget);
    });
  });

  group('photos', () {
    testWidgets('no picker means no control — the coach side is read-only',
        (tester) async {
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('photos'),
          value: null,
          onChanged: (_) {},
        ),
      )));
      expect(find.textContaining('Add photo'), findsNothing);
    });

    testWidgets('with a picker, the cap is shown and honoured', (tester) async {
      dynamic got;
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('photos',
              validation: const QuestionValidation(maxPhotos: 2)),
          value: const ['a.jpg'],
          onChanged: (v) => got = v,
          onPickPhotos: () async => ['b.jpg', 'c.jpg'],
        ),
      )));
      expect(find.textContaining('1/2'), findsOneWidget);
      await tester.tap(find.textContaining('Add photo'));
      await tester.pumpAndSettle();
      // Accepting three would hand the engine an answer it rejects, losing the
      // whole submit rather than one photo.
      expect(got, ['a.jpg', 'b.jpg']);
    });
  });

  group('the card chrome', () {
    testWidgets('a required question is marked, and the marker becomes Done',
        (tester) async {
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('energy', required: true),
          value: null,
          onChanged: (_) {},
        ),
      )));
      expect(find.text('Required'), findsOneWidget);

      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('energy', required: true),
          value: 4,
          onChanged: (_) {},
        ),
      )));
      expect(find.text('Done'), findsOneWidget);
      expect(find.text('Required'), findsNothing);
    });

    testWidgets('a verdict renders its message', (tester) async {
      final q = _q('weight');
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: q,
          value: 9999,
          verdict: validateAnswer(q, 9999),
          onChanged: (_) {},
        ),
      )));
      expect(find.textContaining('400 or less'), findsOneWidget);
    });

    testWidgets('no verdict means no error, even for an invalid value',
        (tester) async {
      // Untouched questions must not turn red — a form that scolds before it is
      // used reads as broken.
      await tester.pumpWidget(_host(QuestionCard(
        ctx: QuestionRenderContext(
          question: _q('weight'),
          value: 9999,
          onChanged: (_) {},
        ),
      )));
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });
  });

  group('the progress bar delegates to the engine', () {
    testWidgets('reads ReportCompletion, so it cannot disagree with submit',
        (tester) async {
      final questions = [
        _q('energy', id: 'a', required: true),
        _q('text', id: 'b'),
      ];
      final completion = completionOf(questions, {
        'a': {'value': 4},
      });
      await tester.pumpWidget(_host(ReportProgressBar(completion: completion)));
      expect(find.text('Ready to send'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);
    });

    testWidgets('an incomplete report names what is left', (tester) async {
      final completion = completionOf([
        _q('energy', id: 'a', required: true),
        _q('mood', id: 'b', required: true),
      ], const {});
      await tester.pumpWidget(_host(ReportProgressBar(completion: completion)));
      expect(find.text('0 of 2 required answered'), findsOneWidget);
    });
  });

  group('section headers', () {
    testWidgets('show progress within the group', (tester) async {
      await tester.pumpWidget(_host(const ReportSectionHeader(
        section: ReportSection(id: 's1', title: 'Recovery'),
        answered: 2,
        total: 3,
      )));
      expect(find.text('RECOVERY'), findsOneWidget);
      expect(find.text('2/3'), findsOneWidget);
    });
  });
}
