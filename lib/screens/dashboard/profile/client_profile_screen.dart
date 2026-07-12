import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../controllers/auth_controller.dart';
import '../../../controllers/member_controller.dart';
import '../../../controllers/membership_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/services/review_service.dart';
import '../../../core/services/feedback_service.dart';
import '../../../core/widgets/brand.dart';
import '../membership_screen.dart';
import 'body_measurements_screen.dart';

/// Profile — member card, partner, subscription, quick access, account.
class ClientProfileScreen extends StatelessWidget {
  const ClientProfileScreen({super.key});

  String _getLatestWeight(Map<String, dynamic>? profile) {
    final log = profile?['weightLog'];
    if (log is List && log.isNotEmpty) {
      final last = log.last;
      if (last is Map) {
        final w = last['weight'];
        if (w is num) return '${w.toStringAsFixed(1)} kg';
      }
    }
    final initialW = profile?['weight'];
    if (initialW is num) return '$initialW kg';
    return '--';
  }

  String _getMemberSince(Map<String, dynamic>? clientData) {
    final created = clientData?['createdAt'];
    if (created is Timestamp) {
      return DateFormat('MMM yyyy').format(created.toDate());
    }
    if (created is String) {
      final parsed = DateTime.tryParse(created);
      if (parsed != null) return DateFormat('MMM yyyy').format(parsed);
    }
    return 'Recent';
  }

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
          final loading = member.isLoading.value || membership.isLoading.value;
          if (loading) {
            return _skeletonLoader(p);
          }

          final linked = member.isLinked.value;

          return RefreshIndicator(
            onRefresh: () async {
              await member.claim();
            },
            color: p.accent,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
              children: [
                _header(p),
                const SizedBox(height: 16),
                _memberCard(member, p),
                const SizedBox(height: 12),
                _statsRow(member, p),
                const SizedBox(height: 16),
                if (linked) ...[
                  _partnerCard(member, p),
                  const SizedBox(height: 16),
                  _subscriptionCard(membership, p),
                  if (membership.isActive) ...[
                    const SizedBox(height: 16),
                    _RateCoachCard(member: member),
                  ],
                  const SizedBox(height: 18),
                ] else ...[
                  _unlinkedPlaceholder(p),
                  const SizedBox(height: 18),
                ],
                _account(context, p),
                const SizedBox(height: 20),
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
                style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 24, fontWeight: FontWeight.w700),
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

  Widget _memberCard(MemberController member, AppPalette p) {
    final name = member.name;
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber ?? 'No Phone';
    final email = member.profile.value?['email']?.toString() ?? 'No Email';
    final active = member.isLinked.value && Get.find<MembershipController>().isActive;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: p.accent, width: 2),
            ),
            child: CircleAvatar(
              radius: 28,
              backgroundColor: p.surfaceAlt,
              backgroundImage: const AssetImage('assets/images/avatar.png'),
              child: name.isEmpty
                  ? null
                  : Text(
                      name[0].toUpperCase(),
                      style: AppText.title(size: 20).copyWith(color: p.accent),
                    ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF2EBD59) : p.textMuted.withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        active ? 'Active' : 'Inactive',
                        style: GoogleFonts.poppins(
                          color: active ? Colors.white : p.textMuted,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                if (email != 'No Email')
                  Row(
                    children: [
                      Icon(Icons.mail_outline, color: p.textMuted, size: 12),
                      const SizedBox(width: 6),
                      Text(email, style: GoogleFonts.poppins(color: p.textMuted, fontSize: 11)),
                    ],
                  ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(Icons.call, color: p.textMuted, size: 12),
                    const SizedBox(width: 6),
                    Text(phone, style: GoogleFonts.poppins(color: p.textMuted, fontSize: 11)),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _statsRow(MemberController member, AppPalette p) {
    final age = member.profile.value?['age']?.toString() ?? '--';
    final height = member.profile.value?['height'] != null ? '${member.profile.value?['height']} cm' : '--';
    final weight = _getLatestWeight(member.profile.value);
    final since = _getMemberSince(member.client.value);

    final s = [
      (Icons.cake_outlined, 'Age', age),
      (Icons.straighten, 'Height', height),
      (Icons.monitor_weight_outlined, 'Weight', weight),
      (Icons.verified_outlined, 'Joined', since),
    ];

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: s
            .map((e) => Expanded(
                  child: Column(
                    children: [
                      Icon(e.$1, color: p.accent, size: 15),
                      const SizedBox(height: 5),
                      Text(e.$2, style: GoogleFonts.poppins(color: p.textMuted, fontSize: 9)),
                      Text(
                        e.$3,
                        style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ))
            .toList(),
      ),
    );
  }

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
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: p.surfaceAlt,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: const AlphaAMark(size: 24),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Coach Organization', style: GoogleFonts.poppins(color: p.textMuted, fontSize: 8)),
                      Text(
                        member.gymName.isNotEmpty ? member.gymName : 'Alpha Arena',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Your journey, our arena.',
                        style: GoogleFonts.poppins(color: p.textMuted, fontSize: 8.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(width: 1, height: 56, color: p.border),
          const SizedBox(width: 10),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Your Trainer', style: GoogleFonts.poppins(color: p.accent, fontSize: 8, fontWeight: FontWeight.w600)),
                      Text(
                        member.trainerName.isNotEmpty ? member.trainerName : 'Your Coach',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Performance Coach',
                        maxLines: 2,
                        style: GoogleFonts.poppins(color: p.textMuted, fontSize: 8, height: 1.2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                ClipOval(
                  child: Image.asset(
                    'assets/images/trainer.png',
                    width: 34,
                    height: 34,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      width: 34,
                      height: 34,
                      color: p.surfaceAlt,
                      alignment: Alignment.center,
                      child: Text(
                        member.trainerName.isNotEmpty ? member.trainerName[0].toUpperCase() : 'C',
                        style: AppText.title(size: 12).copyWith(color: p.accent),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
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
                  style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
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

  Widget _subscriptionCard(MembershipController membership, AppPalette p) {
    final active = membership.isActive;
    final planName = membership.membership?['planName']?.toString() ?? 'Transform Program';
    final expiry = membership.expiry;
    final formattedExpiry = expiry != null ? DateFormat('dd MMM yyyy').format(expiry) : 'N/A';
    final daysLeft = expiry != null ? expiry.difference(DateTime.now()).inDays : 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Subscription Plan',
          style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
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
                  child: const Icon(Icons.workspace_premium, color: Color(0xFF9B5DE5), size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              planName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(
                              color: active ? p.success.withValues(alpha: 0.16) : p.error.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              active ? 'Active' : 'Expired',
                              style: GoogleFonts.poppins(
                                color: active ? p.success : p.error,
                                fontSize: 8.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                      Text('Assigned Package', style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10)),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Valid Till', style: GoogleFonts.poppins(color: p.textMuted, fontSize: 8.5)),
                    Text(
                      formattedExpiry,
                      style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                    if (active && daysLeft > 0)
                      Text(
                        '$daysLeft Days Left',
                        style: GoogleFonts.poppins(color: p.success, fontSize: 8.5),
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
          style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
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
                'Body Measurements',
                'Log and track chest, waist, hips, biceps, and thighs',
                p,
                onTap: () => Get.to(() => const BodyMeasurementsScreen()),
              ),
              Divider(color: p.border, height: 1, indent: 14, endIndent: 14),
              _accountRow(
                Icons.person_outline,
                'Personal Information',
                'Update your personal profile details',
                p,
                onTap: () {
                  Get.snackbar('Profile Update', 'To modify profile information, edit it via your coach.');
                },
              ),
              // ("Health Profile" was removed: it was a dead settings row whose
              // only behavior was a Coming-Soon snackbar — restore it when the
              // dynamic health-log feature actually ships.)
              Divider(color: p.border, height: 1, indent: 14, endIndent: 14),
              _accountRow(
                Icons.support_agent_outlined,
                'Help & Support',
                'Send feedback or a concern to your coach',
                p,
                onTap: () => _openFeedbackSheet(context),
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

  Widget _accountRow(IconData icon, String title, String sub, AppPalette p, {VoidCallback? onTap}) {
    return InkWell(
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
                    style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  Text(sub, style: GoogleFonts.poppins(color: p.textMuted, fontSize: 10)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: p.textMuted, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _logout(BuildContext context, AppPalette p) {
    return GestureDetector(
      onTap: () {
        Get.dialog(
          AlertDialog(
            backgroundColor: p.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('Exit the Arena?', style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
            content: Text(
              'Are you sure you want to log out of AlphaSerena?',
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
                child: Text('Log Out', style: TextStyle(color: p.accent, fontWeight: FontWeight.bold)),
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
              'Log Out',
              style: GoogleFonts.poppins(color: p.error, fontSize: 13.5, fontWeight: FontWeight.w600),
            ),
          ],
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
                Container(width: 100, height: 24, decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(4))),
                const SizedBox(height: 6),
                Container(width: 160, height: 12, decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(4))),
              ],
            ),
          ],
        ),
        const SizedBox(height: 18),
        Container(width: double.infinity, height: 90, decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(16))),
        const SizedBox(height: 12),
        Container(width: double.infinity, height: 60, decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(14))),
        const SizedBox(height: 16),
        Container(width: double.infinity, height: 80, decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(16))),
        const SizedBox(height: 16),
        Container(width: double.infinity, height: 80, decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(14))),
        const SizedBox(height: 20),
        Container(width: double.infinity, height: 150, decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(14))),
      ],
    );
  }
}

/// "Rate your coach" card — shown only to members with an active membership.
/// Live-streams the member's own review and opens an edit sheet on tap.
class _RateCoachCard extends StatelessWidget {
  final MemberController member;
  const _RateCoachCard({required this.member});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final reviews = ReviewService();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Rate Your Coach',
            style: GoogleFonts.poppins(
                color: p.textPrimary, fontSize: 14, fontWeight: FontWeight.w600)),
        const SizedBox(height: 10),
        StreamBuilder<OrgReview?>(
          stream: reviews.watchMyReview(member.adminId, member.clientId),
          builder: (context, snap) {
            final mine = snap.data;
            return InkWell(
              borderRadius: AppRadii.cardR,
              onTap: () => _openSheet(context, reviews, mine),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: p.surface,
                  borderRadius: AppRadii.cardR,
                  border: Border.all(color: p.border),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFC107).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.star_rounded,
                          color: Color(0xFFFFC107), size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            mine != null
                                ? 'Your rating'
                                : 'Rate ${member.gymName.isNotEmpty ? member.gymName : 'your coach'}',
                            style: GoogleFonts.poppins(
                                color: p.textPrimary,
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          if (mine != null)
                            Row(
                              children: List.generate(
                                5,
                                (i) => Icon(
                                  i < mine.rating
                                      ? Icons.star
                                      : Icons.star_border,
                                  color: const Color(0xFFFFC107),
                                  size: 14,
                                ),
                              ),
                            )
                          else
                            Text('Share your experience with the arena.',
                                style: GoogleFonts.poppins(
                                    color: p.textMuted, fontSize: 10)),
                        ],
                      ),
                    ),
                    Text(mine != null ? 'Edit' : 'Rate',
                        style: GoogleFonts.poppins(
                            color: p.accent,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    Icon(Icons.chevron_right, color: p.textMuted, size: 18),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  void _openSheet(BuildContext context, ReviewService reviews, OrgReview? mine) {
    final p = context.palette;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _RateSheet(member: member, reviews: reviews, existing: mine),
    );
  }
}

/// The rating bottom sheet: 5 tappable stars + a comment + submit (busy/error).
class _RateSheet extends StatefulWidget {
  final MemberController member;
  final ReviewService reviews;
  final OrgReview? existing;
  const _RateSheet({
    required this.member,
    required this.reviews,
    required this.existing,
  });

  @override
  State<_RateSheet> createState() => _RateSheetState();
}

class _RateSheetState extends State<_RateSheet> {
  late int _rating = widget.existing?.rating ?? 0;
  late final TextEditingController _comment =
      TextEditingController(text: widget.existing?.comment ?? '');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_rating < 1) {
      setState(() => _error = 'Please tap a star to rate.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.reviews.submit(
        adminId: widget.member.adminId,
        clientId: widget.member.clientId,
        authUid: widget.member.uid,
        memberName: widget.member.name,
        rating: _rating,
        comment: _comment.text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      Get.snackbar('Thank you!', 'Your rating has been submitted.',
          snackPosition: SnackPosition.BOTTOM);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not submit your rating. Please try again.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 16, 20, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: p.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Rate ${widget.member.gymName.isNotEmpty ? widget.member.gymName : 'your coach'}',
            style: GoogleFonts.poppins(
                color: p.textPrimary, fontSize: 17, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 2),
          Text('Only you and your coach can see your feedback.',
              style: GoogleFonts.poppins(color: p.textMuted, fontSize: 11.5)),
          const SizedBox(height: 18),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(5, (i) {
                final filled = i < _rating;
                return GestureDetector(
                  onTap: _busy ? null : () => setState(() => _rating = i + 1),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(
                      filled ? Icons.star_rounded : Icons.star_border_rounded,
                      color: const Color(0xFFFFC107),
                      size: 42,
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _comment,
            enabled: !_busy,
            maxLines: 4,
            maxLength: 500,
            style: GoogleFonts.poppins(color: p.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Write a comment (optional)…',
              hintStyle: GoogleFonts.poppins(color: p.textMuted, fontSize: 12.5),
              filled: true,
              fillColor: p.surfaceAlt,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: p.accent),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Text(_error!,
                style: GoogleFonts.poppins(color: p.error, fontSize: 11.5)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _busy ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: p.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(widget.existing != null ? 'Update Rating' : 'Submit Rating',
                      style: GoogleFonts.poppins(
                          fontSize: 14, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
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
      Get.snackbar('Sent', 'Your coach will get back to you.',
          snackPosition: SnackPosition.BOTTOM);
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
            Text('Help & Support',
                style: AppText.title(size: 18).copyWith(color: p.textPrimary)),
            const SizedBox(height: 4),
            Text(
                'Feedback, an issue, or a concern. Only your gym admin sees this — not your trainer.',
                style: AppText.body(size: 12).copyWith(color: p.textMuted)),
            const SizedBox(height: 16),
            Text('CATEGORY',
                style: AppText.label(size: 11)
                    .copyWith(color: p.textSecondary, letterSpacing: 1)),
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
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color:
                          sel ? p.accent.withValues(alpha: 0.16) : Colors.transparent,
                      borderRadius: AppRadii.smR,
                      border: Border.all(color: sel ? p.accent : p.border),
                    ),
                    child: Text(label,
                        style: AppText.body(size: 12.5).copyWith(
                            color: sel ? p.accent : p.textMuted,
                            fontWeight:
                                sel ? FontWeight.w600 : FontWeight.w500)),
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
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                enabledBorder: OutlineInputBorder(
                    borderRadius: AppRadii.smR,
                    borderSide: BorderSide(color: p.border)),
                focusedBorder: OutlineInputBorder(
                    borderRadius: AppRadii.smR,
                    borderSide: BorderSide(color: p.accent, width: 1.4)),
              ),
            ),
            const SizedBox(height: 4),
            _toggleRow(p, 'Request a different trainer', _requestTrainerChange,
                (v) => setState(() => _requestTrainerChange = v)),
            _toggleRow(p, 'Send anonymously', _anonymous,
                (v) => setState(() => _anonymous = v)),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  style: AppText.body(size: 12)
                      .copyWith(color: const Color(0xFFFF1744))),
            ],
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: p.accent,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape:
                      RoundedRectangleBorder(borderRadius: AppRadii.smR),
                ),
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : Text('Send to coach',
                        style: AppText.label(size: 14)
                            .copyWith(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow(
      AppPalette p, String label, bool value, ValueChanged<bool> onChanged) {
    return Row(
      children: [
        Expanded(
            child: Text(label,
                style: AppText.body(size: 13).copyWith(color: p.textPrimary))),
        Checkbox(
          value: value,
          activeColor: p.accent,
          onChanged: (v) => onChanged(v ?? false),
        ),
      ],
    );
  }
}
