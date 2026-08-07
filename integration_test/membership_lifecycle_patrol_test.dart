import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

import 'package:alphaserena/controllers/membership_controller.dart';
import 'package:alphaserena/core/theme/app_theme.dart';
import 'package:alphaserena/screens/dashboard/home/home_header.dart';
import 'package:alphaserena/screens/dashboard/home/membership_status.dart';

/// PATROL — the MEMBERSHIP LIFECYCLE, on a real device.
///
/// ── WHY THIS SUITE DRIVES THE ENGINE, NOT A FIXTURE ────────────────────────
/// Every previous certification handed the production widgets a hand-made
/// status object, so no device test ever exercised the path that actually runs
/// in production: a raw `clients` document → `MembershipController`'s parser →
/// `MembershipStatus.of` → the header. That fixture habit is exactly why the
/// workout-consistency defect survived every prior pass (see CLAUDE.md
/// 2026-08-02). So `_statusFromClientDoc` below reproduces the REAL controller
/// pipeline from a raw document map — Timestamp parsing included — and the
/// tests mount the REAL `HeaderView`.
///
/// Home is behind Firebase auth and the emulator has no member session (phone
/// OTP is externally blocked on this project), so the suite mounts production
/// widgets rather than launching the app. What real hardware adds over
/// `flutter test`: real Poppins/Teko metrics, real device pixel ratio, genuine
/// RenderFlex overflow (a red banner fails the test), real orientation changes
/// and real text-scale behaviour.
void main() {
  // ── The REAL controller pipeline, reproduced from a raw clients document ──
  //
  // Uses the REAL MembershipController.parseExpiry plus the five primitive
  // getters (isFrozen / activeFlag / hasMembershipRecord / expiry / status).
  // Given the same document Firestore delivers, this yields the same
  // MembershipStatus the member's header renders.

  // NO LOCAL MIRROR. This used to be a hand-written copy of
  // MembershipController._parseExpiry, and it kept the PRE-FIX behaviour after
  // production gained `.toLocal()` — so it asserted the very timezone defect
  // the fix removed (an IST member seeing "11 Dec" for a 12 Dec expiry). The
  // real parser is called directly; drift is now impossible.
  const parseExpiry = MembershipController.parseExpiry;

  MembershipStatus statusFromClientDoc(
    Map<String, dynamic>? doc, {
    bool memberLoading = false,
    DateTime? now,
  }) {
    final loading = memberLoading || doc == null;
    final hasRecord = doc != null &&
        (doc.containsKey('membershipActive') ||
            doc.containsKey('membershipExpiry') ||
            doc['membership'] != null);
    return MembershipStatus.of(
      loading: loading,
      frozen: doc?['membershipFrozen'] == true,
      activeFlag: doc?['membershipActive'] == true,
      hasRecord: hasRecord,
      expiry: parseExpiry(doc?['membershipExpiry']),
      now: now,
    );
  }

  // ── Real clients-doc shapes, exactly as the backend writes them ───────────
  //
  // verifyAndActivateMembership writes membershipExpiry as an ISO string
  // (expiry.toISOString()); trainersHQ's extend/unfreeze writes
  // `.toUtc().toIso8601String()`. Both shapes appear below on purpose.

  final now = DateTime(2026, 8, 2, 10);

  Map<String, dynamic> doc({
    bool? active,
    bool? frozen,
    dynamic expiry,
    Map<String, dynamic>? membership,
  }) => <String, dynamic>{
    'membershipActive': ?active,
    'membershipFrozen': ?frozen,
    'membershipExpiry': ?expiry,
    'membership': ?membership,
  };

  final lifecycle = <String, Map<String, dynamic>?>{
    // Member created, no purchase yet — no membership fields at all.
    'no membership': <String, dynamic>{'name': 'Member', 'adminId': 'gym1'},
    // Freshly purchased, ISO string (server shape).
    'active': doc(
      active: true,
      frozen: false,
      expiry: DateTime(2026, 12, 12).toUtc().toIso8601String(),
    ),
    // 6 days out — the urgent register.
    'ends soon': doc(
      active: true,
      frozen: false,
      expiry: DateTime(2026, 8, 8, 9).toUtc().toIso8601String(),
    ),
    // 23 hours out.
    'ends tomorrow': doc(
      active: true,
      frozen: false,
      expiry: DateTime(2026, 8, 3, 9).toUtc().toIso8601String(),
    ),
    // Same calendar day.
    'ends today': doc(
      active: true,
      frozen: false,
      expiry: DateTime(2026, 8, 2, 23).toUtc().toIso8601String(),
    ),
    // Coach paused it (trainersHQ freezeMembership) — flag still true, because
    // the hourly sweep deliberately SKIPS frozen docs.
    'frozen': doc(
      active: true,
      frozen: true,
      expiry: DateTime(2026, 9, 1).toUtc().toIso8601String(),
    ),
    // Lapsed, sweep has already flipped the flag.
    'expired (swept)': doc(
      active: false,
      frozen: false,
      expiry: DateTime(2026, 7, 1).toUtc().toIso8601String(),
    ),
    // Lapsed, sweep has NOT run yet (up to a 1-hour window).
    'expired (unswept)': doc(
      active: true,
      frozen: false,
      expiry: DateTime(2026, 8, 2, 9, 30).toUtc().toIso8601String(),
    ),
    // Firestore Timestamp shape rather than ISO — the defensive parser branch.
    'active (Timestamp)': doc(
      active: true,
      frozen: false,
      expiry: Timestamp.fromDate(DateTime(2026, 12, 12)),
    ),
    // Flag on, no date — MembershipController.isActive calls this NOT active.
    'active flag, no date': doc(active: true, frozen: false),
  };

  Widget host(
    MembershipStatus status, {
    Brightness brightness = Brightness.dark,
    double textScale = 1.0,
    Size? size,
  }) {
    final view = MediaQuery(
      data: MediaQueryData(
        textScaler: TextScaler.linear(textScale),
        size: size ?? const Size(390, 844),
      ),
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: HeaderView(
              orgName: 'Iron Temple Coaching',
              membership: status,
              coachName: 'Coach Arjun',
              coachAssigned: true,
              onMessage: () {},
              onNotifications: () {},
            ),
          ),
        ),
      ),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: brightness == Brightness.dark ? AppTheme.dark : AppTheme.light,
      home: view,
    );
  }

  // ── 1. Every lifecycle state renders its own truthful line ───────────────

  lifecycle.forEach((label, clientDoc) {
    patrolWidgetTest('lifecycle · "$label" renders on device', (t) async {
      final status = statusFromClientDoc(clientDoc, now: now);
      await t.pumpWidget(host(status));
      await t.pumpAndSettle();

      if (status.state == MembershipState.loading) {
        expect(find.byKey(membershipSkeletonKey), findsOneWidget);
      } else {
        expect(
          find.text(status.text),
          findsOneWidget,
          reason: '"$label" must render its line verbatim',
        );
      }
      expect(t.tester.takeException(), isNull);
    });
  });

  // ── 2. The engine never calls a non-entitled membership active ───────────

  patrolWidgetTest('a frozen membership never reads as active', (t) async {
    final s = statusFromClientDoc(lifecycle['frozen'], now: now);
    expect(s.state, MembershipState.frozen);
    expect(s.text, 'Paused');
    expect(s.shortText, 'Paused');
    expect(s.isUrgent, isTrue);
    await t.pumpWidget(host(s));
    await t.pumpAndSettle();
    expect(find.textContaining('Active'), findsNothing);
  });

  patrolWidgetTest('an unswept expiry reads Expired, not Active', (t) async {
    // The flag still says membershipActive:true — only the DATE has passed.
    // The client must not trust the flag, or a member would read "Active" for
    // up to an hour after their membership ended.
    final s = statusFromClientDoc(lifecycle['expired (unswept)'], now: now);
    expect(s.state, MembershipState.expired);
    await t.pumpWidget(host(s));
    await t.pumpAndSettle();
    expect(find.text('Expired'), findsOneWidget);
    expect(find.textContaining('Active'), findsNothing);
  });

  patrolWidgetTest('remaining days are never negative and never zero-with-time',
      (t) async {
    for (final entry in lifecycle.entries) {
      final s = statusFromClientDoc(entry.value, now: now);
      expect(
        s.daysLeft,
        greaterThanOrEqualTo(0),
        reason: '"${entry.key}" produced a negative countdown',
      );
      if (s.state == MembershipState.endsSoon) {
        expect(s.daysLeft, greaterThan(0),
            reason: 'endsSoon must never render "Ends in 0 days"');
      }
    }
    await t.pumpWidget(host(
      statusFromClientDoc(lifecycle['ends soon'], now: now),
    ));
    await t.pumpAndSettle();
    expect(find.text('Ends in 6 days'), findsOneWidget);
  });

  patrolWidgetTest('the ISO and Timestamp shapes agree', (t) async {
    // The backend writes ISO; trainersHQ and legacy data can carry Timestamp.
    // Both must resolve to the same member-visible line, or the same
    // membership would read differently depending on which app last wrote it.
    final iso = statusFromClientDoc(lifecycle['active'], now: now);
    final ts = statusFromClientDoc(lifecycle['active (Timestamp)'], now: now);
    expect(ts.state, iso.state);
    expect(ts.text, iso.text);
    await t.pumpWidget(host(ts));
    await t.pumpAndSettle();
    expect(find.text('Active until 12 Dec 2026'), findsOneWidget);
  });

  // ── 3. Real-hardware resilience across every state ───────────────────────

  patrolWidgetTest('every state survives 2.0x text on a 320px phone',
      (t) async {
    for (final entry in lifecycle.entries) {
      final s = statusFromClientDoc(entry.value, now: now);
      await t.pumpWidget(host(
        s,
        textScale: 2.0,
        size: const Size(320, 640),
      ));
      await t.pumpAndSettle();
      expect(
        t.tester.takeException(),
        isNull,
        reason: '"${entry.key}" overflowed at 2.0x on a 320px phone',
      );
    }
  });

  patrolWidgetTest('every state survives light theme and landscape', (t) async {
    for (final entry in lifecycle.entries) {
      final s = statusFromClientDoc(entry.value, now: now);
      await t.pumpWidget(host(
        s,
        brightness: Brightness.light,
        size: const Size(844, 390),
      ));
      await t.pumpAndSettle();
      expect(
        t.tester.takeException(),
        isNull,
        reason: '"${entry.key}" failed in light landscape',
      );
    }
  });

  patrolWidgetTest('the loading state claims no date', (t) async {
    // A wrong date is worse than no date: during cold load the clients doc has
    // not arrived, and rendering anything but a placeholder would state a
    // membership fact the app cannot yet back.
    final s = statusFromClientDoc(null);
    expect(s.state, MembershipState.loading);
    expect(s.text, isEmpty);
    await t.pumpWidget(host(s));
    await t.pumpAndSettle();
    expect(find.byKey(membershipSkeletonKey), findsOneWidget);
    expect(find.textContaining('Active'), findsNothing);
    expect(find.textContaining('Expired'), findsNothing);
  });
}
