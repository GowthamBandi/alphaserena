import 'package:cloud_firestore/cloud_firestore.dart';

String? _strOrNull(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

List<String> _strList(dynamic v) {
  if (v is List) {
    return v
        .map((e) => e.toString().trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }
  return const [];
}

double _toDouble(dynamic v) {
  if (v is num) return v.toDouble();
  if (v is String) return double.tryParse(v) ?? 0;
  return 0;
}

int _toInt(dynamic v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? 0;
  return 0;
}

/// One before/after client transformation shown on the storefront.
class Transformation {
  final String beforeUrl;
  final String afterUrl;
  final String name;
  final String? caption;

  const Transformation({
    required this.beforeUrl,
    required this.afterUrl,
    required this.name,
    this.caption,
  });

  factory Transformation.fromMap(Map<String, dynamic> m) => Transformation(
        beforeUrl: (m['beforeUrl'] ?? '').toString(),
        afterUrl: (m['afterUrl'] ?? '').toString(),
        name: (m['name'] ?? '').toString(),
        caption: _strOrNull(m['caption']),
      );

  Map<String, dynamic> toMap() => {
        'beforeUrl': beforeUrl,
        'afterUrl': afterUrl,
        'name': name,
        if (caption != null) 'caption': caption,
      };
}

/// An organization's public storefront (`organizationProfiles/{adminId}`).
/// Doc id == the owning admin's uid (one profile per org).
class OrganizationProfileModel {
  final String adminId;
  final String name;
  final String? logoUrl;
  final String? about;
  final String? address;
  final String? phone;
  final String? email;
  final String? instagram;
  final String? website;
  // Discovery (member app): a shareable code/handle + opt-in to the coach list.
  final String? handle;
  final bool published;

  // Storefront media
  final String? coverImageUrl;
  final String? coverVideoUrl;
  final String? coverVideoPosterUrl; // auto-generated frame; instant video poster

  // Identity
  final String? tagline;
  final String? city;
  final String? state;
  final List<String> specializations;

  /// Languages the coach operates in. Read defensively from either `languages`
  /// or the legacy `spokenLanguages` field on the org doc (TrainersHQ stores
  /// the latter on the admin record). Drives the Discover language filter.
  final List<String> languages;

  // Coach-typed stat band
  final String? statClientsTrained;
  final String? statYearsExperience;
  final String? statCertifiedTrainers;
  final String? statTransformations;

  // Social proof
  final String? testimonialQuote;
  final String? testimonialAuthor;
  final List<Transformation> transformations;

  // Selling points
  final List<String> whatWeOffer;
  final List<String> whyChooseUs;

  // Footer
  final String? operatingHours;
  final String? facebook;
  final String? youtube;
  final String? twitter;

  // Platform-controlled (read-only in this app)
  final double rating;
  final int reviewCount;
  final bool verified;

  const OrganizationProfileModel({
    required this.adminId,
    required this.name,
    this.logoUrl,
    this.about,
    this.address,
    this.phone,
    this.email,
    this.instagram,
    this.website,
    this.handle,
    this.published = false,
    this.coverImageUrl,
    this.coverVideoUrl,
    this.coverVideoPosterUrl,
    this.tagline,
    this.city,
    this.state,
    this.specializations = const [],
    this.languages = const [],
    this.statClientsTrained,
    this.statYearsExperience,
    this.statCertifiedTrainers,
    this.statTransformations,
    this.testimonialQuote,
    this.testimonialAuthor,
    this.transformations = const [],
    this.whatWeOffer = const [],
    this.whyChooseUs = const [],
    this.operatingHours,
    this.facebook,
    this.youtube,
    this.twitter,
    this.rating = 0,
    this.reviewCount = 0,
    this.verified = false,
  });

  bool get hasLogo => logoUrl != null && logoUrl!.isNotEmpty;
  bool get hasCoverImage => coverImageUrl != null && coverImageUrl!.isNotEmpty;
  bool get hasCoverVideo => coverVideoUrl != null && coverVideoUrl!.isNotEmpty;
  bool get hasRating => reviewCount > 0;

  factory OrganizationProfileModel.fromMap(
    Map<String, dynamic> m,
    String id,
  ) {
    return OrganizationProfileModel(
      adminId: id,
      name: (m['name'] ?? '').toString(),
      logoUrl: _strOrNull(m['logoUrl']),
      about: _strOrNull(m['about']),
      address: _strOrNull(m['address']),
      phone: _strOrNull(m['phone']),
      email: _strOrNull(m['email']),
      instagram: _strOrNull(m['instagram']),
      website: _strOrNull(m['website']),
      handle: _strOrNull(m['handle']),
      published: m['published'] == true,
      coverImageUrl: _strOrNull(m['coverImageUrl']),
      coverVideoUrl: _strOrNull(m['coverVideoUrl']),
      coverVideoPosterUrl: _strOrNull(m['coverVideoPosterUrl']),
      tagline: _strOrNull(m['tagline']),
      city: _strOrNull(m['city']),
      state: _strOrNull(m['state']),
      specializations: _strList(m['specializations']),
      languages: m['languages'] != null
          ? _strList(m['languages'])
          : _strList(m['spokenLanguages']),
      statClientsTrained: _strOrNull(m['statClientsTrained']),
      statYearsExperience: _strOrNull(m['statYearsExperience']),
      statCertifiedTrainers: _strOrNull(m['statCertifiedTrainers']),
      statTransformations: _strOrNull(m['statTransformations']),
      testimonialQuote: _strOrNull(m['testimonialQuote']),
      testimonialAuthor: _strOrNull(m['testimonialAuthor']),
      transformations: (m['transformations'] is List)
          ? (m['transformations'] as List)
              .whereType<Map>()
              .map((e) =>
                  Transformation.fromMap(Map<String, dynamic>.from(e)))
              .where((t) => t.beforeUrl.isNotEmpty || t.afterUrl.isNotEmpty)
              .toList()
          : const [],
      whatWeOffer: _strList(m['whatWeOffer']),
      whyChooseUs: _strList(m['whyChooseUs']),
      operatingHours: _strOrNull(m['operatingHours']),
      facebook: _strOrNull(m['facebook']),
      youtube: _strOrNull(m['youtube']),
      twitter: _strOrNull(m['twitter']),
      rating: _toDouble(m['rating']),
      reviewCount: _toInt(m['reviewCount']),
      verified: m['verified'] == true,
    );
  }

  factory OrganizationProfileModel.fromSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snap,
  ) =>
      OrganizationProfileModel.fromMap(snap.data() ?? {}, snap.id);
}
