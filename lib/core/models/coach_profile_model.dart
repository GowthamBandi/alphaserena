import 'package:cloud_firestore/cloud_firestore.dart';

String? _optional(Object? value) {
  final text = (value ?? '').toString().trim();
  return text.isEmpty ? null : text;
}

List<String> _strings(Object? value) => value is List
    ? value
          .map((e) => (e ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toList()
    : const [];

/// Member-safe projection of TrainerHQ's canonical CoachProfile.
class CoachProfileModel {
  final String coachId;
  final String name;
  final String? avatarUrl;
  final String title;
  final String? specialization;
  final String? experience;
  final List<String> qualifications;
  final String? bio;
  final List<String> languages;
  final bool verified;
  final String status;
  final String organizationId;
  final double rating;
  final int reviewCount;

  const CoachProfileModel({
    required this.coachId,
    required this.name,
    this.avatarUrl,
    required this.title,
    this.specialization,
    this.experience,
    this.qualifications = const [],
    this.bio,
    this.languages = const [],
    this.verified = false,
    this.status = 'inactive',
    required this.organizationId,
    this.rating = 0,
    this.reviewCount = 0,
  });

  bool get isActive => status == 'active';

  factory CoachProfileModel.fromMap(Map<String, dynamic> map, String id) {
    final parsedRating = map['rating'] is num
        ? (map['rating'] as num).toDouble()
        : double.tryParse('${map['rating']}') ?? 0;
    final parsedCount = map['reviewCount'] is num
        ? (map['reviewCount'] as num).toInt()
        : int.tryParse('${map['reviewCount']}') ?? 0;
    return CoachProfileModel(
      coachId: (map['coachId'] ?? id).toString(),
      name: (map['name'] ?? '').toString().trim(),
      avatarUrl: _optional(map['avatarUrl']),
      title: (map['title'] ?? 'Coach').toString(),
      specialization: _optional(map['specialization']),
      experience: _optional(map['experience']),
      qualifications: _strings(map['qualifications']),
      bio: _optional(map['bio']),
      languages: _strings(map['languages']),
      verified: map['verified'] == true,
      status: (map['status'] ?? 'inactive').toString(),
      organizationId: (map['organizationId'] ?? '').toString(),
      rating: parsedRating.clamp(0, 5),
      reviewCount: parsedCount < 0 ? 0 : parsedCount,
    );
  }

  factory CoachProfileModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) => CoachProfileModel.fromMap(snapshot.data() ?? {}, snapshot.id);
}
