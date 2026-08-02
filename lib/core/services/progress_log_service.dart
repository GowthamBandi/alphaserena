import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:get/get.dart';

import '../../controllers/member_controller.dart';
import '../constants/firestore_collections.dart';
import '../models/transformation_entry.dart';

/// What actually happened to a check-in write.
///
/// A Firestore write completes only on SERVER acknowledgement. With no usable
/// connection it therefore never completes at all — it is durably queued in the
/// local cache and syncs later. Awaiting it unconditionally is what hung the
/// save button forever, so the member is told which of the two happened
/// instead of being made to wait for an ack that is not coming.
enum TransformationWriteOutcome { acknowledged, queued }

/// The single persistence boundary for Transformation in both applications.
///
/// `client_progress` remains the canonical collection for backward compatibility,
/// but every new record uses schemaVersion 2 and contains the whole check-in.
/// There is no clientProfiles mirror and therefore no dual-write drift.
abstract interface class TransformationWriter {
  String newRecordId();

  Future<void> createUploadDraft({
    required String recordId,
    required DateTime clientRecordedAt,
  });

  /// Uploads one pose's media.
  ///
  /// [persistToRecord] attaches the photo to the record as each upload lands,
  /// so an interrupted first publish can resume from the media already stored.
  /// It must be FALSE when correcting a published checkpoint: that record is
  /// live to the coach, and a half-finished edit must not alter it before the
  /// member saves (the correction write sends the whole photo set at once).
  Future<TransformationPhoto> uploadPose({
    required String recordId,
    required TransformationPose pose,
    required File file,
    required String filename,
    bool persistToRecord = true,
  });

  Future<void> removeDraftPose({
    required String recordId,
    required TransformationPose pose,
    required TransformationPhoto photo,
  });

  Future<TransformationWriteOutcome> finalize({
    required String recordId,
    required DateTime clientRecordedAt,
    required TransformationVisibility visibility,
    double? weightKg,
    double? bodyFatPercent,
    Map<String, double> measurements = const {},
    Map<TransformationPose, TransformationPhoto> photos = const {},
    String? note,
  });

  Future<void> abandon(String recordId, Iterable<TransformationPhoto> photos);

  /// Corrects an ALREADY PUBLISHED checkpoint in place.
  ///
  /// A member who misread the scale, needs to swap a bad photo, or changes
  /// their mind about coach visibility must not be pushed into logging a second
  /// checkpoint for the same day — that would corrupt the very chronology the
  /// record exists to describe. The entry keeps its id, its `recordedAt` and
  /// its `createdAt`; only its content changes, and the backend stamps
  /// `editedAt` so the coach is shown that it was revised.
  Future<TransformationWriteOutcome> updatePublished({
    required TransformationEntry original,
    required TransformationVisibility visibility,
    double? weightKg,
    double? bodyFatPercent,
    Map<String, double> measurements = const {},
    Map<TransformationPose, TransformationPhoto> photos = const {},
    String? note,
  });

  /// Re-shares or hides one published checkpoint without reopening the editor.
  Future<TransformationWriteOutcome> setVisibility({
    required String recordId,
    required TransformationVisibility visibility,
  });
}

class ProgressLogService implements TransformationWriter {
  ProgressLogService({
    FirebaseFirestore? firestore,
    FirebaseStorage? storage,
    Duration ackTimeout = const Duration(seconds: 6),
  }) : _db = firestore ?? FirebaseFirestore.instance,
       _storage = storage ?? FirebaseStorage.instance,
       _ackTimeout = ackTimeout;

  final FirebaseFirestore _db;
  final FirebaseStorage _storage;
  final Duration _ackTimeout;

  /// Waits a bounded time for the server to acknowledge [write].
  ///
  /// Reporting "queued" is not a guess: the write is already in Firestore's
  /// durable local cache, the live stream already reflects it, and it syncs on
  /// reconnect. What this refuses to do is block the member's UI on an ack that
  /// cannot arrive — offline, or on a connection that is up but dead (captive
  /// portal), which no connectivity probe reliably predicts.
  Future<TransformationWriteOutcome> _acked(Future<void> write) {
    final result = Completer<TransformationWriteOutcome>();
    final timer = Timer(_ackTimeout, () {
      if (!result.isCompleted) {
        result.complete(TransformationWriteOutcome.queued);
      }
    });
    write.then(
      (_) {
        timer.cancel();
        if (!result.isCompleted) {
          result.complete(TransformationWriteOutcome.acknowledged);
        }
      },
      // A rejection arriving AFTER "queued" was reported must not escape as an
      // unhandled async error. It is swallowed here and nowhere else: the
      // record simply never appears in the member's live history, which is the
      // truth about what is stored.
      onError: (Object error, StackTrace stack) {
        timer.cancel();
        if (!result.isCompleted) result.completeError(error, stack);
      },
    );
    return result.future;
  }
  final MemberController _member = Get.isRegistered<MemberController>()
      ? Get.find<MemberController>()
      : Get.put(MemberController());

  CollectionReference<Map<String, dynamic>> get _col =>
      _db.collection(FsCollections.clientProgress);

  bool get canLog =>
      _member.clientId.isNotEmpty &&
      _member.adminId.isNotEmpty &&
      _member.uid.isNotEmpty;

  /// Owner-scoped canonical history. Sorting is explicit and never relies on
  /// Firestore array/document order. V1 records remain readable during migration.
  Stream<List<TransformationEntry>> watchTransformations() {
    if (!canLog) return Stream.value(const []);
    return _col.where('authUid', isEqualTo: _member.uid).snapshots().map((
      snap,
    ) {
      final entries = snap.docs
          .map((doc) => TransformationEntry.fromMap(doc.data(), doc.id))
          .toList();
      entries.sort((a, b) {
        final byDate = b.recordedAt.compareTo(a.recordedAt);
        return byDate != 0 ? byDate : b.id.compareTo(a.id);
      });
      return entries;
    });
  }

  @override
  String newRecordId() => _col.doc().id;

  /// Creates the private recovery envelope before any media upload. A coach can
  /// never observe a half-uploaded transformation because only finalization may
  /// change visibility to `shared`.
  @override
  Future<void> createUploadDraft({
    required String recordId,
    required DateTime clientRecordedAt,
  }) async {
    if (!canLog) throw StateError('A linked member is required.');
    await _col.doc(recordId).set({
      'schemaVersion': 2,
      'kind': 'transformation',
      'clientId': _member.clientId,
      'adminId': _member.adminId,
      'authUid': _member.uid,
      'status': 'uploading',
      'visibility': 'private',
      'clientRecordedAt': Timestamp.fromDate(clientRecordedAt.toUtc()),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'photos': <String, dynamic>{},
    });
  }

  @override
  Future<TransformationPhoto> uploadPose({
    required String recordId,
    required TransformationPose pose,
    required File file,
    required String filename,
    bool persistToRecord = true,
  }) async {
    final extension = _extension(filename);
    final path =
        'progress_photos/${_member.uid}/transformations/$recordId/${pose.name}.$extension';
    final ref = _storage.ref(path);
    await ref.putFile(
      file,
      SettableMetadata(contentType: _contentType(extension)),
    );
    final photo = TransformationPhoto(
      url: await ref.getDownloadURL(),
      storagePath: path,
    );
    // Persist each successful pose immediately. If the next pose fails, retry
    // resumes from the already-uploaded media instead of duplicating it.
    if (persistToRecord) {
      await _col.doc(recordId).update({
        'photos.${pose.name}': photo.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
    return photo;
  }

  /// Removes one pose from a private recovery envelope. Completed records are
  /// immutable at the rules layer, so this is only used before publication.
  @override
  Future<void> removeDraftPose({
    required String recordId,
    required TransformationPose pose,
    required TransformationPhoto photo,
  }) async {
    if (photo.storagePath.isNotEmpty) {
      try {
        await _storage.ref(photo.storagePath).delete();
      } catch (_) {
        // Idempotent removal: a missing object is already the desired state.
      }
    }
    await _col.doc(recordId).update({
      'photos.${pose.name}': FieldValue.delete(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Atomically publishes the complete check-in after all selected uploads have
  /// succeeded. At least one observation is required; every field is optional.
  @override
  Future<TransformationWriteOutcome> finalize({
    required String recordId,
    required DateTime clientRecordedAt,
    required TransformationVisibility visibility,
    double? weightKg,
    double? bodyFatPercent,
    Map<String, double> measurements = const {},
    Map<TransformationPose, TransformationPhoto> photos = const {},
    String? note,
  }) async {
    if (!canLog) throw StateError('A linked member is required.');
    final trimmedNote = note?.trim();
    final hasContent =
        weightKg != null ||
        bodyFatPercent != null ||
        measurements.isNotEmpty ||
        photos.isNotEmpty ||
        (trimmedNote?.isNotEmpty ?? false);
    if (!hasContent) {
      throw ArgumentError('Add at least one transformation item.');
    }

    final data = <String, dynamic>{
      'schemaVersion': 2,
      'kind': 'transformation',
      'clientId': _member.clientId,
      'adminId': _member.adminId,
      'authUid': _member.uid,
      'status': 'complete',
      'visibility': visibility.name,
      'measurementUnit': 'cm',
      'recordedAt': FieldValue.serverTimestamp(),
      'clientRecordedAt': Timestamp.fromDate(clientRecordedAt.toUtc()),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
      'weightKg': ?weightKg,
      'bodyFatPercent': ?bodyFatPercent,
      if (measurements.isNotEmpty) 'measurements': measurements,
      if (photos.isNotEmpty)
        'photos': {
          for (final entry in photos.entries)
            entry.key.name: entry.value.toMap(),
        },
      if (trimmedNote != null && trimmedNote.isNotEmpty) 'note': trimmedNote,
    };
    return _acked(_col.doc(recordId).set(data, SetOptions(merge: true)));
  }

  /// Hides a cancelled recovery envelope and best-effort removes uploaded media.
  /// The tombstone is retained because Firestore deletes are intentionally denied.
  @override
  Future<void> abandon(
    String recordId,
    Iterable<TransformationPhoto> photos,
  ) async {
    for (final photo in photos) {
      if (photo.storagePath.isEmpty) continue;
      try {
        await _storage.ref(photo.storagePath).delete();
      } catch (_) {
        // Best effort; backend lifecycle cleanup can remove a remaining orphan.
      }
    }
    await _col.doc(recordId).set({
      'status': 'abandoned',
      'visibility': 'private',
      'photos': <String, dynamic>{},
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  @override
  Future<TransformationWriteOutcome> updatePublished({
    required TransformationEntry original,
    required TransformationVisibility visibility,
    double? weightKg,
    double? bodyFatPercent,
    Map<String, double> measurements = const {},
    Map<TransformationPose, TransformationPhoto> photos = const {},
    String? note,
  }) async {
    if (!canLog) throw StateError('A linked member is required.');
    final trimmedNote = note?.trim();
    final hasNote = trimmedNote != null && trimmedNote.isNotEmpty;
    if (weightKg == null &&
        bodyFatPercent == null &&
        measurements.isEmpty &&
        photos.isEmpty &&
        !hasNote) {
      // Emptying every observation would leave a checkpoint recording nothing.
      // The rules refuse it too; failing here keeps the message useful.
      throw ArgumentError('A check-in must keep at least one item.');
    }

    // `recordedAt`/`createdAt` are deliberately NOT written: they are what pin
    // this entry's place in the member's history, and the rules reject an
    // update that moves either. Cleared values are removed outright rather than
    // merged over, so a member can genuinely take a weight back off a record.
    //
    // `update` — NOT `set(merge: true)`. A merge deep-merges nested maps, so
    // sending the surviving measurements/photos would UNION them with what is
    // stored and a member could never actually remove a measurement or detach a
    // photo. `update` replaces each field wholesale, which is what "this is now
    // the whole check-in" has to mean. It also fails loudly if the record has
    // gone, instead of silently recreating a checkpoint from an edit.
    final outcome = await _acked(
      _col.doc(original.id).update({
        'status': 'complete',
        'visibility': visibility.name,
        'measurementUnit': 'cm',
        'updatedAt': FieldValue.serverTimestamp(),
        'editedAt': FieldValue.serverTimestamp(),
        'weightKg': weightKg ?? FieldValue.delete(),
        'bodyFatPercent': bodyFatPercent ?? FieldValue.delete(),
        'measurements': measurements,
        'photos': {
          for (final entry in photos.entries)
            entry.key.name: entry.value.toMap(),
        },
        'note': hasNote ? trimmedNote : FieldValue.delete(),
      }),
    );

    // Storage cleanup runs only AFTER the record is safely rewritten. Doing it
    // first would, on a failed write, delete media the still-live record points
    // at — turning a failed edit into a permanently broken photo. An orphaned
    // object is recoverable; a broken record is not.
    //
    // A merely QUEUED correction is not "safely rewritten": it has not been
    // accepted by the server and may still be rejected, so the media the live
    // record still points at is left alone. It also could not be deleted from
    // here anyway — with no connection the delete would hang exactly as the
    // write did.
    if (outcome != TransformationWriteOutcome.acknowledged) return outcome;

    for (final entry in original.photos.entries) {
      final path = entry.value.storagePath;
      if (path.isEmpty) continue;
      // A replacement at the SAME pose path has already overwritten the object;
      // deleting it here would remove the photo that was just uploaded.
      if (photos[entry.key]?.storagePath == path) continue;
      try {
        await _storage.ref(path).delete();
      } catch (_) {
        // Idempotent: a missing object is already the desired state.
      }
    }
    return outcome;
  }

  @override
  Future<TransformationWriteOutcome> setVisibility({
    required String recordId,
    required TransformationVisibility visibility,
  }) async {
    if (!canLog) throw StateError('A linked member is required.');
    return _acked(
      _col.doc(recordId).update({
        'visibility': visibility.name,
        'updatedAt': FieldValue.serverTimestamp(),
        'editedAt': FieldValue.serverTimestamp(),
      }),
    );
  }

  String _extension(String filename) {
    final raw = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : 'jpg';
    return const {'jpg', 'jpeg', 'png', 'webp', 'heic'}.contains(raw)
        ? raw
        : 'jpg';
  }

  String _contentType(String extension) => switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    'heic' => 'image/heic',
    _ => 'image/jpeg',
  };
}
