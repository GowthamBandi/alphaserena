import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../../controllers/auth_controller.dart';
import '../../../controllers/member_controller.dart';
import '../../../controllers/theme_controller.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_shadows.dart';
import '../../../core/theme/app_text.dart';
import '../client_chat_screen.dart';
import '../membership_screen.dart';

class ClientProfileScreen extends StatelessWidget {
  ClientProfileScreen({super.key});

  final MemberController member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());
  final ThemeController theme = Get.find<ThemeController>();
  final AuthController auth = Get.find<AuthController>();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final phone = FirebaseAuth.instance.currentUser?.phoneNumber ?? '';
    return Scaffold(
      body: SafeArea(
        child: Obx(() {
          final name = member.name;
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 28),
            children: [
              Center(
                child: Column(
                  children: [
                    Container(
                      width: 84,
                      height: 84,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          colors: BrandColors.selectedGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: Text(
                        name.isEmpty ? 'A' : name[0].toUpperCase(),
                        style: AppText.display(size: 40)
                            .copyWith(color: Colors.white),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(name,
                        style: AppText.title(size: 24)
                            .copyWith(color: p.textPrimary)),
                    if (phone.isNotEmpty)
                      Text(phone,
                          style: AppText.body(size: 13)
                              .copyWith(color: p.textMuted)),
                  ],
                ),
              ),
              const SizedBox(height: 28),
              _tile(p, Icons.flag_outlined, 'Goal',
                  member.goal.isEmpty ? 'Not set' : member.goal),
              _tile(p, Icons.storefront_outlined, 'Gym',
                  member.gymName.isEmpty ? '—' : member.gymName),
              _tile(p, Icons.fitness_center, 'Trainer',
                  member.trainerName.isEmpty ? 'Unassigned' : member.trainerName),
              const SizedBox(height: 12),
              _action(p, Icons.chat_bubble_outline, 'Chat with trainer',
                  () => Get.to(() => const ClientChatScreen())),
              _action(p, Icons.card_membership, 'Membership',
                  () => Get.to(() => MembershipScreen())),
              _action(
                p,
                theme.isDarkMode.value
                    ? Icons.light_mode_outlined
                    : Icons.dark_mode_outlined,
                theme.isDarkMode.value ? 'Light mode' : 'Dark mode',
                theme.toggleTheme,
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: () => _confirmSignOut(context),
                icon: const Icon(Icons.logout),
                label: const Text('Sign out'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: p.error,
                  side: BorderSide(color: p.error),
                  shape:
                      const RoundedRectangleBorder(borderRadius: AppRadii.mdR),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
              Center(
                child: Text('AlphaSerena · The arena for alphas',
                    style: AppText.body(size: 12).copyWith(color: p.textMuted)),
              ),
            ],
          );
        }),
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    final p = context.palette;
    Get.dialog(AlertDialog(
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
      title: const Text('Sign out?'),
      content: const Text('You can sign back in with your phone number.'),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () {
            Get.back();
            auth.signOut();
          },
          style: ElevatedButton.styleFrom(
              backgroundColor: p.error, foregroundColor: Colors.white),
          child: const Text('Sign out'),
        ),
      ],
    ));
  }

  Widget _tile(AppPalette p, IconData icon, String label, String value) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Row(
        children: [
          Icon(icon, color: p.accent, size: 20),
          const SizedBox(width: 14),
          Text(label,
              style: AppText.body(size: 13).copyWith(color: p.textMuted)),
          const Spacer(),
          Flexible(
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppText.label(size: 14).copyWith(color: p.textPrimary)),
          ),
        ],
      ),
    );
  }

  Widget _action(AppPalette p, IconData icon, String label, VoidCallback onTap) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadii.cardR,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(icon, color: p.accent, size: 20),
                const SizedBox(width: 14),
                Text(label,
                    style:
                        AppText.label(size: 14).copyWith(color: p.textPrimary)),
                const Spacer(),
                Icon(Icons.chevron_right, color: p.textMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
