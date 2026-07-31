import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/prescription.dart'
    show ExpectationKind, RhythmType;
import 'package:alphaserena/core/domain/today_expectation.dart';

/// PRESCRIPTION ENGINE — Phase 3: the member app as a READER of the served
/// expectation. Under test: parsing never invents, the presentation matrix
/// covers every state, and the legacy path (no expectation served) renders
/// the pre-Phase-3 UI exactly.
void main() {
  Map<String, dynamic> served({
    String kind = 'required',
    String reason = 'rhythm',
    String note = '',
    bool prescribed = true,
    Map<String, dynamic>? rhythm,
    bool excusedToday = false,
  }) => {
    'kind': kind,
    'reason': reason,
    'note': note,
    'prescribed': prescribed,
    'rhythm': rhythm,
    'excusedToday': excusedToday,
  };

  group('parsing — nothing is ever invented', () {
    test('a full response parses both tracks and the date', () {
      final t = TodayExpectations.fromResponse({
        'workout': {'name': 'Push'},
        'expectation': {
          'date': '2026-07-28',
          'workout': served(kind: 'rest', reason: 'travel', note: 'Goa'),
          'diet': served(kind: 'required'),
        },
      });
      expect(t, isNotNull);
      expect(t!.date, '2026-07-28');
      expect(t.workout!.kind, ExpectationKind.rest);
      expect(t.workout!.reason, 'travel');
      expect(t.workout!.note, 'Goa');
      expect(t.diet!.kind, ExpectationKind.required);
    });

    test('a legacy response (no expectation field) parses to NULL', () {
      // The deploy-order guarantee: an old backend must leave the app exactly
      // as it was — null, never a fabricated `unknown`.
      expect(TodayExpectations.fromResponse({'workout': null}), isNull);
      expect(TodayExpectations.fromResponse(null), isNull);
      expect(TodayExpectations.fromResponse('garbage'), isNull);
    });

    test('an unreadable kind parses to null, not a default', () {
      expect(ServedExpectation.fromMap(served(kind: 'vacation?')), isNull);
      expect(ServedExpectation.fromMap('junk'), isNull);
      expect(ServedExpectation.fromMap(null), isNull);
    });

    test('the frequency rhythm summary is carried for phrasing', () {
      final e = ServedExpectation.fromMap(served(
        kind: 'optional',
        reason: 'frequency',
        rhythm: {'type': 'frequency', 'count': 4},
      ));
      expect(e!.rhythmType, RhythmType.frequency);
      expect(e.frequencyCount, 4);
    });
  });

  group('presentation matrix — every state has decided words', () {
    ServedExpectation e(
      String kind, {
      String reason = 'rhythm',
      String note = '',
      Map<String, dynamic>? rhythm,
      bool excusedToday = false,
    }) => ServedExpectation.fromMap(served(
      kind: kind,
      reason: reason,
      note: note,
      rhythm: rhythm,
      excusedToday: excusedToday,
    ))!;

    TodayWorkoutPresentation pres(
      ServedExpectation? exp, {
      bool hasPlan = true,
      bool doneToday = false,
      int doneThisWeek = 0,
    }) => todayWorkoutPresentation(
      expectation: exp,
      hasPlan: hasPlan,
      doneToday: doneToday,
      doneThisWeek: doneThisWeek,
      coachName: 'Priya',
    );

    test('no expectation (legacy) renders the legacy modes exactly', () {
      expect(pres(null).mode, TodayWorkoutMode.training);
      expect(pres(null).disclosure, '');
      expect(pres(null, hasPlan: false).mode, TodayWorkoutMode.waiting);
    });

    test('required day is the training card', () {
      final r = pres(e('required'));
      expect(r.mode, TodayWorkoutMode.training);
      expect(r.showContent, isTrue);
      expect(r.cta, 'Start Full Workout');
    });

    test('rest day is a POSITIVE state with the coach named', () {
      final r = pres(e('rest'));
      expect(r.mode, TodayWorkoutMode.rest);
      expect(r.body, contains('Priya'));
      expect(r.trainAnyway, isTrue); // bonus, never owed
      expect(r.cta, ''); // no primary CTA pressure
    });

    test('rest day already trained reads as a bonus, not a demand', () {
      final r = pres(e('rest'), doneToday: true);
      expect(r.title, contains('trained anyway'));
      expect(r.trainAnyway, isFalse);
    });

    test('exception reasons surface as chips with the coach note', () {
      expect(pres(e('rest', reason: 'travel')).chip, 'Travel');
      expect(pres(e('rest', reason: 'deload')).chip, 'Deload week');
      expect(
        pres(e('rest', reason: 'travel', note: 'Enjoy Goa!')).body,
        'Enjoy Goa!',
      );
    });

    test('flexible week frames the WEEK, never the day', () {
      final r = pres(
        e('optional', reason: 'frequency',
            rhythm: {'type': 'frequency', 'count': 4}),
        doneThisWeek: 2,
      );
      expect(r.mode, TodayWorkoutMode.flexible);
      expect(r.chip, 'Any 4 × / week');
      expect(r.body, contains('2 of 4'));
      expect(r.cta, 'Start a Session');
    });

    test('a completed flexible week celebrates and stays open', () {
      final r = pres(
        e('optional', reason: 'frequency',
            rhythm: {'type': 'frequency', 'count': 4}),
        doneThisWeek: 5, // 5 of 4 — capped, never >100%
      );
      expect(r.body, contains('all 4'));
      expect(r.cta, 'Start a Session'); // more is bonus, not blocked
    });

    test('excused today outranks everything', () {
      final r = pres(e('required', excusedToday: true));
      expect(r.mode, TodayWorkoutMode.excused);
      expect(r.body, contains('won\'t count against you'));
      expect(r.cta, '');
    });

    test('paused has no CTA and protects the streak in words', () {
      final r = pres(e('paused', reason: 'medical'));
      expect(r.mode, TodayWorkoutMode.paused);
      expect(r.chip, 'Medical leave');
      expect(r.cta, '');
      expect(r.trainAnyway, isFalse);
      expect(r.body, contains('streak is safe'));
    });

    test('notYetStarted and ended say so plainly', () {
      expect(pres(e('notYetStarted')).mode, TodayWorkoutMode.notYetStarted);
      final ended = pres(e('ended'));
      expect(ended.mode, TodayWorkoutMode.ended);
      expect(ended.body, contains('Priya'));
    });

    test('unknown WITH a plan is the legacy card PLUS the disclosure', () {
      final r = pres(e('unknown', reason: ''));
      expect(r.mode, TodayWorkoutMode.unknownDisclosed);
      expect(r.showContent, isTrue);
      expect(r.disclosure, contains('No schedule set'));
    });

    test('unknown with NO plan is waiting — and never discloses a schedule',
        () {
      final r = pres(e('unknown', reason: ''), hasPlan: false);
      expect(r.mode, TodayWorkoutMode.waiting);
      expect(r.disclosure, '');
    });

    test('the coach note always wins over generated copy', () {
      expect(pres(e('paused', note: 'Back after Diwali')).body,
          'Back after Diwali');
      expect(pres(e('rest', note: 'Stretch 10 min')).body, 'Stretch 10 min');
    });
  });

  group('sessionsThisWeek — counts what HAPPENED, Monday-based', () {
    test('counts only the current week up to today', () {
      // Wed 4 Mar 2026. Week = Mon 2 Mar .. Sun 8 Mar.
      final now = DateTime(2026, 3, 4);
      final logged = {
        '2026-03-02', // Mon — counts
        '2026-03-03', // Tue — counts
        '2026-03-01', // last Sunday — previous week
        '2026-02-25', // long past
        '2026-03-06', // future within week — not lived yet, ignored
      };
      expect(sessionsThisWeek(logged, now), 2);
    });

    test('null and empty are 0, never a guess', () {
      expect(sessionsThisWeek(null, DateTime(2026, 3, 4)), 0);
      expect(sessionsThisWeek({}, DateTime(2026, 3, 4)), 0);
    });
  });

  group('workoutNotExpectedToday — the "Pending today" guard', () {
    ServedExpectation e(String kind, {bool excused = false}) =>
        ServedExpectation.fromMap(
            served(kind: kind, excusedToday: excused))!;

    test('rest / paused / optional / excused suppress the chase state', () {
      expect(workoutNotExpectedToday(e('rest')), isTrue);
      expect(workoutNotExpectedToday(e('paused')), isTrue);
      expect(workoutNotExpectedToday(e('optional')), isTrue);
      expect(workoutNotExpectedToday(e('notYetStarted')), isTrue);
      expect(workoutNotExpectedToday(e('ended')), isTrue);
      expect(workoutNotExpectedToday(e('required', excused: true)), isTrue);
    });

    test('required, unknown and legacy keep todays behaviour', () {
      expect(workoutNotExpectedToday(e('required')), isFalse);
      expect(workoutNotExpectedToday(e('unknown')), isFalse);
      expect(workoutNotExpectedToday(null), isFalse);
    });
  });

  group('nutrition note — quiet by design', () {
    ServedExpectation e(String kind, {String note = ''}) =>
        ServedExpectation.fromMap(served(kind: kind, note: note))!;

    test('paused and optional speak; everything else stays silent', () {
      expect(nutritionExpectationNote(e('paused')), contains('paused'));
      expect(nutritionExpectationNote(e('optional')), contains('optional'));
      expect(nutritionExpectationNote(e('optional', note: 'Refeed day')),
          'Refeed day');
      expect(nutritionExpectationNote(e('required')), '');
      expect(nutritionExpectationNote(e('unknown')), '');
      expect(nutritionExpectationNote(null), '');
    });
  });
}
