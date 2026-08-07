import 'package:alphaserena/core/models/weekly_report_models.dart';
import 'package:alphaserena/core/theme/app_colors.dart';
import 'package:alphaserena/screens/dashboard/weekly_report/weekly_report_history_screen.dart';
import 'package:flutter_test/flutter_test.dart';

/// REGRESSION, found by driving production: the member's Report history showed
/// "Sent" for a week the coach had ALREADY reviewed — at the same moment the
/// report screen said "Your coach has reviewed it". The row already held the
/// review and already rendered the coach's comments below; only the status
/// label ignored it, so the timeline could not tell the member which weeks
/// carried feedback.
void main() {
  // The const palette directly — building AppTheme pulls google_fonts, which a
  // plain unit test cannot load.
  const p = AppPalette.dark;

  // `WeeklyReportStatus` is a holder of String constants, not an enum.
  WeeklyReportSnapshot snap(String s) =>
      WeeklyReportSnapshot(id: 'c1_2026-W31', status: s);

  const completed = WeeklyReportReview(id: 'c1_2026-W31', status: 'completed');
  const pending = WeeklyReportReview(id: 'c1_2026-W31', status: 'pending');

  group('historyStatusOf', () {
    test('a submitted week the coach has reviewed reads REVIEWED', () {
      final (label, colour) =
          historyStatusOf(snap(WeeklyReportStatus.submitted), null, completed, p);
      expect(label, 'Reviewed');
      expect(colour, p.success);
    });

    test('a submitted week with no review yet reads SENT', () {
      final (label, _) =
          historyStatusOf(snap(WeeklyReportStatus.submitted), null, null, p);
      expect(label, 'Sent');
    });

    test('a PENDING review is not feedback — still reads SENT', () {
      // The coach tapping "Save progress" must not be broadcast to the member
      // as though they had replied.
      final (label, _) =
          historyStatusOf(snap(WeeklyReportStatus.submitted), null, pending, p);
      expect(label, 'Sent');
    });

    test('reviewed and sent are DISTINGUISHABLE — the defect in one line', () {
      final reviewed =
          historyStatusOf(snap(WeeklyReportStatus.submitted), null, completed, p);
      final sent =
          historyStatusOf(snap(WeeklyReportStatus.submitted), null, null, p);
      expect(reviewed.$1, isNot(sent.$1));
      expect(reviewed.$2, isNot(sent.$2));
    });

    test('a missed week still reads MISSED, review or not', () {
      expect(
        historyStatusOf(snap(WeeklyReportStatus.missed), null, completed, p).$1,
        'Missed',
      );
    });

    test('a cancelled week reads CANCELLED', () {
      expect(
        historyStatusOf(snap(WeeklyReportStatus.cancelled), null, null, p).$1,
        'Cancelled',
      );
    });

    test('an open week with saved answers reads DRAFT, without them OPEN', () {
      const started = WeeklyReportSubmission(
        id: 'c1_2026-W31',
        answers: {'q_energy': 4},
      );
      expect(
        historyStatusOf(snap(WeeklyReportStatus.open), started, null, p).$1,
        'Draft',
      );
      expect(
        historyStatusOf(snap(WeeklyReportStatus.open), null, null, p).$1,
        'Open',
      );
    });
  });
}
