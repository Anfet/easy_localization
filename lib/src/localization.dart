import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'package:easy_localization_continued/src/diagnostics.dart';

class Localization {
  final Translations? _translations, _baseTranslations, _fallbackTranslations;
  final Locale? _baseLocale, _fallbackLocale;
  final Locale _locale;

  /// The locale captured by this translation snapshot.
  Locale get locale => _locale;

  final RegExp _replaceArgRegex = RegExp('{}');
  final RegExp _linkKeyMatcher = RegExp(r'(?:@(?:\.[a-z]+)?:(?:[\w\-|]+(?:\.[\w\-|]+)*|\([\w\-|.]+\)))');
  final RegExp _linkKeyPrefixMatcher = RegExp(r'^@(?:\.([a-z]+))?:');
  final RegExp _bracketsMatcher = RegExp('[()]');
  final _modifiers = <String, String Function(String?)>{
    'upper': (String? val) => val!.toUpperCase(),
    'lower': (String? val) => val!.toLowerCase(),
    'capitalize': (String? val) => val == null || val.isEmpty ? val ?? '' : '${val[0].toUpperCase()}${val.substring(1)}',
  };

  final bool _useFallbackTranslationsForEmptyResources;

  /// An independent translation snapshot. Later loads never change this object.
  Localization.snapshot(
    Locale locale, {
    Translations? translations,
    Translations? fallbackTranslations,
    Translations? baseTranslations,
    Locale? baseLocale,
    Locale? fallbackLocale,
    bool useFallbackTranslationsForEmptyResources = false,
  }) : _locale = locale,
       _translations = translations == null ? null : Translations.copy(translations),
       _baseTranslations = baseTranslations == null ? null : Translations.copy(baseTranslations),
       // ignore: prefer_initializing_formals
       _baseLocale = baseLocale,
       // ignore: prefer_initializing_formals
       _fallbackLocale = fallbackLocale,
       _fallbackTranslations = fallbackTranslations == null ? null : Translations.copy(fallbackTranslations),
       // ignore: prefer_initializing_formals
       _useFallbackTranslationsForEmptyResources = useFallbackTranslationsForEmptyResources;

  static Localization? _instance;

  static Localization get instance => _instance ?? (throw StateError('Call EasyLocalization.initialize before accessing translations'));

  /// Publishes a complete snapshot for the legacy global translation helpers.
  @internal
  static void publish(Localization? snapshot) => _instance = snapshot;

  static Localization? of(BuildContext context) => Localizations.of<Localization>(context, Localization);

  @internal
  static bool load(
    Locale locale, {
    Translations? translations,
    Translations? fallbackTranslations,
    Translations? baseTranslations,
    Locale? baseLocale,
    Locale? fallbackLocale,
    bool useFallbackTranslationsForEmptyResources = false,
  }) {
    _instance = Localization.snapshot(
      locale,
      translations: translations,
      fallbackTranslations: fallbackTranslations,
      useFallbackTranslationsForEmptyResources: useFallbackTranslationsForEmptyResources,
      baseTranslations: baseTranslations,
      baseLocale: baseLocale,
      fallbackLocale: fallbackLocale,
    );
    return translations == null ? false : true;
  }

  String tr(String key, {List<String>? args, Map<String, String>? namedArgs, String? gender}) {
    late String res;

    if (gender != null) {
      res = _gender(key, gender: gender);
    } else {
      res = _resolve(key);
    }

    res = _replaceLinks(res, keys: {key});

    res = _replaceNamedArgs(res, namedArgs);

    return _replaceArgs(res, args);
  }

  String _replaceLinks(String res, {bool logging = true, Set<String>? keys, Set<String>? cycleWarnings}) {
    final resolvingKeys = keys ?? <String>{};
    final reportedCycles = cycleWarnings ?? <String>{};
    final matches = _linkKeyMatcher.allMatches(res);
    var result = res;

    for (final match in matches) {
      final link = match[0]!;
      final linkPrefixMatches = _linkKeyPrefixMatcher.allMatches(link);
      final linkPrefix = linkPrefixMatches.first[0]!;
      final formatterName = linkPrefixMatches.first[1];

      // Remove the leading @:, @.case: and the brackets
      final linkPlaceholder = link.replaceAll(linkPrefix, '').replaceAll(_bracketsMatcher, '');

      if (resolvingKeys.contains(linkPlaceholder)) {
        if (logging && reportedCycles.isEmpty) {
          reportLocalizationDiagnostic(EasyLocalization.onWarning, 'Cyclic linked translation detected at [$linkPlaceholder]');
          reportedCycles.add(linkPlaceholder);
        }
        continue;
      }

      resolvingKeys.add(linkPlaceholder);
      var translated = _replaceLinks(_resolve(linkPlaceholder), logging: logging, keys: resolvingKeys, cycleWarnings: reportedCycles);
      resolvingKeys.remove(linkPlaceholder);

      if (formatterName != null) {
        if (_modifiers.containsKey(formatterName)) {
          translated = _modifiers[formatterName]!(translated);
        } else {
          if (logging) {
            reportLocalizationDiagnostic(
              EasyLocalization.onWarning,
              'Undefined modifier $formatterName, available modifiers: ${_modifiers.keys.toString()}',
            );
          }
        }
      }

      result = translated.isEmpty ? result : result.replaceAll(link, translated);
    }

    return result;
  }

  String _replaceArgs(String res, List<String>? args) {
    if (args == null || args.isEmpty) return res;
    for (var str in args) {
      res = res.replaceFirst(_replaceArgRegex, str);
    }
    return res;
  }

  String _replaceNamedArgs(String res, Map<String, String>? args) {
    if (args == null || args.isEmpty) return res;
    args.forEach((String key, String value) => res = res.replaceAll('{$key}', value));
    return res;
  }

  String plural(String key, num value, {List<String>? args, Map<String, String>? namedArgs, String? name, NumberFormat? format}) {
    final missing = Object();
    String? selected;
    for (final (translations, locale) in [
      (_translations, _locale),
      (_baseTranslations, _baseLocale ?? _locale),
      (_fallbackTranslations, _fallbackLocale ?? _locale),
    ]) {
      if (translations == null) continue;
      String? form(String name) {
        final result = translations.get('$key.$name');
        return result == null || (_useFallbackTranslationsForEmptyResources && result.isEmpty) ? null : result;
      }

      final result = Intl.pluralLogic<Object>(
        value,
        locale: locale.toString(),
        zero: form('zero'),
        one: form('one'),
        two: form('two'),
        few: form('few'),
        many: form('many'),
        other: form('other') ?? missing,
      );
      if (!identical(result, missing)) {
        selected = result as String;
        break;
      }
    }
    if (selected == null) {
      reportLocalizationDiagnostic(EasyLocalization.onWarning, 'Localization key [$key.other] not found');
    }
    var res = selected ?? '$key.other';

    res = _replaceLinks(res, keys: {key});

    final formattedValue = format == null ? '$value' : format.format(value);

    if (name != null) {
      namedArgs = {...?namedArgs, name: formattedValue};
    }
    res = _replaceNamedArgs(res, namedArgs);

    return _replaceArgs(res, args ?? [formattedValue]);
  }

  String _gender(String key, {required String gender}) {
    return _resolve('$key.$gender');
  }

  String _resolve(String key, {bool logging = true, bool fallback = true}) {
    bool available(String? value) => value != null && (!_useFallbackTranslationsForEmptyResources || value.isNotEmpty);
    final primary = _translations?.get(key);
    if (available(primary)) return primary as String;
    if (logging) reportLocalizationDiagnostic(EasyLocalization.onWarning, 'Localization key [$key] not found');
    if (fallback) {
      for (final translations in [_baseTranslations, _fallbackTranslations]) {
        final resource = translations?.get(key);
        if (available(resource)) return resource as String;
      }
      if (logging && (_baseTranslations != null || _fallbackTranslations != null)) {
        reportLocalizationDiagnostic(EasyLocalization.onWarning, 'Fallback localization key [$key] not found');
      }
    }
    return key;
  }

  bool exists(String key, {bool includeFallback = false}) {
    final primary = _translations?.get(key);
    if (!includeFallback) return primary != null;
    if (primary != null && (!_useFallbackTranslationsForEmptyResources || primary.isNotEmpty)) return true;
    final base = _baseTranslations?.get(key);
    if (base != null && (!_useFallbackTranslationsForEmptyResources || base.isNotEmpty)) return true;
    final fallback = _fallbackTranslations?.get(key);
    return fallback != null && (!_useFallbackTranslationsForEmptyResources || fallback.isNotEmpty);
  }
}
