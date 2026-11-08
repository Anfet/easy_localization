import 'package:easy_localization/src/exceptions.dart';
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';

import 'easy_localization_app.dart';
import 'public.dart' as ez;

Text _withData(Text source, String data) => Text(
  data,
  key: source.key,
  style: source.style,
  strutStyle: source.strutStyle,
  textAlign: source.textAlign,
  textDirection: source.textDirection,
  locale: source.locale,
  softWrap: source.softWrap,
  overflow: source.overflow,
  // Preserve the legacy property when no TextScaler was supplied.
  // ignore: deprecated_member_use
  textScaleFactor: source.textScaleFactor,
  textScaler: source.textScaler,
  maxLines: source.maxLines,
  semanticsLabel: source.semanticsLabel,
  semanticsIdentifier: source.semanticsIdentifier,
  textWidthBasis: source.textWidthBasis,
  textHeightBehavior: source.textHeightBehavior,
  selectionColor: source.selectionColor,
);

/// Text widget extension method for access to [tr()] and [plural()]
/// Pass context to use and subscribe to its localization scope. Ordinary widgets
/// under the root rebuild on presentation changes; retained strings are snapshots.
/// Example :
/// ```dart
/// Text('title').tr(context: context)
/// Text('day').plural(21, context: context)
/// ```
extension TextTranslateExtension on Text {
  /// {@macro tr}
  Text tr({
    List<String>? args,
    @Deprecated('Use translations without context; scoped form is removed in 5.0') BuildContext? context,
    Map<String, String>? namedArgs,
    String? gender,
    Locale? locale,
  }) => _withData(
    this,
    ez.tr(
      data ?? (throw ArgumentError('Text.rich cannot be translated; translate each TextSpan string instead')),
      context: context,
      args: args,
      namedArgs: namedArgs,
      gender: gender,
      locale: locale,
    ),
  );

  /// {@macro plural}
  Text plural(
    num value, {
    @Deprecated('Use translations without context; scoped form is removed in 5.0') BuildContext? context,
    List<String>? args,
    Map<String, String>? namedArgs,
    String? name,
    NumberFormat? format,
    Locale? locale,
  }) => _withData(
    this,
    ez.plural(
      data ?? (throw ArgumentError('Text.rich cannot be translated; translate each TextSpan string instead')),
      value,
      context: context,
      args: args,
      namedArgs: namedArgs,
      name: name,
      format: format,
      locale: locale,
    ),
  );
}

/// Strings extension method for access to [tr()] and [plural()]
/// Pass context to use and subscribe to its localization scope. Ordinary widgets
/// under the root rebuild on presentation changes; retained strings are snapshots.
/// Example :
/// ```dart
/// 'title'.tr(context: context)
/// 'day'.plural(21, context: context)
/// ```
extension StringTranslateExtension on String {
  /// {@macro tr}
  String tr({
    List<String>? args,
    Map<String, String>? namedArgs,
    String? gender,
    @Deprecated('Use translations without context; scoped form is removed in 5.0') BuildContext? context,
    Locale? locale,
  }) => ez.tr(this, context: context, args: args, namedArgs: namedArgs, gender: gender, locale: locale);

  bool trExists({
    @Deprecated('Use translations without context; scoped form is removed in 5.0') BuildContext? context,
    bool includeFallback = false,
    Locale? locale,
  }) => ez.trExists(this, context: context, includeFallback: includeFallback, locale: locale);

  /// {@macro plural}
  String plural(
    num value, {
    List<String>? args,
    @Deprecated('Use translations without context; scoped form is removed in 5.0') BuildContext? context,
    Map<String, String>? namedArgs,
    String? name,
    NumberFormat? format,
    Locale? locale,
  }) => ez.plural(this, value, context: context, args: args, namedArgs: namedArgs, name: name, format: format, locale: locale);
}

/// BuildContext extension method for access to [locale], [supportedLocales], [fallbackLocale], [delegates] and [deleteSaveLocale()]
///
/// Example :
///
/// ```dart
/// context.locale = Locale('en', 'US');
/// print(context.locale.toString());
///
/// context.deleteSaveLocale();
///
/// print(context.supportedLocales); // output: [en_US, ar_DZ, de_DE, ru_RU]
/// print(context.fallbackLocale);   // output: en_US
/// ```
extension BuildContextEasyLocalizationExtension on BuildContext {
  /// Get current locale
  Locale get locale => (EasyLocalization.of(this) ?? (throw const LocalizationNotFoundException())).locale;

  /// Change app locale
  /// Waits for loading and the assigned save. Superseded requests do not apply.
  /// Load and save failures complete with an error; a save failure keeps the
  /// applied locale. Widget translations update on the next frame.
  Future<void> setLocale(Locale val) async => (EasyLocalization.of(this) ?? (throw const LocalizationNotFoundException())).setLocale(val);

  /// Reloads the current locale after the asset loader's data has changed.
  /// Waits for acceptance; the current load failure completes with an error.
  /// A later locale change or reload supersedes it. Widgets update next frame.
  Future<void> reloadTranslations() => (EasyLocalization.of(this) ?? (throw const LocalizationNotFoundException())).reloadTranslations();

  /// Old Change app locale
  @Deprecated(
    'This is the func used in the old version of EasyLocalization. The modern func is `setLocale(val)` . '
    'This feature was deprecated after v3.0.0',
  )
  set locale(Locale val) => (EasyLocalization.of(this) ?? (throw const LocalizationNotFoundException())).setLocale(val);

  /// Get List of supported locales.
  List<Locale> get supportedLocales => (EasyLocalization.of(this) ?? (throw const LocalizationNotFoundException())).supportedLocales;

  /// Get fallback locale
  Locale? get fallbackLocale => (EasyLocalization.of(this) ?? (throw const LocalizationNotFoundException())).fallbackLocale;

  /// {@macro flutter.widgets.widgetsApp.localizationsDelegates}
  /// return
  /// ```dart
  ///   delegates = [
  ///     delegate
  ///     GlobalMaterialLocalizations.delegate,
  ///     GlobalWidgetsLocalizations.delegate,
  ///     GlobalCupertinoLocalizations.delegate
  ///   ],
  /// ```
  List<LocalizationsDelegate> get localizationDelegates => (EasyLocalization.of(this) ?? (throw const LocalizationNotFoundException())).delegates;

  /// Clears a saved locale from device storage
  Future<void> deleteSaveLocale() => (EasyLocalization.of(this) ?? (throw const LocalizationNotFoundException())).deleteSaveLocale();

  /// Getting device locale from platform
  Locale get deviceLocale => (EasyLocalization.of(this) ?? (throw const LocalizationNotFoundException())).deviceLocale;
  Locale? get savedLocale => (EasyLocalization.of(this) ?? (throw const LocalizationNotFoundException())).savedLocale;

  /// Follow the platform locale and remove the saved selection.
  Future<void> resetLocale() => (EasyLocalization.of(this) ?? (throw const LocalizationNotFoundException())).resetLocale();

  /// An extension method for translating your language keys.
  /// Subscribes the widget on current [Localization] that provided from context.
  /// Throws exception if [Localization] was not found.
  ///
  /// [key] Localization key
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
  /// Text(context.tr('msg', args: ['Easy localization', 'Dart']), // args
  /// Text(context.tr('msg_named', namedArgs: {'lang': 'Dart'}),   // namedArgs
  /// Text(context.tr('msg_mixed', args: ['Easy localization'], namedArgs: {'lang': 'Dart'}), // args and namedArgs
  /// Text(context.tr('gender', gender: _gender ? "female" : "male"), // gender
  /// ```
  @Deprecated('Use tr(key); scoped form is removed in 5.0')
  String tr(String key, {List<String>? args, Map<String, String>? namedArgs, String? gender}) {
    final localization = Localization.of(this);

    if (localization == null) {
      throw const LocalizationNotFoundException();
    }

    return localization.tr(key, args: args, namedArgs: namedArgs, gender: gender);
  }

  @Deprecated('Use trExists(key); scoped form is removed in 5.0')
  bool trExists(String key, {bool includeFallback = false}) {
    final localization = Localization.of(this);

    if (localization == null) {
      throw const LocalizationNotFoundException();
    }

    return localization.exists(key, includeFallback: includeFallback);
  }

  @Deprecated('Use plural(key, number); scoped form is removed in 5.0')
  String plural(String key, num number, {List<String>? args, Map<String, String>? namedArgs, String? name, NumberFormat? format}) {
    final localization = Localization.of(this);

    if (localization == null) {
      throw const LocalizationNotFoundException();
    }

    return localization.plural(key, number, args: args, namedArgs: namedArgs, name: name, format: format);
  }
}
