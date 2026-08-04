import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';

import 'package:alphaserena/controllers/nutrition_history_controller.dart';
import 'package:alphaserena/core/models/nutrition_day_model.dart';
import 'package:alphaserena/core/services/nutrition_day_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/nutrition/nutrition_day_log_view.dart';
import 'package:alphaserena/screens/dashboard/nutrition/nutrition_history_screen.dart';

/// NUTRITION HISTORY — the screen.
///
/// Only ONE thing is faked: the Firestore read. Everything below it — the
/// month fetch, the selection, the landing day, the summary, the timeline, the
/// legend and the day panel — is the REAL controller and the REAL domain, so
/// these tests exercise production code rather than a mock of it. That is the
/// same discipline `workout_history_screen_test.dart` follows, and it is the
/// reason the workout module's read-path regression was catchable at all.

/// Overrides the network read and nothing else.
class _FakeDays extends NutritionDayService {
  final Map<String, NutritionDayModel> stored;
  bool fail;

  _FakeDays({Map<String, NutritionDayModel>? stored, this.fail = false})
      : stored = stored ?? {};

  @override
  bool get canLog => true;

  @override
  Future<List<NutritionDayModel>> fetchDays(List<String> dateKeys) async {
    // The real service throws when the WHOLE window is unreadable — a failure
    // to read, which must never render as "you logged nothing".
    if (fail) throw StateError('no day in the requested window could be read');
    return [
      for (final k in dateKeys)
        if (stored[k] != null) stored[k]!,
    ];
  }
}

FoodEntry _entry(
  String name, {
  String meal = 'lunch',
  double kcal = 300,
  double protein = 20,
  double carbs = 30,
  double fat = 10,
  double fiber = 4,
  int? loggedAt,
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
      consumed: ConsumedSnapshot(
        calories: kcal,
        protein: protein,
        carbs: carbs,
        fat: fat,
        fiber: fiber,
      ),
    );

String _key(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

NutritionDayModel _day(
  DateTime date, {
  List<FoodEntry> entries = const [],
  double? adherence,
}) {
  final k = _key(date);
  return NutritionDayModel(
    id: 'c1_$k',
    dateKey: k,
    entries: {for (final e in entries) e.entryId: e},
    computed: adherence == null
        ? null
        : NutritionDaySummary(
            targetAdherence: {'calories': adherence},
            entryCount: entries.length,
          ),
  );
}

Future<NutritionHistoryController> _open(
  WidgetTester tester, {
  Map<String, NutritionDayModel> stored = const {},
  bool fail = false,
  required DateTime now,
  Size size = const Size(390, 1600),
  double textScale = 1.0,
  ThemeData? theme,
}) async {
  Get.testMode = true;
  final c = NutritionHistoryController(
    service: _FakeDays(stored: Map.of(stored), fail: fail),
    now: now,
  );
  Get.put<NutritionHistoryController>(c);
  addTearDown(Get.reset);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    GetMaterialApp(
      theme: theme ?? AppTheme.dark,
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
        child: const NutritionHistoryScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return c;
}

void main() {
  final now = DateTime(2026, 8, 4);

  group('the page states what it is, and lets the member move through time',
      () {
    testWidgets('title, month and year are all on screen', (tester) async {
      await _open(tester, now: now);
      expect(find.text('Nutrition History'), findsOneWidget);
      // The pills print their micro-label in caps ("MONTH" · "August").
      expect(find.text('MONTH'), findsOneWidget);
      expect(find.text('YEAR'), findsOneWidget);
      expect(find.text('August'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
    });

    testWidgets('a future month is offered DISABLED, never hidden',
        (tester) async {
      // Hiding them reflows a 12-cell grid to however many months have
      // happened — a grid the member re-reads every time they change year.
      final c = await _open(tester, now: now);
      await tester.tap(find.text('MONTH'));
      await tester.pumpAndSettle();
      expect(find.text('Dec'), findsOneWidget);
      expect(c.isFutureMonth(2026, 12), isTrue);
      expect(c.isFutureMonth(2026, 8), isFalse);
    });

    testWidgets('the year selector offers only years with history',
        (tester) async {
      final c = await _open(tester, now: now, stored: {
        _key(DateTime(2026, 8, 2)): _day(DateTime(2026, 8, 2),
            entries: [_entry('Rice')]),
      });
      // A member who joined this month sees one year, not a decade of empty
      // ones.
      expect(c.years, [2026]);
    });

    testWidgets('choosing a month moves the selection with it', (tester) async {
      final c = await _open(tester, now: now);
      await c.showMonth(2026, 7);
      await tester.pumpAndSettle();
      expect(c.month.value.month, 7);
      // Leaving the selection in a month no longer on screen left the panel
      // describing a date nothing was highlighted for.
      expect(c.selectedDay.value.month, 7);
    });

    testWidgets('a future month cannot be selected at all', (tester) async {
      final c = await _open(tester, now: now);
      await c.showMonth(2026, 12);
      await tester.pumpAndSettle();
      expect(c.month.value.month, 8, reason: 'the month must not have moved');
    });
  });

  group('the timeline centres the day the member came to see', () {
    testWidgets('today is selected on open', (tester) async {
      final c = await _open(tester, now: now);
      expect(c.selectedDay.value, now);
      // The 4th of a 31-day month — index 3.
      expect(c.selectedIndex, 3);
    });

    testWidgets('a month without today lands on the last LOGGED day',
        (tester) async {
      final c = await _open(tester, now: now, stored: {
        _key(DateTime(2026, 7, 9)): _day(DateTime(2026, 7, 9),
            entries: [_entry('Rice')]),
        _key(DateTime(2026, 7, 22)): _day(DateTime(2026, 7, 22),
            entries: [_entry('Dal')]),
      });
      await c.showMonth(2026, 7);
      await tester.pumpAndSettle();
      // Not the 1st, and not the 31st — the most recent day they actually ate.
      expect(c.selectedDay.value, DateTime(2026, 7, 22));
    });

    testWidgets('a month with nothing in it lands on the 1st', (tester) async {
      final c = await _open(tester, now: now);
      await c.showMonth(2026, 7);
      await tester.pumpAndSettle();
      expect(c.selectedDay.value, DateTime(2026, 7, 1));
    });
  });

  group('the legend explains only the states present this month', () {
    testWidgets('a logged and a partial day are both keyed', (tester) async {
      await _open(tester, now: now, stored: {
        _key(DateTime(2026, 8, 1)): _day(DateTime(2026, 8, 1),
            entries: [_entry('Rice')], adherence: 1.0),
        _key(DateTime(2026, 8, 2)): _day(DateTime(2026, 8, 2),
            entries: [_entry('Dal')], adherence: 0.5),
      });
      expect(find.text('Logged'), findsOneWidget);
      expect(find.text('Partial'), findsOneWidget);
    });

    testWidgets('a month with nothing logged renders no legend at all',
        (tester) async {
      await _open(tester, now: now);
      await tester.pumpAndSettle();
      expect(find.text('Logged'), findsNothing);
      expect(find.text('Partial'), findsNothing);
    });
  });

  group('the month summary', () {
    testWidgets('states days, items and the average over LOGGED days',
        (tester) async {
      await _open(tester, now: now, stored: {
        _key(DateTime(2026, 8, 1)): _day(DateTime(2026, 8, 1),
            entries: [_entry('A', kcal: 1000)]),
        _key(DateTime(2026, 8, 2)): _day(DateTime(2026, 8, 2),
            entries: [_entry('B', kcal: 2000)]),
      });
      expect(find.text('Days logged'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(find.text('1500 kcal'), findsOneWidget);
    });

    testWidgets('an empty month states NO items and NO average',
        (tester) async {
      await _open(tester, now: now);
      expect(find.text('Days logged'), findsOneWidget);
      // "0 items" beside "0 days" is the same fact twice, and the second one
      // reads as a judgement.
      expect(find.text('Items'), findsNothing);
      expect(find.text('Avg / day'), findsNothing);
    });
  });

  group('tapping a day opens exactly what was logged', () {
    testWidgets('the full day — macros, meals, foods, amounts, times',
        (tester) async {
      final c = await _open(tester, now: now, stored: {
        _key(DateTime(2026, 8, 2)): _day(DateTime(2026, 8, 2), entries: [
          _entry('Oats', meal: 'breakfast', kcal: 200, protein: 8),
          _entry('Paneer Tikka',
              meal: 'lunch',
              kcal: 400,
              protein: 27,
              loggedAt: DateTime(2026, 8, 2, 13, 30).millisecondsSinceEpoch),
        ]),
      });
      c.select(DateTime(2026, 8, 2));
      await tester.pumpAndSettle();

      expect(find.byType(NutritionDayLogView), findsOneWidget);
      // The day's own totals.
      expect(find.text('600'), findsOneWidget); // calories
      expect(find.text('35 g'), findsOneWidget); // protein
      // The meal timeline, in canonical order, with per-meal totals.
      expect(find.text('Breakfast'), findsOneWidget);
      expect(find.text('Lunch'), findsOneWidget);
      // Twice each, legitimately: the meal's own total and its single food's
      // calories. They coincide ONLY because each meal holds one item — with
      // two they diverge, which is the whole reason both are shown. The same
      // coincidence the workout twin documents for a one-exercise session's
      // "2/2".
      expect(find.text('200 kcal'), findsNWidgets(2));
      expect(find.text('400 kcal'), findsNWidgets(2));
      // The foods themselves, with the amount as the Food Log formats it.
      expect(find.text('Oats'), findsOneWidget);
      expect(find.text('Paneer Tikka'), findsOneWidget);
      expect(find.text('1 katori'), findsNWidgets(2));
      // The time the member said they ATE, only where they stated one.
      expect(find.text('1:30 PM'), findsOneWidget);
    });

    testWidgets('a meal nobody ate occupies NO row', (tester) async {
      final c = await _open(tester, now: now, stored: {
        _key(DateTime(2026, 8, 2)): _day(DateTime(2026, 8, 2),
            entries: [_entry('Oats', meal: 'breakfast')]),
      });
      c.select(DateTime(2026, 8, 2));
      await tester.pumpAndSettle();
      expect(find.text('Breakfast'), findsOneWidget);
      // A six-row grid with five "—" rows is a form, not a record.
      expect(find.text('Dinner'), findsNothing);
      expect(find.text('Bedtime'), findsNothing);
    });

    testWidgets('history is READ-ONLY for a past day', (tester) async {
      final c = await _open(tester, now: now, stored: {
        _key(DateTime(2026, 8, 2)): _day(DateTime(2026, 8, 2),
            entries: [_entry('Rice')]),
      });
      c.select(DateTime(2026, 8, 2));
      await tester.pumpAndSettle();
      expect(find.byType(NutritionDayLogView), findsOneWidget);
      // The same rule Workout History applies: a record built for review must
      // not invite rewrites of days a coach has already read.
      expect(find.text('Edit Food Log'), findsNothing);
    });

    testWidgets("TODAY's log IS editable", (tester) async {
      await _open(tester, now: now, stored: {
        _key(now): _day(now, entries: [_entry('Rice')]),
      });
      expect(find.text('Edit Food Log'), findsOneWidget);
    });
  });

  group('a day with nothing on it says WHICH kind of nothing', () {
    testWidgets('today before the first meal invites, and offers the action',
        (tester) async {
      await _open(tester, now: now);
      expect(find.text('Nothing logged yet today'), findsOneWidget);
      // The one day that can still be acted on gets the action.
      expect(find.text('Log Food'), findsOneWidget);
    });

    testWidgets('a past empty day states the fact, and offers NO action',
        (tester) async {
      final c = await _open(tester, now: now);
      c.select(DateTime(2026, 8, 2));
      await tester.pumpAndSettle();
      expect(find.text('No food logged'), findsOneWidget);
      // "Log Food" three weeks ago would either write to the wrong day or do
      // nothing, and both are worse than no button.
      expect(find.text('Log Food'), findsNothing);
    });

    testWidgets('it is never a blank list', (tester) async {
      final c = await _open(tester, now: now);
      c.select(DateTime(2026, 8, 2));
      await tester.pumpAndSettle();
      // A premium empty state, with a glyph and a sentence about the MEMBER —
      // never "No data", which describes the database.
      expect(find.text('\u{1F37D}'), findsOneWidget);
      expect(find.textContaining('Nothing was recorded on this day'),
          findsOneWidget);
    });
  });

  group('honest states', () {
    testWidgets('a failed read is a network apology, never an empty history',
        (tester) async {
      await _open(tester, now: now, fail: true);
      expect(find.text("Couldn't load your history"), findsOneWidget);
      expect(find.textContaining('connection problem'), findsOneWidget);
      // "You have never logged food" is a claim about the member.
      expect(find.text('Nothing logged yet today'), findsNothing);
    });

    testWidgets('a failed month does NOT trap the member on it',
        (tester) async {
      await _open(tester, now: now, fail: true);
      // The selectors survive the error. Replacing the whole body left the
      // member with two options — retry the same failing month, or leave —
      // and removed the one they actually wanted: show me a different month.
      expect(find.text('MONTH'), findsOneWidget);
      expect(find.text('YEAR'), findsOneWidget);
      expect(find.text("Couldn't load your history"), findsOneWidget);
    });

    testWidgets('returning to a month that ALREADY read clears the error',
        (tester) async {
      Get.testMode = true;
      final service = _FakeDays(stored: {
        _key(DateTime(2026, 8, 1)):
            _day(DateTime(2026, 8, 1), entries: [_entry('Rice')]),
      });
      final c = NutritionHistoryController(service: service, now: now);
      Get.put<NutritionHistoryController>(c);
      addTearDown(Get.reset);
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        GetMaterialApp(
            theme: AppTheme.dark, home: const NutritionHistoryScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text('Days logged'), findsOneWidget);

      // July cannot be read.
      service.fail = true;
      await c.showMonth(2026, 7);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your history"), findsOneWidget);

      // Back to the August they were just reading. It is cached BECAUSE it
      // read successfully, so the apology must not follow them there — and
      // "Try again" could never have cleared it, since the cache hit returns
      // before anything is retried.
      await c.showMonth(2026, 8);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your history"), findsNothing);
      expect(find.text('Days logged'), findsOneWidget);
      expect(c.loadError.value, isFalse);
    });

    testWidgets('moving to a month that CAN be read recovers', (tester) async {
      Get.testMode = true;
      final service = _FakeDays(fail: true);
      final c = NutritionHistoryController(service: service, now: now);
      Get.put<NutritionHistoryController>(c);
      addTearDown(Get.reset);
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        GetMaterialApp(
            theme: AppTheme.dark, home: const NutritionHistoryScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your history"), findsOneWidget);

      // The member picks another month, which reads fine.
      service.fail = false;
      service.stored[_key(DateTime(2026, 7, 9))] =
          _day(DateTime(2026, 7, 9), entries: [_entry('Rice')]);
      await c.showMonth(2026, 7);
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your history"), findsNothing);
      expect(find.text('Days logged'), findsOneWidget);
    });

    testWidgets('retry after a failure recovers', (tester) async {
      Get.testMode = true;
      final service = _FakeDays(fail: true);
      final c = NutritionHistoryController(service: service, now: now);
      Get.put<NutritionHistoryController>(c);
      addTearDown(Get.reset);
      await tester.pumpWidget(
        GetMaterialApp(theme: AppTheme.dark, home: const NutritionHistoryScreen()),
      );
      await tester.pumpAndSettle();
      expect(find.text("Couldn't load your history"), findsOneWidget);

      service.fail = false;
      service.stored[_key(DateTime(2026, 8, 2))] =
          _day(DateTime(2026, 8, 2), entries: [_entry('Rice')]);
      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(find.text('Days logged'), findsOneWidget);
      expect(find.text("Couldn't load your history"), findsNothing);
    });
  });

  group('a re-read never takes the days off the screen', () {
    testWidgets('remounting refreshes QUIETLY, keeping the month visible',
        (tester) async {
      Get.testMode = true;
      final service = _FakeDays(stored: {
        _key(DateTime(2026, 8, 1)):
            _day(DateTime(2026, 8, 1), entries: [_entry('Rice')]),
      });
      final c = NutritionHistoryController(service: service, now: now);
      Get.put<NutritionHistoryController>(c);
      addTearDown(Get.reset);
      tester.view.physicalSize = const Size(390, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      Future<void> mount() async {
        await tester.pumpWidget(
          GetMaterialApp(
              theme: AppTheme.dark, home: const NutritionHistoryScreen()),
        );
        await tester.pumpAndSettle();
      }

      await mount();
      expect(find.text('Days logged'), findsOneWidget);

      // The member goes and logs lunch elsewhere, then comes back. The
      // CONTROLLER survives (Get.put keeps one per session), so without the
      // remount refresh they would be shown the month as it stood before it.
      service.stored[_key(now)] = _day(now, entries: [_entry('Dal')]);
      await tester.pumpWidget(const SizedBox.shrink());
      await mount();

      // The new day is there...
      expect(c.logsByDay.containsKey(_key(now)), isTrue);
      // ...and the refresh never fell back to the first-load skeleton, which
      // would have replaced days the member was already reading.
      expect(c.isLoading.value, isFalse);
      expect(find.text('Days logged'), findsOneWidget);
    });

    testWidgets('a cold load DOES show the skeleton', (tester) async {
      // The flag still means what it says on a genuine first load — the
      // separation is the point, not the suppression.
      Get.testMode = true;
      final c = NutritionHistoryController(service: _FakeDays(), now: now);
      expect(c.isLoading.value, isTrue);
      expect(c.isRefreshing.value, isFalse);
      Get.put<NutritionHistoryController>(c);
      addTearDown(Get.reset);
    });
  });

  group('it survives the screens members actually have', () {
    testWidgets('2.0x text at 320dp does not overflow', (tester) async {
      final c = await _open(
        tester,
        now: now,
        stored: {
          _key(DateTime(2026, 8, 2)): _day(DateTime(2026, 8, 2), entries: [
            _entry('Paneer Tikka Masala', meal: 'lunch'),
            _entry('Whole Wheat Chapati', meal: 'dinner'),
          ]),
        },
        size: const Size(320, 3000),
        textScale: 2.0,
      );
      c.select(DateTime(2026, 8, 2));
      await tester.pumpAndSettle();
      // The workout twin shipped a flat-height strip that clipped every cell
      // at this exact size; this one derives its height from the same styles.
      expect(tester.takeException(), isNull);
    });

    testWidgets('light theme renders', (tester) async {
      await _open(tester, now: now, theme: AppTheme.light, stored: {
        _key(DateTime(2026, 8, 2)): _day(DateTime(2026, 8, 2),
            entries: [_entry('Rice')]),
      });
      expect(tester.takeException(), isNull);
    });
  });
}
