import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/organization_profile_model.dart';

/// "3999" → "3,999" (Indian grouping).
String inr(int n) => NumberFormat.decimalPattern('en_IN').format(n);

/// Presentation model for the discovery / storefront mockups. Carries the rich
/// marketing fields the design shows (rating, location, clients, tags, plans)
/// that the lean Firestore `organizationProfiles` doc does not yet store.
class DiscoverOrg {
  final String id; // == organization adminId
  final String name;
  final String tagline;
  final String city;
  final String state;
  final String clientsLabel; // e.g. "1.2K+"
  final int plusAvatars; // e.g. 120 → "+120"
  final double rating;
  final bool verified;
  final List<String> tags;
  final String thumb; // square card photo (network url)
  final String hero; // storefront hero (network url)
  final String logoUrl; // org logo (network url)
  final Color logoColor;
  final IconData logoIcon;

  const DiscoverOrg({
    required this.id,
    required this.name,
    required this.tagline,
    required this.city,
    required this.state,
    required this.clientsLabel,
    required this.plusAvatars,
    required this.rating,
    required this.verified,
    required this.tags,
    required this.thumb,
    required this.hero,
    this.logoUrl = '',
    required this.logoColor,
    required this.logoIcon,
  });

  /// Bridge a live org profile into the presentation model used by the join
  /// flow. All images are network urls.
  factory DiscoverOrg.fromProfile(OrganizationProfileModel o) => DiscoverOrg(
    id: o.adminId,
    name: o.name,
    tagline: o.tagline ?? '',
    city: o.city ?? '',
    state: o.state ?? '',
    clientsLabel: o.statClientsTrained ?? '',
    plusAvatars: 0,
    rating: o.rating,
    verified: o.verified,
    tags: o.specializations,
    thumb: o.coverImageUrl ?? o.logoUrl ?? '',
    hero: o.coverImageUrl ?? o.logoUrl ?? '',
    logoUrl: o.logoUrl ?? '',
    logoColor: const Color(0xFFE10600),
    logoIcon: Icons.fitness_center,
  );

  String get location => '$city, $state';
}

/// A membership plan in the join flow — built from the real Firestore
/// `membershipPlans` doc (mirrors trainersHQ's MembershipPlanModel). The plan
/// [id] is what the purchase Cloud Functions need.
class PlanVM {
  final String id;
  final String adminId;
  final String name;
  final String description;
  final int price; // whole rupees (for inr() formatting)
  final int months;
  final List<String> points;
  final bool featured; // "MOST POPULAR" highlight

  const PlanVM({
    required this.id,
    required this.adminId,
    required this.name,
    required this.description,
    required this.price,
    required this.months,
    required this.points,
    required this.featured,
  });

  factory PlanVM.fromMap(Map<String, dynamic> m) {
    int monthsOf(dynamic v) {
      final n = (v is num) ? v.toInt() : int.tryParse('$v') ?? 0;
      return n > 0 ? n : 1;
    }

    return PlanVM(
      id: (m['id'] ?? '').toString(),
      adminId: (m['adminId'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      price: ((m['price'] as num?) ?? 0).round(),
      months: monthsOf(m['months'] ?? m['durationMonths']),
      points: List<String>.from(m['points'] ?? const []),
      featured: m['featured'] == true,
    );
  }

  String get durationLabel => months == 1 ? '1 month' : '$months months';
  String get program =>
      months == 1 ? '1 Month Program' : '$months Month Program';
}

/// A small org thumbnail (network cover/logo) with a branded fallback tile —
/// shared by the order cards across the join flow.
class OrgThumb extends StatelessWidget {
  final DiscoverOrg org;
  final double size;
  const OrgThumb({super.key, required this.org, required this.size});

  @override
  Widget build(BuildContext context) {
    final url = org.thumb.isNotEmpty ? org.thumb : org.logoUrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: url.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, _) => _fallback(),
              errorWidget: (_, _, _) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => Container(
    width: size,
    height: size,
    color: const Color(0xFF1E1E1E),
    alignment: Alignment.center,
    child: Icon(org.logoIcon, color: org.logoColor, size: size * 0.45),
  );
}
