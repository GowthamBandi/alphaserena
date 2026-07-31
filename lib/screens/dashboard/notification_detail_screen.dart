import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../core/models/app_notification.dart';
import '../../core/theme/app_colors.dart';
import 'notification_visuals.dart';

/// FULL NOTIFICATION READER (EP-1 A1).
///
/// The notification center is a LIST: it truncates each body to three lines so
/// a backlog stays scannable. That was the whole reading surface in this app,
/// and announcement bodies are allowed up to 4000 characters — so any real
/// announcement was cut off mid-sentence with nowhere to go. `_open()` fell
/// through to `default: break` for the announcements category, so tapping one
/// did nothing at all.
///
/// This screen is that missing destination: the complete, scrollable body with
/// no truncation. It renders purely from the item already in the member's own
/// feed — the broadcast source collections stay founder/author-readable only,
/// so no rules change and no extra read is needed to show the full text.
///
/// Deliberately mirrors TrainerHQ's reader (same structure, same category
/// visuals) so an announcement looks the same to a coach and to a member.
class NotificationDetailScreen extends StatelessWidget {
  const NotificationDetailScreen({
    super.key,
    required this.notification,
    this.onCta,
  });

  final AppNotification notification;

  /// Invoked when the content's call-to-action is tapped. Supplied by the
  /// notification center, which already owns kind-based routing — the reader
  /// deliberately does not duplicate that map.
  final void Function(AppNotification)? onCta;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final n = notification;
    final visual = notificationVisual(n.category);

    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(
        backgroundColor: p.background,
        elevation: 0,
        iconTheme: IconThemeData(color: p.textPrimary),
        title: Text(
          visual.label,
          style: GoogleFonts.inter(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: p.textPrimary,
          ),
        ),
      ),
      body: SafeArea(
        // Scrollable by construction — a 4000-character announcement must be
        // readable to the last word on the shortest supported screen.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: visual.color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(visual.icon, size: 21, color: visual.color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          visual.label.toUpperCase(),
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.8,
                            color: visual.color,
                          ),
                        ),
                        if (n.createdAt != null)
                          Text(
                            DateFormat('d MMM yyyy, h:mm a')
                                .format(n.createdAt!),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: p.textMuted,
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // No maxLines anywhere below: the reader never truncates.
              SelectableText(
                n.title,
                style: GoogleFonts.inter(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: p.textPrimary,
                ),
              ),
              const SizedBox(height: 14),
              // EP-3 hero image. https only — a client that rendered whatever
              // string arrived would be one bad write away from loading
              // arbitrary content. A failed load degrades to nothing.
              if (_imageUrl(n) != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    _imageUrl(n)!,
                    fit: BoxFit.cover,
                    // Screen readers announce the message title for the
                    // image: the content engine carries no alt text, and a
                    // silent unlabelled image is an accessibility gap.
                    semanticLabel: n.title,

                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    loadingBuilder: (ctx, child, progress) => progress == null
                        ? child
                        : const SizedBox(
                            height: 120,
                            child: Center(
                                child: SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2)))),
                  ),
                ),
                const SizedBox(height: 14),
              ],
              SelectableText(
                n.body,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  height: 1.55,
                  color: p.textSecondary,
                ),
              ),
              // EP-3 call to action. The member app routes by KIND rather than
              // a deepLink map, so the button is shown only when the content
              // carries a label; tapping returns to the center's own routing.
              // Shown only when the label exists AND the kind actually leads
              // somewhere. A CTA whose kind falls to the reader default would
              // just push another copy of this screen.
              if ((n.data['ctaLabel'] ?? '').trim().isNotEmpty &&
                  onCta != null &&
                  hasKindRoute(n.kind)) ...[
                const SizedBox(height: 22),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => onCta!(n),
                    style: FilledButton.styleFrom(backgroundColor: p.accent),
                    child: Text(
                      n.data['ctaLabel']!.trim(),
                      style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The hero image URL, or null unless it is an absolute https URL.
  static String? _imageUrl(AppNotification n) {
    final raw = (n.data['imageUrl'] ?? '').trim();
    if (raw.isEmpty || !raw.startsWith('https://')) return null;
    return raw;
  }
}
