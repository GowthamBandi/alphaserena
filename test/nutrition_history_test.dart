import 'package:flutter_test/flutter_test.dart';

import 'package:alphaserena/core/domain/nutrition_history.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';

/// NUTRITION HISTORY — the pure domain.
///
/// Every test here pins an HONESTY rule, not a layout — the same discipline
/// `workout_history_test.dart` applies to the other half of My Plans:
///
///  • a past day is NEVER judged against today's target,
///  • today is never called short before it has ended,
///  • an unlogged day and an unreadable one are different facts,
///  • a figure nobody recorded is absent rather than zero,
///  • and a meal nobody ate does not occupy a row.

FoodEntry _entry(
  String name, {
  String meal = 'lunch',
  double kcal = 300,
  double protein = 20,
  double carbs = 30,
  double fat = 10,
  double fiber = 4,
  int? loggedAt,
  bool deleted = false,
  double? quantity = 1,
  String unit = 'katori',
}) =>
    FoodEntry(
      entryId: name.toLowerCase().replaceAll(' ', '_'),
      foodName: name,
      mealSlot: meal,
      quantity: quantity,
      unit: unit,
      loggedAt: loggedAt,
      deleted: deleted,
      consumed: ConsumedSnapshot(
        calories: kcal,
        protein: protein,
        carbs: carbs,
        fat: fat,
        fiber: fiber,
      ),
    );

NutritionDayLog _log(
  DateTime date, {
  List<FoodEntry> entries = const [],
  double? calorieAdherence,
}) {
  final key = nutritionDayKey(date);
  return NutritionDayLog(
    dateKey: key,
    date: date,
    day: NutritionDayModel(
      id: 'c1_$key',
      dateKey: key,
      entries: {for (final e in entries) e.entryId: e},
      computed: calorieAdherence == null
          ? null
          : NutritionDaySummary(
              targetAdherence: {'calories': calorieAdherence},
              entryCount: entries.length,
            ),
    ),
  );
}

void main() {
  final today = DateTime(2026, 8, 4);
  final month = DateTime(2026, 8, 1);

  Map<String, NutritionDayLog> index(List<NutritionDayLog> logs) =>
      {for (final l in logs) l.dateKey: l};

  NutritionHistoryDay dayOf(List<NutritionHistoryDay> days, int d) =>
      days.firstWhere((x) => x.date.day == d);

  group('the calendar spine is the month, not the documents', () {
    test('every day of the month is present, and only that month', () {
      final days = composeNutritionMonth(
        month: month,
        logsByDay: const {},
        today: today,
      );
      expect(days, hasLength(31));
      expect(days.first.date, DateTime(2026, 8, 1));
      expect(days.last.date, DateTime(2026, 8, 31));
      expect(days.every((d) => d.date.month == 8), isTrue);
    });

    test('February in a leap year is 29 days', () {
      // A month built by counting rather than by a table, so the calendar
      // cannot be one cell short every four years.
      expect(daysInMonth(DateTime(2028, 2, 1)), hasLength(29));
      expect(daysInMonth(DateTime(2026, 2, 1)), hasLength(28));
    });
  });

  group('the five states, and what each one refuses to claim', () {
    test('a day with food is LOGGED', () {
      final days = composeNutritionMonth(
        month: month,
        logsByDay: index([_log(DateTime(2026, 8, 2), entries: [_entry('Rice')])]),
        today: today,
      );
      expect(dayOf(days, 2).state, NutritionDayState.logged);
      expect(dayOf(days, 2).isOpenable, isTrue);
    });

    test('a PAST day with nothing is empty, and cannot be opened', () {
      final days = composeNutritionMonth(
        month: month,
        logsByDay: const {},
        today: today,
      );
      expect(dayOf(days, 2).state, NutritionDayState.empty);
      // A cell that responds with an empty panel is worse than one that does
      // not respond.
      expect(dayOf(days, 2).isOpenable, isFalse);
    });

    test('TODAY with nothing is open, NOT empty', () {
      final days = composeNutritionMonth(
        month: month,
        logsByDay: const {},
        today: today,
      );
      // "Nothing recorded yet" is a different claim from "nothing recorded",
      // and a calendar that marks a member empty over breakfast is judging a
      // day that has not happened.
      expect(dayOf(days, 4).state, NutritionDayState.today);
    });

    test('tomorrow is future, and is never selectable', () {
      final days = composeNutritionMonth(
        month: month,
        logsByDay: const {},
        today: today,
      );
      expect(dayOf(days, 5).state, NutritionDayState.future);
      expect(dayOf(days, 31).state, NutritionDayState.future);
      expect(dayOf(days, 5).isOpenable, isFalse);
    });

    test('a day whose OWN adherence fell short is PARTIAL', () {
      final days = composeNutritionMonth(
        month: month,
        logsByDay: index([
          _log(DateTime(2026, 8, 2),
              entries: [_entry('Rice')], calorieAdherence: 0.62),
        ]),
        today: today,
      );
      expect(dayOf(days, 2).state, NutritionDayState.partial);
      // Still openable — partial is a description of the day, not a reason to
      // withhold it.
      expect(dayOf(days, 2).isOpenable, isTrue);
    });

    test('adherence of exactly 1.0 is LOGGED, never partial', () {
      final days = composeNutritionMonth(
        month: month,
        logsByDay: index([
          _log(DateTime(2026, 8, 2),
              entries: [_entry('Rice')], calorieAdherence: 1.0),
        ]),
        today: today,
      );
      expect(dayOf(days, 2).state, NutritionDayState.logged);
    });
  });

  group('a past day is NEVER judged against today\'s target', () {
    test('NO frozen adherence → logged, never partial', () {
      // THE RULE THIS WHOLE FILE EXISTS FOR. The obvious shortcut — score a
      // past day against the target the coach has set NOW — silently relabels
      // months of a member's record every time that target changes. So a day
      // the server never scored is simply a day the member ate on.
      final days = composeNutritionMonth(
        month: month,
        logsByDay: index([
          _log(DateTime(2026, 8, 2), entries: [_entry('Rice', kcal: 120)]),
        ]),
        today: today,
      );
      expect(dayOf(days, 2).state, NutritionDayState.logged);
      expect(dayOf(days, 2).log!.calorieAdherence, isNull);
    });

    test('TODAY is never called short, however little is logged so far', () {
      // A daily total cannot be behind before the day is over. Marking a member
      // partial at breakfast would be the calendar scolding them for not having
      // eaten dinner yet — Home already answers "am I on track right now?".
      final days = composeNutritionMonth(
        month: month,
        logsByDay: index([
          _log(today, entries: [_entry('Toast')], calorieAdherence: 0.08),
        ]),
        today: today,
      );
      expect(dayOf(days, 4).state, NutritionDayState.logged);
    });
  });

  group('what the day says it contains', () {
    test('a soft-deleted entry is not part of what the member ate', () {
      final log = _log(
        DateTime(2026, 8, 2),
        entries: [
          _entry('Rice', kcal: 300),
          _entry('Cake', kcal: 500, deleted: true),
        ],
      );
      expect(log.entryCount, 1);
      expect(log.calories, 300);
      expect(log.hasEntries, isTrue);
    });

    test('a day whose only entries are deleted has NOTHING in it', () {
      final log = _log(
        DateTime(2026, 8, 2),
        entries: [_entry('Cake', deleted: true)],
      );
      expect(log.hasEntries, isFalse);
      final days = composeNutritionMonth(
        month: month,
        logsByDay: index([log]),
        today: today,
      );
      // The document exists; the day does not. An emptied day must read as
      // empty rather than as a day with an unopenable panel behind it.
      expect(dayOf(days, 2).state, NutritionDayState.empty);
      expect(dayOf(days, 2).isOpenable, isFalse);
    });

    test('macros are summed from the FROZEN snapshots, every one of them', () {
      final log = _log(DateTime(2026, 8, 2), entries: [
        _entry('A', kcal: 300, protein: 20, carbs: 30, fat: 10, fiber: 4),
        _entry('B', kcal: 250, protein: 12, carbs: 25, fat: 8, fiber: 3),
      ]);
      expect(log.calories, 550);
      expect(log.protein, 32);
      expect(log.carbs, 55);
      expect(log.fat, 18);
      expect(log.fiber, 7);
    });
  });

  group('meals are a sequence of what was eaten, not a six-row form', () {
    test('only meals with food render, in canonical slot order', () {
      final log = _log(DateTime(2026, 8, 2), entries: [
        _entry('Dinner Dal', meal: 'dinner'),
        _entry('Oats', meal: 'breakfast'),
        _entry('Rice', meal: 'lunch'),
      ]);
      // Breakfast → Lunch → Dinner, and NOT the three slots nobody ate in.
      expect(log.meals.map((m) => m.slot), ['breakfast', 'lunch', 'dinner']);
      expect(log.meals.map((m) => m.label),
          ['Breakfast', 'Lunch', 'Dinner']);
      expect(log.meals, hasLength(3));
    });

    test('entries within a meal are ordered by when they were EATEN', () {
      final log = _log(DateTime(2026, 8, 2), entries: [
        _entry('Second', meal: 'lunch', loggedAt: 2000),
        _entry('First', meal: 'lunch', loggedAt: 1000),
      ]);
      expect(log.meals.single.entries.map((e) => e.foodName),
          ['First', 'Second']);
    });

    test('a meal totals only its own food', () {
      final log = _log(DateTime(2026, 8, 2), entries: [
        _entry('Oats', meal: 'breakfast', kcal: 200, protein: 8),
        _entry('Rice', meal: 'lunch', kcal: 400, protein: 10),
      ]);
      final breakfast = log.meals.first;
      expect(breakfast.calories, 200);
      expect(breakfast.protein, 8);
      expect(log.calories, 600);
    });

    test('a meal time is the EARLIEST entry in it', () {
      final log = _log(DateTime(2026, 8, 2), entries: [
        _entry('Late', meal: 'lunch', loggedAt: 5000),
        _entry('Early', meal: 'lunch', loggedAt: 1000),
      ]);
      expect(log.meals.single.time,
          DateTime.fromMillisecondsSinceEpoch(1000));
    });

    test('NO time is stated when no entry carried one', () {
      // Never the document's write time — a different fact, which would move
      // every time an entry was corrected.
      final log = _log(DateTime(2026, 8, 2),
          entries: [_entry('Rice', meal: 'lunch')]);
      expect(log.meals.single.time, isNull);
    });

    test('`other` sorts last rather than being dropped', () {
      final log = _log(DateTime(2026, 8, 2), entries: [
        _entry('Mystery', meal: kOtherMealSlot),
        _entry('Oats', meal: 'breakfast'),
      ]);
      // Losing a member's food because the app cannot place it is not an
      // option; it goes at the end.
      expect(log.meals.map((m) => m.slot), ['breakfast', kOtherMealSlot]);
    });
  });

  group('the month summary never flatters and never fabricates', () {
    test('days logged counts DAYS WITH FOOD, not documents', () {
      final s = summariseNutritionMonth(composeNutritionMonth(
        month: month,
        logsByDay: index([
          _log(DateTime(2026, 8, 1), entries: [_entry('A', kcal: 400)]),
          _log(DateTime(2026, 8, 2), entries: [_entry('B', kcal: 600)]),
          // Emptied: a document, but not a day the member logged.
          _log(DateTime(2026, 8, 3),
              entries: [_entry('C', deleted: true)]),
        ]),
        today: today,
      ));
      expect(s.daysLogged, 2);
      expect(s.entryCount, 2);
      expect(s.calories, 1000);
    });

    test('the average is over LOGGED days, never over the month', () {
      // Dividing by 31 would report a member who logged a perfect week as
      // eating 400 kcal a day.
      final s = summariseNutritionMonth(composeNutritionMonth(
        month: month,
        logsByDay: index([
          _log(DateTime(2026, 8, 1), entries: [_entry('A', kcal: 1000)]),
          _log(DateTime(2026, 8, 2), entries: [_entry('B', kcal: 2000)]),
        ]),
        today: today,
      ));
      expect(s.averageCalories, 1500);
    });

    test('an empty month reports NO average rather than zero', () {
      final s = summariseNutritionMonth(composeNutritionMonth(
        month: month,
        logsByDay: const {},
        today: today,
      ));
      expect(s.daysLogged, 0);
      // Null, not 0 — "you averaged 0 kcal a day" is a claim nobody made.
      expect(s.averageCalories, isNull);
    });
  });

  group('day keys', () {
    test('are zero-padded, so they sort lexicographically', () {
      expect(nutritionDayKey(DateTime(2026, 8, 4)), '2026-08-04');
      expect(nutritionDayKey(DateTime(2026, 12, 31)), '2026-12-31');
    });
  });
}
