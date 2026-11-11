import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'localization.dart';
import 'easy_localization_app.dart';
import 'exceptions.dart';

Localization _translator(Locale? locale, BuildContext? context) {
  if (locale != null) {
    final owner = EasyLocalization.instance;
    if (!owner.supportedLocales.contains(locale)) throw ArgumentError.value(locale, 'locale', 'Must be supported');
    if (locale == owner.locale) return owner.dataTranslator;
    return owner.translators[locale] ?? (throw StateError('Translations for $locale are not loaded; call instance.translators.load first'));
  }
  return context != null ? (Localization.of(context) ?? (throw const LocalizationNotFoundException())) : Localization.instance;
}

/// {@template tr}
/// Main function for translate your language keys
///
/// The `context` parameter is deprecated and will be removed in 5.0. Ordinary
/// widgets under the root rebuild on presentation changes; retained strings are snapshots.
/// [key] Localization key
/// [BuildContext] The location in the tree where this widget builds
/// [args] List of localized strings. Replaces {} left to right
/// [namedArgs] Map of localized strings. Replaces the name keys {key_name} according to its name
/// [gender] Gender switcher. Changes the localized string based on gender string
///
/// Example:
///
/// ```json
/// {
///    "msg":"{} are written in the {} language",
///    "msg_named":"Easy localization is written in the {lang} language",
///    "msg_mixed":"{} are written in the {lang} language",
///    "gender":{
///       "male":"Hi man ;) {}",
///       "female":"Hello girl :) {}",
///       "other":"Hello {}"
///    }
/// }
/// ```
/// ```dart
/// Text('msg').tr(args: ['Easy localization', 'Dart']), // args
/// Text('msg_named').tr(namedArgs: {'lang': 'Dart'}),   // namedArgs
/// Text('msg_mixed').tr(args: ['Easy localization'], namedArgs: {'lang': 'Dart'}), // args and namedArgs
/// Text('gender').tr(gender: _gender ? "female" : "male"), // gender
/// ```
/// {@endtemplate}
String tr(
  String key, {
  @Deprecated('Use translations without context; scoped form is removed in 5.0') BuildContext? context,
  List<String>? args,
  Map<String, String>? namedArgs,
  String? gender,
  Locale? locale,
}) {
  return _translator(locale, context).tr(key, args: args, namedArgs: namedArgs, gender: gender);
}

bool trExists(
  String key, {
  @Deprecated('Use trExists without context; scoped form is removed in 5.0') BuildContext? context,
  bool includeFallback = false,
  Locale? locale,
}) {
  return _translator(locale, context).exists(key, includeFallback: includeFallback);
}

/// {@template plural}
/// function translate with pluralization
///
/// The `context` parameter is deprecated and will be removed in 5.0. Ordinary
/// widgets under the root rebuild on presentation changes; retained strings are snapshots.
/// [key] Localization key
/// [value] Number value for pluralization
/// [BuildContext] The location in the tree where this widget builds
/// [args] List of localized strings. Replaces {} left to right
/// [namedArgs] Map of localized strings. Replaces the name keys {key_name} according to its name
/// [name] Name of number value. Replaces {$name} to value
/// [format] Formats a numeric value using a [NumberFormat](https://pub.dev/documentation/intl/latest/intl/NumberFormat-class.html) class
///
/// Example:
///```json
/// {
///   "day": {
///     "zero":"{} дней",
///     "one": "{} день",
///     "two": "{} дня",
///     "few": "{} дня",
///     "many": "{} дней",
///     "other": "{} дней"
///   },
///   "money": {
///     "zero": "You not have money",
///     "one": "You have {} dollar",
///     "many": "You have {} dollars",
///     "other": "You have {} dollars"
///   },
///   "money_args": {
///     "zero": "{} has no money",
///     "one": "{} has {} dollar",
///     "many": "{} has {} dollars",
///     "other": "{} has {} dollars"
///   },
///   "money_named_args": {
///     "zero": "{name} has no money",
///     "one": "{name} has {money} dollar",
///     "many": "{name} has {money} dollars",
///     "other": "{name} has {money} dollars"
///   }
/// }
/// ```
///
///```dart
/// Text('money').plural(1000000, format: NumberFormat.compact(locale: EasyLocalization.instance.locale.toString())) // output: You have 1M dollars
/// print('day'.plural(21)); // output: 21 день
/// var money = plural('money', 10.23) // output: You have 10.23 dollars
/// var money = plural('money_args', 10.23, args: ['John', '10.23'])  // output: John has 10.23 dollars
/// var money = plural('money_named_args', 10.23, namedArgs: {'name': 'Jane'}, name: 'money')  // output: Jane has 10.23 dollars
/// ```
/// {@endtemplate}
String plural(
  String key,
  num value, {
  List<String>? args,
  @Deprecated('Use translations without context; scoped form is removed in 5.0') BuildContext? context,
  Map<String, String>? namedArgs,
  String? name,
  NumberFormat? format,
  Locale? locale,
}) {
  return _translator(locale, context).plural(key, value, args: args, namedArgs: namedArgs, name: name, format: format);
}
