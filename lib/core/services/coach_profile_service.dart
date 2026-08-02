import 'package:cloud_firestore/cloud_firestore.dart';

import '../constants/firestore_collections.dart';
import '../models/coach_profile_model.dart';

class CoachProfileService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Stream<CoachProfileModel?> watch(String coachId) {
    if (coachId.isEmpty) return Stream.value(null);
    return _db
        .collection(FsCollections.coachProfiles)
        .doc(coachId)
        .snapshots()
        .map((d) => d.exists ? CoachProfileModel.fromSnapshot(d) : null);
  }

  Future<Map<String, CoachProfileModel>> byIds(Iterable<String> ids) async {
    final unique = ids.where((id) => id.isNotEmpty).toSet();
    final entries = await Future.wait(
      unique.map((id) async {
        final d = await _db
            .collection(FsCollections.coachProfiles)
            .doc(id)
            .get();
        return MapEntry(
          id,
          d.exists ? CoachProfileModel.fromSnapshot(d) : null,
        );
      }),
    );
    return {
      for (final e in entries)
        if (e.value != null) e.key: e.value!,
    };
  }
}
