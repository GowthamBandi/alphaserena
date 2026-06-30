import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';

import 'member_controller.dart';
import '../core/services/client_profile_service.dart';

class ProgressController extends GetxController {
  final MemberController memberController = Get.find<MemberController>();
  final ClientProfileService _profileService = ClientProfileService();

  // Tab Selection (0: Overview, 1: Body Stats, 2: Photos, 3: Strength)
  final RxInt selectedTab = 0.obs;

  // Weight Logging state
  final RxBool isSavingWeight = false.obs;

  // Form input field state
  final RxString weightInputError = ''.obs;

  // Weight spots for fl_chart
  List<FlSpot> get weightSpots {
    final log = memberController.profile.value?['weightLog'] as List? ?? [];
    if (log.isEmpty) {
      // Fallback: single spot representing initial weight or 70.0
      final w = memberController.profile.value?['weight'] as num? ?? 70.0;
      return [FlSpot(0, w.toDouble())];
    }

    final spots = <FlSpot>[];
    // Take the last 7 weight logs
    final recentLogs = log.length > 7 ? log.sublist(log.length - 7) : log;
    for (int i = 0; i < recentLogs.length; i++) {
      final entry = recentLogs[i];
      if (entry is Map) {
        final w = entry['weight'];
        if (w is num) {
          spots.add(FlSpot(i.toDouble(), w.toDouble()));
        }
      }
    }
    return spots;
  }

  // Weight & Progress Stats getters
  double get latestWeight {
    final log = memberController.profile.value?['weightLog'];
    if (log is List && log.isNotEmpty) {
      final last = log.last;
      if (last is Map) {
        final w = last['weight'];
        if (w is num) return w.toDouble();
      }
    }
    final initialW = memberController.profile.value?['weight'];
    if (initialW is num) return initialW.toDouble();
    return 70.0;
  }

  String get weightDeltaText {
    final log = memberController.profile.value?['weightLog'];
    if (log is List && log.length >= 2) {
      final last = log[log.length - 1];
      final prev = log[log.length - 2];
      if (last is Map && prev is Map) {
        final lastW = last['weight'];
        final prevW = prev['weight'];
        if (lastW is num && prevW is num) {
          final diff = lastW.toDouble() - prevW.toDouble();
          if (diff == 0) return 'No change';
          return '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(1)} kg';
        }
      }
    }
    return '0.0 kg';
  }

  bool get isWeightUp {
    final log = memberController.profile.value?['weightLog'];
    if (log is List && log.length >= 2) {
      final last = log[log.length - 1];
      final prev = log[log.length - 2];
      if (last is Map && prev is Map) {
        final lastW = last['weight'];
        final prevW = prev['weight'];
        if (lastW is num && prevW is num) {
          return lastW.toDouble() > prevW.toDouble();
        }
      }
    }
    return false;
  }

  double get latestBodyFat {
    final fat = memberController.profile.value?['bodyFat'];
    if (fat is num) return fat.toDouble();
    return 15.0; // fallback default
  }

  double get latestMuscleMass {
    final muscle = memberController.profile.value?['muscleMass'];
    if (muscle is num) return muscle.toDouble();
    return 30.0; // fallback default
  }

  // Helper to determine the min/max values for charting
  double get minWeight {
    final spots = weightSpots;
    if (spots.isEmpty) return 50.0;
    double min = spots.first.y;
    for (final s in spots) {
      if (s.y < min) min = s.y;
    }
    return (min - 2).clamp(0.0, double.infinity);
  }

  double get maxWeight {
    final spots = weightSpots;
    if (spots.isEmpty) return 100.0;
    double max = spots.first.y;
    for (final s in spots) {
      if (s.y > max) max = s.y;
    }
    return max + 2;
  }

  List<String> get chartXLabels {
    final log = memberController.profile.value?['weightLog'] as List? ?? [];
    if (log.isEmpty) return ['Today'];

    final recentLogs = log.length > 7 ? log.sublist(log.length - 7) : log;
    final labels = <String>[];
    for (final entry in recentLogs) {
      if (entry is Map) {
        final dateStr = entry['date']?.toString() ?? '';
        final date = DateTime.tryParse(dateStr);
        if (date != null) {
          labels.add('${date.day}/${date.month}');
        } else {
          labels.add('');
        }
      }
    }
    return labels;
  }

  Future<bool> logWeight(double weight) async {
    if (weight <= 0 || weight > 300) {
      weightInputError.value = 'Please enter a valid weight (1-300 kg).';
      return false;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return false;

    isSavingWeight.value = true;
    weightInputError.value = '';

    try {
      final entry = {
        'date': DateTime.now().toIso8601String(),
        'weight': weight,
      };

      await _profileService.update(uid, {
        'weight': weight,
        'weightLog': FieldValue.arrayUnion([entry]),
      });

      return true;
    } catch (_) {
      weightInputError.value = 'Failed to save weight. Try again.';
      return false;
    } finally {
      isSavingWeight.value = false;
    }
  }
}
