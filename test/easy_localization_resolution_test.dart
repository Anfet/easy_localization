import 'package:easy_localization/src/localization.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  test('nested lookup returns only complete string leaves and permits fallback', () {
    final translations = Translations({
      'title': 'Parent',
      'object': {'child': 2},
      'number': 3,
      'flag': true,
      'nested': {'child': 'Nested'},
      'exact.child': 'Exact',
      'exact': {'child': 'Nested exact'},
    });
    Localization.load(const Locale('en'),
        translations: translations,
        fallbackTranslations: Translations({
          'title': {'child': 'Fallback'}
        }));

    expect(translations.get('title.child'), isNull);
    expect(Localization.instance.exists('title.child'), isFalse);
    expect(Localization.instance.tr('title.child'), 'Fallback');
    expect(Localization.instance.tr('missing.path'), 'missing.path');
    for (final key in ['object', 'object.child', 'number', 'flag', 'number.child']) {
      expect(translations.get(key), isNull);
    }
    expect(translations.get('exact.child'), 'Exact');
    expect(translations.get('nested.child'), 'Nested');
    expect(translations.get('nested.child'), 'Nested');
    expect(translations.isNestedCached('nested.child'), isTrue);
    expect(translations.isNestedCached('object.child'), isFalse);
  });

  test('plural expands links before replacing named and positional arguments', () {
    Localization.load(
      const Locale('en'),
      translations: Translations({
        'round': 'round {who} {count} {}',
        'items': {'one': '@:round', 'other': '@.upper:label @:round'},
        'label': 'total',
        'plain': 'Hello @:person',
        'person': 'friend',
      }),
      fallbackTranslations: Translations({
        'fallbackItems': {'one': '@:fallbackLink'},
        'fallbackLink': 'fallback {count} {}',
      }),
    );
    final localization = Localization.instance;
    expect(localization.plural('items', 1, name: 'count', namedArgs: {'who': 'Ada'}, args: ['!']), 'round Ada 1 !');
    expect(localization.plural('items', 1234, name: 'count', format: NumberFormat('#,##0', 'en'), namedArgs: {'who': 'Ada'}, args: ['!']),
        'TOTAL round Ada 1,234 !');
    expect(localization.plural('fallbackItems', 1, name: 'count', args: ['!']), 'fallback 1 !');
    expect(localization.tr('plain'), 'Hello friend');
  });
}
