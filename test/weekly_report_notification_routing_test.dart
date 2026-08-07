import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// EVERY MEMBER-DIRECTED WEEKLY-REPORT NOTIFICATION MUST HAVE A DESTINATION.
///
/// 🔴 WHY THIS FILE EXISTS. The backend has emitted `weekly_report_ready` since
/// the feature shipped. This app routed none of the weekly-report kinds, so
/// every one fell through to the generic reader — a page that restates the
/// title and offers no way to the report it is about.
///
/// Found in PRODUCTION, by tapping a real notification on a real device:
///
///     "Your weekly report is ready · 10m ago"  →  a dead end.
///
/// No test caught it because both halves were self-consistent: the backend sent
/// a kind nobody claimed, and the client's `default` branch handled the unknown
/// kind exactly as designed. That is this platform's recurring defect — correct
/// code that nothing reaches — and the fix for the CLASS is to assert the two
/// sides against each other rather than each against itself.
///
/// These tests read the SOURCE of both apps. A source-level assertion is the
/// right shape here: the failure is a missing `case`, and no runtime fixture can
/// prove a `switch` covers a set it never receives.

/// Kinds the server addresses to `clientProfiles` — i.e. to THIS app's user.
/// Mirrors the `notify(...)` call sites in `functions/src/weekly_reports.ts`.
const _memberDirectedKinds = <String>{
  'weekly_report_ready',
  'weekly_report_reminder',
  'weekly_report_overdue',
  'weekly_report_reviewed',
  'weekly_report_update_requested',
};

/// Kinds the server addresses to the COACH. This app can never receive them,
/// and routing one would be coverage it does not have.
const _coachDirectedKinds = <String>{
  'weekly_report_submitted',
  'weekly_report_member_overdue',
};

/// Resolved from THIS file, so the test works from any working directory.
Directory get _repoRoot => Directory.current;

File _f(String relative) => File('${_repoRoot.path}/$relative');

void main() {
  final centre = _f('lib/screens/dashboard/notification_center_screen.dart');
  final push = _f('lib/core/services/member_push_service.dart');

  group('the in-app notification centre routes every member kind', () {
    late String src;
    setUpAll(() => src = centre.readAsStringSync());

    test('the file exists', () => expect(centre.existsSync(), isTrue));

    for (final kind in _memberDirectedKinds) {
      test('"$kind" has a destination', () {
        expect(
          src.contains("case '$kind':"),
          isTrue,
          reason: 'The server sends "$kind" to this app\'s user and nothing '
              'here claims it, so it falls through to the generic reader — a '
              'notification the member cannot act on.',
        );
      });
    }

    for (final kind in _coachDirectedKinds) {
      test('"$kind" is NOT routed — it is addressed to the coach', () {
        expect(
          src.contains("case '$kind':"),
          isFalse,
          reason: '"$kind" is sent to the coach. Routing it in the member app '
              'is dead code that reads as coverage.',
        );
      });
    }
  });

  group('a push tap lands in the same place as an in-app tap', () {
    late String src;
    setUpAll(() => src = push.readAsStringSync());

    for (final kind in _memberDirectedKinds) {
      test('"$kind" deep-links', () {
        expect(
          src.contains("case '$kind':"),
          isTrue,
          reason: 'A push tap on "$kind" fell through to the durable reader '
              'while the in-app tap opened the report. One notification must '
              'not have two destinations.',
        );
      });
    }
  });

  test('both surfaces route the SAME set — they cannot drift apart', () {
    final a = _kindsRoutedTo(centre.readAsStringSync(), 'WeeklyReportScreen');
    final b = _kindsRoutedTo(push.readAsStringSync(), 'WeeklyReportScreen');
    expect(
      a,
      equals(b),
      reason: 'The notification centre and the push handler send different '
          'kinds to the weekly report. Whichever is missing a kind is the one '
          'that dead-ends.',
    );
    expect(a.containsAll(_memberDirectedKinds), isTrue);
  });
}

/// Every `case '<kind>':` label falling through to a `Get.to(... [screen] ...)`.
Set<String> _kindsRoutedTo(String source, String screen) {
  final out = <String>{};
  final pending = <String>[];
  for (final rawLine in source.split('\n')) {
    final line = rawLine.trim();
    final m = RegExp(r"^case '([a-z_]+)':$").firstMatch(line);
    if (m != null) {
      pending.add(m.group(1)!);
      continue;
    }
    if (line.startsWith('//') || line.isEmpty) continue;
    if (pending.isNotEmpty) {
      if (line.contains(screen)) out.addAll(pending);
      pending.clear();
    }
  }
  return out;
}
