import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/core/models/organization_profile_model.dart';
import 'package:alphaserena/controllers/discover_controller.dart';

OrganizationProfileModel _org(String name,
        {String? city,
        String? state,
        List<String> specs = const [],
        List<String> langs = const []}) =>
    OrganizationProfileModel(
        adminId: name,
        name: name,
        city: city,
        state: state,
        specializations: specs,
        languages: langs);

void main() {
  final orgs = [
    _org('Alpha Strength', city: 'Mumbai', state: 'Maharashtra',
        specs: ['Strength Training', 'Fat Loss'], langs: ['English', 'Hindi']),
    _org('FitNation', city: 'Bangalore', state: 'Karnataka',
        specs: ['HIIT', 'Fat Loss'], langs: ['English', 'Kannada']),
    _org('Zenith Wellness', city: 'Pune', state: 'Maharashtra',
        specs: ['Yoga'], langs: ['Marathi']),
  ];

  test('query matches name and specialization, case-insensitive', () {
    expect(filterOrgs(orgs, query: 'alpha').map((o) => o.name), ['Alpha Strength']);
    expect(filterOrgs(orgs, query: 'fat loss').map((o) => o.name),
        ['Alpha Strength', 'FitNation']);
  });

  test('location filter matches city', () {
    expect(filterOrgs(orgs, location: 'Mumbai').map((o) => o.name),
        ['Alpha Strength']);
  });

  test('specialization filter narrows the list', () {
    expect(filterOrgs(orgs, specialization: 'Yoga').map((o) => o.name),
        ['Zenith Wellness']);
  });

  test('language filter narrows the list', () {
    expect(filterOrgs(orgs, language: 'Hindi').map((o) => o.name),
        ['Alpha Strength']);
    expect(filterOrgs(orgs, language: 'English').map((o) => o.name),
        ['Alpha Strength', 'FitNation']);
  });

  test('filters and query combine with AND', () {
    expect(
        filterOrgs(orgs, query: 'fit', specialization: 'Fat Loss')
            .map((o) => o.name),
        ['FitNation']);
    expect(
        filterOrgs(orgs, language: 'English', specialization: 'HIIT')
            .map((o) => o.name),
        ['FitNation']);
  });

  test('distinct helpers are sorted and de-duped', () {
    expect(distinctLocations(orgs), ['Bangalore', 'Mumbai', 'Pune']);
    expect(distinctSpecializations(orgs),
        ['Fat Loss', 'HIIT', 'Strength Training', 'Yoga']);
    expect(distinctLanguages(orgs),
        ['English', 'Hindi', 'Kannada', 'Marathi']);
  });

  test('model reads languages from legacy spokenLanguages fallback', () {
    final o = OrganizationProfileModel.fromMap(
        {'name': 'X', 'spokenLanguages': ['Tamil', 'Telugu']}, 'id');
    expect(o.languages, ['Tamil', 'Telugu']);
  });
}
