import 'dart:io';

import 'package:alphaserena/core/models/transformation_entry.dart';
import 'package:alphaserena/core/services/progress_log_service.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/log_transformation_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeWriter implements TransformationWriter {
  _FakeWriter({this.outcome = TransformationWriteOutcome.acknowledged});

  /// What the write reports back. `queued` is what a REAL Firestore write does
  /// with no reachable server: it is stored locally and never acknowledged.
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
  String newRecordId() => 'record-1';

  @override
  Future<void> abandon(
    String recordId,
    Iterable<TransformationPhoto> photos,
  ) async {}

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
  }) async {}

  @override
  Future<TransformationPhoto> uploadPose({
    required String recordId,
    required TransformationPose pose,
    required File file,
    required String filename,
    bool persistToRecord = true,
  }) async => const TransformationPhoto(url: 'url', storagePath: 'path');
}

Future<void> _pump(
  WidgetTester tester, {
  required Size size,
  double textScale = 1,
  _FakeWriter? writer,
  bool offline = false,
  bool dark = true,
  VoidCallback? onSaved,
  TransformationEntry? editing,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      theme: dark ? AppTheme.dark : AppTheme.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: LogTransformationScreen(
        service: writer ?? _FakeWriter(),
        offlineCheck: () async => offline,
        onSaved: onSaved,
        editing: editing,
      ),
    ),
  );
  await tester.pump();
}

TransformationEntry _published({
  double? weightKg = 82.4,
  double? bodyFatPercent,
  Map<String, double> measurements = const {'waist': 88.2},
  String? note = 'felt strong',
  TransformationVisibility visibility = TransformationVisibility.shared,
}) => TransformationEntry(
  id: 'record-1',
  clientId: 'client-1',
  adminId: 'admin-1',
  authUid: 'member-1',
  recordedAt: DateTime.utc(2026, 7, 20, 8),
  createdAt: DateTime.utc(2026, 7, 20, 8),
  updatedAt: DateTime.utc(2026, 7, 20, 8),
  visibility: visibility,
  status: TransformationStatus.complete,
  measurementUnit: 'cm',
  weightKg: weightKg,
  bodyFatPercent: bodyFatPercent,
  measurements: measurements,
  photos: const {},
  note: note,
);

void main() {
  testWidgets('premium flow exposes every section and large photo slots', (
    tester,
  ) async {
    await _pump(tester, size: const Size(390, 844));

    expect(find.text("Today's check-in"), findsOneWidget);
    expect(find.text('Weight'), findsWidgets);
    expect(find.text('Measurements'), findsOneWidget);
    expect(find.text('Progress photos'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
    expect(find.text('Privacy'), findsOneWidget);
    expect(find.text('Save Check-in'.toUpperCase()), findsOneWidget);

    final front = tester.getSize(find.text('Front').first);
    expect(front.height, greaterThan(10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('large text and landscape reflow without RenderFlex errors', (
    tester,
  ) async {
    await _pump(tester, size: const Size(800, 360), textScale: 1.8);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CustomScrollView), findsOneWidget);
  });

  testWidgets('small phone and light tablet remain usable', (tester) async {
    await _pump(tester, size: const Size(320, 700), textScale: 1.6);
    expect(tester.takeException(), isNull);

    await _pump(tester, size: const Size(1024, 768), dark: false);
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('offline measurements-only check-in queues once', (tester) async {
    // A real Firestore write with no reachable server never acknowledges; it is
    // stored locally and syncs later. The fake reports what that genuinely does.
    final writer = _FakeWriter(outcome: TransformationWriteOutcome.queued);
    var savedCalls = 0;
    await _pump(
      tester,
      size: const Size(390, 844),
      writer: writer,
      offline: true,
      onSaved: () => savedCalls++,
    );

    await tester.enterText(
      find.byKey(const ValueKey('transformation_weight')),
      '72.5',
    );
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Only me'));
    await tester.pump();
    await tester.tap(find.text('SAVE CHECK-IN'));
    await tester.pump();

    expect(writer.finalizeCalls, 1);
    expect(savedCalls, 1);
    expect(writer.visibility, TransformationVisibility.private);
    expect(find.text('Queued safely'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('a double tap on Save publishes exactly one check-in', (
    tester,
  ) async {
    final writer = _FakeWriter();
    await _pump(tester, size: const Size(390, 844), writer: writer);

    await tester.enterText(
      find.byKey(const ValueKey('transformation_weight')),
      '72.5',
    );
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Only me'));
    await tester.pump();

    // Both taps land before the button can rebuild disabled. The guard used to
    // check only `_saving`, which is set AFTER the awaited connection probe —
    // so the second tap minted a second record id and published twice.
    final save = find.text('SAVE CHECK-IN');
    await tester.tap(save, warnIfMissed: false);
    await tester.tap(save, warnIfMissed: false);
    await tester.pump();
    await tester.pumpAndSettle();

    expect(writer.finalizeCalls, 1);
    expect(writer.draftCalls, 0);
  });

  testWidgets('a write that never reaches the server is reported as queued', (
    tester,
  ) async {
    // The connection probe says ONLINE — a captive portal or a dead router
    // looks exactly like this. The old screen reported "Transformation saved"
    // off that probe while awaiting an acknowledgement that never came.
    final writer = _FakeWriter(outcome: TransformationWriteOutcome.queued);
    await _pump(
      tester,
      size: const Size(390, 844),
      writer: writer,
      offline: false,
    );

    await tester.enterText(
      find.byKey(const ValueKey('transformation_weight')),
      '80',
    );
    for (var i = 0; i < 5; i++) {
      await tester.drag(find.byType(CustomScrollView), const Offset(0, -500));
      await tester.pumpAndSettle();
    }
    await tester.tap(find.text('Shared with coach'));
    await tester.pump();
    await tester.tap(find.text('SAVE CHECK-IN'));
    await tester.pump();

    expect(find.text('Queued safely'), findsOneWidget);
    expect(find.text('Transformation saved'), findsNothing);
    await tester.pump(const Duration(milliseconds: 800));
  });

  testWidgets('dark phone form golden', (tester) async {
    await _pump(tester, size: const Size(390, 844));
    await expectLater(
      find.byType(LogTransformationScreen),
      matchesGoldenFile('goldens/log_transformation_dark_phone.png'),
    );
  });

  group('correcting a published check-in', () {
    testWidgets('opens with what the member already recorded', (tester) async {
      await _pump(
        tester,
        size: const Size(390, 844),
        editing: _published(),
      );

      expect(find.text('Edit check-in'), findsOneWidget);
      expect(find.text('SAVE CHANGES'), findsOneWidget);
      // Prefilled values must read the way they were entered — a stray ".0"
      // makes an untouched field look like a change the member did not make.
      expect(find.widgetWithText(TextField, '82.4'), findsOneWidget);
      expect(find.widgetWithText(TextField, '88.2'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'felt strong'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a whole-number weight has no trailing decimal', (
      tester,
    ) async {
      await _pump(
        tester,
        size: const Size(390, 844),
        editing: _published(weightKg: 82),
      );

      expect(find.widgetWithText(TextField, '82'), findsOneWidget);
      expect(find.widgetWithText(TextField, '82.0'), findsNothing);
    });

    testWidgets('saving corrects the record in place, never republishes it', (
      tester,
    ) async {
      final writer = _FakeWriter();
      await _pump(
        tester,
        size: const Size(390, 844),
        writer: writer,
        editing: _published(),
      );

      await tester.enterText(find.widgetWithText(TextField, '82.4'), '78.1');
      await tester.pump();
      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pump();

      // finalize() would stamp a NEW recordedAt and move the check-in in the
      // member's history; the correction path keeps it where it belongs.
      expect(writer.updateCalls, 1);
      expect(writer.finalizeCalls, 0);
      expect(writer.weightKg, 78.1);
      expect(find.text('Check-in updated'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 800));
    });

    testWidgets('a legacy measurement key survives the correction', (
      tester,
    ) async {
      final writer = _FakeWriter();
      await _pump(
        tester,
        size: const Size(390, 844),
        writer: writer,
        // `arms`/`thighs` are what an older AlphaSerena build wrote. The editor
        // offers the left/right pairs instead, so before this these keys had no
        // field, were absent from the map a correction sends, and the whole-map
        // replace DELETED them — the member lost a measurement by fixing a typo
        // somewhere else on the same record.
        editing: _published(measurements: const {'waist': 88.2, 'arms': 35.5}),
      );

      expect(find.widgetWithText(TextField, '35.5'), findsOneWidget);

      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pump();

      expect(writer.measurements['arms'], 35.5);
      expect(writer.measurements['waist'], 88.2);
      await tester.pump(const Duration(milliseconds: 800));
    });

    testWidgets('body fat the editor never collects is not deleted', (
      tester,
    ) async {
      final writer = _FakeWriter();
      await _pump(
        tester,
        size: const Size(390, 844),
        writer: writer,
        editing: _published(bodyFatPercent: 18.4),
      );

      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pump();

      // A correction replaces the record wholesale, and this screen has no body
      // fat field — passing null erased a real observation.
      expect(writer.bodyFatPercent, 18.4);
      await tester.pump(const Duration(milliseconds: 800));
    });

    testWidgets('an already-private check-in reopens as private', (
      tester,
    ) async {
      final writer = _FakeWriter();
      await _pump(
        tester,
        size: const Size(390, 844),
        writer: writer,
        editing: _published(visibility: TransformationVisibility.private),
      );

      await tester.tap(find.text('SAVE CHANGES'));
      await tester.pump();

      // Reopening an editor must never quietly re-share a hidden check-in.
      expect(writer.visibility, TransformationVisibility.private);
      await tester.pump(const Duration(milliseconds: 800));
    });
  });
}
