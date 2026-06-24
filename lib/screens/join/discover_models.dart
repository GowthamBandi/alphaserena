import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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

/// The four organizations exactly as shown in the discovery mockup.
const List<DiscoverOrg> kSampleOrgs = [
  DiscoverOrg(
    id: 'alpha',
    name: 'Alpha Strength Co.',
    tagline: 'Build Strength. Build Legacy.',
    city: 'Mumbai',
    state: 'Maharashtra',
    clientsLabel: '1.2K+',
    plusAvatars: 120,
    rating: 4.9,
    verified: true,
    tags: ['Strength Training', 'Muscle Building', 'Fat Loss'],
    thumb: 'assets/images/org1.png',
    hero: 'assets/images/org1.png',
    logoColor: Color(0xFFE10600),
    logoIcon: Icons.change_history,
  ),
  DiscoverOrg(
    id: 'fitnation',
    name: 'FitNation Studio',
    tagline: 'Stronger Every Day',
    city: 'Bangalore',
    state: 'Karnataka',
    clientsLabel: '980+',
    plusAvatars: 85,
    rating: 4.8,
    verified: true,
    tags: ['Weight Loss', 'HIIT', 'Functional Training'],
    thumb: 'assets/images/org2.png',
    hero: 'assets/images/org2.png',
    logoColor: Colors.white,
    logoIcon: Icons.diamond_outlined,
  ),
  DiscoverOrg(
    id: 'prime',
    name: 'Prime Performance',
    tagline: 'Performance. Power. Progress.',
    city: 'Delhi',
    state: 'NCR',
    clientsLabel: '850+',
    plusAvatars: 60,
    rating: 4.7,
    verified: true,
    tags: ['Strength', 'Powerlifting', 'Sports Conditioning'],
    thumb: 'assets/images/org3.png',
    hero: 'assets/images/org3.png',
    logoColor: Colors.white,
    logoIcon: Icons.bolt,
  ),
  DiscoverOrg(
    id: 'zenith',
    name: 'Zenith Wellness',
    tagline: 'Mind. Body. Balance.',
    city: 'Pune',
    state: 'Maharashtra',
    clientsLabel: '620+',
    plusAvatars: 45,
    rating: 4.9,
    verified: true,
    tags: ['Yoga', 'Mobility', 'Mental Wellness'],
    thumb: 'assets/images/org4.png',
    hero: 'assets/images/org4.png',
    logoColor: Colors.white,
    logoIcon: Icons.spa_outlined,
  ),
];
