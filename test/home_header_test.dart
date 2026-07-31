import 'package:alphaserena/core/theme/app_colors.dart';
import 'package:alphaserena/screens/dashboard/home/home_header.dart';
import 'package:alphaserena/screens/dashboard/home/membership_status.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Home header — every repository-supported state, plus the honesty rules the
/// header must never break (no fabricated verification, no fabricated unread
/// count, no fabricated coach identity, no implied action that doesn't work).
void main() {
  /// Renders [HeaderView] on a phone-width canvas in the requested theme.
  Future<void> pumpHeader(
    WidgetTester tester,
    Widget header, {
    bool dark = true,
    double width = 360,
    double textScale = 1.0,
  }) async {
    final palette = dark ? AppPalette.dark : AppPalette.light;
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          extensions: [palette],
        ),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            backgroundColor: palette.background,
            body: Padding(
              padding: const EdgeInsets.all(18),
              child: Align(alignment: Alignment.topCenter, child: header),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// A calm, populated membership line unless a test asks for another state.
  const defaultMembership = MembershipStatus(
    MembershipState.active,
    daysLeft: 42,
  );

  HeaderView header({
    String orgName = 'Iron Temple Fitness',
    bool orgLoading = false,
    bool orgVerified = false,
    Widget? orgLogo,
    VoidCallback? onOpenOrg,
    String? coachName,
    bool coachAssigned = false,
    VoidCallback? onMessage,
    int unread = 0,
    MembershipStatus membership = defaultMembership,
  }) {
    return HeaderView(
      orgName: orgName,
      orgLoading: orgLoading,
      orgVerified: orgVerified,
      onOpenOrg: onOpenOrg ?? () {},
      coachName: coachName,
      coachAssigned: coachAssigned,
      onMessage: onMessage ?? () {},
      membership: membership,
      notificationUnread: unread,
      onNotifications: () {},
    );
  }

  // ── Organization states ────────────────────────────────────────────────
  group('organization', () {
    testWidgets('loaded — shows the real name', (tester) async {
      // Section 1 redesign: the org is an EYEBROW — small caps, letterspaced,
      // demoted below the coach because the member opens this app to reach a
      // person, not a building.
      await pumpHeader(tester, header(orgName: 'Iron Temple Fitness'));
      expect(find.text('IRON TEMPLE FITNESS'), findsOneWidget);
    });

    testWidgets('loading — skeletons instead of a fallback name', (
      tester,
    ) async {
      await pumpHeader(
        tester,
        header(orgName: 'Your Organization', orgLoading: true),
      );
      expect(find.text('YOUR ORGANIZATION'), findsNothing);
      // The bar must stay a short placeholder, not stretch the whole row.
      expect(tester.getSize(find.byKey(orgNameSkeletonKey)).width, 96);
    });

    testWidgets('the org LOGO is gone — name only', (tester) async {
      // Removed by design: a 48px tile was the heaviest element in the card and
      // belonged to the party the member interacts with least. Its removal is
      // the single largest space saving in the redesign.
      await pumpHeader(tester, header());
      expect(tester.takeException(), isNull);
      expect(find.text('IRON TEMPLE FITNESS'), findsOneWidget);
      // No logo tile: the eyebrow is the only org element in the card.
      expect(find.byType(Image), findsNothing);
    });

    testWidgets('verified badge is HIDDEN unless the backend says true', (
      tester,
    ) async {
      await pumpHeader(tester, header(orgVerified: false));
      expect(find.byIcon(Icons.verified_rounded), findsNothing);
    });

    testWidgets('verified badge shows when the backend says true', (
      tester,
    ) async {
      await pumpHeader(tester, header(orgVerified: true));
      expect(find.byIcon(Icons.verified_rounded), findsOneWidget);
    });

    testWidgets('no storefront to open → row is not a button', (tester) async {
      await pumpHeader(
        tester,
        HeaderView(
          orgName: 'Your Organization',
          onOpenOrg: null,
          onMessage: () {},
          onNotifications: () {},
        ),
      );
      expect(
        tester.getSemantics(
          find.bySemanticsLabel('Organization Your Organization'),
        ),
        containsSemantics(isButton: false),
      );
    });

    testWidgets('tapping the org row opens the storefront', (tester) async {
      var opened = 0;
      await pumpHeader(tester, header(onOpenOrg: () => opened++));
      await tester.tap(
        find.bySemanticsLabel(
          'Organization Iron Temple Fitness. Open storefront',
        ),
      );
      expect(opened, 1);
    });
  });

  // ── Membership line ────────────────────────────────────────────────────
  group('membership', () {
    testWidgets('a healthy membership states a DATE, not a countdown', (
      tester,
    ) async {
      // 42 days is not news. A date is a calm fact to plan around; a countdown
      // re-states the same non-news every morning.
      await pumpHeader(
        tester,
        header(
          membership: MembershipStatus(
            MembershipState.active,
            daysLeft: 42,
            expiry: DateTime(2026, 12, 12),
          ),
        ),
      );
      expect(find.text('Active until 12 Dec 2026'), findsOneWidget);
    });

    testWidgets('close to expiry it switches to a COUNTDOWN', (tester) async {
      // Here the number IS the actionable fact.
      await pumpHeader(
        tester,
        header(
          membership: const MembershipStatus(
            MembershipState.endsSoon,
            daysLeft: 3,
          ),
        ),
      );
      expect(find.text('Ends in 3 days'), findsOneWidget);
    });

    testWidgets('loading shows a placeholder and NO date', (tester) async {
      await pumpHeader(
        tester,
        header(membership: const MembershipStatus(MembershipState.loading)),
      );
      expect(find.byKey(membershipSkeletonKey), findsOneWidget);
      expect(find.textContaining('Active'), findsNothing);
    });

    testWidgets('expired never reads as active', (tester) async {
      await pumpHeader(
        tester,
        header(membership: const MembershipStatus(MembershipState.expired)),
      );
      expect(find.text('Expired'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('frozen reads as paused with a glyph', (tester) async {
      await pumpHeader(
        tester,
        header(membership: const MembershipStatus(MembershipState.frozen)),
      );
      expect(find.text('Paused'), findsOneWidget);
      expect(find.byIcon(Icons.pause_circle_outline_rounded), findsOneWidget);
    });

    testWidgets('no membership record', (tester) async {
      await pumpHeader(
        tester,
        header(membership: const MembershipStatus(MembershipState.none)),
      );
      expect(find.text('No membership'), findsOneWidget);
    });

    testWidgets('calm state carries no warning glyph', (tester) async {
      await pumpHeader(tester, header());
      expect(find.byIcon(Icons.schedule_rounded), findsNothing);
      expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
    });

    testWidgets('membership is its OWN spoken row, not part of the org', (
      tester,
    ) async {
      // Redesign: a fact about the MEMBER no longer rides on a row about the
      // GYM. Each is separately scannable and separately announced.
      await pumpHeader(
        tester,
        header(membership: const MembershipStatus(MembershipState.expired)),
      );
      expect(find.bySemanticsLabel('Expired'), findsOneWidget);
      expect(
        find.bySemanticsLabel(
          'Organization Iron Temple Fitness. Open storefront',
        ),
        findsOneWidget,
      );
    });
  });

  // ── Coach states ───────────────────────────────────────────────────────
  group('coach', () {
    testWidgets('assigned — shows the real name and its monogram', (
      tester,
    ) async {
      await pumpHeader(
        tester,
        header(coachName: 'Sam Rivera', coachAssigned: true),
      );
      expect(find.text('Sam Rivera'), findsOneWidget);
      expect(find.text('S'), findsOneWidget);
    });

    testWidgets('assigned but unnamed — neutral copy, no invented name', (
      tester,
    ) async {
      await pumpHeader(tester, header(coachName: null, coachAssigned: true));
      expect(find.text('Your coach'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline_rounded), findsOneWidget);
      // The spoken label must match the visible line, not the unassigned one.
      // The label is assembled from non-empty parts; with no conversation it
      // is just the role and the action.
      expect(find.bySemanticsLabel('Your coach. Open chat'), findsOneWidget);
    });

    testWidgets('not assigned — honest copy, messaging still offered', (
      tester,
    ) async {
      var messaged = 0;
      await pumpHeader(
        tester,
        header(
          coachName: null,
          coachAssigned: false,
          onMessage: () => messaged++,
        ),
      );
      expect(find.text('Not assigned yet'), findsOneWidget);
      // Chat resolves from linkedClientId, so the action genuinely works. The
      // "Message" PILL was removed (Section 1.5) — a verb carrying no
      // information, occupying the position that now shows recency and unread.
      // The whole row is the target, which is a larger one.
      await tester.tap(find.text('Not assigned yet'));
      expect(messaged, 1);
    });

    testWidgets('a named coach reads "Assigned Coach" over the name', (
      tester,
    ) async {
      // The secondary line briefly carried the last message preview, so a
      // one-character message rendered the coach as "Gowtham / d". Identity
      // must not fluctuate with chat traffic.
      await pumpHeader(
        tester,
        header(coachName: 'Gowtham', coachAssigned: true),
      );
      expect(find.text('Assigned Coach'), findsOneWidget);
      expect(find.text('Gowtham'), findsOneWidget);
    });

    testWidgets('no coach → an honest empty state, never a placeholder', (
      tester,
    ) async {
      await pumpHeader(
        tester,
        header(coachName: null, coachAssigned: false),
      );
      expect(find.text('Coach'), findsOneWidget);
      expect(find.text('Not assigned yet'), findsOneWidget);
      // No stray characters, no nulls, no leftover preview line.
      expect(find.text('null'), findsNothing);
      expect(find.text('Assigned Coach'), findsNothing);
    });

    testWidgets('the org name uses the brand accent, not white', (
      tester,
    ) async {
      await pumpHeader(tester, header(orgName: 'Iron Temple Fitness'));
      final t = tester.widget<Text>(find.text('IRON TEMPLE FITNESS'));
      expect(t.style?.color, const Color(0xFFD50000));
    });

    testWidgets('the whole coach row is the chat button', (tester) async {
      var messaged = 0;
      await pumpHeader(
        tester,
        header(
          coachName: 'Sam Rivera',
          coachAssigned: true,
          onMessage: () => messaged++,
        ),
      );
      await tester.tap(find.text('Sam Rivera'));
      expect(messaged, 1);
    });
  });

  // ── Notification states ────────────────────────────────────────────────
  group('notifications', () {
    testWidgets('zero unread — no badge', (tester) async {
      await pumpHeader(tester, header(unread: 0));
      expect(find.text('0'), findsNothing);
      expect(
        tester.getSemantics(find.bySemanticsLabel('Notifications')),
        containsSemantics(isButton: true),
      );
    });

    testWidgets('unread — real count on the badge', (tester) async {
      await pumpHeader(tester, header(unread: 7));
      expect(find.text('7'), findsOneWidget);
      expect(find.bySemanticsLabel('Notifications, 7 unread'), findsOneWidget);
    });

    testWidgets('caps at 99+', (tester) async {
      await pumpHeader(tester, header(unread: 250));
      expect(find.text('99+'), findsOneWidget);
    });

    testWidgets('meets the 44dp touch target', (tester) async {
      await pumpHeader(tester, header(unread: 3));
      // The drawn tile is 40; the tap target is padded to the platform
      // minimum of 44 without a 44px chrome box dominating the row.
      final size = tester.getSize(
        find.ancestor(
          of: find.byIcon(Icons.notifications_none_rounded),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });

  // ── Layout resilience ──────────────────────────────────────────────────
  group('layout', () {
    testWidgets('long org and coach names do not overflow', (tester) async {
      await pumpHeader(
        tester,
        header(
          orgName:
              'The Extremely Long Metropolitan Strength & Conditioning Academy',
          orgVerified: true,
          coachName: 'Bartholomew Featherstonehaugh-Cholmondeley',
          coachAssigned: true,
          unread: 128,
        ),
        width: 320,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('survives a 1.6x text scale', (tester) async {
      await pumpHeader(
        tester,
        header(coachName: 'Sam Rivera', coachAssigned: true, unread: 4),
        width: 320,
        textScale: 1.6,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('stays compact on a phone', (tester) async {
      await pumpHeader(
        tester,
        header(coachName: 'Sam Rivera', coachAssigned: true, unread: 2),
      );
      // Section 1 redesign budget. The 48px org logo tile is gone and the card
      // carries MORE information than before (conversation preview, two badged
      // actions, membership on its own row) in LESS height.
      final height = tester.getSize(find.byType(HeaderView)).height;
      expect(height, lessThan(136));
    });

    testWidgets('renders in light theme', (tester) async {
      await pumpHeader(
        tester,
        header(coachName: 'Sam Rivera', coachAssigned: true, unread: 2),
        dark: false,
      );
      expect(tester.takeException(), isNull);
    });
  });

  // ── Visual review baselines ────────────────────────────────────────────
  // Regenerate with: flutter test --update-goldens test/home_header_test.dart
  group('goldens', () {
    testWidgets('dark — fully populated', (tester) async {
      await pumpHeader(
        tester,
        header(
          orgVerified: true,
          coachName: 'Sam Rivera',
          coachAssigned: true,
          unread: 3,
        ),
      );
      await expectLater(
        find.byType(HeaderView),
        matchesGoldenFile('goldens/home_header_dark.png'),
      );
    });

    testWidgets('light — fully populated', (tester) async {
      await pumpHeader(
        tester,
        header(
          orgVerified: true,
          coachName: 'Sam Rivera',
          coachAssigned: true,
          unread: 3,
        ),
        dark: false,
      );
      await expectLater(
        find.byType(HeaderView),
        matchesGoldenFile('goldens/home_header_light.png'),
      );
    });

    testWidgets('dark — no coach, no logo, unverified, no unread', (
      tester,
    ) async {
      await pumpHeader(tester, header(orgName: 'Your Organization'));
      await expectLater(
        find.byType(HeaderView),
        matchesGoldenFile('goldens/home_header_empty.png'),
      );
    });

    testWidgets('dark — long names at 320px', (tester) async {
      await pumpHeader(
        tester,
        header(
          orgName:
              'The Extremely Long Metropolitan Strength & Conditioning Academy',
          orgVerified: true,
          coachName: 'Bartholomew Featherstonehaugh-Cholmondeley',
          coachAssigned: true,
          unread: 128,
        ),
        width: 320,
      );
      await expectLater(
        find.byType(HeaderView),
        matchesGoldenFile('goldens/home_header_long_names.png'),
      );
    });
  });
}
