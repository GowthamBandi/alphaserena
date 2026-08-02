import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/controllers/member_controller.dart';
import 'package:alphaserena/controllers/progress_controller.dart';
import 'package:alphaserena/core/models/transformation_entry.dart';
import 'package:alphaserena/core/services/progress_log_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/client_progress_screen.dart';
import 'package:alphaserena/screens/dashboard/log_transformation_screen.dart';

/// PATROL — THE TRANSFORMATION MODULE, ON A REAL DEVICE.
///
/// ── WHAT THESE JOURNEYS CAN AND CANNOT CERTIFY ────────────────────────────
/// Phone-OTP auth is externally blocked on this Firebase project, so no member
/// session exists on the emulator (the workout suite documents the same
/// constraint). These journeys therefore drive the REAL screens through their
/// REAL code paths with the persistence boundary injected — which is exactly
/// the seam `LogTransformationScreen` already exposes for the purpose.
///
/// Certified here, on device:
///  • Every save decision the screen makes: what counts as content, what the
///    validator refuses, which writer method a correction uses, what is
///    reported back to the member, and how many times a write happens.
///  • The timeline at a realistic multi-year size, including that it is built
///    lazily rather than all at once.
///  • Reflow at 1.0/1.6 text scale, small phone, tablet width, and landscape.
///
/// NOT certified here, and deliberately not faked:
///  • A real Firestore/Storage round trip (needs a linked member) — covered by
///    the rules suite on the emulator and by the contract tests instead.
///  • Camera/gallery selection, which is a native picker no Flutter-level
///    driver can satisfy; the photo REMOVAL, replace and upload-progress paths
///    that follow selection are covered by unit tests.
void main() {
  setUpAll(() async {
    if (Firebase.apps.isEmpty) {
      try {
        await Firebase.initializeApp();
      } catch (_) {
        // The screens under test never reach Firebase — the writer is injected.
      }
    }
  });

  tearDown(Get.reset);

  Widget host(Widget child, {bool dark = true, double textScale = 1.0}) =>
      GetMaterialApp(
        debugShowCheckedModeBanner: false,
        theme: dark ? AppTheme.dark : AppTheme.light,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child,
          ),
        ),
      );

  // ══ FIXTURES ════════════════════════════════════════════════════════════

  TransformationEntry entry({
    required String id,
    required DateTime recordedAt,
    double? weightKg = 82.4,
    double? bodyFatPercent,
    Map<String, double> measurements = const {'waist': 88.2},
    Map<TransformationPose, TransformationPhoto> photos = const {},
    String? note,
    TransformationVisibility visibility = TransformationVisibility.shared,
    TransformationStatus status = TransformationStatus.complete,
    DateTime? editedAt,
  }) => TransformationEntry(
    id: id,
    clientId: 'client-1',
    adminId: 'admin-1',
    authUid: 'member-1',
    recordedAt: recordedAt,
    createdAt: recordedAt,
    updatedAt: recordedAt,
    editedAt: editedAt,
    visibility: visibility,
    status: status,
    measurementUnit: 'cm',
    weightKg: weightKg,
    bodyFatPercent: bodyFatPercent,
    measurements: measurements,
    photos: photos,
    note: note,
  );

  /// Registers the real controllers and seeds the history the screen will show.
  ///
  /// `isLinked` is set BEFORE the controller exists on purpose: its `ever`
  /// worker re-binds the (empty) live stream on any change, which would wipe
  /// the fixtures straight back out again.
  ProgressController seed(List<TransformationEntry> entries) {
    final member = Get.put(MemberController());
    member.isLoading.value = false;
    member.isLinked.value = true;
    final progress = Get.put(ProgressController());
    progress.entries.assignAll(entries);
    progress.isLoading.value = false;
    progress.selectedTab.value = 1;
    return progress;
  }

  /// Re-applies the fixture after the first frame.
  ///
  /// `MemberController` resolves a real session in the background and finds
  /// none here, and `ProgressController` re-binds its (empty) live stream
  /// whenever `isLinked` changes — which lands after the first pump and clears
  /// the seed. Re-applying is the harness working around the absence of a
  /// member session, not the screen behaving differently.
  Future<void> showHistory(
    PatrolIntegrationTester $,
    List<TransformationEntry> entries, {
    double textScale = 1.0,
  }) async {
    final progress = seed(entries);
    await $.pumpWidgetAndSettle(
      host(const ClientProgressScreen(), textScale: textScale),
    );
    Get.find<MemberController>()
      ..isLoading.value = false
      ..isLinked.value = true;
    progress.entries.assignAll(entries);
    progress.isLoading.value = false;
    progress.selectedTab.value = 1;
    await $.pumpAndSettle();
  }

  List<TransformationEntry> history(int count) => [
    for (var i = 0; i < count; i++)
      entry(
        id: 'record-$i',
        recordedAt: DateTime(2026, 1, 1).subtract(Duration(days: i * 7)),
        weightKg: 82.4 - (i * 0.1),
        measurements: {'waist': 88.2 - (i * 0.1)},
        photos: const {
          TransformationPose.front: TransformationPhoto(
            url: 'https://example.invalid/front.jpg',
            storagePath: 'progress_photos/member-1/transformations/x/front.jpg',
          ),
        },
      ),
  ];

  // ══ 1. LOGGING — WHAT COUNTS, WHAT IS REFUSED ═══════════════════════════

  patrolTest('the check-in offers every section and requires none of them', (
    $,
  ) async {
    await $.pumpWidgetAndSettle(
      host(LogTransformationScreen(service: _Writer())),
    );

    expect($("Today's check-in"), findsOneWidget);
    expect($('Measurements'), findsOneWidget);
    expect($('Progress photos'), findsOneWidget);
    expect($('Notes'), findsOneWidget);
    expect($('Privacy'), findsOneWidget);
    // Nothing entered yet: the member is told what is missing, not just blocked.
    expect($('Add one item to continue'), findsOneWidget);
  });

  patrolTest('an empty check-in cannot be published', ($) async {
    final writer = _Writer();
    await $.pumpWidgetAndSettle(
      host(
        LogTransformationScreen(
          service: writer,
          offlineCheck: () async => false,
        ),
      ),
    );

    await $('SAVE CHECK-IN').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pump();

    expect(writer.finalizeCalls, 0);
  });

  patrolTest('content alone is not enough — privacy is an explicit choice', (
    $,
  ) async {
    final writer = _Writer();
    await $.pumpWidgetAndSettle(
      host(
        LogTransformationScreen(
          service: writer,
          offlineCheck: () async => false,
        ),
      ),
    );

    await $(const ValueKey('transformation_weight')).enterText('80');
    await $.pumpAndSettle();

    // A check-in that reaches a coach must never do so by default.
    expect($('Choose a privacy option to continue'), findsOneWidget);
    await $('SAVE CHECK-IN').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pump();
    expect(writer.finalizeCalls, 0);
  });

  patrolTest('a measurements-only check-in publishes once and reports back', (
    $,
  ) async {
    final writer = _Writer();
    var saved = 0;
    await $.pumpWidgetAndSettle(
      host(
        LogTransformationScreen(
          service: writer,
          onSaved: () => saved++,
          offlineCheck: () async => false,
        ),
      ),
    );

    await $(const ValueKey('measurement_waist')).enterText('88.2');
    await $(const ValueKey('measurement_chest')).enterText('101');
    await $.pumpAndSettle();
    await $('Shared with coach').scrollTo().tap();
    await $('SAVE CHECK-IN').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pump();

    await $.pumpAndSettle();
    expect(writer.finalizeCalls, 1);
    expect(writer.measurements['waist'], 88.2);
    expect(writer.measurements['chest'], 101.0);
    expect(writer.weightKg, isNull);
    expect(writer.visibility, TransformationVisibility.shared);
    expect(saved, 1);
    expect($('Transformation saved'), findsOneWidget);
  });

  patrolTest('a decimal weight survives the keyboard exactly as typed', (
    $,
  ) async {
    final writer = _Writer();
    await $.pumpWidgetAndSettle(
      host(
        LogTransformationScreen(
          service: writer,
          offlineCheck: () async => false,
        ),
      ),
    );

    await $(const ValueKey('transformation_weight')).enterText('72.5');
    await $.pumpAndSettle();
    await $('Only me').scrollTo().tap();
    await $('SAVE CHECK-IN').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pump();

    await $.pumpAndSettle();
    expect(writer.weightKg, 72.5);
    expect(writer.visibility, TransformationVisibility.private);
  });

  patrolTest('an out-of-range value is refused before anything is written', (
    $,
  ) async {
    final writer = _Writer();
    await $.pumpWidgetAndSettle(
      host(
        LogTransformationScreen(
          service: writer,
          offlineCheck: () async => false,
        ),
      ),
    );

    // 999.9 is the largest the field's formatter physically allows.
    await $(const ValueKey('transformation_weight')).enterText('999.9');
    await $.pumpAndSettle();
    await $('Only me').scrollTo().tap();
    await $('SAVE CHECK-IN').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pumpAndSettle();

    expect(writer.finalizeCalls, 0);
    expect($('Use 0.1–300'), findsWidgets);
  });

  patrolTest('zero is refused — it is not a measurement', ($) async {
    final writer = _Writer();
    await $.pumpWidgetAndSettle(
      host(
        LogTransformationScreen(
          service: writer,
          offlineCheck: () async => false,
        ),
      ),
    );

    await $(const ValueKey('measurement_waist')).enterText('0');
    await $.pumpAndSettle();
    await $('Only me').scrollTo().tap();
    await $('SAVE CHECK-IN').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pumpAndSettle();

    expect(writer.finalizeCalls, 0);
  });

  // ══ 2. THE WRITE ITSELF ═════════════════════════════════════════════════

  patrolTest('a rapid double tap publishes exactly one check-in', ($) async {
    final writer = _Writer();
    await $.pumpWidgetAndSettle(
      host(
        LogTransformationScreen(
          service: writer,
          offlineCheck: () async => false,
        ),
      ),
    );

    await $(const ValueKey('transformation_weight')).enterText('80');
    await $.pumpAndSettle();
    await $('Only me').scrollTo().tap();

    // Driven through the raw tester: both taps must land in the SAME frame,
    // which is the case the guard exists for. Patrol's own tap settles between
    // gestures and would never reproduce it.
    final save = find.text('SAVE CHECK-IN');
    await $.tester.tap(save, warnIfMissed: false);
    await $.tester.tap(save, warnIfMissed: false);
    await $.pump();
    await $.pumpAndSettle();

    // Two taps inside one frame both used to pass the guard, mint two record
    // ids, and publish the same check-in twice.
    expect(writer.finalizeCalls, 1);
  });

  patrolTest('a write that never reaches the server is reported as queued', (
    $,
  ) async {
    // The connectivity probe says ONLINE. A captive portal looks exactly like
    // this, and a Firestore write only ever completes on server ack — so this
    // is the case that used to spin the save button forever.
    final writer = _Writer(outcome: TransformationWriteOutcome.queued);
    await $.pumpWidgetAndSettle(
      host(
        LogTransformationScreen(
          service: writer,
          offlineCheck: () async => false,
        ),
      ),
    );

    await $(const ValueKey('transformation_weight')).enterText('80');
    await $.pumpAndSettle();
    await $('Only me').scrollTo().tap();
    await $('SAVE CHECK-IN').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pump();

    expect($('Queued safely'), findsOneWidget);
    expect($('Transformation saved'), findsNothing);
  });

  patrolTest('offline, photos are refused and nothing entered is lost', (
    $,
  ) async {
    final writer = _Writer();
    await $.pumpWidgetAndSettle(
      host(
        LogTransformationScreen(
          service: writer,
          offlineCheck: () async => true,
        ),
      ),
    );

    await $(const ValueKey('transformation_weight')).enterText('80');
    await $.pumpAndSettle();
    await $('Only me').scrollTo().tap();
    await $('SAVE CHECK-IN').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pump();

    await $.pumpAndSettle();
    // No photo was selected, so an offline metadata-only check-in still goes.
    expect(writer.finalizeCalls, 1);
  });

  // ══ 3. CORRECTING A PUBLISHED CHECKPOINT ════════════════════════════════

  patrolTest('a correction rewrites in place and never republishes', (
    $,
  ) async {
    final writer = _Writer();
    final published = entry(id: 'record-1', recordedAt: DateTime(2026, 7, 20));
    await $.pumpWidgetAndSettle(
      host(
        LogTransformationScreen(
          service: writer,
          editing: published,
          offlineCheck: () async => false,
        ),
      ),
    );

    expect($('Edit check-in'), findsOneWidget);
    await $(const ValueKey('transformation_weight')).enterText('78.1');
    await $.pumpAndSettle();
    await $('SAVE CHANGES').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pumpAndSettle();

    // finalize() would stamp a new recordedAt and move the entry in history.
    expect(writer.updateCalls, 1);
    expect(writer.finalizeCalls, 0);
    expect(writer.weightKg, 78.1);
  });

  patrolTest('a correction keeps values this editor never shows', ($) async {
    final writer = _Writer();
    final published = entry(
      id: 'record-1',
      recordedAt: DateTime(2026, 7, 20),
      bodyFatPercent: 18.4,
      // `arms` is what an older AlphaSerena build wrote. A correction replaces
      // the whole measurement map, so a key with no field was deleted by the
      // act of editing anything else on the same record.
      measurements: const {'waist': 88.2, 'arms': 35.5},
    );
    await $.pumpWidgetAndSettle(
      host(
        LogTransformationScreen(
          service: writer,
          editing: published,
          offlineCheck: () async => false,
        ),
      ),
    );

    await $('SAVE CHANGES').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pumpAndSettle();

    expect(writer.measurements['arms'], 35.5);
    expect(writer.measurements['waist'], 88.2);
    expect(writer.bodyFatPercent, 18.4);
  });

  patrolTest('a private checkpoint never quietly re-shares on reopen', (
    $,
  ) async {
    final writer = _Writer();
    await $.pumpWidgetAndSettle(
      host(
        LogTransformationScreen(
          service: writer,
          offlineCheck: () async => false,
          editing: entry(
            id: 'record-1',
            recordedAt: DateTime(2026, 7, 20),
            visibility: TransformationVisibility.private,
          ),
        ),
      ),
    );

    await $('SAVE CHANGES').tap(settlePolicy: SettlePolicy.noSettle);
    await $.pumpAndSettle();

    expect(writer.visibility, TransformationVisibility.private);
  });

  patrolTest('leaving a started check-in asks before discarding it', (
    $,
  ) async {
    await $.pumpWidgetAndSettle(
      host(LogTransformationScreen(service: _Writer())),
    );

    await $(const ValueKey('transformation_weight')).enterText('80');
    await $.pumpAndSettle();
    await $(Icons.close).tap();

    expect($('Leave this check-in?'), findsOneWidget);
    await $('Keep editing').tap();
    // The member's work is still exactly where they left it.
    expect($(TextField).which<TextField>((f) => f.controller?.text == '80'),
        findsOneWidget);
  });

  // ══ 4. THE TIMELINE, AT A REALISTIC SIZE ════════════════════════════════

  patrolTest('an empty history invites a first check-in, never shows zeroes', (
    $,
  ) async {
    await showHistory($, const []);

    expect($('Your transformation starts with evidence'), findsOneWidget);
    expect($('LOG FIRST TRANSFORMATION'), findsOneWidget);
  });

  patrolTest('a single check-in shows a snapshot and no false comparison', (
    $,
  ) async {
    await showHistory($, [entry(id: 'record-1', recordedAt: DateTime(2026, 7, 20))]);

    expect($('Latest Transformation'), findsOneWidget);
    // One checkpoint cannot be compared with anything.
    expect($('Latest vs previous'), findsNothing);
  });

  patrolTest('two check-ins compare only what both actually contain', (
    $,
  ) async {
    await showHistory($, [
      entry(
        id: 'record-2',
        recordedAt: DateTime(2026, 7, 20),
        weightKg: 80.0,
        measurements: const {'waist': 86.0},
      ),
      entry(
        id: 'record-1',
        recordedAt: DateTime(2026, 7, 13),
        weightKg: 82.0,
        // No waist here: the waist must NOT appear as a change.
        measurements: const {},
      ),
    ]);

    expect($('Latest vs previous'), findsOneWidget);
    expect($('Weight · Reduced 2.0 kg'), findsOneWidget);
    expect($(RegExp('Waist · ')), findsNothing);
  });

  patrolTest('a private checkpoint is labelled private in the timeline', (
    $,
  ) async {
    await showHistory($, [
      entry(
        id: 'record-1',
        recordedAt: DateTime(2026, 7, 20),
        visibility: TransformationVisibility.private,
      ),
    ]);

    expect($('Private'), findsWidgets);
    expect($('Shared'), findsNothing);
  });

  patrolTest('an unfinished upload is surfaced as recoverable, not as history', (
    $,
  ) async {
    await showHistory($, [
      entry(
        id: 'draft-1',
        recordedAt: DateTime(2026, 7, 20),
        status: TransformationStatus.uploading,
        visibility: TransformationVisibility.private,
      ),
    ]);

    expect($('1 unfinished upload safely hidden from your coach.'),
        findsOneWidget);
    // It is a draft, so it is not counted as a published checkpoint either.
    expect($('Your transformation starts with evidence'), findsOneWidget);
  });

  patrolTest('a three-year history is built lazily, not all at once', (
    $,
  ) async {
    await showHistory($, history(150));

    expect($('Transformation history'), findsOneWidget);
    // The whole history used to sit in ONE Column: every one of these 150
    // check-ins was laid out and every photo decoded before the member had
    // scrolled anywhere. Only what the viewport can reach may be built.
    final built = $(ExpansionTile).evaluate().length;
    expect(built, lessThan(20), reason: 'built $built of 150 timeline rows');
    expect(built, greaterThan(0));
  });

  patrolTest('a long history scrolls without breaking', ($) async {
    await showHistory($, history(150));

    for (var i = 0; i < 6; i++) {
      await $.tester.drag($(CustomScrollView), const Offset(0, -600));
      await $.pump();
    }
    await $.pumpAndSettle();

    expect($(CustomScrollView), findsOneWidget);
    expect($.tester.takeException(), isNull);
  });

  // ══ 5. REFLOW ═══════════════════════════════════════════════════════════

  patrolTest('the check-in survives large accessibility fonts', ($) async {
    await $.pumpWidgetAndSettle(
      host(LogTransformationScreen(service: _Writer()), textScale: 1.6),
    );
    expect($('Measurements'), findsOneWidget);
    expect($.tester.takeException(), isNull);
  });

  patrolTest('the check-in renders in light mode', ($) async {
    await $.pumpWidgetAndSettle(
      host(LogTransformationScreen(service: _Writer()), dark: false),
    );
    expect($('Privacy'), findsOneWidget);
    expect($.tester.takeException(), isNull);
  });

  patrolTest('the timeline survives large accessibility fonts', ($) async {
    await showHistory($, history(8), textScale: 1.6);
    expect($('Transformation history'), findsOneWidget);
    expect($.tester.takeException(), isNull);
  });
}

/// The persistence boundary, recorded rather than performed.
class _Writer implements TransformationWriter {
  _Writer({this.outcome = TransformationWriteOutcome.acknowledged});

  final TransformationWriteOutcome outcome;

  int finalizeCalls = 0;
  int updateCalls = 0;
  int draftCalls = 0;
  TransformationVisibility? visibility;
  String? note;
  double? weightKg;
  double? bodyFatPercent;
  Map<String, double> measurements = const {};
  Map<TransformationPose, TransformationPhoto> photos = const {};

  @override
  String newRecordId() => 'record-${finalizeCalls + 1}';

  @override
  Future<void> abandon(String recordId, Iterable<TransformationPhoto> photos) =>
      Future.value();

  @override
  Future<void> createUploadDraft({
    required String recordId,
    required DateTime clientRecordedAt,
  }) async {
    draftCalls++;
  }

  @override
  Future<TransformationWriteOutcome> finalize({
    required String recordId,
    required DateTime clientRecordedAt,
    required TransformationVisibility visibility,
    double? weightKg,
    double? bodyFatPercent,
    Map<String, double> measurements = const {},
    Map<TransformationPose, TransformationPhoto> photos = const {},
    String? note,
  }) async {
    finalizeCalls++;
    this.visibility = visibility;
    this.note = note;
    this.weightKg = weightKg;
    this.bodyFatPercent = bodyFatPercent;
    this.measurements = measurements;
    this.photos = photos;
    return outcome;
  }

  @override
  Future<TransformationWriteOutcome> updatePublished({
    required TransformationEntry original,
    required TransformationVisibility visibility,
    double? weightKg,
    double? bodyFatPercent,
    Map<String, double> measurements = const {},
    Map<TransformationPose, TransformationPhoto> photos = const {},
    String? note,
  }) async {
    updateCalls++;
    this.visibility = visibility;
    this.note = note;
    this.weightKg = weightKg;
    this.bodyFatPercent = bodyFatPercent;
    this.measurements = measurements;
    this.photos = photos;
    return outcome;
  }

  @override
  Future<TransformationWriteOutcome> setVisibility({
    required String recordId,
    required TransformationVisibility visibility,
  }) async {
    this.visibility = visibility;
    return outcome;
  }

  @override
  Future<void> removeDraftPose({
    required String recordId,
    required TransformationPose pose,
    required TransformationPhoto photo,
  }) => Future.value();

  @override
  Future<TransformationPhoto> uploadPose({
    required String recordId,
    required TransformationPose pose,
    required File file,
    required String filename,
    bool persistToRecord = true,
  }) async => const TransformationPhoto(url: 'url', storagePath: 'path');
}
