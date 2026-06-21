import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';

import '../../controllers/auth_controller.dart';
import '../../core/services/client_profile_service.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/app_text_field.dart';
import '../../core/widgets/gradient_title.dart';
import '../../core/widgets/primary_button.dart';
import '../dashboard/dashboard_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _age = TextEditingController();
  final ClientProfileService _profiles = ClientProfileService();

  String? _goal;
  String? _gender;
  String? _activity;
  bool _saving = false;

  static const _goals = [
    'Fat loss',
    'Muscle gain',
    'Strength',
    'Endurance',
    'General fitness',
  ];
  static const _genders = ['Male', 'Female', 'Other'];
  static const _activities = [
    'Sedentary',
    'Lightly active',
    'Active',
    'Very active',
  ];

  @override
  void dispose() {
    _name.dispose();
    _age.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (_name.text.trim().isEmpty || _goal == null) {
      Get.snackbar('Almost there', 'Tell us your name and your main goal.');
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    setState(() => _saving = true);
    try {
      await _profiles.saveOnboarding(
        user.uid,
        phone: user.phoneNumber ?? Get.find<AuthController>().phone,
        data: {
          'name': _name.text.trim(),
          'goal': _goal,
          'gender': _gender,
          'age': int.tryParse(_age.text.trim()),
          'activityLevel': _activity,
        },
      );
      Get.offAll(() => const ClientDashboard());
    } catch (_) {
      Get.snackbar('Error', 'Could not save. Please try again.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const GradientTitle('WELCOME, ALPHA',
                  size: 34, textAlign: TextAlign.start),
              const SizedBox(height: 8),
              Text(
                "Let's set up your arena. This shapes your plans and progress.",
                style: AppText.body(size: 14).copyWith(color: p.textMuted),
              ),
              const SizedBox(height: 28),
              AppTextField(
                controller: _name,
                label: 'Your name',
                icon: Icons.person_outline,
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 22),
              _section(p, 'Your main goal'),
              _chips(p, _goals, _goal, (v) => setState(() => _goal = v)),
              const SizedBox(height: 22),
              _section(p, 'Gender'),
              _chips(p, _genders, _gender, (v) => setState(() => _gender = v)),
              const SizedBox(height: 22),
              AppTextField(
                controller: _age,
                label: 'Age',
                icon: Icons.cake_outlined,
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 22),
              _section(p, 'Activity level'),
              _chips(p, _activities, _activity,
                  (v) => setState(() => _activity = v)),
              const SizedBox(height: 32),
              PrimaryButton(
                label: 'Enter the Arena',
                icon: Icons.bolt,
                isLoading: _saving,
                onPressed: _finish,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(AppPalette p, String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title,
            style: AppText.label(size: 14).copyWith(color: p.textSecondary)),
      );

  Widget _chips(
    AppPalette p,
    List<String> options,
    String? selected,
    ValueChanged<String> onTap,
  ) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: options.map((o) {
        final sel = selected == o;
        return InkWell(
          onTap: () => onTap(o),
          borderRadius: AppRadii.smR,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            decoration: BoxDecoration(
              color: sel ? p.accent.withValues(alpha: 0.14) : p.surface,
              borderRadius: AppRadii.smR,
              border: Border.all(color: sel ? p.accent : p.border),
            ),
            child: Text(o,
                style: AppText.label(size: 13)
                    .copyWith(color: sel ? p.accent : p.textSecondary)),
          ),
        );
      }).toList(),
    );
  }
}
