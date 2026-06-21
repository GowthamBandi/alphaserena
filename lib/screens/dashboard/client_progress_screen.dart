import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:intl/intl.dart';

import '../../controllers/member_controller.dart';
import '../../core/constants/firestore_collections.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_radii.dart';
import '../../core/theme/app_shadows.dart';
import '../../core/theme/app_text.dart';
import '../../core/widgets/gradient_title.dart';

class ClientProgressScreen extends StatelessWidget {
  ClientProgressScreen({super.key});

  final MemberController member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  List<Map<String, dynamic>> _log() {
    final raw = (member.profile.value?['weightLog'] as List?) ?? const [];
    final list = raw.map((e) => Map<String, dynamic>.from(e)).toList();
    list.sort((a, b) => (b['date'] ?? '').toString().compareTo(
          (a['date'] ?? '').toString(),
        ));
    return list;
  }

  Future<void> _addWeight(BuildContext context) async {
    final p = context.palette;
    final ctrl = TextEditingController();
    await Get.dialog(AlertDialog(
      backgroundColor: p.surface,
      shape: const RoundedRectangleBorder(borderRadius: AppRadii.lgR),
      title: const Text('Log weight'),
      content: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Weight (kg)'),
      ),
      actions: [
        TextButton(onPressed: () => Get.back(), child: const Text('Cancel')),
        ElevatedButton(
          onPressed: () async {
            final kg = double.tryParse(ctrl.text.trim());
            if (kg == null) return;
            Get.back();
            await FirebaseFirestore.instance
                .collection(FsCollections.clientProfiles)
                .doc(member.uid)
                .set({
              'weightLog': FieldValue.arrayUnion([
                {'date': DateTime.now().toIso8601String(), 'kg': kg}
              ]),
            }, SetOptions(merge: true));
          },
          child: const Text('Save'),
        ),
      ],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    return Scaffold(
      floatingActionButton: FloatingActionButton(
        backgroundColor: p.accent,
        onPressed: () => _addWeight(context),
        child: const Icon(Icons.add, color: Colors.white),
      ),
      body: SafeArea(
        child: Obx(() {
          final log = _log();
          final latest = log.isNotEmpty ? log.first['kg'] : null;
          return ListView(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 28),
            children: [
              const GradientTitle('PROGRESS',
                  size: 30, textAlign: TextAlign.start),
              const SizedBox(height: 16),
              Row(
                children: [
                  _stat(p, 'GOAL',
                      member.goal.isEmpty ? '—' : member.goal),
                  const SizedBox(width: 12),
                  _stat(p, 'CURRENT',
                      latest == null ? '—' : '$latest kg'),
                ],
              ),
              const SizedBox(height: 24),
              Text('WEIGHT LOG',
                  style: AppText.label(size: 12)
                      .copyWith(color: p.textMuted, letterSpacing: 3)),
              const SizedBox(height: 12),
              if (log.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 30),
                  child: Center(
                    child: Text('Tap + to log your first weigh-in.',
                        style: AppText.body(size: 14)
                            .copyWith(color: p.textMuted)),
                  ),
                )
              else
                ...log.map((e) => _entry(p, e)),
            ],
          );
        }),
      ),
    );
  }

  Widget _stat(AppPalette p, String label, String value) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: p.surface,
            borderRadius: AppRadii.cardR,
            border: Border.all(color: p.border),
            boxShadow: AppShadows.card(p.isDark),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: AppText.body(size: 11)
                      .copyWith(color: p.textMuted, letterSpacing: 1)),
              const SizedBox(height: 6),
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.cardTitle(size: 16)
                      .copyWith(color: p.textPrimary)),
            ],
          ),
        ),
      );

  Widget _entry(AppPalette p, Map<String, dynamic> e) {
    final kg = e['kg'];
    DateTime? dt;
    try {
      dt = DateTime.tryParse((e['date'] ?? '').toString());
    } catch (_) {}
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: AppRadii.cardR,
        border: Border.all(color: p.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(dt == null ? '—' : DateFormat('d MMM yyyy').format(dt),
              style: AppText.body(size: 13).copyWith(color: p.textSecondary)),
          Text('$kg kg',
              style: AppText.label(size: 14).copyWith(color: p.accent)),
        ],
      ),
    );
  }
}
