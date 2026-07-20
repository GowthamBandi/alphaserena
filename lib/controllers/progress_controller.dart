import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';

import 'member_controller.dart';
import '../core/services/client_profile_service.dart';
import '../core/services/progress_log_service.dart';

class ProgressController extends GetxController {
  final MemberController memberController = Get.find<MemberController>();
  final ClientProfileService _profileService = ClientProfileService();
  final ProgressLogService _progressLog = ProgressLogService();

  // Tab Selection (0: Overview, 1: Body Stats, 2: Photos, 3: Strength)
  final RxInt selectedTab = 0.obs;

  // Weight Logging state
  final RxBool isSavingWeight = false.obs;

  // Form input field state
  final RxString weightInputError = ''.obs;

  // Progress-photo state (backed by the coach-readable client_progress).
  final RxBool isUploadingPhoto = false.obs;
  final RxString photoError = ''.obs;
  final RxList<Map<String, dynamic>> progressPhotos =
      <Map<String, dynamic>>[].obs;
  StreamSubscription<List<Map<String, dynamic>>>? _photosSub;
  Worker? _linkWorker;

  @override
  void onInit() {
    super.onInit();
    _bindPhotos();
    // Re-bind when the member becomes linked: on first init `canLog` may still be
    // false (claim() hasn't resolved), which would otherwise yield a permanently
    // empty stream.
    _linkWorker = ever(memberController.isLinked, (_) => _bindPhotos());
  }

  void _bindPhotos() {
    _photosSub?.cancel();
    _photosSub = _progressLog.watchEntries().listen((entries) {
      progressPhotos.assignAll(entries
          .where((e) => (e['photoUrl'] ?? '').toString().isNotEmpty)
          .toList());
    }, onError: (_) {});
  }

  @override
  void onClose() {
    _photosSub?.cancel();
    _linkWorker?.dispose();
    super.onClose();
  }

  /// Pending visibility for the NEXT photo upload (V1.2): null until the
  /// member consciously chooses on the photo card; reset after a successful
  /// upload so every photo is an explicit decision.
  final Rxn<String> photoVisibility = Rxn<String>();

  /// Picks an image (camera/gallery), uploads it to Storage and writes a
  /// `client_progress` entry with the photo URL, stamped with the member's
  /// chosen [visibility].
  Future<void> pickAndUploadPhoto(ImageSource source,
      {required String visibility}) async {
    if (isUploadingPhoto.value) return; // re-entry guard (no duplicate uploads)
    if (!_progressLog.canLog) {
      photoError.value = 'Join a coach to upload progress photos.';
      return;
    }
    try {
      final picked = await ImagePicker()
          .pickImage(source: source, maxWidth: 1600, imageQuality: 82);
      if (picked == null) return;
      isUploadingPhoto.value = true;
      photoError.value = '';
      final url = await _progressLog.uploadPhoto(File(picked.path), picked.name);
      final id = await _progressLog.addEntry(
          photoUrl: url, visibility: visibility);
      if (id == null) {
        photoError.value = 'Could not save the photo. Please try again.';
      } else {
        photoVisibility.value = null; // next photo → fresh conscious choice
      }
    } catch (_) {
      photoError.value = 'Upload failed. Check your connection and try again.';
    } finally {
      isUploadingPhoto.value = false;
    }
  }

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

  /// 0 means "never measured" — the UI shows a placeholder, never a fabricated
  /// default (a fake 15% body fat is worse than no number).
  double get latestBodyFat {
    final fat = memberController.profile.value?['bodyFat'];
    if (fat is num) return fat.toDouble();
    return 0.0;
  }

  double get latestMuscleMass {
    final muscle = memberController.profile.value?['muscleMass'];
    if (muscle is num) return muscle.toDouble();
    return 0.0;
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

  Future<bool> logWeight(double weight, {String visibility = 'shared'}) async {
    // Re-entry guard: the caller's Save button isn't disabled while saving, so a
    // double-tap would otherwise create duplicate clientProfiles + client_progress
    // entries (duplicate coach-visible weight data).
    if (isSavingWeight.value) return false;
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

      // Also write the coach-readable `client_progress` entry so the trainer
      // sees this weight (the clientProfiles copy above stays for the in-app
      // chart). A momentary failure here must not fail the member's own log —
      // and must not surface "Failed to save" once the member's copy is already
      // committed: a retry after that would arrayUnion a SECOND (new-ISO-date)
      // entry, duplicating the chart point.
      try {
        await _progressLog.addEntry(weightKg: weight, visibility: visibility);
      } catch (_) {
        // Coach copy lagging is invisible to the member and self-heals on the
        // next weight log; the member's own record is safe.
      }

      return true;
    } catch (_) {
      weightInputError.value = 'Failed to save weight. Try again.';
      return false;
    } finally {
      isSavingWeight.value = false;
    }
  }
}
