import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../core/constants/firestore_collections.dart';
import '../../core/models/app_notification.dart';
import '../../core/services/notification_center_service.dart';
import '../../core/theme/app_colors.dart';
import 'weekly_report/weekly_report_screen.dart';
import 'client_chat_screen.dart';
import 'membership_screen.dart';
import 'plans/my_plans_screen.dart';
import 'notification_detail_screen.dart';
import 'notification_visuals.dart';

/// A center filter tab.
enum _Filter { all, unread }

/// In-app notification center — the durable history behind push (a missed
/// push is no longer a lost event). Items stream newest-first, grouped by
/// day; category-tinted icons cover all 10 taxonomy categories; tap marks
/// read + deep-links; swipe archives (reversible via an Undo snackbar). An
/// All / Unread filter narrows the list. Opening the screen zeroes the bell
/// badge (markAllSeen). The live stream covers the first page; scrolling to
/// the end loads older pages (one-shot, 30 at a time).
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
  final ScrollController _scrollCtrl = ScrollController();

  // Pagination: pages loaded below the live first page.
  final List<AppNotification> _older = [];
  bool _loadingMore = false;
  bool _hasMore = true;
  List<AppNotification> _lastLiveItems = const [];

  bool _markingAll = false;
  _Filter _filter = _Filter.all;

  /// How long a swipe-archive stays reversible before its Firestore write
  /// fires. The rules allow setting `archivedAt` but never clearing it (no
  /// server "unarchive"), so the reversible window must live entirely on the
  /// client, before the write.
  static const Duration _archiveGrace = Duration(seconds: 4);
  final Set<String> _pendingArchiveIds = {};
  final Map<String, Timer> _archiveTimers = {};

  @override
  void initState() {
    super.initState();
    // Opening the center clears the badge — fire-and-forget, never blocks UI.
    _svc.markAllSeen().catchError((_) {});
    _scrollCtrl.addListener(_onScroll);
  }

  @override
  void dispose() {
    // Commit any still-pending archives so a close doesn't silently drop them.
    for (final entry in _archiveTimers.entries) {
      entry.value.cancel();
      _svc.archive(entry.key).catchError((_) {});
    }
    _archiveTimers.clear();
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollCtrl.hasClients || !_hasMore || _loadingMore) return;
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadMore() async {
    if (_uid.isEmpty || _loadingMore || !_hasMore) return;
    // Anchor on the id of the last rendered item (older tail, else live tail);
    // the service resolves it to a DocumentSnapshot cursor.
    final anchorId = _older.isNotEmpty
        ? _older.last.id
        : (_lastLiveItems.isNotEmpty ? _lastLiveItems.last.id : null);
    if (anchorId == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _svc.loadMore(_uid, afterId: anchorId);
      if (!mounted) return;
      setState(() {
        _older.addAll(page);
        _hasMore = page.length >= 30;
      });
    } catch (_) {
      // Non-fatal — the next scroll-to-bottom retries.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _markAllRead(List<AppNotification> visible) async {
    final ids = visible.where((n) => n.isUnread).map((n) => n.id).toList();
    if (ids.isEmpty || _markingAll) return;
    setState(() => _markingAll = true);
    try {
      await _svc.markAllRead(ids);
    } catch (_) {
      Get.snackbar('Error', 'Could not mark all as read. Please try again.',
          snackPosition: SnackPosition.BOTTOM);
    } finally {
      if (mounted) setState(() => _markingAll = false);
    }
  }

  // ── deferred archive with undo ──────────────────────────────────────────
  void _archive(AppNotification n) {
    if (_pendingArchiveIds.contains(n.id)) return;
    HapticFeedback.lightImpact();
    setState(() => _pendingArchiveIds.add(n.id));
    _archiveTimers[n.id]?.cancel();
    _archiveTimers[n.id] = Timer(_archiveGrace, () => _commitArchive(n.id));
    final messenger = ScaffoldMessenger.of(context);
    messenger.clearSnackBars();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Notification archived'),
        duration: _archiveGrace,
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => _undoArchive(n.id),
        ),
      ),
    );
  }

  void _undoArchive(String id) {
    _archiveTimers.remove(id)?.cancel();
    if (mounted) setState(() => _pendingArchiveIds.remove(id));
  }

  Future<void> _commitArchive(String id) async {
    _archiveTimers.remove(id);
    try {
      await _svc.archive(id);
      if (mounted) setState(() => _older.removeWhere((e) => e.id == id));
    } catch (_) {
      // Failed → let it reappear (truth restored) below via pending removal.
    } finally {
      if (mounted) setState(() => _pendingArchiveIds.remove(id));
    }
  }

  /// Pull-to-refresh: a one-shot server read for a guaranteed fresh snapshot,
  /// AND reset pagination. Resetting `_older`/`_hasMore` heals the one narrow
  /// gap the live-window + one-shot-older design has (a new item arriving after
  /// an older page was loaded leaves a boundary item in an unrendered gap).
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
    if (mounted) {
      setState(() {
        _older.clear();
        _hasMore = true;
      });
    }
  }

  /// Keeps the first occurrence of each id — the live page wins over any
  /// overlapping older-page copy, so a boundary item can never render twice.
  List<AppNotification> _dedupById(List<AppNotification> items) {
    final seen = <String>{};
    final out = <AppNotification>[];
    for (final n in items) {
      if (seen.add(n.id)) out.add(n);
    }
    return out;
  }

  void _open(AppNotification n) {
    if (n.isUnread) _svc.markRead(n.id).catchError((_) {});
    _routeByKind(n);
  }

  /// What a list row shows beneath the title: the content engine's summary
  /// when one was authored, otherwise the body.
  static String _rowText(AppNotification n) {
    final s = (n.data['summary'] ?? '').trim();
    return s.isNotEmpty ? s : n.body;
  }

  /// The app's SINGLE kind→destination map. Used both when a row is tapped and
  /// when the reader's content CTA is pressed, so the two can never diverge.
  void _routeByKind(AppNotification n) {
    switch (n.kind) {
      case 'missed_call':
      case 'trainer_changed':
        Get.to(() => const ClientChatScreen());
        break;
      // 🔴 THE FOUR WEEKLY-REPORT KINDS WERE MISSING, AND EVERY ONE OF THEM
      // FELL THROUGH TO THE GENERIC READER — a dead end that restates the
      // title and offers no way to the report it is about.
      //
      // Observed in production: the scheduler issued a real report, sent
      // "Your weekly report is ready", and tapping it landed the member on a
      // page with nothing to do. The backend has emitted these kinds since the
      // feature shipped (`weekly_reports.ts`); this map had never heard of
      // them. `checkin_reviewed` is the LEGACY kind and stays — migrated
      // history still carries it.
      //
      // ⚠️ These are the MEMBER-DIRECTED kinds only. `weekly_report_submitted`
      // and `weekly_report_member_overdue` are addressed to the COACH and must
      // never appear here — routing a kind this app can never receive reads as
      // coverage it does not have.
      case 'checkin_reviewed':
      case 'weekly_report_ready':
      case 'weekly_report_reminder':
      case 'weekly_report_overdue':
      case 'weekly_report_reviewed':
      case 'weekly_report_update_requested':
        Get.to(() => const WeeklyReportScreen());
        break;
      case 'membership_expired':
      case 'membership_expiring':
      case 'membership_activated':
        Get.to(() => MembershipScreen());
        break;
      case 'plan_assigned_workout':
      case 'plan_assigned_diet':
      case 'plan_updated_workout':
      case 'plan_updated_diet':
      case 'plan_removed_workout':
      case 'plan_removed_diet':
        Get.to(() => const MyPlansScreen());
        break;
      default:
        // No kind-route claimed it → open the full reader. Announcements land
        // here (an announcement's destination IS its own text), as does any
        // future kind this client doesn't know yet. This used to `break` with
        // no navigation, which left every announcement stuck at the list's
        // three-line truncation with no way to read the rest. (EP-1 A1)
        Get.to(() => NotificationDetailScreen(
              notification: n,
              // The CTA reuses this screen's own kind routing. Passing the
              // callback keeps one routing map in the app rather than a second
              // copy inside the reader.
              onCta: _routeByKind,
            ));
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return StreamBuilder<List<AppNotification>>(
      stream: _stream,
      builder: (context, snap) {
        final liveItems = snap.data ?? const <AppNotification>[];
        _lastLiveItems = liveItems; // cached for the next _loadMore() anchor
        final combined = _dedupById([...liveItems, ..._older]);
        final visible = combined
            .where((n) => !_pendingArchiveIds.contains(n.id))
            .toList();
        final unreadCount = visible.where((n) => n.isUnread).length;

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
            actions: [
              if (unreadCount > 0)
                TextButton(
                  onPressed: _markingAll ? null : () => _markAllRead(visible),
                  child: _markingAll
                      ? SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: p.accent),
                        )
                      : Text(
                          'Mark all read',
                          style: GoogleFonts.poppins(
                              color: p.accent,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600),
                        ),
                ),
              const SizedBox(width: 6),
            ],
          ),
          body: _uid.isEmpty
              ? _empty(p)
              : _content(snap, visible, unreadCount, p),
        );
      },
    );
  }

  Widget _content(AsyncSnapshot<List<AppNotification>> snap,
      List<AppNotification> visible, int unreadCount, AppPalette p) {
    if (snap.hasError && visible.isEmpty) return _error(p);
    if (!snap.hasData && visible.isEmpty) return _skeleton(p);
    if (visible.isEmpty) return _wrapRefresh(_empty(p));

    final filtered = _filter == _Filter.unread
        ? visible.where((n) => n.isUnread).toList()
        : visible;

    return Column(
      children: [
        _filterBar(p, unreadCount),
        Expanded(
          child: filtered.isEmpty
              ? _wrapRefresh(_emptyFilter(p))
              : _wrapRefresh(_list(filtered, p)),
        ),
      ],
    );
  }

  Widget _filterBar(AppPalette p, int unreadCount) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          _filterChip(p, _Filter.all, 'All', null),
          const SizedBox(width: 8),
          _filterChip(p, _Filter.unread, 'Unread',
              unreadCount > 0 ? unreadCount : null),
        ],
      ),
    );
  }

  Widget _filterChip(AppPalette p, _Filter f, String label, int? count) {
    final selected = _filter == f;
    return Semantics(
      button: true,
      selected: selected,
      label: count == null ? label : '$label, $count',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => setState(() => _filter = f),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              color: selected ? p.accent.withValues(alpha: 0.14) : p.surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected ? p.accent : p.border,
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: GoogleFonts.poppins(
                    color: selected ? p.accent : p.textMuted,
                    fontSize: 12.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                  ),
                ),
                if (count != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: p.accent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '$count',
                      style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
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
    if (_loadingMore) {
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: p.accent),
          ),
        ),
      ));
    }
    return ListView(
      controller: _scrollCtrl,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
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
    final visual = notificationVisual(n.category);
    final rel = _relative(n.createdAt);
    final title = n.title.isEmpty ? 'Notification' : n.title;
    final semanticLabel = [
      if (n.isUnread) 'Unread.',
      '${visual.label}.',
      '$title.',
      if (n.body.isNotEmpty) '${n.body}.',
      if (rel.isNotEmpty) rel,
    ].join(' ');

    return Dismissible(
      key: ValueKey(n.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => _archive(n),
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
          child: Semantics(
            button: true,
            label: semanticLabel,
            child: ExcludeSemantics(
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
                        color: visual.color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child:
                          Icon(visual.icon, color: visual.color, size: 20),
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
                                  title,
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
                                  margin:
                                      const EdgeInsets.only(left: 6, top: 4),
                                  decoration: BoxDecoration(
                                    color: p.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          // EP-3: prefer the content engine's one-line summary
                          // on this dense surface. Templates author it for
                          // exactly this purpose, so a row shows a purposeful
                          // précis rather than the first three lines of prose.
                          if (_rowText(n).isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Text(
                              _rowText(n),
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(
                                  color: p.textSecondary, fontSize: 12),
                            ),
                            // The list stays scannable at three lines, but a
                            // long announcement must ADVERTISE that there is
                            // more — otherwise the ellipsis reads as the end of
                            // the message and the reader is never opened.
                            // (EP-1 A1). Keyed on the FULL body, not the row
                            // text: a short summary over a long body is
                            // exactly when the reader is most needed.
                            if (n.body.length > 150) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Read full announcement',
                                style: GoogleFonts.poppins(
                                  color: p.accent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ],
                          const SizedBox(height: 4),
                          Text(
                            rel,
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
        ),
      ),
    );
  }

  /// Placeholder rows while the first page loads — steadier than a lone spinner.
  Widget _skeleton(AppPalette p) {
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(
            color: p.textMuted.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
        );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: 7,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (_, _) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: p.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: p.textMuted.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(130, 12),
                  const SizedBox(height: 8),
                  bar(double.infinity, 10),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyFilter(AppPalette p) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.mark_email_read_outlined, color: p.textMuted, size: 40),
            const SizedBox(height: 10),
            Text(
              'No unread notifications',
              style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );

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
