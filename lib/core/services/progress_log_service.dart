import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';

/// Writes the member's body-progress entries to `client_progress` — the
/// coach-readable collection (ownership enforced by rules via the linked
/// `clients` doc, keyed on `authUid`). One doc per entry (a weight, a set of
/// measurements, and/or a progress photo). Also uploads photos to Storage
/// `progress_photos/{uid}/…`.
class ProgressLogService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsCollections.clientProgress);

  bool get canLog =>
      _member.clientId.isNotEmpty &&
      _member.adminId.isNotEmpty &&
      _member.uid.isNotEmpty;

  DateTime _ts(dynamic v) {
    if (v is Timestamp) return v.toDate();
    if (v is String) return DateTime.tryParse(v) ?? DateTime(2000);
    return DateTime(2000);
  }

  /// The member's own progress entries, newest first (equality filter only — no
  /// composite index needed).
  Stream<List<Map<String, dynamic>>> watchEntries() {
    if (!canLog) return Stream.value(const []);
    return _col.where('authUid', isEqualTo: _member.uid).snapshots().map((s) {
      final list = s.docs.map((d) {
        final m = Map<String, dynamic>.from(d.data());
        m['id'] = d.id;
        return m;
      }).toList();
      list.sort((a, b) => _ts(b['date']).compareTo(_ts(a['date'])));
      return list;
    });
  }

  /// Uploads a progress photo and returns its download URL. Content type is set
  /// explicitly (picker temp files infer unreliably) so the Storage rule accepts it.
  Future<String> uploadPhoto(File file, String filename) async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final ref = _storage.ref('progress_photos/${_member.uid}/${ts}_$filename');
    await ref.putFile(
      file,
      SettableMetadata(contentType: _contentType(filename)),
    );
    return ref.getDownloadURL();
  }

  String _contentType(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'image/jpeg';
    }
  }

  /// Creates a `client_progress` entry (weight and/or measurements and/or a
  /// photo). Returns the doc id, or null if the member isn't linked / it fails.
  Future<String?> addEntry({
    double? weightKg,
    Map<String, dynamic>? measurements,
    String? photoUrl,
    String? note,
    String visibility = 'shared',
  }) async {
    if (!canLog) return null;
    final data = <String, dynamic>{
      'clientId': _member.clientId,
      'adminId': _member.adminId,
      'authUid': _member.uid,
      'date': FieldValue.serverTimestamp(),
      'weightKg': ?weightKg,
      if (measurements != null && measurements.isNotEmpty)
        'measurements': measurements,
      if (photoUrl != null && photoUrl.isNotEmpty) 'photoUrl': photoUrl,
      if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
      // Transformation V1 (additive): 'shared' | 'private'. The coach app
      // filters private entries out of every general surface and shows only a
      // privacy placeholder in the Transformation tool. Absent on legacy
      // entries → shared.
      'visibility': visibility == 'private' ? 'private' : 'shared',
      'createdAt': FieldValue.serverTimestamp(),
    };
    try {
      final doc = await _col.add(data);
      return doc.id;
    } catch (_) {
      return null;
    }
  }
}
