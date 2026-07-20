import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:alphaserena/screens/dashboard/notification_visuals.dart';

/// The 10 frozen backend categories
/// (trainershq-backend/functions/src/lib/notification_center.ts
/// `NOTIFICATION_CATEGORIES`). The member center must render each distinctly,
/// and identically to the coach app — this guards the earlier defect where
/// most categories collapsed to a generic grey icon.
const _backendCategories = <String>[
  'calls',
  'communication',
  'coaching',
  'membership',
  'billing',
  'organization',
  'security',
  'system',
  'announcements',
  'marketing',
];

void main() {
  group('notificationVisual (member app)', () {
    test('every backend category has an explicit (non-fallback) visual', () {
      final fallback = notificationVisual('__definitely_unknown__');
      for (final cat in _backendCategories) {
        final v = notificationVisual(cat);
        expect(v.label.isNotEmpty, isTrue, reason: '$cat has a label');
        final degraded =
            v.icon == fallback.icon && v.color == fallback.color;
        expect(degraded, isFalse,
            reason: '$cat must not fall back to the default visual');
      }
    });

    test('mapped set is exactly the 10 backend categories', () {
      expect(mappedNotificationCategories.toSet(), _backendCategories.toSet());
    });

    test('category colours are visually distinct', () {
      final colors = <Color, String>{};
      for (final cat in _backendCategories) {
        final v = notificationVisual(cat);
        expect(colors.containsKey(v.color), isFalse,
            reason: '$cat shares a colour with ${colors[v.color]}');
        colors[v.color] = cat;
      }
    });

    test('an unknown category returns a safe, non-empty fallback', () {
      final v = notificationVisual('something_new');
      expect(v.label.isNotEmpty, isTrue);
    });
  });
}
