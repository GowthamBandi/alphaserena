import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../controllers/home_controller.dart';
import '../../../core/models/app_notification.dart';
import '../../../core/domain/coach_conversation.dart';
import '../../../core/services/chat_service.dart';
import '../../../core/services/coach_service.dart';
import '../../../core/services/notification_center_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/brand.dart';
import '../../../core/widgets/glass_card.dart';
import '../../join/coach_storefront_screen.dart';
import '../client_chat_screen.dart';
import '../notification_center_screen.dart';
import 'membership_status.dart';

/// Home's identity surface. Answers exactly four questions at a glance:
/// which organization the member belongs to, who their coach is, how to reach
/// that coach, and whether anything is unread.
///
/// Every value is repository-backed. Nothing here is decorative: there is no
/// greeting, no motivational line, no presence dot, no status chip, and the
/// verified badge appears only when `organizationProfiles/{adminId}.verified`
/// is genuinely true.
///
/// Offline is deliberately NOT handled here — `ConnectivityController` mounts a
/// full-screen takeover above every route in `main.dart`, so this widget is
/// never on screen while the member is offline.
///
/// This wrapper is the only part that knows about GetX, Firebase and routing;
/// the rendering lives in [HeaderView], which is pure so every state can be
/// rendered and reviewed in a widget test.
class HomeHeader extends StatelessWidget {
  final HomeController controller;

  const HomeHeader({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final h = controller;
    return Obx(() {
      final logoUrl = h.orgLogoUrl.value;
      final m = h.membershipController;
      final clientId = h.memberController.clientId;
      return _WithCoachConversation(
        clientId: clientId,
        builder: (conversation, notifUnread) => HeaderView(
          conversation: conversation,
          orgName: h.gymName,
          orgLoading: h.orgLoading.value && !h.hasOrgName,
          orgVerified: h.orgVerified.value,
          orgLogo: logoUrl == null ? null : _NetworkLogo(url: logoUrl),
          // ONE membership engine. This used to call `MembershipStatus.of` here
          // with five hand-passed primitives, which meant any second surface
          // wanting the same verdict had to repeat the call — and Profile
          // instead invented its own two-state binary. The derivation now lives
          // on MembershipController and both screens read the same getter.
          membership: m.status,
          // No adminId → no storefront to resolve, so the row stays inert
          // rather than implying a destination that doesn't exist.
          onOpenOrg: h.canOpenStorefront ? () => _openStorefront(h) : null,
          coachName: h.hasCoachName ? h.coachName : null,
          coachPhotoUrl: h.coachPhotoUrl,
          coachAssigned: h.hasTrainer,
          // Always available for a linked member: ClientChatScreen resolves the
          // thread from `linkedClientId`, NOT from `trainerId`, so the
          // conversation works even when a solo coach never assigned a separate
          // trainer record.
          onMessage: () => Get.to(() => const ClientChatScreen()),
          notificationUnread: notifUnread,
          onNotifications: () => Get.to(() => const NotificationCenterScreen()),
        ),
      );
    });
  }

  /// Loads the member's own storefront (`organizationProfiles/{adminId}`) then
  /// opens it. Unchanged behavior — lifted verbatim from the previous header.
  Future<void> _openStorefront(HomeController h) async {
    final adminId = h.memberController.adminId;
    if (adminId.isEmpty) return;
    Get.dialog(
      const Center(child: CircularProgressIndicator()),
      barrierDismissible: false,
    );
    try {
      final org = await CoachService().byId(adminId);
      if (Get.isDialogOpen ?? false) Get.back();
      if (org != null) {
        Get.to(() => CoachStorefrontScreen(org: org));
      } else {
        Get.snackbar(
          'Unavailable',
          'Your coach\'s storefront isn\'t available right now.',
        );
      }
    } catch (_) {
      if (Get.isDialogOpen ?? false) Get.back();
      Get.snackbar(
        'Error',
        'Could not open the storefront. Check your connection.',
      );
    }
  }
}

/// The org-name loading placeholder, keyed so tests can assert its size.
const Key orgNameSkeletonKey = Key('org-name-skeleton');

/// The membership-line loading placeholder, keyed so tests can assert that no
/// date is claimed before the clients document arrives.
const Key membershipSkeletonKey = Key('membership-skeleton');

/// Feeds the coach unread count into the pure [HeaderView].
///
/// A separate widget so the stream is created ONCE per clientId and not
/// rebuilt on every `Obx` tick — a `StreamBuilder` built inline inside the
/// reactive builder would resubscribe to Firestore on each emission of any
/// other observable the header reads.
class _WithCoachConversation extends StatefulWidget {
  final String clientId;
  final Widget Function(CoachConversation c, int notificationUnread) builder;

  const _WithCoachConversation({required this.clientId, required this.builder});

  @override
  State<_WithCoachConversation> createState() => _WithCoachConversationState();
}

class _WithCoachConversationState extends State<_WithCoachConversation> {
  Stream<CoachConversation>? _stream;
  String _boundTo = '';

  /// The notification-centre summary, bound once for the signed-in uid. Lives
  /// here beside the conversation stream so the header takes exactly TWO
  /// listeners in total, both created once rather than per Obx tick.
  late final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final Stream<NotificationSummary>? _notifStream = _uid.isEmpty
      ? null
      : NotificationCenterService().watchSummary(_uid);

  void _bind() {
    if (_boundTo == widget.clientId) return;
    _boundTo = widget.clientId;
    _stream = widget.clientId.isEmpty
        ? null
        : ChatService().watchConversation(widget.clientId);
  }

  @override
  Widget build(BuildContext context) {
    _bind();
    final s = _stream;
    final n = _notifStream;

    Widget withNotifications(CoachConversation c) {
      if (n == null) return widget.builder(c, 0);
      return StreamBuilder<NotificationSummary>(
        stream: n,
        // No data yet → no badge. A count is only claimed once reported.
        builder: (_, snap) => widget.builder(c, snap.data?.unread ?? 0),
      );
    }

    if (s == null) return withNotifications(CoachConversation.empty);
    return StreamBuilder<CoachConversation>(
      stream: s,
      // Empty while loading: a badge that flashes a stale number and then
      // corrects is worse than one that appears once it is known.
      builder: (_, snap) =>
          withNotifications(snap.data ?? CoachConversation.empty),
    );
  }
}

/// The header's pure presentation. Holds no controller, no Firebase and no
/// navigation — every state it can occupy is reachable by construction.
class HeaderView extends StatelessWidget {
  /// The organization's real name. Callers pass the repository value; this
  /// widget never substitutes one of its own.
  final String orgName;

  /// The storefront profile is still resolving AND nothing is cached, so the
  /// name renders as a skeleton instead of flashing a generic fallback.
  final bool orgLoading;

  /// `organizationProfiles/{adminId}.verified`. Platform-controlled.
  final bool orgVerified;

  /// The org's real logo. Null → the neutral AlphaSerena house mark.
  final Widget? orgLogo;

  /// Null → the organization row is not actionable.
  final VoidCallback? onOpenOrg;

  /// The membership line shown directly beneath the organization name.
  final MembershipStatus membership;

  /// The coach's real name, or null when it isn't known.
  final String? coachName;

  /// The coach's avatar, mirrored onto `clientProfiles` by `claimClientAccount`.
  /// Null/empty → initials. Never a stranger's face: the resolver suppresses the
  /// photo whenever it suppresses the name as stale, so the picture and the
  /// name can never describe two different people.
  final String? coachPhotoUrl;

  /// The member's conversation with their coach — unread count, last message
  /// preview, sender and time. Every field comes from the `chats/{clientId}`
  /// thread document the `onMessageCreated` trigger already maintains.
  final CoachConversation conversation;

  /// Whether a trainer record is actually assigned. Only changes the copy —
  /// never whether messaging is offered, because messaging works regardless.
  final bool coachAssigned;

  final VoidCallback onMessage;

  /// Unread notification-centre items. 0 → no badge.
  final int notificationUnread;

  /// Opens the notification centre.
  final VoidCallback onNotifications;

  const HeaderView({
    super.key,
    required this.orgName,
    required this.onMessage,
    required this.onNotifications,
    this.notificationUnread = 0,
    this.membership = const MembershipStatus(MembershipState.loading),
    this.orgLoading = false,
    this.orgVerified = false,
    this.orgLogo,
    this.onOpenOrg,
    this.coachName,
    this.coachPhotoUrl,
    this.conversation = CoachConversation.empty,
    this.coachAssigned = false,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: glassCard(p),
      // 14 top / 12 elsewhere: optical balance. An eyebrow's cap-height sits
      // lower in its line box than an avatar sits in its row, so equal metric
      // padding reads top-heavy.
      padding: const EdgeInsets.fromLTRB(14, 13, 12, 11),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1 — ORGANISATION, as an eyebrow. Context, not headline.
          _orgEyebrow(p),
          const SizedBox(height: 9),
          // 2 — THE COACH. The primary identity of this card.
          _coachRow(p),
          const SizedBox(height: 10),
          Divider(height: 1, thickness: 1, color: p.border),
          const SizedBox(height: 9),
          // 3 — MEMBERSHIP. Standing, read rarely, states itself in one line.
          _membershipLine(p),
        ],
      ),
    );
  }

  /// The organisation as a small-caps EYEBROW.
  ///
  /// It was a 48 px logo tile with a 14 px name beside it — the visually
  /// heaviest element in the card, given to the party the member interacts with
  /// least. A member opens this app to reach their COACH; the gym is the
  /// context that relationship sits inside, and context belongs in an eyebrow.
  /// Removing the tile is the single largest space saving available here, and
  /// it corrects the hierarchy at the same time.
  ///
  /// Letterspaced small caps because at this size lowercase would read as a
  /// forgotten label rather than a deliberate one.
  Widget _orgEyebrow(AppPalette p) {
    final loading = orgLoading;
    final row = Row(
      children: [
        Flexible(
          child: loading
              ? Container(
                  key: orgNameSkeletonKey,
                  height: 9,
                  width: 96,
                  decoration: BoxDecoration(
                    color: p.border,
                    borderRadius: BorderRadius.circular(3),
                  ),
                )
              : Text(
                  orgName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  // THE BRAND RED, at the app's single accent value — not a
                  // brighter variant. At 10.5px small caps the colour reads as
                  // considered branding; the same hue at headline size would
                  // shout, which is why the org stays an eyebrow.
                  style: GoogleFonts.poppins(
                    color: p.accent,
                    fontSize: 10.5,
                    height: 1.2,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
        ),
        if (!loading && orgVerified) ...[
          const SizedBox(width: 5),
          // Sized to the cap-height of the eyebrow, not to a comfortable icon
          // size — a badge larger than the text it qualifies outranks it.
          Icon(Icons.verified_rounded, color: p.accent, size: 12),
        ],
      ],
    );

    final spoken = orgVerified
        ? 'Organization $orgName, verified'
        : 'Organization $orgName';

    if (onOpenOrg == null) {
      return Semantics(label: spoken, excludeSemantics: true, child: row);
    }
    return Semantics(
      button: true,
      label: '$spoken. Open storefront',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: onOpenOrg,
          // The eyebrow is small; the PADDING carries the touch target.
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: row,
          ),
        ),
      ),
    );
  }

  /// The membership line — secondary by design: smaller and quieter than the
  /// organization name, and never coloured unless the state warrants attention.
  /// Urgent states also carry a glyph, so meaning does not depend on colour.
  /// The membership standing, on its own row at the foot of the card.
  ///
  /// It used to be a sub-line of the organisation identity, which tied a fact
  /// about the MEMBER to a row about the GYM and made both harder to scan. As
  /// its own row under a divider it reads as what it is: the member's standing
  /// with this organisation.
  Widget _membershipLine(AppPalette p) {
    if (membership.state == MembershipState.loading) {
      // A short placeholder keeps the header's height stable, so nothing
      // shifts when the clients document lands.
      return Container(
        key: membershipSkeletonKey,
        width: 104,
        height: 10,
        decoration: BoxDecoration(
          color: p.surfaceAlt,
          borderRadius: BorderRadius.circular(3),
        ),
      );
    }

    final urgent = membership.isUrgent;
    final colour = urgent ? p.error : p.textMuted;
    final icon = membership.icon;

    return Semantics(
      label: membership.text,
      excludeSemantics: true,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: colour),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              membership.text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: colour,
                fontSize: 10.5,
                height: 1.2,
                fontWeight: urgent ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The org mark. Real logo when the profile carries one, otherwise the
  /// AlphaSerena "A" — a neutral house mark, never a stand-in for another brand.

  // ── Coach ──────────────────────────────────────────────────────────────
  /// The coach, with messaging built into the same row so contact reads as an
  /// attribute of the coach rather than a floating action. The whole row is one
  /// button, so there is a single target and a single semantic node.
  /// The role label above the coach's name.
  ///
  /// A FIXED label, never conversation content. The secondary line briefly
  /// carried the last message preview, which meant a one-character message
  /// rendered the coach as "Gowtham / d" — technically accurate and completely
  /// wrong for an identity card. Identity does not fluctuate with chat traffic;
  /// unread lives on the message badge, where it cannot corrupt who the person
  /// is.
  String get _roleLabel =>
      coachAssigned || (coachName?.trim().isNotEmpty ?? false)
      ? 'Assigned Coach'
      : 'Coach';

  Widget _coachRow(AppPalette p) {
    final name = coachName?.trim();
    final hasName = name != null && name.isNotEmpty;
    final String line;
    if (hasName) {
      line = name;
    } else if (coachAssigned) {
      line = 'Your coach';
    } else {
      line = 'Not assigned yet';
    }

    final who = hasName
        ? 'Coach $name'
        : coachAssigned
        ? 'Your coach'
        : 'Your coaching team, no coach assigned yet';
    // Assembled from non-empty parts only — interpolating possibly-empty
    // segments produced doubled spaces, which some screen readers announce as
    // an extra pause.
    final label = [
      if (conversation.hasUnread)
        '${conversation.unread} unread '
            '${conversation.unread == 1 ? 'message' : 'messages'}',
      who,
      'Open chat',
    ].join('. ');

    final identity = Padding(
      // The 40px avatar already sets this row's height; extra vertical padding
      // was pure cost.
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: [
          _coachAvatar(p, hasName ? name : null),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // ROLE first, name second — the eyebrow pattern used one level
                // up for the organisation, so the card reads consistently:
                // small muted qualifier, then the thing itself.
                Text(
                  _roleLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: p.textMuted,
                    fontSize: 10.5,
                    height: 1.2,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  line,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: hasName ? p.textPrimary : p.textMuted,
                    fontSize: 15,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // The IDENTITY is the tappable region — NOT the whole row.
    //
    // Wrapping everything in `excludeSemantics: true` silently swallowed the two
    // action icons: ExcludeSemantics drops every descendant node, so a
    // screen-reader user would have found no notification and no message
    // control anywhere in the header. The tap target now stops before the
    // actions, and each icon keeps its own button role and its own count.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Semantics(
            button: true,
            label: label,
            excludeSemantics: true,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: onMessage,
                child: identity,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        // Actions sit on the COACH row, vertically centred on the avatar — the
        // row's optical anchor. Placing them on the org eyebrow would have tied
        // the two most-used controls in the app to the least-important line.
        _actionIcon(
          p,
          icon: Icons.notifications_none_rounded,
          badge: unreadLabel(notificationUnread),
          semantic: notificationUnread > 0
              ? 'Notifications, $notificationUnread unread'
              : 'Notifications',
          onTap: onNotifications,
        ),
        // 10px between the two controls: with 40px tiles and a badge that
        // overhangs its top-right by 4px, anything tighter lets the
        // notification badge visually touch the message tile.
        const SizedBox(width: 10),
        _actionIcon(
          p,
          icon: Icons.chat_bubble_outline_rounded,
          badge: unreadLabel(conversation.unread),
          semantic: conversation.hasUnread
              ? 'Messages, ${conversation.unread} unread'
              : 'Messages',
          onTap: onMessage,
        ),
      ],
    );
  }

  /// Photo → initial → generic glyph, in that order.
  ///
  /// 40px, matching the action tiles beside it so the row has one optical
  /// height. The initial renders UNDERNEATH the network image as both the
  /// loading and the error state: the avatar is always a complete, correct
  /// element and the face simply arrives when it can — never a spinner, never a
  /// blank circle, never a layout shift when it lands.
  Widget _coachAvatar(AppPalette p, String? name) {
    final initial = name != null && name.isNotEmpty
        ? Text(
            name[0].toUpperCase(),
            style: GoogleFonts.poppins(
              color: p.accent,
              fontSize: 15,
              height: 1.1,
              fontWeight: FontWeight.w700,
            ),
          )
        : Icon(Icons.person_outline_rounded, color: p.textMuted, size: 19);

    final url = coachPhotoUrl?.trim() ?? '';
    return Container(
      width: 40,
      height: 40,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: p.surfaceAlt,
        shape: BoxShape.circle,
        border: Border.all(color: p.border),
      ),
      alignment: Alignment.center,
      child: url.isEmpty
          ? initial
          : CachedNetworkImage(
              imageUrl: url,
              width: 40,
              height: 40,
              fit: BoxFit.cover,
              placeholder: (_, _) => initial,
              errorWidget: (_, _, _) => initial,
            ),
    );
  }

  /// One 40x40 action affordance with an optional count badge.
  ///
  /// ONE builder for both the bell and the chat icon, so they can never drift
  /// apart in size, radius, badge geometry or press feedback — two
  /// hand-maintained near-copies is exactly how a card starts looking
  /// assembled rather than designed.
  ///
  /// 40x40 is the drawn box; the Semantics/InkWell target is padded to 44 so it
  /// meets the platform minimum without a 44px chrome box dominating the row.
  Widget _actionIcon(
    AppPalette p, {
    required IconData icon,
    required String badge,
    required String semantic,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: semantic,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: p.surfaceAlt,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Stack(
                  clipBehavior: Clip.none,
                  alignment: Alignment.center,
                  children: [
                    Icon(icon, color: p.textPrimary, size: 19),
                    if (badge.isNotEmpty)
                      Positioned(
                        top: -3,
                        right: -4,
                        // Entry only, keyed on the VALUE: it replays when the
                        // count changes and stays still otherwise. There is no
                        // exit animation — that would pull the eye back to
                        // something the member has just dealt with.
                        child: TweenAnimationBuilder<double>(
                          key: ValueKey(badge),
                          tween: Tween(begin: 0.8, end: 1),
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutBack,
                          builder: (_, t, child) => Transform.scale(
                            scale: t,
                            child: Opacity(
                              opacity: t.clamp(0.0, 1.0),
                              child: child,
                            ),
                          ),
                          child: Container(
                            constraints: const BoxConstraints(minWidth: 17),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.5,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: p.accent,
                              borderRadius: BorderRadius.circular(9),
                              // A ring in the CARD colour, so the badge reads as
                              // floating above the tile instead of merging with
                              // its corner.
                              border: Border.all(color: p.surface, width: 1.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              badge,
                              style: GoogleFonts.poppins(
                                color: Colors.white,
                                fontSize: 9.5,
                                height: 1.25,
                                fontWeight: FontWeight.w700,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                            ),
                          ),
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
}

/// The real org logo, cached. Falls back to the house mark if the image fails.
class _NetworkLogo extends StatelessWidget {
  final String url;

  const _NetworkLogo({required this.url});

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      width: 52,
      height: 52,
      fit: BoxFit.cover,
      placeholder: (_, _) => const SizedBox.shrink(),
      errorWidget: (_, _, _) => const AlphaAMark(size: 26),
    );
  }
}

/// Header for a member with no organization yet — house brand + notifications.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Container(
      decoration: glassCard(p),
      padding: const EdgeInsets.fromLTRB(12, 11, 11, 11),
      child: Row(
        children: [
          const AlphaAMark(size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'AlphaSerena',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.poppins(
                color: p.textPrimary,
                fontSize: 16,
                height: 1.25,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.4,
              ),
            ),
          ),
          const SizedBox(width: 8),
          const NotificationBell(),
        ],
      ),
    );
  }
}

/// Notification button with the real unread badge.
///
/// Stateful so the Firestore stream is created ONCE and survives the
/// dashboard's Obx rebuilds — an inline `StreamBuilder(stream: watchSummary())`
/// handed a brand-new stream to every rebuild, re-subscribing the snapshot
/// listener and flashing the badge back to 0 each time.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});

  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  late final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final Stream<NotificationSummary>? _stream = _uid.isEmpty
      ? null
      : NotificationCenterService().watchSummary(_uid);

  @override
  Widget build(BuildContext context) {
    final stream = _stream;
    if (stream == null) return const SizedBox.shrink();
    return StreamBuilder<NotificationSummary>(
      stream: stream,
      builder: (context, snap) {
        // No data yet (still loading, or no summary doc) → no badge. An unread
        // count is only ever claimed once the document actually reports one.
        return NotificationButton(
          unread: snap.data?.unread ?? 0,
          onTap: () => Get.to(() => const NotificationCenterScreen()),
        );
      },
    );
  }
}

/// The bell's presentation — pure, so the badge states are directly testable.
class NotificationButton extends StatelessWidget {
  final int unread;
  final VoidCallback onTap;

  const NotificationButton({
    super.key,
    required this.unread,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Semantics(
      button: true,
      label: unread > 0 ? 'Notifications, $unread unread' : 'Notifications',
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(13),
          onTap: onTap,
          // 44x44 minimum touch target.
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: p.border),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Icon(
                  Icons.notifications_none_rounded,
                  color: p.textPrimary,
                  size: 21,
                ),
                if (unread > 0)
                  Positioned(
                    top: -5,
                    right: -6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1.5,
                      ),
                      constraints: const BoxConstraints(minWidth: 15),
                      decoration: BoxDecoration(
                        color: p.accent,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: p.background, width: 1.5),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.poppins(
                          color: Colors.white,
                          fontSize: 8.5,
                          height: 1.2,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
