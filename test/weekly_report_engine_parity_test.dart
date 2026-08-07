// ═══════════════════════════════════════════════════════════════════════════
// CROSS-APP PARITY GUARD FOR THE WEEKLY REPORTS QUESTION ENGINE
// ═══════════════════════════════════════════════════════════════════════════
//
// ⚠️  THIS FILE IS TWINNED, like the file it guards. The identical test lives at:
//        alphaserena/test/weekly_report_engine_parity_test.dart
//        trainersHQ/test/weekly_report_engine_parity_test.dart
//     (only the import's package name differs).
//
// ── WHY A HASH ────────────────────────────────────────────────────────────
//
// A weekly report is ANSWERED in alphaserena and RENDERED in trainersHQ from
// the same frozen snapshot. If the two copies of the engine drift, a coach and
// their member read the same report differently — different required questions,
// different bounds, a different completion count — and each app's own tests stay
// green, because each is self-consistent about its own version. This repository
// has already paid for that failure mode twice (`transformation_comparison.dart`
// silently diverged; `lifestyle_math.dart` grew helpers on one side only).
//
// The behaviour half of the guard is `weekly_report_contract_test.dart`, which
// runs the SAME `shared/weekly_report_contract.json` in both repos AND in the
// backend's TypeScript suite.
//
// ── WHEN THIS FAILS ────────────────────────────────────────────────────────
//
// Never update only this repo's constant. Copy the engine to the other repo,
// re-run `shasum -a 256`, and update the constant in BOTH copies of this test.

import 'dart:convert';
import 'dart:io';

import 'package:alphaserena/core/weekly_reports/question_engine.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

/// SHA-256 of `lib/core/weekly_reports/question_engine.dart`, identical in both
/// repositories. Regenerate with:
///
///   shasum -a 256 lib/core/weekly_reports/question_engine.dart
///
/// and update it in BOTH repos in the same change.
const String kWeeklyReportEngineSha256 =
    '714171e06a3402166eaaaf30de050a79aee61a28d932d3075d1f52ef2591da38';


/// SHA-256 of `lib/core/weekly_reports/question_renderers.dart`.
///
/// The renderer registry is twinned for a reason the engine's hash does not
/// cover: the coach's LIVE PREVIEW must draw the exact widget the member will
/// answer. If the two copies drift, "preview" becomes a second rendering of the
/// same fact — and the coach is shown a form their member will not see.
const String kWeeklyReportRenderersSha256 =
    '61cd5ed3e9c7102e87e0a966ddfdaec36cdd0e8947f3e3561043e0484c639b22';

void main() {
  group('the engine is byte-identical across both apps', () {
    test('question_engine.dart matches the pinned hash', () {
      final file = File('lib/core/weekly_reports/question_engine.dart');
      expect(file.existsSync(), isTrue,
          reason: 'The weekly-reports engine is missing from this repository.');
      final digest = sha256.convert(file.readAsBytesSync()).toString();
      expect(
        digest,
        kWeeklyReportEngineSha256,
        reason: '\n\nTHE WEEKLY REPORTS ENGINE HAS DRIFTED.\n\n'
            'This file is twinned with the other app. It was edited here and\n'
            'either (a) not copied to the other repository, or (b) copied but\n'
            'the pinned hash was not updated in both.\n\n'
            'Fix: copy lib/core/weekly_reports/question_engine.dart to the\n'
            'other repo, run `shasum -a 256` on it, and update\n'
            'kWeeklyReportEngineSha256 in BOTH copies of this test.\n\n'
            'Do NOT update only this repository\'s constant. That is exactly\n'
            'how transformation_comparison.dart diverged while staying green.\n',
      );
    });

    test('question_renderers.dart matches the pinned hash', () {
      final file = File('lib/core/weekly_reports/question_renderers.dart');
      expect(file.existsSync(), isTrue,
          reason: 'The renderer registry is missing from this repository.');
      expect(
        sha256.convert(file.readAsBytesSync()).toString(),
        kWeeklyReportRenderersSha256,
        reason: '\n\nTHE RENDERER REGISTRY HAS DRIFTED.\n\n'
            'The coach builds a report in trainersHQ and the member answers it\n'
            'in alphaserena. Two copies of this file means the preview and the\n'
            'form are different screens.\n\n'
            'Fix: copy lib/core/weekly_reports/question_renderers.dart to the\n'
            'other repo, run `shasum -a 256`, update the constant in BOTH.\n',
      );
    });
  });

  // ── THE SHAPE MATRIX ──────────────────────────────────────────────────────
  //
  // The contract fixture covers validation behaviour in both languages. What it
  // does NOT cover is the LIBRARY — the built-in questions and the default
  // template — because those are Dart constants, not wire data. They are the
  // most likely thing to be edited in one repo only, so they are pinned here as
  // literals rather than derived from the engine.

  group('the shared library is the same in both apps', () {
    test('the type registry, in order', () {
      expect(kQuestionTypeIds, <String>[
        'rating',
        'emoji',
        'slider',
        'number',
        'text',
        'paragraph',
        'yesNo',
        'multipleChoice',
        'singleChoice',
        'water',
        'sleep',
        'weight',
        'photos',
        'mood',
        'energy',
        'stress',
        'recovery',
        'workoutSatisfaction',
        'dietSatisfaction',
        'supplementAdherence',
        'pain',
        'digestion',
      ]);
    });

    test('the default template, in order', () {
      expect(
        defaultTemplateQuestions().map((q) => q.id).toList(),
        kDefaultTemplateQuestionIds,
      );
      expect(kDefaultTemplateQuestionIds, <String>[
        'q_week_summary',
        'q_energy',
        'q_stress',
        'q_sleep_quality',
        'q_recovery',
        'q_workout_difficulty',
        'q_workout_enjoyment',
        'q_diet_adherence',
        'q_diet_satisfaction',
        'q_water',
        'q_digestion',
        'q_cravings',
        'q_mood',
        'q_progress_photos',
        'q_weight',
        'q_coach_notes',
        'q_additional_comments',
      ]);
    });

    test('the sections, in order', () {
      expect(kDefaultSections.map((s) => s.id).toList(), <String>[
        's_general',
        's_recovery',
        's_training',
        's_nutrition',
        's_body',
        's_notes',
      ]);
    });

    test('the legacy bridge map', () {
      // Editing this in one app only would make a coach surface blank in one
      // build and populated in the other, for the same member and week.
      expect(kLegacyRatingKeyByAnalyticsKey, <String, String>{
        'energy': 'energy',
        'sleep': 'sleep',
        'stress': 'stress',
        'cravings': 'hunger',
        'mood': 'motivation',
        'workout_satisfaction': 'training',
        'diet_adherence': 'diet',
      });
    });

    test('the canonical string of the default template', () {
      // One literal that moves if ANY question's wire shape changes — title,
      // bounds, order, required flag or analytics key. The value a snapshot
      // hash is taken of, pinned across both apps.
      final s = canonicalContentString(
        sections: kDefaultSections,
        questions: defaultTemplateQuestions(),
      );
      expect(s.length, 4284);
      // utf8.encode, NOT codeUnits: the descriptions contain em dashes, and a
      // UTF-16 code unit of 8212 does not fit in a byte — hashing codeUnits
      // silently truncates it, so the digest could never match the same string
      // hashed by Node. The backend pins this identical value.
      expect(sha256.convert(utf8.encode(s)).toString(),
          '0fe9ca8c434d01db672b876b9bd1bd11e83ef68ba9210cee05ab42c562759a8c');
    });
  });
}
