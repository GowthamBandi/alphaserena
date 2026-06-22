import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/client_razorpay_controller.dart';
import '../../controllers/member_controller.dart';
import '../../controllers/membership_controller.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/gradient_title.dart';
import '../../core/widgets/primary_button.dart';

class MembershipScreen extends StatelessWidget {
  MembershipScreen({super.key});

  final MemberController member = Get.find<MemberController>();
  final MembershipController c = Get.isRegistered<MembershipController>()
      ? Get.find<MembershipController>()
      : Get.put(MembershipController());
  final ClientRazorpayController razor =
      Get.isRegistered<ClientRazorpayController>()
          ? Get.find<ClientRazorpayController>()
          : Get.put(ClientRazorpayController());

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text('Membership',
            style: AppText.title(size: 22).copyWith(color: p.textPrimary)),
      ),
      body: SafeArea(
        child: Obx(() {
          if (!member.isLinked.value) return _needLink(p);
          if (c.isLoading.value) {
            return Center(
                child:
                    CircularProgressIndicator(strokeWidth: 2.4, color: p.accent));
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
            children: [
              _statusCard(p),
              const SizedBox(height: 22),
              Text('PLANS',
                  style: AppText.label(size: 12)
                      .copyWith(color: p.textMuted, letterSpacing: 3)),
              const SizedBox(height: 12),
              if (c.plans.isEmpty)
                _empty(p)
              else
                ...c.plans.map((plan) => _planCard(context, p, plan)),
            ],
          );
        }),
      ),
    );
  }

  Widget _statusCard(AppPalette p) {
    final active = c.isActive;
    final exp = c.expiry;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: AppRadii.lgR,
        gradient: active
            ? const LinearGradient(
                colors: BrandColors.selectedGradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight)
            : null,
        color: active ? null : p.surface,
        border: active ? null : Border.all(color: p.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(active ? 'MEMBERSHIP ACTIVE' : 'NO ACTIVE MEMBERSHIP',
              style: AppText.label(size: 12).copyWith(
                  color: active ? Colors.white : p.textMuted,
                  letterSpacing: 2)),
          const SizedBox(height: 6),
          Text(
            active
                ? (c.membership?['planName']?.toString() ?? 'Member')
                : 'Pick a plan below to join the arena.',
            style: AppText.cardTitle(size: 18)
                .copyWith(color: active ? Colors.white : p.textPrimary),
          ),
          if (active && exp != null) ...[
            const SizedBox(height: 4),
            Text('Valid until ${DateFormat('d MMM yyyy').format(exp)}',
                style: AppText.body(size: 13).copyWith(color: Colors.white70)),
          ],
        ],
      ),
    );
  }

  Widget _planCard(
      BuildContext context, AppPalette p, Map<String, dynamic> plan) {
    final price = (plan['price'] is num) ? (plan['price'] as num).round() : 0;
    final months = (plan['months'] ?? plan['durationMonths'] ?? 1);
    final points =
        ((plan['points'] as List?) ?? const []).map((e) => e.toString()).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.lgR,
        border: Border.all(color: p.border),
        boxShadow: AppShadows.card(p.isDark),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(plan['name']?.toString() ?? 'Membership',
              style: AppText.title(size: 20).copyWith(color: p.textPrimary)),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('₹${NumberFormat.decimalPattern('en_IN').format(price)}',
                  style: AppText.display(size: 32).copyWith(color: p.accent)),
              const SizedBox(width: 6),
              Text('/ $months mo',
                  style: AppText.body(size: 13).copyWith(color: p.textMuted)),
            ],
          ),
          if ((plan['description'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(plan['description'].toString(),
                style: AppText.body(size: 13).copyWith(color: p.textSecondary)),
          ],
          if (points.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...points.map((pt) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Icon(Icons.check_circle, size: 17, color: p.accent),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(pt,
                            style: AppText.feature(size: 14)
                                .copyWith(color: p.textSecondary))),
                  ]),
                )),
          ],
          const SizedBox(height: 16),
          Obx(() => PrimaryButton(
                label: 'Buy membership',
                icon: Icons.bolt,
                isLoading: razor.isProcessing.value,
                onPressed: () => razor.buy(
                  planId: (plan['id'] ?? '').toString(),
                  planName: plan['name']?.toString() ?? 'Membership',
                  contact:
                      FirebaseAuth.instance.currentUser?.phoneNumber ?? '',
                ),
              )),
        ],
      ),
    );
  }

  Widget _needLink(AppPalette p) => Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.link_off, size: 42, color: p.textMuted),
            const SizedBox(height: 14),
            Text('Link your membership first',
                style: AppText.title(size: 20).copyWith(color: p.textPrimary)),
            const SizedBox(height: 6),
            Text('Ask your gym to add your number, then buy a plan here.',
                textAlign: TextAlign.center,
                style: AppText.body(size: 14).copyWith(color: p.textMuted)),
          ]),
        ),
      );

  Widget _empty(AppPalette p) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          const GradientTitle('NO PLANS YET', size: 24),
          const SizedBox(height: 8),
          Text('Your gym hasn\'t published membership plans yet.',
              textAlign: TextAlign.center,
              style: AppText.body(size: 14).copyWith(color: p.textMuted)),
        ]),
      );
}
