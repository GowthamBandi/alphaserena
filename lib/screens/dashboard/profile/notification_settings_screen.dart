import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/models/notification_preferences.dart';
import '../../../core/services/client_profile_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';

/// Notification settings (N-series preferences UI) — a master switch, per-
/// category push toggles, a locked "always on for safety" section for calls
/// + security, and quiet hours. Reads/merge-writes
/// `clientProfiles/{uid}.notificationPreferences` in the v2 shape the
/// server's `parseNotificationPrefs` expects.
class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() =>
      _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState
    extends State<NotificationSettingsScreen> {
  final ClientProfileService _svc = ClientProfileService();
  late final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _loading = true;
  MemberNotificationPrefs _prefs = const MemberNotificationPrefs();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_uid.isEmpty) {
      setState(() => _loading = false);
      return;
    }
    try {
      final data = await _svc.get(_uid);
      final raw = data?['notificationPreferences'];
      setState(() {
        _prefs = MemberNotificationPrefs.fromMap(
            raw is Map ? Map<String, dynamic>.from(raw) : null);
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false); // keep defaults
    }
  }

  /// Optimistic save: flip the UI immediately, revert + toast on failure.
  Future<void> _save(MemberNotificationPrefs next) async {
    final prev = _prefs;
    setState(() => _prefs = next);
    if (_uid.isEmpty) return;
    try {
      await _svc.update(_uid, {'notificationPreferences': next.toMap()});
    } catch (_) {
      if (!mounted) return;
      setState(() => _prefs = prev);
      Get.snackbar('Error', 'Could not save notification settings. Please try again.',
          snackPosition: SnackPosition.BOTTOM);
    }
  }

  Future<void> _pickHour(bool isStart) async {
    final p = context.palette;
    final current = isStart ? _prefs.quietHoursStart : _prefs.quietHoursEnd;
    final picked = await showModalBottomSheet<int>(
      context: context,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _HourPickerSheet(
        title: isStart ? 'Quiet hours start' : 'Quiet hours end',
        selected: current,
      ),
    );
    if (picked == null) return;
    _save(isStart
        ? _prefs.copyWith(quietHoursStart: picked)
        : _prefs.copyWith(quietHoursEnd: picked));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: p.textPrimary),
          onPressed: () => Get.back(),
        ),
        title: Text(
          'Notifications',
          style: GoogleFonts.poppins(
              color: p.textPrimary, fontSize: 18, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: _loading
            ? Center(child: CircularProgressIndicator(color: p.accent))
            : ListView(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 28),
                children: [
                  Text(
                    'Choose what you get notified about. Calls and security '
                    'alerts always reach you.',
                    style: GoogleFonts.poppins(color: p.textMuted, fontSize: 12),
                  ),
                  const SizedBox(height: 16),
                  _card(p, [
                    _toggle(
                      p,
                      Icons.notifications_active_rounded,
                      'All notifications',
                      _prefs.enabled
                          ? 'On — you\'ll get pushes for what\'s enabled below'
                          : 'Off — no pushes will reach this device',
                      _prefs.enabled,
                      (v) => _save(_prefs.copyWith(enabled: v)),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _sectionLabel(p, 'What you hear about'),
                  const SizedBox(height: 8),
                  _card(p, [
                    _toggle(
                      p,
                      Icons.chat_bubble_outline_rounded,
                      'Messages',
                      'New messages from your coach',
                      _prefs.communication,
                      (v) => _save(_prefs.copyWith(communication: v)),
                    ),
                    _divider(p),
                    _toggle(
                      p,
                      Icons.person_outline_rounded,
                      'Coaching',
                      'Check-ins, plan updates, trainer changes',
                      _prefs.coaching,
                      (v) => _save(_prefs.copyWith(coaching: v)),
                    ),
                    _divider(p),
                    _toggle(
                      p,
                      Icons.card_membership_outlined,
                      'Membership',
                      'Renewal reminders and expiry alerts',
                      _prefs.membership,
                      (v) => _save(_prefs.copyWith(membership: v)),
                    ),
                    _divider(p),
                    _toggle(
                      p,
                      Icons.receipt_long_outlined,
                      'Billing',
                      'Payments, receipts and subscription updates',
                      _prefs.billing,
                      (v) => _save(_prefs.copyWith(billing: v)),
                    ),
                    _divider(p),
                    _toggle(
                      p,
                      Icons.campaign_outlined,
                      'Announcements',
                      'News from your coach and the platform',
                      _prefs.announcements,
                      (v) => _save(_prefs.copyWith(announcements: v)),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _sectionLabel(p, 'Always on'),
                  const SizedBox(height: 8),
                  _card(p, [
                    _toggle(
                      p,
                      Icons.call_outlined,
                      'Calls',
                      'Always on for safety',
                      true,
                      null,
                    ),
                    _divider(p),
                    _toggle(
                      p,
                      Icons.shield_outlined,
                      'Security',
                      'Always on for safety',
                      true,
                      null,
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _sectionLabel(p, 'Offers'),
                  const SizedBox(height: 8),
                  _card(p, [
                    _toggle(
                      p,
                      Icons.local_offer_outlined,
                      'Offers & promotions',
                      'Deals and marketing from your coach — opt in anytime',
                      _prefs.marketing,
                      (v) => _save(_prefs.copyWith(marketing: v)),
                    ),
                  ]),
                  const SizedBox(height: 18),
                  _sectionLabel(p, 'Quiet hours'),
                  const SizedBox(height: 8),
                  _card(p, [
                    _toggle(
                      p,
                      Icons.bedtime_outlined,
                      'Quiet hours',
                      'Hold non-urgent pushes overnight',
                      _prefs.quietHoursEnabled,
                      (v) => _save(_prefs.copyWith(quietHoursEnabled: v)),
                    ),
                    if (_prefs.quietHoursEnabled) ...[
                      _divider(p),
                      _hourRow(p, 'Starts', _prefs.quietHoursStart,
                          () => _pickHour(true)),
                      _divider(p),
                      _hourRow(p, 'Ends', _prefs.quietHoursEnd,
                          () => _pickHour(false)),
                    ],
                  ]),
                ],
              ),
      ),
    );
  }

  Widget _sectionLabel(AppPalette p, String text) => Text(
        text.toUpperCase(),
        style: GoogleFonts.poppins(
          color: p.textMuted,
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
        ),
      );

  Widget _card(AppPalette p, List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: AppRadii.cardR,
          border: Border.all(color: p.border),
        ),
        child: Column(children: children),
      );

  Widget _divider(AppPalette p) =>
      Divider(color: p.border, height: 1, indent: 66, endIndent: 14);

  Widget _toggle(AppPalette p, IconData icon, String label, String subtitle,
      bool value, ValueChanged<bool>? onChanged) {
    final locked = onChanged == null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: (locked ? p.textMuted : p.accent).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: locked ? p.textMuted : p.accent, size: 19),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    style: GoogleFonts.poppins(
                        color: p.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10.5)),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Switch(value: value, activeThumbColor: p.accent, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _hourRow(AppPalette p, String label, int hour, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        child: Row(
          children: [
            const SizedBox(width: 51),
            Expanded(
              child: Text(label,
                  style: GoogleFonts.poppins(
                      color: p.textPrimary,
                      fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ),
            Text(_formatHour(hour),
                style: GoogleFonts.poppins(
                    color: p.accent, fontSize: 13, fontWeight: FontWeight.w600)),
            const SizedBox(width: 6),
            Icon(Icons.chevron_right, color: p.textMuted, size: 18),
          ],
        ),
      ),
    );
  }
}

String _formatHour(int hour) {
  final h = hour % 24;
  final display = h % 12 == 0 ? 12 : h % 12;
  final ampm = h < 12 ? 'AM' : 'PM';
  return '$display:00 $ampm';
}

/// A simple 0-23 hour picker bottom sheet (quiet hours only needs whole
/// hours — no minute granularity).
class _HourPickerSheet extends StatelessWidget {
  final String title;
  final int selected;
  const _HourPickerSheet({required this.title, required this.selected});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 360,
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: p.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 14),
            Text(title,
                style: GoogleFonts.poppins(
                    color: p.textPrimary, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                itemCount: 24,
                itemBuilder: (context, hour) {
                  final sel = hour == selected;
                  return ListTile(
                    onTap: () => Navigator.of(context).pop(hour),
                    title: Text(_formatHour(hour),
                        style: GoogleFonts.poppins(
                            color: sel ? p.accent : p.textPrimary,
                            fontSize: 14,
                            fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
                    trailing: sel ? Icon(Icons.check, color: p.accent, size: 18) : null,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
