// Engine-native tests: the built-in library, the default template blueprint,
// the canonical content string, and the Stage-A legacy bridge.
//
// The cross-language cases live in `weekly_report_contract_test.dart`.

import 'package:alphaserena/core/models/check_in_submission_model.dart';
import 'package:alphaserena/core/weekly_reports/question_engine.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('the type registry', () {
    test('ids are unique', () {
      expect(kQuestionTypeIds.toSet().length, kQuestionTypeIds.length);
    });

    test('a choice-like type declares that it needs options', () {
      for (final id in <String>['emoji', 'singleChoice', 'multipleChoice']) {
        expect(questionTypeSpec(id)!.requiresOptions, isTrue, reason: id);
      }
    });

    test('an unknown type resolves to null rather than throwing', () {
      expect(questionTypeSpec('holographicScan'), isNull);
    });

    test('every type with a default analytics key names a snake_case series',
        () {
      for (final t in kQuestionTypes) {
        final k = t.defaultAnalyticsKey;
        if (k == null) continue;
        expect(RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(k), isTrue,
            reason: '${t.id} → "$k"');
      }
    });
  });

  group('the built-in library', () {
    test('ids are unique', () {
      final ids = kBuiltInQuestions.map((q) => q.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('every built-in uses a registered type', () {
      for (final q in kBuiltInQuestions) {
        expect(questionTypeSpec(q.type), isNotNull,
            reason: '${q.id} has unknown type "${q.type}"');
      }
    });

    test('every built-in sits in a declared section', () {
      final known = kDefaultSections.map((s) => s.id).toSet();
      for (final q in kBuiltInQuestions) {
        expect(known.contains(q.sectionId), isTrue,
            reason: '${q.id} → "${q.sectionId}"');
      }
    });

    test('a built-in is its own library entry — provenance is self-evident',
        () {
      for (final q in kBuiltInQuestions) {
        expect(q.libraryId, q.id);
      }
    });
  });

  group('the default template (Phase 3)', () {
    test('carries the 17 questions the brief specifies, in order', () {
      final qs = defaultTemplateQuestions();
      expect(qs.length, 17);
      expect(qs.map((q) => q.title).toList(), <String>[
        'How was your week?',
        'Energy',
        'Stress',
        'Sleep',
        'Recovery',
        'Workout Difficulty',
        'Workout Enjoyment',
        'Diet Adherence',
        'Diet Satisfaction',
        'Water Intake',
        'Digestion',
        'Cravings',
        'Mood',
        'Progress Photos',
        'Current Weight',
        'Notes for your coach',
        'Additional Comments',
      ]);
    });

    test('order is dense and matches list position', () {
      final qs = defaultTemplateQuestions();
      for (var i = 0; i < qs.length; i++) {
        expect(qs[i].order, i);
      }
    });

    test('every id resolves to a built-in — no dangling reference', () {
      for (final id in kDefaultTemplateQuestionIds) {
        expect(builtInQuestion(id), isNotNull, reason: id);
      }
    });

    test('a fresh template is not submittable with nothing answered', () {
      final c = completionOf(defaultTemplateQuestions(), const {});
      expect(c.canSubmit, isFalse);
      expect(c.requiredTotal, greaterThan(0));
      expect(c.progress, 0);
    });

    test('answering every required question opens the gate', () {
      final qs = defaultTemplateQuestions();
      final answers = <String, dynamic>{};
      for (final q in qs) {
        if (!q.required) continue;
        answers[q.id] = <String, dynamic>{'value': _plausible(q)};
      }
      final c = completionOf(qs, answers);
      expect(c.issues, isEmpty, reason: c.issues.toString());
      expect(c.canSubmit, isTrue);
    });

    test('photos and the two note fields are optional — a member is never '
        'blocked on a camera', () {
      for (final id in <String>[
        'q_progress_photos',
        'q_coach_notes',
        'q_additional_comments'
      ]) {
        expect(builtInQuestion(id)!.required, isFalse, reason: id);
      }
    });
  });

  group('the canonical content string', () {
    List<QuestionDefinition> sample() => <QuestionDefinition>[
          const QuestionDefinition(
              id: 'b', type: 'rating', title: 'B', order: 1),
          const QuestionDefinition(
              id: 'a', type: 'text', title: 'A', order: 0),
        ];

    test('is independent of input ordering', () {
      final forward = canonicalContentString(
          sections: kDefaultSections, questions: sample());
      final reversed = canonicalContentString(
          sections: kDefaultSections.reversed.toList(),
          questions: sample().reversed.toList());
      expect(forward, reversed);
    });

    test('changing one title changes the hash input', () {
      final before = canonicalContentString(
          sections: kDefaultSections, questions: sample());
      final after = canonicalContentString(
        sections: kDefaultSections,
        questions: <QuestionDefinition>[
          const QuestionDefinition(
              id: 'b', type: 'rating', title: 'B2', order: 1),
          const QuestionDefinition(
              id: 'a', type: 'text', title: 'A', order: 0),
        ],
      );
      expect(before, isNot(after));
    });

    test('INTEGRAL DOUBLES ARE EMITTED AS INTEGERS — otherwise Dart writes '
        '"1.0" where JS writes "1" and every cross-language hash differs', () {
      final s = canonicalContentString(
        sections: const <ReportSection>[],
        questions: <QuestionDefinition>[
          const QuestionDefinition(
            id: 'a',
            type: 'rating',
            title: 'A',
            validation: QuestionValidation(min: 1.0, max: 5.0, step: 1.0),
          ),
        ],
      );
      expect(s.contains('"min":1'), isTrue);
      expect(s.contains('1.0'), isFalse, reason: s);
    });

    test('a disabled question still changes the snapshot', () {
      final on = canonicalContentString(
          sections: const [],
          questions: const [
            QuestionDefinition(id: 'a', type: 'text', title: 'A')
          ]);
      final off = canonicalContentString(
          sections: const [],
          questions: const [
            QuestionDefinition(
                id: 'a', type: 'text', title: 'A', enabled: false)
          ]);
      expect(on, isNot(off));
    });
  });

  group('the Stage-A legacy bridge', () {
    test('EVERY projected key is a real legacy rating key', () {
      // The bridge writes into `client_check_in_submissions`, whose parser
      // silently DROPS any key it does not know. A typo here would look like a
      // working projection and read as a blank week on 25 coach surfaces.
      for (final entry in kLegacyRatingKeyByAnalyticsKey.entries) {
        expect(kCheckInRatingKeys.contains(entry.value), isTrue,
            reason: '${entry.key} → "${entry.value}" is not a legacy key');
      }
    });

    test('no two analytics keys fight over one legacy key', () {
      final targets = kLegacyRatingKeyByAnalyticsKey.values.toList();
      expect(targets.toSet().length, targets.length);
    });

    test('every source key is produced by some default-template question', () {
      final produced = defaultTemplateQuestions()
          .map((q) => q.effectiveAnalyticsKey)
          .where((k) => k.isNotEmpty)
          .toSet();
      for (final k in kLegacyRatingKeyByAnalyticsKey.keys) {
        expect(produced.contains(k), isTrue,
            reason: '"$k" is mapped but nothing in the default template emits '
                'it — the legacy surface for it would always be blank');
      }
    });

    test('a rescaled value always lands inside the legacy 1..5 parser', () {
      for (var v = 1; v <= 10; v++) {
        final out = projectToLegacyRating(v, min: 1, max: 10);
        expect(out, isNotNull);
        expect(out! >= 1 && out <= 5, isTrue, reason: 'v=$v → $out');
      }
    });
  });

  group('the model round-trips', () {
    test('a question survives toMap → fromMap', () {
      const before = QuestionDefinition(
        id: 'q_x',
        libraryId: 'lib_x',
        type: 'rating',
        title: 'X',
        description: 'desc',
        sectionId: 's1',
        order: 4,
        required: true,
        unit: 'kg',
        validation: QuestionValidation(min: 1, max: 10, step: 1),
        options: <QuestionOption>[
          QuestionOption(id: 'o1', label: 'One', value: 1, emoji: '1️⃣')
        ],
        visibility: QuestionVisibility(
            questionId: 'q_y', op: VisibilityOp.gte, value: 3),
        analyticsKey: 'custom_key',
      );
      final after = QuestionDefinition.fromMap(before.toMap());

      expect(after.id, before.id);
      expect(after.libraryId, before.libraryId);
      expect(after.type, before.type);
      expect(after.order, before.order);
      expect(after.required, isTrue);
      expect(after.unit, 'kg');
      expect(after.bounds.max, 10);
      expect(after.options.single.emoji, '1️⃣');
      expect(after.visibility!.questionId, 'q_y');
      expect(after.visibility!.op, VisibilityOp.gte);
      expect(after.analyticsKey, 'custom_key');
    });

    test('A MISSING `enabled` MEANS ENABLED — an absent field must never '
        'remove a question from a member\'s report', () {
      final q = QuestionDefinition.fromMap(
          <String, dynamic>{'id': 'a', 'type': 'text', 'title': 'A'});
      expect(q.enabled, isTrue);
    });

    test('an unparsable visibility rule is dropped, not half-applied', () {
      final q = QuestionDefinition.fromMap(<String, dynamic>{
        'id': 'a',
        'type': 'text',
        'title': 'A',
        'visibility': {
          'showIf': {'questionId': 'b', 'op': 'nonsense'}
        },
      });
      expect(q.visibility, isNull);
    });

    test('bounds inherit the type default and the author overrides win', () {
      const inherited =
          QuestionDefinition(id: 'a', type: 'rating', title: 'A');
      expect(inherited.bounds.min, 1);
      expect(inherited.bounds.max, 5);

      const overridden = QuestionDefinition(
          id: 'a',
          type: 'rating',
          title: 'A',
          validation: QuestionValidation(max: 10));
      expect(overridden.bounds.min, 1, reason: 'not specified → type default');
      expect(overridden.bounds.max, 10, reason: 'specified → author wins');
    });

    test('effectiveAnalyticsKey falls back to the type default', () {
      const q = QuestionDefinition(id: 'a', type: 'mood', title: 'A');
      expect(q.effectiveAnalyticsKey, 'mood');

      const named = QuestionDefinition(
          id: 'a', type: 'mood', title: 'A', analyticsKey: 'vibes');
      expect(named.effectiveAnalyticsKey, 'vibes');
    });
  });
}

/// A valid answer for [q], used to prove the default template is completable.
dynamic _plausible(QuestionDefinition q) {
  final spec = questionTypeSpec(q.type)!;
  switch (spec.valueKind) {
    case QuestionValueKind.integer:
      return q.bounds.min ?? 1;
    case QuestionValueKind.decimal:
      final min = q.bounds.min ?? 0;
      final max = q.bounds.max ?? 100;
      return min > 0 ? min : (max > 1 ? 1 : max);
    case QuestionValueKind.text:
      return spec.requiresOptions ? q.options.first.id : 'answer';
    case QuestionValueKind.boolean:
      return true;
    case QuestionValueKind.textList:
      return spec.requiresOptions
          ? <String>[q.options.first.id]
          : <String>['a.jpg'];
  }
}
