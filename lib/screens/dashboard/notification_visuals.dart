import 'package:flutter/material.dart';

/// The visual identity (icon + accent colour + human label) for one
/// notification category. Mirrors the backend taxonomy's 10 frozen categories
/// (`trainershq-backend/functions/src/lib/notification_center.ts`
/// `NOTIFICATION_CATEGORIES`) so the in-app center renders EVERY category with
/// a distinct look instead of collapsing the unmapped ones to a grey "info".
///
/// Colours are the SAME fixed accents the coach app uses, so a category reads
/// identically across the two apps (a member's "Membership" alert and the
/// coach's look match). They are shown as a full-strength icon on a low-alpha
/// tint of the same hue, which keeps contrast in both light and dark.
@immutable
class NotificationVisual {
  final IconData icon;
  final Color color;
  final String label;
  const NotificationVisual(this.icon, this.color, this.label);
}

const Map<String, NotificationVisual> _kCategoryVisuals = {
  'calls': NotificationVisual(
      Icons.call_rounded, Color(0xFFE24B4A), 'Calls'),
  'communication': NotificationVisual(
      Icons.chat_bubble_rounded, Color(0xFF378ADD), 'Messages'),
  'coaching': NotificationVisual(
      Icons.fitness_center_rounded, Color(0xFF1D9E75), 'Coaching'),
  'membership': NotificationVisual(
      Icons.card_membership_rounded, Color(0xFFEF9F27), 'Membership'),
  'billing': NotificationVisual(
      Icons.receipt_long_rounded, Color(0xFF0EA5A5), 'Billing'),
  'organization': NotificationVisual(
      Icons.apartment_rounded, Color(0xFF6C5CE7), 'Organization'),
  'security': NotificationVisual(
      Icons.shield_rounded, Color(0xFFEA6A2E), 'Security'),
  'system': NotificationVisual(
      Icons.settings_suggest_rounded, Color(0xFF64748B), 'System'),
  'announcements': NotificationVisual(
      Icons.campaign_rounded, Color(0xFFB05CE7), 'Announcement'),
  'marketing': NotificationVisual(
      Icons.local_offer_rounded, Color(0xFFEC5A8D), 'Offer'),
};

const NotificationVisual _fallback =
    NotificationVisual(Icons.notifications_rounded, Color(0xFF64748B), 'Update');

/// The visual for [category], or a safe default for an unknown one. Total —
/// never throws, so a future backend category still renders something sensible.
NotificationVisual notificationVisual(String category) =>
    _kCategoryVisuals[category] ?? _fallback;

/// The categories with an explicit (non-fallback) visual — for coverage tests.
Iterable<String> get mappedNotificationCategories => _kCategoryVisuals.keys;
