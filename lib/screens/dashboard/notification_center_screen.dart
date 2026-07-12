import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/firestore_collections.dart';
import '../../core/models/app_notification.dart';
import '../../core/services/notification_center_service.dart';
import '../../core/theme/app_colors.dart';
import 'client_chat_screen.dart';
import 'membership_screen.dart';

/// In-app notification center — the durable history behind push (a missed
/// push is no longer a lost event). Items stream newest-first, grouped by
/// day; tap marks read + deep-links; swipe archives. Opening the screen
/// zeroes the bell badge (markAllSeen).
class NotificationCenterScreen extends StatefulWidget {
  const NotificationCenterScreen({super.key});

  @override
  State<NotificationCenterScreen> createState() =>
      _NotificationCenterScreenState();
}

class _NotificationCenterScreenState extends State<NotificationCenterScreen> {
  final NotificationCenterService _svc = NotificationCenterService();
  late final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final Stream<List<AppNotification>> _stream =
      _svc.watchItems(_uid).asBroadcastStream();

  @override
  void initState() {
    super.initState();
    // Opening the center clears the badge — fire-and-forget, never blocks UI.
    _svc.markAllSeen().catchError((_) {});
  }

  /// Pull-to-refresh: a one-shot server read so the member gets a guaranteed
  /// fresh snapshot (the live stream keeps the list current afterwards).
  Future<void> _refresh() async {
    if (_uid.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection(FsCollections.notifications)
          .doc(_uid)
          .collection(FsCollections.notificationItems)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .get(const GetOptions(source: Source.server));
    } catch (_) {
      // Offline refresh is non-fatal — the cached stream still renders.
    }
  }

  void _open(AppNotification n) {
    if (n.isUnread) _svc.markRead(n.id).catchError((_) {});
    switch (n.kind) {
      case 'missed_call':
      case 'trainer_changed':
        Get.to(() => const ClientChatScreen());
        break;
      case 'membership_expired':
        Get.to(() => MembershipScreen());
        break;
      default:
        break; // no deep-link target — mark read is enough
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
        title: Text(
          'Notifications',
          style: GoogleFonts.poppins(
            color: p.textPrimary,
            fontSize: 17,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: _uid.isEmpty
          ? _empty(p)
          : StreamBuilder<List<AppNotification>>(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) return _error(p);
                if (!snap.hasData) {
                  return Center(
                      child: CircularProgressIndicator(color: p.accent));
                }
                final items = snap.data!;
                if (items.isEmpty) return _wrapRefresh(_empty(p));
                return _wrapRefresh(_list(items, p));
              },
            ),
    );
  }

  Widget _wrapRefresh(Widget child) {
    final p = context.palette;
    return RefreshIndicator(
      onRefresh: _refresh,
      color: p.accent,
      child: child is ListView
          ? child
          : LayoutBuilder(
              builder: (context, c) => ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  SizedBox(height: c.maxHeight, child: child),
                ],
              ),
            ),
    );
  }

  Widget _list(List<AppNotification> items, AppPalette p) {
    // Day grouping: a flat row list with a header row whenever the day changes.
    final rows = <Widget>[];
    String? lastLabel;
    for (final n in items) {
      final label = _dayLabel(n.createdAt);
      if (label != lastLabel) {
        rows.add(_dayHeader(label, p));
        lastLabel = label;
      }
      rows.add(_tile(n, p));
    }
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: rows,
    );
  }

  Widget _dayHeader(String label, AppPalette p) => Padding(
        padding: const EdgeInsets.fromLTRB(2, 16, 2, 8),
        child: Text(
          label,
          style: GoogleFonts.poppins(
            color: p.textMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.4,
          ),
        ),
      );

  Widget _tile(AppNotification n, AppPalette p) {
    final style = _categoryStyle(n.category, p);
    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _svc.archive(n.id).catchError((_) {}),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          color: p.error.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.archive_outlined, color: p.error, size: 22),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _open(n),
          child: Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: n.isUnread
                    ? p.accent.withValues(alpha: 0.4)
                    : p.border,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: style.color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(style.icon, color: style.color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              n.title.isEmpty ? 'Notification' : n.title,
                              style: GoogleFonts.poppins(
                                color: p.textPrimary,
                                fontSize: 13.5,
                                fontWeight: n.isUnread
                                    ? FontWeight.w700
                                    : FontWeight.w600,
                              ),
                            ),
                          ),
                          if (n.isUnread)
                            Container(
                              width: 8,
                              height: 8,
                              margin: const EdgeInsets.only(left: 6, top: 4),
                              decoration: BoxDecoration(
                                color: p.accent,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                      if (n.body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          n.body,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                              color: p.textSecondary, fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 4),
                      Text(
                        _relative(n.createdAt),
                        style: GoogleFonts.poppins(
                            color: p.textMuted, fontSize: 10.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty(AppPalette p) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.notifications_none_rounded,
                color: p.textMuted, size: 44),
            const SizedBox(height: 10),
            Text(
              'No notifications yet',
              style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Missed calls, coaching and membership\nupdates will show up here.',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: p.textMuted, fontSize: 12),
            ),
          ],
        ),
      );

  Widget _error(AppPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded, color: p.error, size: 40),
              const SizedBox(height: 10),
              Text(
                "Couldn't load notifications",
                style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                'Check your connection and try again.',
                style: GoogleFonts.poppins(color: p.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      );
}

class _CategoryStyle {
  final IconData icon;
  final Color color;
  const _CategoryStyle(this.icon, this.color);
}

_CategoryStyle _categoryStyle(String category, AppPalette p) {
  switch (category) {
    case 'calls':
      return _CategoryStyle(Icons.phone_missed_rounded, p.error);
    case 'coaching':
      return _CategoryStyle(Icons.person_rounded, p.success);
    case 'membership':
      return const _CategoryStyle(
          Icons.card_membership_rounded, BrandColors.amber);
    case 'billing':
      return const _CategoryStyle(
          Icons.receipt_long_rounded, Color(0xFF42A5F5));
    default:
      return _CategoryStyle(Icons.info_outline_rounded, p.textMuted);
  }
}

String _dayLabel(DateTime? d) {
  if (d == null) return 'Earlier';
  final now = DateTime.now();
  final day = DateTime(d.year, d.month, d.day);
  final today = DateTime(now.year, now.month, now.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return 'Today';
  if (diff == 1) return 'Yesterday';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  final year = d.year == now.year ? '' : ' ${d.year}';
  return '${d.day} ${months[d.month - 1]}$year';
}

String _relative(DateTime? d) {
  if (d == null) return '';
  final diff = DateTime.now().difference(d);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final ampm = d.hour < 12 ? 'AM' : 'PM';
  return '$h:${d.minute.toString().padLeft(2, '0')} $ampm';
}
