import 'package:alphaserena/core/domain/member_identity.dart';
import 'package:flutter_test/flutter_test.dart';

/// Member identity — the app must never invent who someone is.
///
/// Every case below is a regression guard for something that actually shipped:
/// a member called 'Alpha', an organisation called 'Alpha Arena', an age tile
/// that read '--' for every member in production, and a stale organisation name
/// that outranked the freshly fetched one.
void main() {
  group('member name — real, or absent', () {
    test('canonical display name wins', () {
      expect(
        resolveMemberName(
          canonicalDisplayName: 'Priya Sharma',
          legacyClientName: 'Priya S',
          coachRecordName: 'Priya (new)',
        ),
        'Priya Sharma',
      );
    });

    test('falls back to the legacy dual-write, then the coach record', () {
      expect(
        resolveMemberName(legacyClientName: 'Priya S', coachRecordName: 'P'),
        'Priya S',
      );
      expect(resolveMemberName(coachRecordName: 'Priya'), 'Priya');
    });

    test('nothing known → empty, NEVER a placeholder name', () {
      expect(resolveMemberName(), isEmpty);
      // The exact string that used to ship, and that flowed into review and
      // feedback authorship in the coach's inbox.
      expect(resolveMemberName(), isNot('Alpha'));
    });

    test('whitespace-only values are not names', () {
      expect(
        resolveMemberName(canonicalDisplayName: '   ', legacyClientName: '\n'),
        isEmpty,
      );
    });

    test('a blank canonical value does not mask a real fallback', () {
      expect(
        resolveMemberName(canonicalDisplayName: '  ', coachRecordName: 'Ravi'),
        'Ravi',
      );
    });
  });

  group('member photo', () {
    test('returns the uploaded photo', () {
      expect(
        resolveMemberPhoto(canonicalPhotoUrl: 'https://x/y.jpg'),
        'https://x/y.jpg',
      );
    });

    test('no photo → empty so the caller renders initials, not a stock face', () {
      expect(resolveMemberPhoto(), isEmpty);
      expect(resolveMemberPhoto(canonicalPhotoUrl: '   '), isEmpty);
    });
  });

  group('member age — the tile that was structurally dead', () {
    final now = DateTime(2026, 7, 28);

    test('derived from the member-authored date of birth', () {
      expect(resolveMemberAge(dob: '1994-03-15', now: now), 32);
    });

    test('a birthday later this year has NOT happened yet', () {
      expect(resolveMemberAge(dob: '1994-12-31', now: now), 31);
    });

    test('the birthday itself counts', () {
      expect(resolveMemberAge(dob: '1994-07-28', now: now), 32);
    });

    test('date of birth outranks the coach-typed integer', () {
      expect(
        resolveMemberAge(dob: '1994-03-15', coachRecordAge: 99, now: now),
        32,
      );
    });

    test('falls back to the coach record, in any stored numeric form', () {
      expect(resolveMemberAge(coachRecordAge: 28, now: now), 28);
      expect(resolveMemberAge(coachRecordAge: 28.0, now: now), 28);
      expect(resolveMemberAge(coachRecordAge: '28', now: now), 28);
    });

    test('nothing known → null, so the tile says unknown rather than 0', () {
      expect(resolveMemberAge(now: now), isNull);
      expect(resolveMemberAge(dob: 'not-a-date', now: now), isNull);
      expect(resolveMemberAge(coachRecordAge: 'abc', now: now), isNull);
    });

    test('impossible values read as unknown, not as confident absurdity', () {
      expect(resolveMemberAge(dob: '2030-01-01', now: now), isNull);
      expect(resolveMemberAge(coachRecordAge: -5, now: now), isNull);
      expect(resolveMemberAge(coachRecordAge: 500, now: now), isNull);
      expect(resolveMemberAge(dob: '1850-01-01', now: now), isNull);
    });
  });

  group('organisation name — live outranks the stale mirror', () {
    test('the freshly fetched storefront name wins', () {
      expect(
        resolveOrgName(liveName: 'Iron Temple', mirroredName: 'Old Gym Name'),
        'Iron Temple',
      );
    });

    test('a RENAMED organisation shows its current name', () {
      // The mirror is written once by claimClientAccount and never re-derived,
      // so preferring it (the previous behaviour) pinned members to the former
      // name indefinitely.
      expect(
        resolveOrgName(liveName: 'Apex Strength', mirroredName: 'Apex Gym'),
        'Apex Strength',
      );
    });

    test('falls back to the mirror when nothing has been fetched', () {
      expect(resolveOrgName(mirroredName: 'Apex Gym'), 'Apex Gym');
    });

    test('nothing known → empty, NEVER a plausible gym name', () {
      expect(resolveOrgName(), isEmpty);
      expect(resolveOrgName(), isNot('Alpha Arena'));
    });
  });

  group('initials — derived from a real name only', () {
    test('first and last initial', () {
      expect(initialsOf('Priya Sharma'), 'PS');
      expect(initialsOf('ravi kumar singh'), 'RS');
    });

    test('single word takes one letter', () {
      expect(initialsOf('Priya'), 'P');
    });

    test('no name → no initials, so the caller shows a neutral glyph', () {
      expect(initialsOf(''), isEmpty);
      expect(initialsOf('   '), isEmpty);
    });

    test('leading punctuation and emoji do not become initials', () {
      expect(initialsOf('@ravi'), 'R');
      expect(initialsOf('👋'), isEmpty);
    });

    test('extra whitespace between words is tolerated', () {
      expect(initialsOf('  Priya   Sharma  '), 'PS');
    });
  });
}
