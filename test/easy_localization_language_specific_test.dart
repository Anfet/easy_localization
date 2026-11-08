import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('language categories use intl for non-explicit values', () {
    final translations = Translations({
      'p': {'one': 'one', 'few': 'few', 'many': 'many', 'other': 'other'},
    });
    for (final (locale, value, expected) in <(String, num, String)>[
      ('ru', 21, 'one'),
      ('ru', 22, 'few'),
      ('ru', 5, 'many'),
      ('ru', 1.5, 'other'),
      ('be', 21, 'one'),
      ('kk', 3, 'other'),
      ('en', 3, 'other'),
      ('fi', 3, 'other'),
      ('sv', 3, 'other'),
    ]) {
      expect(Localization.snapshot(Locale(locale), translations: translations).plural('p', value), expected, reason: '$locale $value');
    }
  });
}
