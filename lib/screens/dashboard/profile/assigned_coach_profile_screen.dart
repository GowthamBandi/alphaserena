import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../controllers/member_controller.dart';
import '../../../core/models/coach_profile_model.dart';
import '../../../core/services/coach_profile_service.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/widgets/brand.dart';
import '../../join/coach_storefront_screen.dart';
import '../client_chat_screen.dart';

class AssignedCoachProfileScreen extends StatelessWidget {
  const AssignedCoachProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final member = Get.find<MemberController>();
    return Obx(() {
      final coachId = member.coachId;
      if (coachId.isEmpty) return _empty(context);
      return StreamBuilder<CoachProfileModel?>(
        key: ValueKey(coachId),
        stream: CoachProfileService().watch(coachId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              snapshot.data == null) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) return _error(context);
          final coach = snapshot.data;
          if (coach == null || !coach.isActive) return _empty(context);
          return _content(context, coach, member);
        },
      );
    });
  }

  Widget _content(
    BuildContext context,
    CoachProfileModel coach,
    MemberController member,
  ) {
    final p = context.palette;
    return Scaffold(
      backgroundColor: p.background,
      appBar: AppBar(title: const Text('Assigned Coach')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
          children: [
            _hero(coach, p),
            if (coach.bio != null) ...[
              const SizedBox(height: 14),
              _section(p, 'About', Text(coach.bio!)),
            ],
            if (coach.experience != null || coach.specialization != null) ...[
              const SizedBox(height: 14),
              _section(
                p,
                'Coaching Profile',
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (coach.experience != null)
                      _chip(
                        Icons.workspace_premium_outlined,
                        coach.experience!,
                        p,
                      ),
                    if (coach.specialization != null)
                      _chip(Icons.fitness_center, coach.specialization!, p),
                  ],
                ),
              ),
            ],
            if (coach.qualifications.isNotEmpty) ...[
              const SizedBox(height: 14),
              _section(
                p,
                'Certifications',
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: coach.qualifications
                      .map((e) => _chip(Icons.verified_outlined, e, p))
                      .toList(),
                ),
              ),
            ],
            if (coach.languages.isNotEmpty) ...[
              const SizedBox(height: 14),
              _section(
                p,
                'Languages',
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: coach.languages
                      .map((e) => _chip(Icons.translate, e, p))
                      .toList(),
                ),
              ),
            ],
            const SizedBox(height: 14),
            _organization(member, p),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Get.to(() => const ClientChatScreen()),
              icon: const Icon(Icons.chat_bubble_outline),
              label: const Text('Chat with Coach'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('Call — Soon'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: null,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: const Text('Schedule — Soon'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _hero(CoachProfileModel coach, AppPalette p) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: AppRadii.cardR,
      border: Border.all(color: p.border),
    ),
    child: Column(
      children: [
        Hero(
          tag: 'assigned-coach-${coach.coachId}',
          child: CircleAvatar(
            radius: 46,
            backgroundColor: p.surfaceAlt,
            backgroundImage: coach.avatarUrl == null
                ? null
                : CachedNetworkImageProvider(coach.avatarUrl!),
            child: coach.avatarUrl == null
                ? Icon(Icons.person_outline, color: p.textMuted, size: 38)
                : null,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Flexible(
              child: Text(
                coach.name,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  color: p.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (coach.verified) ...[
              const SizedBox(width: 5),
              Icon(Icons.verified, color: p.accent, size: 18),
            ],
          ],
        ),
        Text(coach.title, style: TextStyle(color: p.textMuted)),
        if (coach.reviewCount > 0) ...[
          const SizedBox(height: 8),
          Text(
            '★ ${coach.rating.toStringAsFixed(1)} · ${coach.reviewCount} reviews',
            style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w600),
          ),
        ],
      ],
    ),
  );

  Widget _organization(MemberController member, AppPalette p) => InkWell(
    borderRadius: AppRadii.cardR,
    onTap: member.adminId.isEmpty
        ? null
        : () =>
              Get.to(() => LiveCoachStorefrontScreen(adminId: member.adminId)),
    child: Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        children: [
          const AlphaAMark(size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Organization', style: TextStyle(color: p.textMuted)),
                Text(
                  member.orgName.isEmpty ? 'View organization' : member.orgName,
                  style: TextStyle(
                    color: p.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: p.textMuted),
        ],
      ),
    ),
  );

  Widget _section(AppPalette p, String title, Widget child) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: p.surface,
      borderRadius: AppRadii.cardR,
      border: Border.all(color: p.border),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: p.textPrimary, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        DefaultTextStyle(
          style: TextStyle(color: p.textMuted, height: 1.5),
          child: child,
        ),
      ],
    ),
  );

  Widget _chip(IconData icon, String text, AppPalette p) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: p.surfaceAlt,
      borderRadius: AppRadii.smR,
      border: Border.all(color: p.border),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: p.accent),
        const SizedBox(width: 6),
        Flexible(
          child: Text(text, style: TextStyle(color: p.textPrimary)),
        ),
      ],
    ),
  );

  Widget _empty(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Assigned Coach')),
    body: const Center(child: Text('No coach is currently assigned.')),
  );

  Widget _error(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Assigned Coach')),
    body: const Center(child: Text('Could not load your coach right now.')),
  );
}
