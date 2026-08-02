import 'package:alphaserena/core/models/coach_profile_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses the canonical safe coach projection defensively', () {
    final profile = CoachProfileModel.fromMap({
      'coachId': 'coach-1',
      'organizationId': 'org-1',
      'name': '  Serena Coach  ',
      'title': 'Strength Coach',
      'experience': '7 years',
      'specialization': 'Strength & Mobility',
      'qualifications': ['CPT'],
      'languages': ['English', 'Telugu'],
      'rating': '4.8',
      'reviewCount': 12,
      'verified': true,
      'status': 'active',
    }, 'coach-1');

    expect(profile.coachId, 'coach-1');
    expect(profile.organizationId, 'org-1');
    expect(profile.name, 'Serena Coach');
    expect(profile.title, 'Strength Coach');
    expect(profile.experience, '7 years');
    expect(profile.specialization, 'Strength & Mobility');
    expect(profile.rating, 4.8);
    expect(profile.reviewCount, 12);
    expect(profile.isActive, isTrue);
  });

  test('empty and malformed optional values stay honest', () {
    final profile = CoachProfileModel.fromMap({
      'rating': 'not-a-number',
      'reviewCount': -4,
      'languages': 'English',
      'status': 'inactive',
    }, 'coach-2');

    expect(profile.name, isEmpty);
    expect(profile.rating, 0);
    expect(profile.reviewCount, 0);
    expect(profile.languages, isEmpty);
    expect(profile.isActive, isFalse);
  });
}
