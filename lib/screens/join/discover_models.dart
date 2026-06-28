import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/models/organization_profile_model.dart';

/// "3999" → "3,999" (Indian grouping).
String inr(int n) => NumberFormat.decimalPattern('en_IN').format(n);

/// Presentation model for the discovery / storefront mockups. Carries the rich
/// marketing fields the design shows (rating, location, clients, tags, plans)
/// that the lean Firestore `organizationProfiles` doc does not yet store.
class DiscoverOrg {
  final String id;
  final String name;
  final String tagline;
  final String city;
  final String state;
  final String clientsLabel; // e.g. "1.2K+"
  final int plusAvatars; // e.g. 120 → "+120"
  final double rating;
  final bool verified;
  final List<String> tags;
  final String thumb; // square card photo asset
  final String hero; // storefront hero asset
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
    required this.logoColor,
    required this.logoIcon,
  });

  /// Bridge a live org profile into the legacy presentation model used by the
  /// (still-mock) storefront + checkout flow. Network images via [thumb]/[hero].
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
        logoColor: const Color(0xFFE10600),
        logoIcon: Icons.fitness_center,
      );

  String get location => '$city, $state';
}

/// A membership plan shown in the plans / checkout flow.
class MembershipPlan {
  final String name;
  final int weeks;
  final int price;
  final List<String> features;
  final String clientsTransformed; // e.g. "1.2K+"
  final bool popular;

  const MembershipPlan({
    required this.name,
    required this.weeks,
    required this.price,
    required this.features,
    required this.clientsTransformed,
    this.popular = false,
  });

  String get program => '$weeks Weeks Program';
}

/// The three plans exactly as shown in the plans mockup.
const List<MembershipPlan> kPlans = [
  MembershipPlan(
    name: 'Premium Transformation',
    weeks: 12,
    price: 3999,
    popular: true,
    clientsTransformed: '1.2K+',
    features: [
      'Personalized Workout Plan',
      'Customized Nutrition Plan',
      '1-on-1 Expert Coaching',
      'Progress Tracking',
      '24/7 Support',
    ],
  ),
  MembershipPlan(
    name: 'Standard Fitness',
    weeks: 8,
    price: 2499,
    clientsTransformed: '850+',
    features: [
      'Workout Plan',
      'Nutrition Guidance',
      'Weekly Check-ins',
      'Progress Tracking',
    ],
  ),
  MembershipPlan(
    name: 'Basic Starter',
    weeks: 4,
    price: 1499,
    clientsTransformed: '400+',
    features: [
      'Basic Workout Plan',
      'Basic Nutrition Plan',
      'Email Support',
    ],
  ),
];

