import 'package:easy_localization_continued/src/localization.dart';
import 'package:easy_localization_continued/src/translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('explicit cases and language categories', () {
    final all = Translations({
      'p': {'zero': 'zero', 'one': 'one', 'two': 'two', 'few': 'few', 'many': 'many', 'other': 'other'},
    });
    final noExplicit = Translations({
      'p': {'one': 'one', 'few': 'few', 'many': 'many', 'other': 'other'},
    });
    for (final (locale, translations, cases) in <(Locale, Translations, Map<num, String>)>[
      (const Locale('en'), all, {0: 'zero', 1: 'one', 2: 'two', 3: 'other', 4: 'other', 5: 'other'}),
      (const Locale('en'), noExplicit, {0: 'other'}),
      (const Locale('ru'), noExplicit, {1: 'one', 2: 'few', 5: 'many', 21: 'one', 1.5: 'other'}),
      (const Locale('ru'), all, {0: 'zero'}),
      (const Locale('ar'), all, {0: 'zero', 2: 'two', 3: 'few', 11: 'many', 100: 'other'}),
      (const Locale('ar'), noExplicit, {2: 'few'}),
      (const Locale('pt', 'PT'), noExplicit, {0: 'other'}),
      (const Locale('pt', 'BR'), noExplicit, {0: 'one'}),
    ]) {
      final snapshot = Localization.snapshot(locale, translations: translations);
      for (final entry in cases.entries) {
        expect(snapshot.plural('p', entry.key), entry.value, reason: '$locale ${entry.key}');
      }
    }
  });
}
