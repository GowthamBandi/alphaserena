import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/domain/member_profile.dart';
import 'package:alphaserena/core/domain/member_profile_adapter.dart';

/// UMHIPP P2 — the member-app copy of the canonical domain must behave
/// IDENTICALLY to the backend reference + the coach app (byte-identical port),
/// plus the member `clientProfiles` doc adapter.
void main() {
  group('MemberProfile privacy policy', () {
    test('member sees all own sections except pure AI data', () {
      for (final s in kMemberSections) {
        expect(canViewSection(s.key, ViewerRole.member), s.key != 'aiData',
            reason: s.key);
      }
    });

    test('coach sees coach-default but not private medical/preferences', () {
      expect(canViewSection('goals', ViewerRole.coach), isTrue);
      expect(canViewSection('bodyMetrics', ViewerRole.coach), isTrue);
      expect(canViewSection('medical', ViewerRole.coach), isFalse);
      expect(canViewSection('preferences', ViewerRole.coach), isFalse);
    });

    test('member can opt in to share medical, and can tighten a section', () {
      expect(
          canViewSection('medical', ViewerRole.coach,
              {'medical': SectionVisibility.coach}),
          isTrue);
      expect(
          canViewSection('bodyMetrics', ViewerRole.coach,
              {'bodyMetrics': SectionVisibility.onlyMe}),
          isFalse);
    });

    test('an override never broadens past the section max (clamp)', () {
      expect(
          effectiveVisibility(
              sectionSpec('bodyMetrics')!, SectionVisibility.organization),
          SectionVisibility.coach);
      expect(
          effectiveVisibility(
              sectionSpec('medical')!, SectionVisibility.organization),
          SectionVisibility.coach);
    });

    test('emergency break-glass, org supersedes coach, AI-only, fail-closed', () {
      expect(canViewSection('emergencyContact', ViewerRole.coach), isFalse);
      expect(canViewSection('emergencyContact', ViewerRole.emergency), isTrue);
      expect(canViewSection('membership', ViewerRole.orgAdmin), isTrue);
      expect(canViewSection('medical', ViewerRole.orgAdmin), isFalse);
      expect(canViewSection('aiData', ViewerRole.aiSystem), isTrue);
      expect(canViewSection('aiData', ViewerRole.member), isFalse);
      for (final v in ViewerRole.values) {
        expect(canViewSection('ghost_section', v), isFalse, reason: v.name);
      }
    });

    test('coachProjection leaks only member-owned, coach-visible sections', () {
      final profile = <String, dynamic>{
        'goals': {'primary': 'fat loss'},
        'medical': {'conditions': 'asthma'},
        'coachNotes': {'text': 'coach only'},
        'identity': {'name': 'A'},
      };
      expect(coachProjection(profile).keys.toSet(), {'goals', 'identity'});
      expect(
          coachProjection(profile, {'medical': SectionVisibility.coach})
              .containsKey('medical'),
          isTrue);
    });
  });

  group('MemberProfile serialization', () {
    test('fromMap/toMap round-trips; null-safe defaults; forward compatible', () {
      final m = <String, dynamic>{
        'profile': {
          'goals': {'primary': 'x'}
        },
        'privacy': {'medical': 'coach'},
      };
      final round = MemberProfile.fromMap(MemberProfile.fromMap(m).toMap());
      expect(round.section('goals')!['primary'], 'x');
      expect(round.privacy['medical'], SectionVisibility.coach);
      expect(MemberProfile.fromMap(null).sections, isEmpty);
      expect(completionRatio(const {}), 0);
      final fut = MemberProfile.fromMap(<String, dynamic>{
        'privacy': {'goals': 'future_tier'}
      });
      expect(fut.privacy.containsKey('goals'), isFalse);
    });
  });

  group('MemberProfileDocAdapter (member) round-trip', () {
    test('reads canonical profile; bridges legacy notificationPreferences', () {
      final doc = <String, dynamic>{
        'profile': {
          'goals': {'primary': 'x'}
        },
        'privacy': {'medical': 'coach'},
        'notificationPreferences': {'version': 2},
        'linkedClientId': 'c1',
      };
      final p = MemberProfileDocAdapter.fromDoc(doc);
      expect(p.section('goals')!['primary'], 'x');
      expect(p.privacy['medical'], SectionVisibility.coach);
      expect(p.section('preferences')!['notificationPreferences'], isA<Map>());

      // toDocPatch is additive — profile+privacy only, never legacy fields.
      final patch = MemberProfileDocAdapter.toDocPatch(p);
      expect(patch.containsKey('profile'), isTrue);
      expect(patch.containsKey('notificationPreferences'), isFalse);
      expect(patch.containsKey('linkedClientId'), isFalse);
    });

    test('does not shadow an existing canonical preferences section', () {
      final doc = <String, dynamic>{
        'profile': {
          'preferences': {'units': 'metric'}
        },
        'notificationPreferences': {'version': 2},
      };
      final p = MemberProfileDocAdapter.fromDoc(doc);
      expect(p.section('preferences')!['units'], 'metric');
      expect(p.section('preferences')!.containsKey('notificationPreferences'),
          isFalse);
    });
  });
}
