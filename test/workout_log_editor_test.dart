import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/domain/workout_history.dart';
import 'package:alphaserena/core/domain/workout_session.dart';
import 'package:alphaserena/core/services/workout_log_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/plans/workout_log_editor_screen.dart';
import 'package:alphaserena/screens/dashboard/plans/workout_set_edit_sheet.dart';

/// Records every write the editor makes, so the tests can assert on the WIRE
/// rather than on the screen's internal state. That is the point: this file is
/// really a test of what TrainerHQ will read.
class _FakeLog extends WorkoutLogService {
  final List<List<Map<String, dynamic>>> entryWrites = [];
  final List<String> noteWrites = [];
  WorkoutSaveResult result = WorkoutSaveResult.synced;

  /// Would fail loudly if the editor ever routed a correction through the
  /// full-session write, which re-sends status/date/duration.
  int fullSessionWrites = 0;

  @override
  Future<WorkoutSaveResult> saveEditedEntries({
    required String sessionId,
    required List<Map<String, dynamic>> entries,
  }) async {
    entryWrites.add(entries);
    return result;
  }

  @override
  Future<WorkoutSaveResult> saveMemberNote({
    required String sessionId,
    required String note,
  }) async {
    noteWrites.add(note);
    return result;
  }

  @override
  Future<WorkoutSaveResult> saveSession({
    required String sessionId,
    required String planName,
    String? planId,
    required DateTime date,
    required List<Map<String, dynamic>> entries,
    required String status,
    DateTime? startedAt,
    DateTime? finishedAt,
    int? durationSeconds,
    bool markCreated = false,
  }) async {
    fullSessionWrites++;
    return WorkoutSaveResult.synced;
  }
}

WorkoutDayLog _log({DateTime? date, String memberNote = ''}) =>
    parseWorkoutDayLog(
      {
        'date': date ?? DateTime(2026, 8, 4),
        'planName': 'Workout Plan 11',
        'status': kSessionCompleted,
        'durationSeconds': 3600,
        'finishedAt': DateTime(2026, 8, 4, 8, 30),
        if (memberNote.isNotEmpty) 'memberNote': memberNote,
        'entries': [
          {
            'exerciseName': 'Bench Press',
            'exerciseId': 'ex_1',
            'note': 'Elbows tucked',
            'sets': [
              {
                'setNumber': 1,
                'prescribedReps': '10',
                'prescribedWeight': '20',
                'prescribedRest': '90',
                'actualReps': '10',
                'actualWeight': '20',
                'completed': true,
              },
              {
                'setNumber': 2,
                'prescribedReps': '10',
                'prescribedWeight': '20',
                'prescribedRest': '90',
                'actualReps': '',
                'actualWeight': '',
                'completed': false,
              },
            ],
          },
        ],
      },
      'ws_c1_2026-08-04',
    )!;

Future<_FakeLog> _open(
  WidgetTester tester, {
  WorkoutDayLog? log,
  Size size = const Size(390, 1200),
  double textScale = 1.0,
}) async {
  final fake = _FakeLog();
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: WorkoutLogEditorScreen(
          sessionId: 'ws_c1_2026-08-04',
          initial: log ?? _log(),
          service: fake,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return fake;
}

/// Opens the sheet on set [n] of the only exercise.
Future<void> _tapSet(WidgetTester tester, int n) async {
  await tester.tap(find.text('Set $n').last);
  await tester.pumpAndSettle();
}

/// The sheet's own fields. Scoped deliberately: the editor screen behind the
/// sheet carries the coach-note TextField, and an unscoped `.first` types the
/// member's reps into their note.
Finder get _repsField => find
    .descendant(
      of: find.byType(WorkoutSetEditSheet),
      matching: find.byType(TextField),
    )
    .first;

Finder get _saveSet => find.descendant(
      of: find.byType(WorkoutSetEditSheet),
      matching: find.widgetWithText(ElevatedButton, 'Save set'),
    );

void main() {
  group('the log opens as a log, not as a player', () {
    testWidgets('every exercise and every set is on screen at once',
        (tester) async {
      await _open(tester);
      expect(find.text('Bench Press'), findsOneWidget);
      // Both sets visible without a single tap — history and corrections are
      // reading tasks, not guided ones.
      expect(find.text('Set 1'), findsWidgets);
      expect(find.text('Set 2'), findsWidgets);
    });

    testWidgets('the session summary is live, from the one engine',
        (tester) async {
      await _open(tester);
      expect(find.text('50%'), findsOneWidget); // 1 of 2 sets
      expect(find.text('1/2'), findsOneWidget);
    });
  });

  group('a correction writes ONLY the logged performance', () {
    testWidgets('changing reps writes entries, never a full session',
        (tester) async {
      final fake = await _open(tester);
      await _tapSet(tester, 1);

      await tester.enterText(_repsField, '8');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save set'));
      await tester.pumpAndSettle();

      expect(fake.entryWrites, hasLength(1));
      // THE INVARIANT: a correction must not restate the session's lifecycle.
      // Routing this through `saveSession` would re-send status, date,
      // startedAt/finishedAt and durationSeconds from whatever the screen was
      // holding — so a typo fix could re-open a finished workout.
      expect(fake.fullSessionWrites, 0);

      final sets = (fake.entryWrites.single.single['sets'] as List)
          .cast<Map<String, dynamic>>();
      expect(sets.first['actualReps'], '8');
      expect(sets.first['completed'], isTrue);
    });

    testWidgets('a corrected set is marked edited for the coach',
        (tester) async {
      final fake = await _open(tester);
      await _tapSet(tester, 1);
      await tester.enterText(_repsField, '8');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save set'));
      await tester.pumpAndSettle();

      final sets = (fake.entryWrites.single.single['sets'] as List)
          .cast<Map<String, dynamic>>();
      // The number is the member's; the coach simply knows it was revised
      // rather than logged live. Same flag TrainerHQ's SessionSet.edited reads.
      expect(sets.first['edited'], isTrue);
      expect(find.text('edited'), findsWidgets);
    });

    testWidgets("a coach's note on the exercise SURVIVES the rewrite",
        (tester) async {
      // The regression a merge write invites: `buildSessionEntries` replaces
      // the whole entries array, so a field parsed but not written back is
      // deleted the first time a member fixes a rep count.
      final fake = await _open(tester);
      await _tapSet(tester, 1);
      await tester.enterText(_repsField, '8');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save set'));
      await tester.pumpAndSettle();

      expect(fake.entryWrites.single.single['note'], 'Elbows tucked');
    });

    testWidgets('saving an IDENTICAL set writes nothing and marks nothing',
        (tester) async {
      final fake = await _open(tester);
      await _tapSet(tester, 1);
      await tester.tap(find.text('Save set'));
      await tester.pumpAndSettle();
      expect(fake.entryWrites, isEmpty);
      expect(find.text('edited'), findsNothing);
    });

    testWidgets('a failed write says so and does not claim success',
        (tester) async {
      final fake = await _open(tester);
      fake.result = WorkoutSaveResult.failed;
      await _tapSet(tester, 1);
      await tester.enterText(_repsField, '8');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save set'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Could not save'), findsOneWidget);
      // And the PERSISTENT indicator must not contradict the transient toast:
      // a member who missed the snackbar would otherwise be left reading a
      // green "Saved" over a correction that never reached Firestore.
      expect(find.text('Saved'), findsNothing);
      expect(find.text('Not saved'), findsOneWidget);
    });

    testWidgets('a QUEUED write is neither a success nor a failure',
        (tester) async {
      final fake = await _open(tester);
      fake.result = WorkoutSaveResult.queued;
      await _tapSet(tester, 1);
      await tester.enterText(_repsField, '8');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save set'));
      await tester.pumpAndSettle();
      // The write is in Firestore's local queue and will sync. Saying "Saved"
      // would be a claim about the coach's screen the app cannot yet make.
      expect(find.text('Saved on this device'), findsOneWidget);
      // And NOT "Saved offline": `queued` means the server did not ack inside
      // 4s, which happens on a perfectly connected device during a slow cold
      // start. Naming a network state nothing measured told online members
      // they were offline.
      expect(find.text('Saved offline'), findsNothing);
    });
  });

  group('a set cannot be completed with no evidence behind it', () {
    testWidgets('Save is refused, and the reason is on screen', (tester) async {
      // `setHitTarget` reads a completed set with no numeric actuals as having
      // HIT its target, so an empty completed set would award both a completion
      // and 100% adherence for work with nothing recorded against it.
      await _open(tester);
      await _tapSet(tester, 2); // the pending set, both fields empty
      // Leaving it pending is fine — that is what it already is. The guard is
      // about claiming it was COMPLETED.
      expect(tester.widget<ElevatedButton>(_saveSet).onPressed, isNotNull);
      await tester.tap(find.text('Completed'));
      await tester.pumpAndSettle();
      expect(tester.widget<ElevatedButton>(_saveSet).onPressed, isNull);
      expect(
        find.textContaining('Add the reps or the weight'),
        findsOneWidget,
      );
    });

    testWidgets('marking it skipped instead is always allowed', (tester) async {
      final fake = await _open(tester);
      await _tapSet(tester, 2);
      await tester.tap(find.text('Skipped'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save set'));
      await tester.pumpAndSettle();

      final sets = (fake.entryWrites.single.single['sets'] as List)
          .cast<Map<String, dynamic>>();
      expect(sets[1]['skipped'], isTrue);
      expect(sets[1]['completed'], isFalse);
    });

    testWidgets('bodyweight work needs only ONE of the two fields',
        (tester) async {
      final fake = await _open(tester);
      await _tapSet(tester, 2);
      await tester.enterText(_repsField, '15');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save set'));
      await tester.pumpAndSettle();
      expect(fake.entryWrites, hasLength(1));
    });
  });

  group('the prescription belongs to the coach', () {
    testWidgets('the sheet states it read-only and offers no way to change it',
        (tester) async {
      await _open(tester);
      await _tapSet(tester, 1);
      expect(find.textContaining('coach asked for 10 reps × 20 kg'),
          findsOneWidget);
      // Exactly two editable fields: reps done and weight used.
      expect(
        find.descendant(
          of: find.byType(WorkoutSetEditSheet),
          matching: find.byType(TextField),
        ),
        findsNWidgets(2),
      );
    });

    testWidgets('the hints are TYPABLE on the numeric keyboard they open',
        (tester) async {
      // The fields open a decimal pad. A hint echoing the coach's prescription
      // verbatim showed members placeholder text with letters or a hyphen in
      // it — an example they physically could not enter — and repeated a
      // target already stated in full one line above.
      await _open(
        tester,
        log: parseWorkoutDayLog(
          {
            'date': DateTime(2026, 8, 4),
            'planName': 'Workout Plan 11',
            'status': kSessionCompleted,
            'entries': [
              {
                'exerciseName': 'Push Up',
                'exerciseId': 'ex_pu',
                'sets': [
                  {
                    'setNumber': 1,
                    'prescribedReps': '8-12',
                    'prescribedWeight': 'bodyweight',
                    'actualReps': '',
                    'actualWeight': '',
                    'completed': false,
                  },
                ],
              },
            ],
          },
          'ws_c1_2026-08-04',
        )!,
      );
      await _tapSet(tester, 1);

      final hints = tester
          .widgetList<TextField>(find.descendant(
            of: find.byType(WorkoutSetEditSheet),
            matching: find.byType(TextField),
          ))
          .map((f) => f.decoration?.hintText)
          .toList();

      // "8-12" → its leading number, a useful anchor the pad can produce.
      expect(hints.first, '8');
      // "bodyweight" has no number at all → a plain unit, never the word.
      expect(hints.last, 'kg');
      for (final h in hints) {
        expect(RegExp(r'^[\d.]+$').hasMatch(h!) || h == 'kg', isTrue,
            reason: 'hint "$h" is not enterable on a decimal pad');
      }

      // The full prescription still reaches the member — in the subtitle,
      // stated once, where it is a fact rather than an instruction to type.
      expect(find.textContaining('coach asked for 8-12 reps × bodyweight'),
          findsOneWidget);
    });
  });

  group('the note is the member speaking to their coach', () {
    testWidgets('it loads what was written and saves only when changed',
        (tester) async {
      final fake = await _open(tester, log: _log(memberNote: 'Shoulder tight'));
      expect(find.text('Shoulder tight'), findsOneWidget);

      // Nothing typed yet → the Save is inert rather than writing a no-op.
      final before = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Save note'),
          matching: find.byType(TextButton),
        ),
      );
      expect(before.onPressed, isNull);

      await tester.enterText(
          find.widgetWithText(TextField, 'Shoulder tight'), 'All good');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();
      expect(fake.noteWrites, ['All good']);
    });

    testWidgets('a note the member thinks better of can be RETRACTED',
        (tester) async {
      // ── THE DEFECT THIS PINS ────────────────────────────────────────────
      //
      // `WorkoutLogService.saveMemberNote` used to `return failed` on an empty
      // string, borrowing the guard `saveEditedEntries` carries for a real
      // destructive case. The note field enables Save on ANY keystroke,
      // deletion included — so a member who cleared their note tapped Save and
      // was told "Could not send that note — try again", at an action that
      // could never succeed no matter how many times they tried — and their
      // coach carried on reading the retracted note in TrainerHQ's
      // `member_logs_session_screen`.
      final fake = await _open(tester, log: _log(memberNote: 'Shoulder tight'));

      await tester.enterText(
          find.widgetWithText(TextField, 'Shoulder tight'), '');
      await tester.pumpAndSettle();

      // Save is live — clearing IS a change.
      final button = tester.widget<TextButton>(
        find.ancestor(
          of: find.text('Save note'),
          matching: find.byType(TextButton),
        ),
      );
      expect(button.onPressed, isNotNull);

      await tester.tap(find.text('Save note'));
      await tester.pumpAndSettle();

      // The retraction reaches the wire as an empty string — which both apps
      // already parse as "no note" and gate their rendering on.
      expect(fake.noteWrites, ['']);
      // And it is announced as a removal, not as a message sent to the coach.
      expect(find.text('Note removed.'), findsOneWidget);
      expect(find.textContaining('Could not'), findsNothing);
    });
  });

  group('an exercise skip can be undone in one tap', () {
    testWidgets('Skip then Un-skip round-trips through the wire',
        (tester) async {
      final fake = await _open(tester);
      await tester.tap(find.text('Skip'));
      await tester.pumpAndSettle();
      expect(fake.entryWrites.last.single['skipped'], isTrue);

      await tester.tap(find.text('Un-skip'));
      await tester.pumpAndSettle();
      // Absent, not `false` — the wire shape omits a skip that did not happen.
      expect(fake.entryWrites.last.single.containsKey('skipped'), isFalse);
    });
  });

  group('it survives the screens members actually have', () {
    testWidgets('2.0x text at 320dp does not overflow', (tester) async {
      await _open(tester,
          size: const Size(320, 2400), textScale: 2.0);
      expect(tester.takeException(), isNull);
    });
  });
}
