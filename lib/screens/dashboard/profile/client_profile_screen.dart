import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../controllers/auth_controller.dart';
import '../../../controllers/member_controller.dart';
import '../../../controllers/membership_controller.dart';
import '../../../controllers/theme_controller.dart';
import '../../../core/domain/member_identity.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/brand.dart';
import '../home/membership_status.dart';
import '../log_transformation_screen.dart';
import '../membership_screen.dart';
import '../../join/coach_storefront_screen.dart';
import 'account_screen.dart';
import 'assigned_coach_profile_screen.dart';
import 'feedback_history_screen.dart';
import 'edit_profile_screen.dart';
import 'notification_settings_screen.dart';
import 'privacy_visibility_screen.dart';
import 'rating_center_screen.dart';

/// Profile — member card, partner, subscription, quick access, account.
///
/// **Every value on this screen is production data or an honest absence.** It
/// previously carried five fabrications that shipped as if they were facts: an
/// organization called 'Alpha Arena', a coach called 'Your Coach' holding the
/// job title 'Performance Coach', a stock portrait from `assets/images/trainer.png`
/// presented as that coach's face, and a plan called 'Transform Program'. Each
/// of those had already been removed from Home — the domain layer even documents
/// why — and this screen was simply never brought forward with it.
class ClientProfileScreen extends StatelessWidget {
  const ClientProfileScreen({super.key});

  /// Member-since, or `''` when the record carries no creation date.
  ///
  /// The previous fallback was the word 'Recent', which asserted a recency the
  /// document did not state. Note this is when the COACH created the member's
  /// record, which is the only join date the platform actually stores.
  String _memberSince(Map<String, dynamic>? clientData) {
    final created = clientData?['createdAt'];
    if (created is Timestamp) {
      return DateFormat('MMM yyyy').format(created.toDate());
    }
    if (created is String) {
      final parsed = DateTime.tryParse(created);
      if (parsed != null) return DateFormat('MMM yyyy').format(parsed);
    }
    return '';
  }

  /// `72.0` → `72`, `72.5` → `72.5`. A whole number should not carry a decimal
  /// the member never typed.
  String _trim(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final member = Get.isRegistered<MemberController>()
        ? Get.find<MemberController>()
        : Get.put(MemberController());
    final membership = Get.isRegistered<MembershipController>()
        ? Get.find<MembershipController>()
        : Get.put(MembershipController());

    return Scaffold(
      backgroundColor: p.background,
      body: SafeArea(
        bottom: false,
        child: Obx(() {
          // The whole-screen skeleton waits ONLY on the member's own load.
          //
          // It must NOT wait on `isMembershipLoading`: that stays true forever
          // for an unlinked member (no `clients` document is ever streamed for
          // them), which would leave them staring at a skeleton for the entire
          // session. Membership loading is handled per-component below, exactly
          // as Home does it — the card that makes a membership claim is the card
          // that waits for the evidence.
          //
          // It must also NOT gate on `membership.isLoading`, the previous gate:
          // that tracks the membership PLANS query and, as MembershipController
          // documents in so many words, "says nothing about the member's own
          // membership". It clears immediately when no adminId is known yet,
          // while `isLinked` flips true from the earlier clientProfiles snapshot
          // — so the screen rendered a full membership verdict before the
          // `clients` document arrived, and an active, paying member's first
          // paint read "Transform Program · Expired · Valid Till N/A".
          if (member.isLoading.value) {
            return _skeletonLoader(p);
          }

          final linked = member.isLinked.value;
          final status = membership.status;

          return RefreshIndicator(
            onRefresh: () async {
              // Refresh BOTH identities. This used to call `claim()` alone, so
              // a renamed organization had no in-app path to its current name:
              // the storefront is fetched once per session.
              await Future.wait([member.claim(), member.refreshOrg()]);
            },
            color: p.accent,
            child: ListView(
              // Without this the list is not scrollable when the content fits
              // the viewport (tablet, or an unlinked member on a large device),
              // and pull-to-refresh silently cannot be triggered at all.
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width >= 700 ? 28 : 18,
                8,
                MediaQuery.sizeOf(context).width >= 700 ? 28 : 18,
                24,
              ),
              children: [
                _header(p),
                const SizedBox(height: 12),
                _memberCard(member, status, p),
                const SizedBox(height: 12),
                if (linked) ...[
                  _partnerCard(member, p),
                  const SizedBox(height: 12),
                  _subscriptionCard(membership, status, p),
                  if (membership.isActive) ...[
                    const SizedBox(height: 12),
                    _rateUsEntry(p),
                  ],
                  const SizedBox(height: 14),
                ] else ...[
                  _unlinkedPlaceholder(p),
                  const SizedBox(height: 14),
                ],
                _editProfileSection(p),
                const SizedBox(height: 14),
                _account(context, p),
                const SizedBox(height: 16),
                _logout(context, p),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _header(AppPalette p) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Profile',
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Manage your profile and preferences.',
                style: GoogleFonts.poppins(color: p.textMuted, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _memberCard(
    MemberController member,
    MembershipStatus status,
    AppPalette p,
  ) {
    final name = member.name;
    // Contact rows are RENDERED ONLY WHEN REAL. They previously fell back to the
    // literal strings 'No Phone' / 'No Email', which a Google-signed-in member
    // saw beside their own verified address: the phone came straight from
    // `FirebaseAuth.phoneNumber` (null for Google) and the email was read from a
    // key only Identity Setup ever writes.
    final email = member.email;

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _memberAvatar(member, p),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      name.isNotEmpty ? name : 'Add your name',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: name.isNotEmpty ? p.textPrimary : p.textMuted,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: p.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Align(
                alignment: Alignment.topRight,
                child: _statusBadge(status, p),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: p.border, height: 1),
          const SizedBox(height: 11),
          _statsRow(member, p),
        ],
      ),
    );
  }

  Widget _rateUsEntry(AppPalette p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Rate Us',
        style: GoogleFonts.poppins(
          color: p.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Semantics(
        button: true,
        label: 'Open Rating Center',
        child: InkWell(
          borderRadius: AppRadii.cardR,
          onTap: () => Get.to(() => const RatingCenterScreen()),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: AppRadii.cardR,
              border: Border.all(color: p.border),
            ),
            child: Row(
              children: [
                Icon(Icons.star_outline_rounded, color: p.accent, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Rating Center',
                        style: TextStyle(
                          color: p.textPrimary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        'Rate your organization and assigned coach',
                        style: TextStyle(color: p.textMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: p.textMuted),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  /// The member's OWN photo, or their initials. Never a stock avatar.
  ///
  /// The member uploads this in Identity Setup, it is stored on their profile
  /// and projected to their coach — and until now it was never shown back to
  /// them anywhere in the app. This card rendered `assets/images/avatar.png`
  /// with a letter painted on top of it.
  Widget _memberAvatar(MemberController member, AppPalette p) {
    final photo = member.photoUrl;
    final initials = member.initials;

    Widget fallback() => Container(
      color: p.surfaceAlt,
      alignment: Alignment.center,
      child: initials.isNotEmpty
          ? Text(
              initials,
              style: AppText.title(size: 20).copyWith(color: p.accent),
            )
          : Icon(Icons.person_outline, color: p.textMuted, size: 26),
    );

    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: p.accent, width: 2),
      ),
      child: ClipOval(
        child: SizedBox(
          width: 64,
          height: 64,
          child: photo.isEmpty
              ? fallback()
              : CachedNetworkImage(
                  imageUrl: photo,
                  fit: BoxFit.cover,
                  placeholder: (_, _) => Container(color: p.surfaceAlt),
                  errorWidget: (_, _, _) => fallback(),
                ),
        ),
      ),
    );
  }

  /// The membership badge — one vocabulary, shared with Home.
  ///
  /// This was an independent Active/Inactive binary computed from
  /// `isLinked && isActive`, giving the screen a THIRD word for a fact its own
  /// subscription card described differently and Home described differently
  /// again. It now renders `MembershipStatus`, glyph included, so a paused
  /// membership reads "Paused" everywhere.
  Widget _statusBadge(MembershipStatus status, AppPalette p) {
    if (status.state == MembershipState.loading) return const SizedBox.shrink();
    final urgent = status.isUrgent;
    final fg = urgent ? p.error : p.success;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: fg.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (status.icon != null) ...[
            Icon(status.icon, color: fg, size: 11),
            const SizedBox(width: 4),
          ],
          Text(
            status.shortText,
            style: GoogleFonts.poppins(
              color: fg,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(MemberController member, AppPalette p) {
    // AGE WAS STRUCTURALLY DEAD. This read `clientProfiles.age`, but `age` is a
    // coach-authored field on `clients` (TrainerHQ's ClientModel writes it), and
    // the rules make `clientProfiles` writable by exactly one party — the member
    // — so the coach could not have written it there even in principle. Nothing
    // in any of the three repositories wrote that key, and the tile rendered
    // '--' for every member in production. `member.age` now resolves the two
    // REAL sources, preferring the member's own date of birth over the coach's
    // frozen integer.
    final age = member.age;
    final height = member.heightCm;
    final weight = member.weightKg;
    final since = _memberSince(member.client.value);

    // '--' now means genuinely unknown, and only that.
    final s = [
      (Icons.cake_outlined, 'Age', age == null ? '--' : '$age'),
      (
        Icons.straighten,
        'Height',
        height == null ? '--' : '${_trim(height)} cm',
      ),
      (
        Icons.monitor_weight_outlined,
        'Weight',
        weight == null ? '--' : '${_trim(weight)} kg',
      ),
      (Icons.verified_outlined, 'Member Since', since.isEmpty ? '--' : since),
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: s
          .map(
            (e) => Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  children: [
                    Icon(e.$1, color: p.accent, size: 15),
                    const SizedBox(height: 4),
                    Text(
                      e.$2,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: p.textMuted,
                        fontSize: 8.5,
                      ),
                    ),
                    const SizedBox(height: 1),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        e.$3,
                        style: GoogleFonts.poppins(
                          color: p.textPrimary,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _editProfileSection(AppPalette p) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'Edit Profile',
        style: GoogleFonts.poppins(
          color: p.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      const SizedBox(height: 8),
      Container(
        decoration: BoxDecoration(
          color: p.surface,
          borderRadius: AppRadii.cardR,
          border: Border.all(color: p.border),
        ),
        child: _accountRow(
          Icons.person_outline,
          'Edit Profile',
          'Manage your personal information, photo and health profile.',
          p,
          onTap: () => Get.to(() => const EditProfileScreen()),
        ),
      ),
    ],
  );

  Widget _partnerCard(MemberController member, AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              borderRadius: AppRadii.smR,
              onTap: member.adminId.isEmpty
                  ? null
                  : () => Get.to(
                      () => LiveCoachStorefrontScreen(adminId: member.adminId),
                    ),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    // The organization's OWN logo when it has one, else the neutral
                    // AlphaSerena mark — never another org's branding.
                    Container(
                      width: 40,
                      height: 40,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: p.surfaceAlt,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: (member.orgLogoUrl.value ?? '').isEmpty
                          ? const AlphaAMark(size: 24)
                          : CachedNetworkImage(
                              imageUrl: member.orgLogoUrl.value!,
                              width: 40,
                              height: 40,
                              fit: BoxFit.cover,
                              placeholder: (_, _) => const AlphaAMark(size: 24),
                              errorWidget: (_, _, _) =>
                                  const AlphaAMark(size: 24),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Organization',
                            style: GoogleFonts.poppins(
                              color: p.textMuted,
                              fontSize: 11,
                            ),
                          ),
                          // 'Alpha Arena' is gone. HomeController's own comment
                          // records why it was removed there: the fallback "looked
                          // like a real gym". `member.orgName` resolves the LIVE
                          // storefront name ahead of the stale mirror, so a renamed
                          // organization shows its current name.
                          // The SAME unknown-state wording Home uses. A generic role
                          // label ("Your Organization") is not a fabrication — it
                          // cannot be mistaken for a gym's name, which is exactly
                          // why Home adopted it over 'Alpha Arena'. What matters
                          // here is that both screens say the identical thing: a
                          // member must never read "Not available" on one tab and
                          // "Your Organization" on the next.
                          Text(
                            member.orgName.isNotEmpty
                                ? member.orgName
                                : 'Your Organization',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: member.orgName.isNotEmpty
                                  ? p.textPrimary
                                  : p.textMuted,
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          // The hardcoded tagline "Your journey, our arena." used to
                          // sit here, presented as if the organization had written
                          // it. No organization tagline is stored anywhere, so
                          // nothing replaces it.
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(width: 1, height: 56, color: p.border),
          const SizedBox(width: 10),
          Expanded(
            child: InkWell(
              borderRadius: AppRadii.smR,
              onTap: member.coachId.isEmpty
                  ? null
                  : () => Get.to(() => const AssignedCoachProfileScreen()),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Your coach',
                            style: GoogleFonts.poppins(
                              color: p.accent,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          // 'Your Coach' as a NAME is gone. `resolveCoachName`
                          // deliberately returns '' when no name can be honestly
                          // claimed — its own comment records that placeholder coach
                          // names "fired for essentially every member in
                          // production" — and this card was re-fabricating the exact
                          // placeholder that rule exists to prevent.
                          Text(
                            member.trainerName.isNotEmpty
                                ? member.trainerName
                                : 'Not assigned yet',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(
                              color: member.trainerName.isNotEmpty
                                  ? p.textPrimary
                                  : p.textMuted,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          // The hardcoded job title 'Performance Coach' used to sit
                          // here. No coach job title is stored anywhere.
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    _coachAvatar(member, p),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The coach's REAL photo, or their initials, or a neutral glyph.
  ///
  /// This rendered `assets/images/trainer.png` — a stock portrait of a person
  /// who is not the member's coach — under the heading "Your Trainer". The
  /// domain layer already forbids exactly this: `resolveCoachPhoto` exists so
  /// that callers "render initials, never a stranger's face", and it gates the
  /// photo on the name so a suppressed stale name suppresses its picture too.
  /// `member.trainerPhotoUrl` is that resolver's output, live-resolved per
  /// session, and this card simply ignored it.
  Widget _coachAvatar(MemberController member, AppPalette p) {
    final photo = member.trainerPhotoUrl;
    final initials = initialsOf(member.trainerName);

    Widget fallback() => Container(
      color: p.surfaceAlt,
      alignment: Alignment.center,
      child: initials.isNotEmpty
          ? Text(
              initials,
              style: AppText.title(size: 12).copyWith(color: p.accent),
            )
          : Icon(Icons.person_outline, color: p.textMuted, size: 16),
    );

    return ClipOval(
      child: SizedBox(
        width: 34,
        height: 34,
        child: photo.isEmpty
            ? fallback()
            : CachedNetworkImage(
                imageUrl: photo,
                fit: BoxFit.cover,
                placeholder: (_, _) => Container(color: p.surfaceAlt),
                errorWidget: (_, _, _) => fallback(),
              ),
      ),
    );
  }

  Widget _unlinkedPlaceholder(AppPalette p) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Icon(Icons.link_off_rounded, color: p.accent, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'No Coach Connected',
                  style: GoogleFonts.poppins(
                    color: p.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Connect with a coach to see trainer bio and organization info here.',
                  style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _subscriptionCard(
    MembershipController membership,
    MembershipStatus status,
    AppPalette p,
  ) {
    final loading = status.state == MembershipState.loading;
    // 'Transform Program' is gone. An absent plan name is stated as absent.
    final planName = membership.planName;
    final expiry = membership.expiry;
    final formattedExpiry = expiry != null
        ? DateFormat('dd MMM yyyy').format(expiry)
        : '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Membership',
          style: GoogleFonts.poppins(
            color: p.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        // Per-component loading: the card that makes the membership claim is
        // the one that waits for the `clients` document, so an unlinked member
        // is never trapped behind a whole-screen skeleton.
        if (loading)
          Container(
            height: 74,
            decoration: BoxDecoration(
              color: p.surfaceAlt,
              borderRadius: AppRadii.cardR,
            ),
          )
        else
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: p.surface,
              borderRadius: AppRadii.cardR,
              border: Border.all(color: p.border),
            ),
            child: InkWell(
              onTap: () => Get.to(() => MembershipScreen()),
              borderRadius: AppRadii.cardR,
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFF9B5DE5).withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.workspace_premium,
                      color: Color(0xFF9B5DE5),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          planName.isNotEmpty ? planName : 'No plan on record',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(
                            color: planName.isNotEmpty
                                ? p.textPrimary
                                : p.textMuted,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        // THE contradiction this replaces: the pill was a
                        // two-state Active/Expired binary derived from
                        // `membership.isActive`, which is false when a membership
                        // is FROZEN. A coach who paused a member's membership —
                        // usually a kindness, for travel, injury or a payment
                        // holiday — had that member told their membership had
                        // EXPIRED here, "Inactive" in the card above, and "Paused"
                        // on Home. One fact, three words, two screens.
                        Row(
                          children: [
                            if (status.icon != null) ...[
                              Icon(
                                status.icon,
                                size: 12,
                                color: status.isUrgent ? p.error : p.success,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                status.text,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(
                                  color: status.isUrgent ? p.error : p.success,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Only the expiry DATE. The old "N Days Left" line was a third
                  // day-count algorithm (raw `Duration.inDays` truncation)
                  // alongside MembershipStatus's calendar-day maths and
                  // TrainerHQ's `ceil()`, so the same membership could report
                  // different numbers on different screens. The countdown now
                  // comes from the shared engine, and only when it is actually
                  // the actionable fact (see MembershipStatus.text).
                  if (formattedExpiry.isNotEmpty)
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Valid till',
                          style: GoogleFonts.poppins(
                            color: p.textMuted,
                            fontSize: 11,
                          ),
                        ),
                        Text(
                          formattedExpiry,
                          style: GoogleFonts.poppins(
                            color: p.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  Icon(Icons.chevron_right, color: p.textMuted, size: 18),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _account(BuildContext context, AppPalette p) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account Settings',
          style: GoogleFonts.poppins(
            color: p.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: AppRadii.cardR,
            border: Border.all(color: p.border),
          ),
          child: Column(
            children: [
              _accountRow(
                Icons.straighten,
                'Transformation',
                'Log weight, measurements, photos, and notes together',
                p,
                onTap: () => Get.to(() => const LogTransformationScreen()),
              ),
              Divider(color: p.border, height: 1, indent: 14, endIndent: 14),
              _accountRow(
                Icons.notifications_outlined,
                'Notifications',
                'Choose what you get notified about',
                p,
                onTap: () => Get.to(() => const NotificationSettingsScreen()),
              ),
              Divider(color: p.border, height: 1, indent: 14, endIndent: 14),
              _appearanceRow(p),
              Divider(color: p.border, height: 1, indent: 14, endIndent: 14),
              _accountRow(
                Icons.visibility_outlined,
                'What your coach can see',
                'Exactly what is shared from your profile',
                p,
                onTap: () => Get.to(() => const PrivacyVisibilityScreen()),
              ),
              Divider(color: p.border, height: 1, indent: 14, endIndent: 14),
              // The recipient is now named correctly. This row said "to your
              // coach" while the sheet it opens says "Only your gym admin sees
              // this — not your trainer" — and the sheet was the accurate one:
              // the rules deny trainers read access to `client_feedback`.
              _accountRow(
                Icons.support_agent_outlined,
                'Report a problem',
                'Goes to your organization, not your trainer',
                p,
                onTap: () => _openFeedbackSheet(context),
              ),
              Divider(color: p.border, height: 1, indent: 14, endIndent: 14),
              _accountRow(
                Icons.forum_outlined,
                'My requests',
                'What you have sent, and any replies',
                p,
                onTap: () => Get.to(() => const FeedbackHistoryScreen()),
              ),
              Divider(color: p.border, height: 1, indent: 14, endIndent: 14),
              _accountRow(
                Icons.shield_outlined,
                'Account & legal',
                'Terms, privacy, app version and account deletion',
                p,
                onTap: () => Get.to(() => const AccountScreen()),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _openFeedbackSheet(BuildContext context) {
    final p = context.palette;
    final member = Get.isRegistered<MemberController>()
        ? Get.find<MemberController>()
        : Get.put(MemberController());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _FeedbackSheet(member: member),
    );
  }

  /// Dark/light switch. Relocated here from the Home header, which was the
  /// app's ONLY theme entry point — the header now carries organization,
  /// coach and notifications alone, so the setting lives with the other
  /// preferences instead of disappearing.
  Widget _appearanceRow(AppPalette p) {
    final theme = Get.find<ThemeController>();
    return Obx(() {
      final dark = theme.isDarkMode.value;
      return Semantics(
        toggled: dark,
        label: 'Dark mode',
        excludeSemantics: true,
        child: Padding(
          padding: const EdgeInsets.only(left: 14, right: 6),
          child: Row(
            children: [
              Icon(
                dark ? Icons.dark_mode_outlined : Icons.light_mode_outlined,
                color: p.textMuted,
                size: 18,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Dark mode',
                      style: GoogleFonts.poppins(
                        color: p.textPrimary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      dark ? 'Dark theme is on' : 'Light theme is on',
                      style: GoogleFonts.poppins(
                        color: p.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
              Switch.adaptive(
                value: dark,
                activeThumbColor: p.accent,
                onChanged: (_) => theme.toggleTheme(),
              ),
            ],
          ),
        ),
      );
    });
  }

  Widget _accountRow(
    IconData icon,
    String title,
    String sub,
    AppPalette p, {
    VoidCallback? onTap,
  }) {
    // These rows had no screen-reader semantics at all — the whole screen
    // exposed exactly one Semantics node (the dark-mode switch).
    return Semantics(
      button: true,
      label: '$title. $sub',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Icon(icon, color: p.textMuted, size: 18),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.poppins(
                        color: p.textPrimary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      sub,
                      // 10px was below any readable floor; 11 is the label floor
                      // used by the rest of this foundation.
                      style: GoogleFonts.poppins(
                        color: p.textMuted,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: p.textMuted, size: 18),
            ],
          ),
        ),
      ),
    );
  }

  Widget _logout(BuildContext context, AppPalette p) {
    return Semantics(
      button: true,
      label: 'Log out',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: () {
          Get.dialog(
            AlertDialog(
              backgroundColor: p.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              // Plain words in a destructive confirmation. "Exit the Arena?" spent
              // the one moment that must be unambiguous on brand voice.
              title: Text(
                'Log out?',
                style: AppText.title(size: 18).copyWith(color: p.textPrimary),
              ),
              content: Text(
                'You\'ll need to sign in again to reach your coaching.',
                style: AppText.body(size: 14).copyWith(color: p.textSecondary),
              ),
              actions: [
                TextButton(
                  onPressed: () => Get.back(),
                  child: Text('Cancel', style: TextStyle(color: p.textMuted)),
                ),
                TextButton(
                  onPressed: () {
                    Get.back();
                    Get.find<AuthController>().signOut();
                  },
                  child: Text(
                    'Log Out',
                    style: TextStyle(
                      color: p.accent,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: p.error.withValues(alpha: 0.4)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.logout, color: p.error, size: 18),
              const SizedBox(width: 8),
              Text(
                'Log out',
                style: GoogleFonts.poppins(
                  color: p.error,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _skeletonLoader(AppPalette p) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 100,
                  height: 24,
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Container(
                  width: 160,
                  height: 12,
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(
          width: double.infinity,
          height: 90,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          height: 60,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          height: 80,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          height: 80,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          height: 150,
          decoration: BoxDecoration(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ],
    );
  }
}

/// The Help & Support bottom sheet: pick a category, write a message, optionally
/// request a different trainer / stay anonymous, and submit to `client_feedback`.
class _FeedbackSheet extends StatefulWidget {
  final MemberController member;
  const _FeedbackSheet({required this.member});

  @override
  State<_FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<_FeedbackSheet> {
  final FeedbackService _service = FeedbackService();
  final TextEditingController _message = TextEditingController();
  // (display label, canonical FeedbackCategory id consumed by TrainerHQ).
  static const List<(String, String)> _categories = [
    ('General', 'other'),
    ('Trainer', 'trainer'),
    ('Plans', 'plans'),
    ('Service', 'service'),
    ('Billing', 'billing'),
    ('App issue', 'app'),
  ];
  String _category = 'other';
  bool _requestTrainerChange = false;
  bool _anonymous = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _message.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return; // re-entry guard: a double-tap must not create two docs
    final msg = _message.text.trim();
    if (msg.isEmpty) {
      setState(() => _error = 'Please describe your feedback or concern.');
      return;
    }
    if (!_service.canSend) {
      setState(() => _error = 'Join a coach before sending feedback.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final aboutTrainer = _category == 'trainer';
    final id = await _service.submit(
      category: _category,
      message: msg,
      anonymous: _anonymous,
      requestTrainerChange: _requestTrainerChange,
      trainerId: aboutTrainer ? widget.member.trainerId : null,
      trainerName: aboutTrainer ? widget.member.trainerName : null,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (id != null) {
      Navigator.of(context).pop();
      Get.snackbar(
        'Sent',
        'Your coach will get back to you.',
        snackPosition: SnackPosition.BOTTOM,
      );
    } else {
      setState(() => _error = 'Could not send. Please try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Help & Support',
              style: AppText.title(size: 18).copyWith(color: p.textPrimary),
            ),
            const SizedBox(height: 4),
            Text(
              'Feedback, an issue, or a concern. Only your gym admin sees this — not your trainer.',
              style: AppText.body(size: 12).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 16),
            Text(
              'CATEGORY',
              style: AppText.label(
                size: 11,
              ).copyWith(color: p.textSecondary, letterSpacing: 1),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _categories.map((cat) {
                final label = cat.$1;
                final id = cat.$2;
                final sel = id == _category;
                return GestureDetector(
                  onTap: () => setState(() => _category = id),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: sel
                          ? p.accent.withValues(alpha: 0.16)
                          : Colors.transparent,
                      borderRadius: AppRadii.smR,
                      border: Border.all(color: sel ? p.accent : p.border),
                    ),
                    child: Text(
                      label,
                      style: AppText.body(size: 12.5).copyWith(
                        color: sel ? p.accent : p.textMuted,
                        fontWeight: sel ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _message,
              maxLines: 4,
              style: AppText.body(size: 14).copyWith(color: p.textPrimary),
              decoration: InputDecoration(
                hintText: 'Describe your feedback or concern…',
                hintStyle: AppText.body(size: 13).copyWith(color: p.textMuted),
                filled: true,
                fillColor: p.background,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: AppRadii.smR,
                  borderSide: BorderSide(color: p.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: AppRadii.smR,
                  borderSide: BorderSide(color: p.accent, width: 1.4),
                ),
              ),
            ),
            const SizedBox(height: 4),
            _toggleRow(
              p,
              'Request a different trainer',
              _requestTrainerChange,
              (v) => setState(() => _requestTrainerChange = v),
            ),
            // ACCURATE LABEL. This read "Send anonymously", which promises more
            // than the system delivers: the submission still carries `authUid`,
            // `clientId` and `clientName`, and TrainerHQ honours the flag only
            // by rendering "Anonymous" in place of the name. The organization
            // can still tell who wrote it. Describing the actual behaviour is
            // the honest fix; claiming untraceability would not be.
            _toggleRow(
              p,
              'Don\'t show my name',
              _anonymous,
              (v) => setState(() => _anonymous = v),
              hint:
                  'Your name is hidden in your coach\'s inbox. This is not '
                  'fully anonymous — your organization can still identify you.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: AppText.body(
                  size: 12,
                ).copyWith(color: const Color(0xFFFF1744)),
              ),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: AppRadii.smR),
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Text(
                        'Send to coach',
                        style: AppText.label(
                          size: 14,
                        ).copyWith(color: Colors.white),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow(
    AppPalette p,
    String label,
    bool value,
    ValueChanged<bool> onChanged, {
    String? hint,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: AppText.body(size: 13).copyWith(color: p.textPrimary),
              ),
              if (hint != null && value) ...[
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: AppText.body(size: 11).copyWith(color: p.textMuted),
                ),
              ],
            ],
          ),
        ),
        Checkbox(
          value: value,
          activeColor: p.accent,
          onChanged: (v) => onChanged(v ?? false),
        ),
      ],
    );
  }
}
