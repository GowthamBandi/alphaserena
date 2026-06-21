import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/member_controller.dart';
import '../../../controllers/theme_controller.dart';
import '../../../core/constants/quotes.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text.dart';
import '../../../core/widgets/gradient_title.dart';

class ClientHomeScreen extends StatefulWidget {
  const ClientHomeScreen({super.key});

  @override
  State<ClientHomeScreen> createState() => _ClientHomeScreenState();
}

class _ClientHomeScreenState extends State<ClientHomeScreen> {
  late final MemberController member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());
  final ThemeController theme = Get.find<ThemeController>();
  final String _quote = Quotes.daily();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          if (member.isLoading.value) {
            return Center(
              child: CircularProgressIndicator(strokeWidth: 2.4, color: p.accent),
            );
          }
          if (!member.isLinked.value && member.notice.value == 'no_membership') {
            return _notLinked(p);
          }
          return _content(p);
        }),
      ),
    );
  }

  Widget _content(AppPalette p) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('WELCOME BACK',
                        style: AppText.label(size: 12).copyWith(
                            color: p.textMuted, letterSpacing: 3)),
                    const SizedBox(height: 2),
                    GradientTitle(member.name.toUpperCase(),
                        size: 32, textAlign: TextAlign.start),
                  ],
                ),
              ),
              Obx(() => IconButton(
                    icon: Icon(
                      theme.isDarkMode.value
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      color: theme.isDarkMode.value
                          ? BrandColors.amber
                          : p.textSecondary,
                    ),
                    onPressed: theme.toggleTheme,
                  )),
            ],
          ),
          const SizedBox(height: 18),

          // Motivational quote banner.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: AppRadii.lgR,
              gradient: const LinearGradient(
                colors: BrandColors.selectedGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.format_quote, color: Colors.white70, size: 22),
                const SizedBox(height: 6),
                Text(_quote,
                    style: AppText.cardTitle(size: 16)
                        .copyWith(color: Colors.white, height: 1.3)),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Membership info.
          Row(
            children: [
              Expanded(
                child: _infoCard(p, Icons.flag_outlined, 'Your goal',
                    member.goal.isEmpty ? 'Set in profile' : member.goal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _infoCard(p, Icons.fitness_center, 'Trainer',
                    member.trainerName.isEmpty ? 'Unassigned' : member.trainerName),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _infoCard(p, Icons.storefront_outlined, 'Your gym',
              member.gymName.isEmpty ? '—' : member.gymName, full: true),

          const SizedBox(height: 24),
          Text('TODAY', style: AppText.label(size: 12).copyWith(color: p.textMuted, letterSpacing: 3)),
          const SizedBox(height: 12),
          _ctaCard(
            p,
            icon: Icons.bolt,
            title: 'Own today',
            subtitle: 'Your assigned workout & diet appear in the tabs below.',
          ),
        ],
      ),
    );
  }

  Widget _infoCard(AppPalette p, IconData icon, String label, String value,
      {bool full = false}) {
    return Container(
      width: full ? double.infinity : null,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
                color: p.accent.withValues(alpha: 0.12),
                borderRadius: AppRadii.smR),
            child: Icon(icon, color: p.accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: AppText.body(size: 12).copyWith(color: p.textMuted)),
                const SizedBox(height: 2),
                Text(value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.label(size: 14)
                        .copyWith(color: p.textPrimary)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _ctaCard(AppPalette p,
      {required IconData icon,
      required String title,
      required String subtitle}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Row(
        children: [
          Icon(icon, color: p.accent, size: 26),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: AppText.cardTitle(size: 15)
                        .copyWith(color: p.textPrimary)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: AppText.body(size: 12).copyWith(color: p.textMuted)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _notLinked(AppPalette p) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.link_off, size: 44, color: p.textMuted),
            const SizedBox(height: 16),
            Text('Membership not found',
                style: AppText.title(size: 22).copyWith(color: p.textPrimary)),
            const SizedBox(height: 8),
            Text(
              'We couldn\'t find a membership for your number yet. Ask your gym to add you, then tap retry.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 14).copyWith(color: p.textMuted),
            ),
            const SizedBox(height: 22),
            OutlinedButton.icon(
              onPressed: member.claim,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
