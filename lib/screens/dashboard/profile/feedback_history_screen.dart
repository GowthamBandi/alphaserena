import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/services/feedback_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text.dart';

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

/// The member's own feedback history — every message they sent to their
/// coach, its Open/Resolved status, and the coach's reply when one exists.
/// This closes the loop: replies used to be written to a doc the member app
/// never read.
class FeedbackHistoryScreen extends StatelessWidget {
  const FeedbackHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final service = FeedbackService();
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
        title: Text('My feedback',
            style: AppText.title(size: 17).copyWith(color: p.textPrimary)),
      ),
      body: StreamBuilder<List<MyFeedbackEntry>>(
        stream: service.watchMine(),
        builder: (context, snap) {
          if (snap.hasError) {
            return _message(p, Icons.cloud_off_outlined,
                'Could not load your feedback right now.');
          }
          if (!snap.hasData) {
            return Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    strokeWidth: 2.2, color: p.accent),
              ),
            );
          }
          final items = snap.data!;
          if (items.isEmpty) {
            return _message(p, Icons.forum_outlined,
                'Nothing sent yet. Messages you send to your coach — and '
                'their replies — appear here.');
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            itemCount: items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, i) => _card(p, items[i]),
          );
        },
      ),
    );
  }

  Widget _message(AppPalette p, IconData icon, String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: p.textMuted, size: 40),
              const SizedBox(height: 14),
              Text(text,
                  textAlign: TextAlign.center,
                  style: AppText.body(size: 13).copyWith(color: p.textMuted)),
            ],
          ),
        ),
      );

  Widget _card(AppPalette p, MyFeedbackEntry f) {
    final statusColor = f.isResolved ? p.textMuted : p.accent;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(_cap(f.category),
                    style:
                        AppText.label(size: 11).copyWith(color: p.accent)),
              ),
              const Spacer(),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(f.isResolved ? 'Resolved' : 'Open',
                    style: AppText.label(size: 11)
                        .copyWith(color: statusColor)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(f.message,
              style: AppText.body(size: 13)
                  .copyWith(color: p.textPrimary, height: 1.4)),
          if (f.createdAt != null) ...[
            const SizedBox(height: 6),
            Text(DateFormat('d MMM y').format(f.createdAt!),
                style: AppText.body(size: 11).copyWith(color: p.textMuted)),
          ],
          if (f.hasReply) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.07),
                borderRadius: AppRadii.smR,
                border:
                    Border.all(color: p.accent.withValues(alpha: 0.25)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.support_agent_outlined,
                          size: 14, color: p.accent),
                      const SizedBox(width: 6),
                      Text('COACH REPLY',
                          style: AppText.label(size: 10).copyWith(
                              color: p.accent, letterSpacing: 0.6)),
                      const Spacer(),
                      if (f.respondedAt != null)
                        Text(DateFormat('d MMM y').format(f.respondedAt!),
                            style: AppText.body(size: 10.5)
                                .copyWith(color: p.textMuted)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(f.adminResponse!,
                      style: AppText.body(size: 13)
                          .copyWith(color: p.textPrimary, height: 1.4)),
                ],
              ),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text('Waiting for your coach to reply.',
                style: AppText.body(size: 11.5).copyWith(
                    color: p.textMuted, fontStyle: FontStyle.italic)),
          ],
        ],
      ),
    );
  }
}
