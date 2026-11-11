import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import 'package:easy_localization_continued/src/diagnostics.dart';
import 'package:easy_localization_continued/src/linked_key_parser.dart';

class Localization {
  final Translations? _translations, _baseTranslations, _fallbackTranslations;
  final Locale? _baseLocale, _fallbackLocale;
  final Locale _locale;

  /// The locale captured by this translation snapshot.
  Locale get locale => _locale;

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

    return _replaceArgs(res, args, namedArgs);
  }

  String _replaceLinks(String res, {bool logging = true, Set<String>? keys, Set<String>? cycleWarnings}) {
    final resolvingKeys = keys ?? <String>{};
    final reportedCycles = cycleWarnings ?? <String>{};
    return res.replaceAllMapped(linkedKeyMatcher, (match) {
      final link = match[0]!;
      final linkPrefixMatches = linkedKeyPrefixMatcher.allMatches(link);
      final linkPrefix = linkPrefixMatches.first[0]!;
      final formatterName = linkPrefixMatches.first[1];

      // Remove the leading @:, @.case: and the brackets
      final linkPlaceholder = link.replaceAll(linkPrefix, '').replaceAll(_bracketsMatcher, '');

      if (resolvingKeys.contains(linkPlaceholder)) {
        if (logging && reportedCycles.isEmpty) {
          reportLocalizationDiagnostic(EasyLocalization.onWarning, 'Cyclic linked translation detected at [$linkPlaceholder]');
          reportedCycles.add(linkPlaceholder);
        }
        return link;
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

      return translated;
    });
  }

  String _replaceArgs(String res, List<String>? args, Map<String, String>? namedArgs) {
    final tokens = <String>{if (args != null && args.isNotEmpty) '{}', ...?namedArgs?.keys.map((key) => '{$key}')};
    if (tokens.isEmpty) return res;
    final matcher = RegExp(tokens.map(RegExp.escape).join('|'));
    var index = 0;
    return res.replaceAllMapped(matcher, (match) {
      final token = match[0] ?? '';
      final namedValue = namedArgs?[token.substring(1, token.length - 1)];
      if (namedValue != null) return namedValue;
      if (token == '{}' && args != null && index < args.length) return args[index++];
      return token;
    });
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
    return _replaceArgs(res, args == null || args.isEmpty ? [formattedValue] : args, namedArgs);
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
    if (primary != null && (!_useFallbackTranslationsForEmptyResources || primary.isNotEmpty)) return true;
    if (!includeFallback) return false;
    final base = _baseTranslations?.get(key);
    if (base != null && (!_useFallbackTranslationsForEmptyResources || base.isNotEmpty)) return true;
    final fallback = _fallbackTranslations?.get(key);
    return fallback != null && (!_useFallbackTranslationsForEmptyResources || fallback.isNotEmpty);
  }
}
