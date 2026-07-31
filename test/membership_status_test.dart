import 'package:alphaserena/screens/dashboard/home/membership_status.dart';
import 'package:flutter_test/flutter_test.dart';

/// Membership line — the header must never claim a date it cannot back, and
/// must never call an expired or frozen membership "active".
void main() {
  final now = DateTime(2026, 7, 25, 12);

  MembershipStatus status({
    bool loading = false,
    bool frozen = false,
    bool activeFlag = true,
    bool hasRecord = true,
    DateTime? expiry,
  }) => MembershipStatus.of(
    loading: loading,
    frozen: frozen,
    activeFlag: activeFlag,
    hasRecord: hasRecord,
    expiry: expiry,
    now: now,
  );

  group('precedence', () {
    test('loading wins over everything and claims no date', () {
      final s = status(loading: true, expiry: DateTime(2026, 8, 30));
      expect(s.state, MembershipState.loading);
      expect(s.text, isEmpty);
    });

    test('frozen reads as paused, not active', () {
      final s = status(frozen: true, expiry: DateTime(2026, 8, 30));
      expect(s.state, MembershipState.frozen);
      expect(s.text, 'Paused');
      expect(s.isUrgent, isTrue);
    });

    test('no membership fields at all', () {
      final s = status(hasRecord: false, activeFlag: false);
      expect(s.state, MembershipState.none);
      expect(s.text, 'No membership');
    });

    test('past expiry is expired even when the active flag is on', () {
      final s = status(expiry: DateTime(2026, 7, 20));
      expect(s.state, MembershipState.expired);
      expect(s.text, 'Expired');
    });

    test('flag off is inactive', () {
      final s = status(activeFlag: false, expiry: DateTime(2026, 8, 30));
      expect(s.state, MembershipState.inactive);
      expect(s.text, 'Inactive');
    });

    test('active flag with NO expiry is inactive — matches isActive', () {
      final s = status(expiry: null);
      expect(s.state, MembershipState.inactive);
    });
  });

  group('countdown', () {
    test('expiring later today reads as ends today', () {
      final s = status(expiry: DateTime(2026, 7, 25, 23, 59));
      expect(s.state, MembershipState.endsToday);
      expect(s.text, 'Ends today');
    });

    test('tomorrow is a whole day, not zero', () {
      final s = status(expiry: DateTime(2026, 7, 26, 1));
      expect(s.state, MembershipState.endsSoon);
      expect(s.text, 'Ends tomorrow');
    });

    test('within the soon window is urgent', () {
      final s = status(expiry: DateTime(2026, 7, 30));
      expect(s.state, MembershipState.endsSoon);
      expect(s.text, 'Ends in 5 days');
      expect(s.isUrgent, isTrue);
    });

    test('the soon boundary itself is urgent', () {
      final s = status(expiry: DateTime(2026, 8, 1));
      expect(s.daysLeft, MembershipStatus.soonDays);
      expect(s.state, MembershipState.endsSoon);
    });

    test('comfortable runway is calm, not urgent', () {
      final s = status(expiry: DateTime(2026, 8, 6));
      expect(s.state, MembershipState.active);
      // Section 1 redesign: a comfortable runway states a DATE, not a
      // countdown. 12 days is not news; re-stating it every morning is noise.
      expect(s.text, startsWith('Active until '));
      expect(s.isUrgent, isFalse);
      expect(s.icon, isNull);
    });
  });

  group('non-colour signalling', () {
    test('every urgent state carries a glyph', () {
      final urgent = [
        status(frozen: true),
        status(expiry: DateTime(2026, 7, 1)),
        status(activeFlag: false),
        status(hasRecord: false, activeFlag: false),
        status(expiry: DateTime(2026, 7, 25, 20)),
        status(expiry: DateTime(2026, 7, 28)),
      ];
      for (final s in urgent) {
        expect(s.isUrgent, isTrue, reason: '${s.state}');
        expect(s.icon, isNotNull, reason: '${s.state}');
      }
    });

    test('calm states carry no glyph', () {
      expect(status(expiry: DateTime(2026, 9, 1)).icon, isNull);
      expect(status(loading: true).icon, isNull);
    });
  });

  /// ONE ENGINE, TWO REGISTERS. Profile renders membership in a badge beside the
  /// member's name, where the header's full line ("Active until 12 Dec 2026")
  /// does not fit. Rather than let a second screen invent its own shorter
  /// wording — which is exactly how Profile ended up with an Active/Inactive
  /// binary that called a PAUSED membership "Expired" — the compact register
  /// lives on the same object. These tests hold the two registers in agreement.
  group('compact register (Profile badge)', () {
    test('every state has compact wording except loading', () {
      expect(status(loading: true).shortText, isEmpty);
      final states = [
        status(frozen: true),
        status(hasRecord: false, activeFlag: false),
        status(activeFlag: false),
        status(expiry: DateTime(2026, 7, 1)),
        status(expiry: DateTime(2026, 7, 25, 20)),
        status(expiry: DateTime(2026, 7, 27)),
        status(expiry: DateTime(2026, 7, 30)),
        status(expiry: DateTime(2026, 9, 1)),
      ];
      for (final s in states) {
        expect(s.shortText, isNotEmpty, reason: '${s.state}');
      }
    });

    test('a paused membership never reads as expired or inactive', () {
      final s = status(frozen: true, expiry: DateTime(2026, 7, 1));
      // The frozen membership carries a stale PAST expiry here on purpose: the
      // old Profile card derived its label from `isActive`, which is false for
      // both, and so printed "Expired" at a member whose coach had paused them.
      expect(s.shortText, 'Paused');
      expect(s.text, 'Paused');
    });

    test('no state is ever called Active unless it genuinely is', () {
      final notActive = [
        status(frozen: true),
        status(hasRecord: false, activeFlag: false),
        status(activeFlag: false),
        status(expiry: DateTime(2026, 7, 1)),
      ];
      for (final s in notActive) {
        expect(s.shortText, isNot('Active'), reason: '${s.state}');
        expect(s.text, isNot(startsWith('Active')), reason: '${s.state}');
      }
    });

    test('the two registers agree on urgency for every state', () {
      final all = [
        status(loading: true),
        status(frozen: true),
        status(hasRecord: false, activeFlag: false),
        status(activeFlag: false),
        status(expiry: DateTime(2026, 7, 1)),
        status(expiry: DateTime(2026, 7, 25, 20)),
        status(expiry: DateTime(2026, 7, 30)),
        status(expiry: DateTime(2026, 9, 1)),
      ];
      for (final s in all) {
        // Whatever the register, a calm state never gains a glyph and an urgent
        // one never loses it — the badge and the header cannot disagree.
        expect(s.isUrgent, s.icon != null, reason: '${s.state}');
      }
    });

    test('the compact countdown stays short and correct', () {
      expect(status(expiry: DateTime(2026, 7, 26, 20)).shortText, 'Ends tomorrow');
      expect(status(expiry: DateTime(2026, 7, 30)).shortText, 'Ends in 5d');
      expect(status(expiry: DateTime(2026, 9, 1)).shortText, 'Active');
    });
  });
}
