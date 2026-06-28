import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/models/organization_profile_model.dart';

void main() {
  test('fromMap parses rich fields defensively', () {
    final m = OrganizationProfileModel.fromMap({
      'name': 'Alpha Strength Co.',
      'tagline': 'Build Strength.',
      'city': 'Mumbai',
      'state': 'Maharashtra',
      'specializations': ['Strength Training', '', 'Fat Loss'],
      'statClientsTrained': '1.2K+',
      'rating': '4.9', // string → double
      'reviewCount': 320,
      'verified': true,
      'published': true,
      'logoUrl': '  ', // blank → null
    }, 'admin123');

    expect(m.adminId, 'admin123');
    expect(m.name, 'Alpha Strength Co.');
    expect(m.city, 'Mumbai');
    expect(m.specializations, ['Strength Training', 'Fat Loss']); // blanks dropped
    expect(m.statClientsTrained, '1.2K+');
    expect(m.rating, 4.9);
    expect(m.reviewCount, 320);
    expect(m.verified, isTrue);
    expect(m.hasRating, isTrue);
    expect(m.logoUrl, isNull); // blank string → null
    expect(m.hasLogo, isFalse);
  });

  test('fromMap tolerates a near-empty doc', () {
    final m = OrganizationProfileModel.fromMap({'name': 'X'}, 'id1');
    expect(m.name, 'X');
    expect(m.specializations, isEmpty);
    expect(m.rating, 0);
    expect(m.reviewCount, 0);
    expect(m.verified, isFalse);
    expect(m.hasRating, isFalse);
  });
}
