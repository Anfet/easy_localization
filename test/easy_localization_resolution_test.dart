import 'package:easy_localization_continued/src/easy_localization_app.dart';
import 'package:easy_localization_continued/src/localization.dart';
import 'package:easy_localization_continued/src/translations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

void main() {
  test('exists can inspect usable primary and fallback strings without diagnostics', () {
    for (final skipEmpty in [false, true]) {
      final snapshot = Localization.snapshot(
        const Locale('en'),
        translations: Translations({'empty': '', 'nonString': 42, 'emptyWithFallback': ''}),
        fallbackTranslations: Translations({'missing': 'F', 'emptyWithFallback': 'F', 'fallbackEmpty': '', 'nonString': false}),
        useFallbackTranslationsForEmptyResources: skipEmpty,
      );
      expect(snapshot.exists('missing'), isFalse);
      expect(snapshot.exists('missing', includeFallback: true), isTrue);
      expect(snapshot.exists('empty'), !skipEmpty);
      expect(snapshot.exists('emptyWithFallback'), !skipEmpty);
      expect(snapshot.exists('empty', includeFallback: true), !skipEmpty);
      expect(snapshot.exists('emptyWithFallback', includeFallback: true), isTrue);
      expect(snapshot.exists('fallbackEmpty', includeFallback: true), !skipEmpty);
      expect(snapshot.exists('nonString', includeFallback: true), isFalse);
    }
  });

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
    Localization.load(
      const Locale('en'),
      translations: translations,
      fallbackTranslations: Translations({
        'title': {'child': 'Fallback'},
      }),
    );

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

  test('linked keys leave sentence punctuation outside the key', () {
    Localization.load(
      const Locale('en'),
      translations: Translations({
        'title': 'Enable repayment',
        'd': 'Please turn off @:title.',
        'nested': {'b': 'Nested value'},
        'dotted': '@:nested.b',
        'bracketed': '@:(nested.b)',
      }),
    );

    final localization = Localization.instance;
    expect(localization.tr('d'), 'Please turn off Enable repayment.');
    expect(localization.tr('dotted'), 'Nested value');
    expect(localization.tr('bracketed'), 'Nested value');
  });

  test('linked translations resolve nested and sibling links in one call', () {
    final localization = Localization.snapshot(
      const Locale('en'),
      translations: Translations({
        'label': 'Email',
        'field': '@:label',
        'placeholder': 'Enter @:field',
        'upper': '@.upper:field',
        'siblings': '@:label / @:field',
      }),
    );

    expect(localization.tr('placeholder'), 'Enter Email');
    expect(localization.tr('upper'), 'EMAIL');
    expect(localization.tr('siblings'), 'Email / Email');
  });

  test('linked keys with common prefixes are replaced independently', () {
    final localization = Localization.snapshot(
      const Locale('en'),
      translations: Translations({'a': 'A', 'ab': 'B', 'source': '@:a @:ab @:a @.lower:ab'}),
    );
    expect(localization.tr('source'), 'A B A b');
  });

  test('arguments remain literal in translations and plurals', () {
    final localization = Localization.snapshot(
      const Locale('en'),
      translations: Translations({
        'positional': '{} / {}',
        'named': '{a} / {b}',
        'items': {'one': '{} / {} / {a} / {b}'},
      }),
    );
    expect(localization.tr('positional', args: ['{}', 'B']), '{} / B');
    for (final named in [
      {'a': '{b}', 'b': 'B'},
      {'b': 'B', 'a': '{b}'},
    ]) {
      expect(localization.tr('named', namedArgs: named), '{b} / B');
      expect(localization.plural('items', 1, args: ['{}', 'B'], namedArgs: named), '{} / B / {b} / B');
    }
  });

  test('cyclic linked translations remain unresolved and warn once', () {
    final warnings = <String>[];
    EasyLocalization.onWarning = (message, {stackTrace}) => warnings.add(message);
    try {
      final localization = Localization.snapshot(const Locale('en'), translations: Translations({'a': 'x @:b', 'b': 'y @:a'}));

      expect(localization.tr('a'), 'x y @:a');
      expect(warnings, ['Cyclic linked translation detected at [a]']);
    } finally {
      EasyLocalization.onWarning = null;
    }
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
    expect(
      localization.plural('items', 1234, name: 'count', format: NumberFormat('#,##0', 'en'), namedArgs: {'who': 'Ada'}, args: ['!']),
      'TOTAL round Ada 1,234 !',
    );
    expect(localization.plural('fallbackItems', 1, name: 'count', args: ['!']), 'fallback 1 !');
    expect(localization.tr('plain'), 'Hello friend');
  });

  test('named arguments use literal keys and values in translations and plurals', () {
    Localization.load(
      const Locale('en'),
      translations: Translations({
        'literal': '{0}|{a.b}|{a+b}|{aXb}|{cash}|{slash}',
        'literalPlural': {'one': '{a.b}|{a+b}|{aXb}', 'other': '{a.b}|{a+b}|{aXb}'},
      }),
    );
    final localization = Localization.instance;
    final namedArgs = {'0': r'$0\x', 'a.b': r'$1\x', 'a+b': r'$2\x', 'cash': r'$3\x', 'slash': r'$4\x'};

    expect(localization.tr('literal', namedArgs: namedArgs), r'$0\x|$1\x|$2\x|{aXb}|$3\x|$4\x');
    expect(localization.plural('literalPlural', 1, namedArgs: namedArgs), r'$1\x|$2\x|{aXb}');
  });

  test('empty linked translations stay empty with and without modifiers', () {
    Localization.load(
      const Locale('en'),
      translations: Translations({'source': 'A@:empty B', 'plain': '@:empty', 'modified': '@.capitalize:empty', 'empty': ''}),
    );

    final localization = Localization.instance;
    expect(localization.tr('source'), 'A B');
    expect(localization.tr('plain'), '');
    expect(localization.tr('modified'), '');
    expect(localization.tr('empty'), '');

    Localization.load(
      const Locale('en'),
      translations: Translations({'source': 'A@:empty B', 'plain': '@:empty', 'modified': '@.capitalize:empty', 'empty': ''}),
      fallbackTranslations: Translations({'empty': 'fallback'}),
      useFallbackTranslationsForEmptyResources: true,
    );

    final withFallback = Localization.instance;
    expect(withFallback.tr('source'), 'Afallback B');
    expect(withFallback.tr('plain'), 'fallback');
    expect(withFallback.tr('modified'), 'Fallback');
  });
}
