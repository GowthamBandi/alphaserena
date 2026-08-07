// Executes `shared/weekly_report_contract.json` — the SAME file the trainersHQ
// suite and the backend's TypeScript suite execute.
//
// This is the guard on the invariant that matters most in a three-app feature:
// the client validator is never LOOSER than the server's. A weekly report is
// answered here, rendered in trainersHQ and validated in trainershq-backend; a
// disagreement between the three shows up as an answer the member watched being
// accepted and a coach never receives.
//
// The fixture is NOT copied into this package. Copying it would recreate the
// exact drift this platform has already paid for twice.

import 'dart:convert';
import 'dart:io';

import 'package:alphaserena/core/utils/check_in_math.dart';
import 'package:alphaserena/core/weekly_reports/question_engine.dart';
import 'package:flutter_test/flutter_test.dart';

/// The contract lives at the repo root, beside the three projects that share
/// it. Candidates cover `flutter test` from the package root (the normal case)
/// and from the repo root.
const List<String> _candidatePaths = <String>[
  '../shared/weekly_report_contract.json',
  'shared/weekly_report_contract.json',
  '../../shared/weekly_report_contract.json',
];

Map<String, dynamic> _loadContract() {
  for (final p in _candidatePaths) {
    final f = File(p);
    if (f.existsSync()) {
      return jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
    }
  }
  throw StateError(
    'weekly_report_contract.json not found. Looked in: '
    '${_candidatePaths.join(", ")} from ${Directory.current.path}. '
    'The contract is a SINGLE shared file — do not copy it into this package.',
  );
}

/// JSON cannot distinguish 2500 from 2500.0, and the engine returns a double
/// for every `decimal` type. Compare numerically so the fixture stays readable.
bool _valueMatches(dynamic expected, dynamic actual) {
  if (expected is num && actual is num) {
    return expected.toDouble() == actual.toDouble();
  }
  if (expected is List && actual is List) {
    if (expected.length != actual.length) return false;
    for (var i = 0; i < expected.length; i++) {
      if (!_valueMatches(expected[i], actual[i])) return false;
    }
    return true;
  }
  return expected == actual;
}

QuestionDefinition _question(Map<String, dynamic> raw) =>
    QuestionDefinition.fromMap(raw);

void main() {
  final contract = _loadContract();

  test('the contract targets this engine schema', () {
    expect(contract['schema'], kWeeklyReportSchema);
  });

  group('answerCases', () {
    final cases = (contract['answerCases'] as List).cast<Map<String, dynamic>>();

    test('the fixture is not empty', () => expect(cases, isNotEmpty));

    for (final c in cases) {
      test(c['name'] as String, () {
        final q = _question(Map<String, dynamic>.from(c['question'] as Map));
        final expected = Map<String, dynamic>.from(c['expect'] as Map);
        final verdict = validateAnswer(q, c['answer']);

        expect(verdict.code, expected['code'],
            reason: 'verdict CODE is cross-language API');
        expect(verdict.ok, expected['ok']);
        if (expected.containsKey('value')) {
          expect(_valueMatches(expected['value'], verdict.value), isTrue,
              reason: 'expected ${expected['value']}, got ${verdict.value}');
        }
      });
    }

    test('EVERY registered type is exercised by at least one case', () {
      // The rule that keeps this fixture honest as types are added: a type with
      // no case here is a type whose two implementations have never been
      // compared.
      final covered = <String>{
        for (final c in cases)
          ((c['question'] as Map)['type'] ?? '').toString(),
      };
      final missing =
          kQuestionTypeIds.where((t) => !covered.contains(t)).toList();
      expect(missing, isEmpty,
          reason: 'no contract case for: ${missing.join(", ")}');
    });
  });

  group('visibilityCases', () {
    for (final c in (contract['visibilityCases'] as List)
        .cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final questions = (c['questions'] as List)
            .map((e) => _question(Map<String, dynamic>.from(e as Map)))
            .toList();
        final answers = Map<String, dynamic>.from(c['answers'] as Map);
        final visible =
            visibleQuestions(questions, answers).map((q) => q.id).toList();
        expect(visible, (c['expectVisible'] as List).cast<String>());
      });
    }
  });

  group('completionCases', () {
    for (final c in (contract['completionCases'] as List)
        .cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final questions = (c['questions'] as List)
            .map((e) => _question(Map<String, dynamic>.from(e as Map)))
            .toList();
        final answers = Map<String, dynamic>.from(c['answers'] as Map);
        final e = Map<String, dynamic>.from(c['expect'] as Map);
        final got = completionOf(questions, answers);

        expect(got.answered, e['answered'], reason: 'answered');
        expect(got.total, e['total'], reason: 'total');
        expect(got.requiredAnswered, e['requiredAnswered'],
            reason: 'requiredAnswered');
        expect(got.requiredTotal, e['requiredTotal'], reason: 'requiredTotal');
        expect(got.canSubmit, e['canSubmit'], reason: 'canSubmit');
      });
    }
  });

  group('weekKeyCases', () {
    // Pins the RETIRING Dart rule against the new server rule. Both will exist
    // until Stage C removes the old check-in screen, and a week keyed
    // differently by the two would split one week into two documents that never
    // reconcile. The TypeScript suite runs these same cases.
    for (final c in (contract['weekKeyCases'] as List)
        .cast<Map<String, dynamic>>()) {
      test('${c['date']} → ${c['expect']}  (${c['why']})', () {
        final parts = (c['date'] as String).split('-').map(int.parse).toList();
        expect(
          weekKeyFor(DateTime(parts[0], parts[1], parts[2])),
          c['expect'],
        );
      });
    }
  });

  group('ONE SUNDAY RULE', () {
    test('`weekKeyFor` is declared EXACTLY ONCE in this app', () {
      // The week-key rule exists in three places by design — here (for the
      // retiring check-in), and once in TypeScript (for the Weekly Reports
      // scheduler). A FOURTH copy, or a second Dart one, is how one week comes
      // to be keyed two ways and split into documents that never reconcile.
      final declarations = <String>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (RegExp(r'String\s+weekKeyFor\s*\(')
            .hasMatch(entity.readAsStringSync())) {
          declarations.add(entity.path);
        }
      }
      expect(declarations, hasLength(1), reason: declarations.join(', '));
      expect(declarations.single, contains('check_in_math.dart'));
    });

    test('Weekly Reports never derives a period on the device', () {
      // The member app READS `periodKey`, `opensAt` and `dueAt` off the frozen
      // snapshot the server wrote. Device clock skew of +3 and +6 days is
      // already proven in production here; a client that computed its own
      // window would open next week's report early, or never.
      final dir = Directory('lib/core/weekly_reports');
      if (!dir.existsSync()) return;
      for (final entity in dir.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        // CODE ONLY. Scanning raw text matched this engine's own header
        // comment — which says it contains no `DateTime.now()` — and failed a
        // file for documenting the very rule it obeys.
        final code = entity
            .readAsLinesSync()
            .map((l) => l.replaceFirst(RegExp(r'//.*$'), ''))
            .join('\n');
        expect(code.contains('DateTime.now()'), isFalse,
            reason: '${entity.path} reads the device clock');
        expect(code.contains('weekKeyFor'), isFalse,
            reason: '${entity.path} derives a period locally');
      }
    });
  });

  group('legacyProjectionCases', () {
    for (final c in (contract['legacyProjectionCases'] as List)
        .cast<Map<String, dynamic>>()) {
      test(c['name'] as String, () {
        final got = projectToLegacyRating(
          c['value'] as num?,
          min: c['min'] as num,
          max: c['max'] as num,
        );
        expect(got, c['expect']);
      });
    }
  });
}
