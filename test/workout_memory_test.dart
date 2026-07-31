import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/workout_memory.dart';

/// WORKOUT EXPERIENCE Phase 2 — EXERCISE MEMORY.
///
/// The invariant: memory reports what the member actually did, or says
/// nothing. It never averages, predicts, or carries a prescription forward
/// as if it were performance.
void main() {
  Map<String, dynamic> session({
    required String id,
    required String date,
    required List<Map<String, dynamic>> entries,
  }) => {'id': id, 'date': date, 'entries': entries};

  Map<String, dynamic> entry({
    String name = 'Bench',
    String exerciseId = 'e1',
    required List<Map<String, dynamic>> sets,
  }) => {'exerciseName': name, 'exerciseId': exerciseId, 'sets': sets};

  Map<String, dynamic> set({
    String reps = '10',
    String weight = '40',
    bool completed = true,
  }) => {
    'actualReps': reps,
    'actualWeight': weight,
    'completed': completed,
  };

  test('reports the MOST RECENT session that actually did the exercise', () {
    final memory = buildExerciseMemory([
      session(id: 's-old', date: '2026-07-20T10:00:00', entries: [
        entry(sets: [set(weight: '30')]),
      ]),
      session(id: 's-new', date: '2026-07-26T10:00:00', entries: [
        entry(sets: [set(weight: '45'), set(weight: '45')]),
      ]),
    ]);
    final m = memory[exerciseMemoryKey('e1', 'Bench')]!;
    expect(m.setCount, 2);
    expect(m.topWeight, '45');
    expect(m.date.day, 26);
  });

  test('a session where nothing was COMPLETED is not "last time"', () {
    final memory = buildExerciseMemory([
      session(id: 's-new', date: '2026-07-26T10:00:00', entries: [
        entry(sets: [set(completed: false), set(completed: false)]),
      ]),
      session(id: 's-old', date: '2026-07-20T10:00:00', entries: [
        entry(sets: [set(weight: '30')]),
      ]),
    ]);
    expect(memory[exerciseMemoryKey('e1', 'Bench')]!.topWeight, '30');
  });

  test('today\'s own session is excluded — it cannot be its own memory', () {
    final memory = buildExerciseMemory(
      [
        session(id: 'today', date: '2026-07-28T10:00:00', entries: [
          entry(sets: [set(weight: '99')]),
        ]),
        session(id: 'prev', date: '2026-07-25T10:00:00', entries: [
          entry(sets: [set(weight: '40')]),
        ]),
      ],
      excludeId: 'today',
    );
    expect(memory[exerciseMemoryKey('e1', 'Bench')]!.topWeight, '40');
  });

  test('the heaviest completed set is the one reported', () {
    final memory = buildExerciseMemory([
      session(id: 's1', date: '2026-07-26T10:00:00', entries: [
        entry(sets: [
          set(reps: '12', weight: '30'),
          set(reps: '8', weight: '50'),
          set(reps: '10', weight: '40'),
        ]),
      ]),
    ]);
    final m = memory[exerciseMemoryKey('e1', 'Bench')]!;
    expect(m.topWeight, '50');
    expect(m.topReps, '8');
    expect(m.setCount, 3);
    expect(m.summary, '3 sets · top 8 × 50kg');
  });

  test('bodyweight work falls back to the longest set, never invents load', () {
    final memory = buildExerciseMemory([
      session(id: 's1', date: '2026-07-26T10:00:00', entries: [
        entry(name: 'Push-ups', exerciseId: '', sets: [
          set(reps: '15', weight: ''),
          set(reps: '22', weight: ''),
        ]),
      ]),
    ]);
    final m = memory[exerciseMemoryKey('', 'Push-ups')]!;
    expect(m.topReps, '22');
    expect(m.topWeight, '');
    expect(m.summary, '2 sets · top 22');
  });

  test('identity is exerciseId-first so a rename keeps its history', () {
    expect(exerciseMemoryKey('e1', 'Bench Press'),
        exerciseMemoryKey('e1', 'Barbell Bench'));
    // Freehand items fall back to a normalised name.
    expect(exerciseMemoryKey('', 'Push-Ups'), exerciseMemoryKey('', 'push-ups'));
    expect(exerciseMemoryKey('', 'Rows'), isNot(exerciseMemoryKey('e1', 'Rows')));
  });

  test('no history at all → no memory, and nothing invented', () {
    expect(buildExerciseMemory(const []), isEmpty);
    expect(
      buildExerciseMemory([
        session(id: 's1', date: 'junk-date', entries: [
          entry(sets: [set()]),
        ]),
      ]),
      isEmpty,
    );
  });

  test('relative dates stay honest as they age', () {
    final today = DateTime(2026, 7, 28);
    ExerciseMemory at(String d) => buildExerciseMemory([
          session(id: 's', date: d, entries: [
            entry(sets: [set()]),
          ]),
        ])[exerciseMemoryKey('e1', 'Bench')]!;
    expect(at('2026-07-27T10:00:00').ago(today), 'yesterday');
    expect(at('2026-07-25T10:00:00').ago(today), '3 days ago');
    expect(at('2026-07-01T10:00:00').ago(today), 'on 1 Jul');
  });
}
