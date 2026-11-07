import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show DiagnosticsProperty;
import 'package:flutter/material.dart';
import 'package:intl/intl_standalone.dart' if (dart.library.html) 'package:intl/intl_browser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translations.dart';

class EasyLocalizationController extends ChangeNotifier {
  static Locale? _savedLocale;
  static Future<void>? _storageQueue;
  int _request = 0;
  bool _disposed = false;
  bool _loading = false;
  Future<void>? _activeTransition;
  static late Locale _deviceLocale;

  late Locale _locale;
  Locale? _fallbackLocale;
  List<Locale>? _supportedLocales;

  final Function(FlutterError e) onLoadError;
  final AssetLoader assetLoader;
  final String path;
  final bool useFallbackTranslations;
  final bool saveLocale;
  final bool useOnlyLangCode;
  List<AssetLoader>? extraAssetLoaders;
  Translations? _translations, _fallbackTranslations;
  Translations? get translations => _translations;
  Translations? get fallbackTranslations => _fallbackTranslations;

  EasyLocalizationController({
    required List<Locale> supportedLocales,
    required this.useFallbackTranslations,
    required this.saveLocale,
    required this.assetLoader,
    required this.path,
    required this.useOnlyLangCode,
    required this.onLoadError,
    this.extraAssetLoaders,
    Locale? startLocale,
    Locale? fallbackLocale,
    Locale? forceLocale, // used for testing
  }) {
    _fallbackLocale = fallbackLocale;
    _supportedLocales = supportedLocales;
    if (forceLocale != null) {
      _locale = forceLocale;
    } else if ((!saveLocale || _savedLocale == null) && startLocale != null) {
      _locale = _getFallbackLocale(supportedLocales, startLocale);
      EasyLocalization.onVerbose?.call('Start locale loaded ${_locale.toString()}');
    }
    // If saved locale then get
    else if (saveLocale && _savedLocale != null) {
      EasyLocalization.onVerbose?.call('Saved locale loaded ${_savedLocale.toString()}');
      _locale = selectLocaleFrom(
        supportedLocales,
        _savedLocale!,
        fallbackLocale: fallbackLocale,
      );
    } else {
      // From Device Locale
      _locale = selectLocaleFrom(
        supportedLocales,
        _deviceLocale,
        fallbackLocale: fallbackLocale,
      );
    }
  }

  @visibleForTesting
  static Locale selectLocaleFrom(
    List<Locale> supportedLocales,
    Locale deviceLocale, {
    Locale? fallbackLocale,
  }) {
    final selectedLocale = supportedLocales.firstWhere(
      (locale) => locale.supports(deviceLocale),
      orElse: () => _getFallbackLocale(
        supportedLocales,
        fallbackLocale,
        deviceLocale: deviceLocale,
      ),
    );
    return selectedLocale;
  }

  //Get fallback Locale
  static Locale _getFallbackLocale(List<Locale> supportedLocales, Locale? fallbackLocale, {final Locale? deviceLocale}) {
    if (deviceLocale != null) {
      // a locale that matches the language code of the device locale is
      // preferred over the fallback locale
      final deviceLanguage = deviceLocale.languageCode;
      for (Locale locale in supportedLocales) {
        if (locale.languageCode == deviceLanguage) {
          return locale;
        }
      }
    }
    //If fallbackLocale not set then return first from supportedLocales
    if (fallbackLocale != null) {
      return fallbackLocale;
    } else {
      return supportedLocales.first;
    }
  }

  Future<void> loadTranslations() => _loadLocale(_locale, initial: true);

  Future<void> _loadLocale(Locale target, {bool initial = false}) async {
    final supersededInitial = initial && _loading && _activeTransition != null;
    final request = supersededInitial ? _request - 1 : ++_request;
    if (!supersededInitial) _loading = true;
    final callbackErrors = <AsyncError>[];
    final callbackZone = Zone.current;
    return runZoned(() async {
      late _LocaleResources resources;
      try {
        final data = Map<String, dynamic>.from(await loadTranslationData(target));
        Translations? fallback;
        if (useFallbackTranslations && _fallbackLocale != null) {
          Map<String, dynamic>? baseLangData;
          if (target.countryCode != null && target.countryCode!.isNotEmpty) {
            baseLangData = await loadBaseLangTranslationData(Locale(target.languageCode));
          }
          final fallbackData = Map<String, dynamic>.from(await loadTranslationData(_fallbackLocale!));
          if (baseLangData != null) fallbackData.addAll(baseLangData);
          fallback = Translations(fallbackData);
        }
        resources = _LocaleResources(target, Translations(data), fallback);
      } catch (error, stackTrace) {
        if (callbackErrors.isNotEmpty) {
          final callbackError = callbackErrors.first;
          return Future.error(callbackError.error, callbackError.stackTrace);
        }
        if (_disposed || request != _request) return;
        _loading = false;
        final failure =
            error is FlutterError ? error : FlutterError.fromParts([ErrorSummary(error.toString()), DiagnosticsProperty<Object>('cause', error)]);
        try {
          callbackZone.run(() => EasyLocalization.onError?.call(error.toString(), stackTrace: stackTrace));
        } finally {
          if (!_disposed && request == _request) callbackZone.run(() => onLoadError(failure));
        }
        if (_disposed || request != _request) return;
        if (!initial) return Future.error(failure, stackTrace);
        return;
      }
      if (_disposed || request != _request) return;
      _loading = false;
      _locale = resources.locale;
      _translations = resources.translations;
      _fallbackTranslations = resources.fallbackTranslations;
      final saving = initial ? Future<void>.value() : _saveLocale(target);
      notifyListeners();
      if (!initial) EasyLocalization.onVerbose?.call('Locale $target changed');
      await saving;
    }, zoneValues: {#easyLocalizationCallbackErrors: callbackErrors, #easyLocalizationCallbackZone: callbackZone});
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }

  Future<Map<String, dynamic>?> loadBaseLangTranslationData(Locale locale) async {
    try {
      return await loadTranslationData(Locale(locale.languageCode));
    } on FlutterError catch (e) {
      final callbackErrors = Zone.current[#easyLocalizationCallbackErrors] as List<AsyncError>?;
      if (callbackErrors?.isNotEmpty ?? false) rethrow;
      // Disregard asset not found FlutterError when attempting to load base language fallback
      try {
        final callbackZone = Zone.current[#easyLocalizationCallbackZone] as Zone? ?? Zone.current;
        callbackZone.run(() => EasyLocalization.onWarning?.call(e.message));
      } catch (error, stackTrace) {
        (Zone.current[#easyLocalizationCallbackErrors] as List<AsyncError>?)?.add(AsyncError(error, stackTrace));
        rethrow;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>> loadTranslationData(Locale locale) async => _combineAssetLoaders(
        path: path,
        locale: locale,
        assetLoader: assetLoader,
        useOnlyLangCode: useOnlyLangCode,
        extraAssetLoaders: extraAssetLoaders,
      );

  Future<Map<String, dynamic>> _combineAssetLoaders({
    required String path,
    required Locale locale,
    required AssetLoader assetLoader,
    required bool useOnlyLangCode,
    List<AssetLoader>? extraAssetLoaders,
  }) async {
    final result = <String, dynamic>{};
    final loaderFutures = <Future<Map<String, dynamic>?>>[];

    // need scriptCode, it might be better to use ignoreCountryCode as the variable name of useOnlyLangCode
    final Locale desiredLocale = useOnlyLangCode ? Locale.fromSubtags(languageCode: locale.languageCode, scriptCode: locale.scriptCode) : locale;

    List<AssetLoader> loaders = [assetLoader, if (extraAssetLoaders != null) ...extraAssetLoaders];

    for (final loader in loaders) {
      loaderFutures.add(loader.load(path, desiredLocale));
    }

    await Future.wait(loaderFutures).then((List<Map<String, dynamic>?> value) {
      for (final Map<String, dynamic>? map in value) {
        if (map != null) {
          result.addAllRecursive(map);
        }
      }
    });

    return result;
  }

  Locale get locale => _locale;

  /// Applies a locale after its resources load and waits for its storage operation.
  /// A superseded request completes after its own loading without applying it.
  /// Loading or storage errors complete this future with an error; storage errors
  /// leave the applied locale in place. Widgets update on a subsequent frame.
  Future<void> setLocale(Locale locale) async {
    if (_disposed) return;
    if (locale == _locale && _translations != null) {
      if (_loading) {
        _request++;
        _loading = false;
      }
      return;
    }
    final transition = _loadLocale(locale);
    _activeTransition = transition;
    try {
      await transition;
    } finally {
      if (identical(_activeTransition, transition)) _activeTransition = null;
    }
  }

  static Future<void> _enqueueStorage(Future<void> Function() operation) {
    final previous = _storageQueue;
    final result = previous == null ? operation() : previous.then((_) => operation());
    late Future<void> settled;
    settled = result.then<void>((_) {}, onError: (Object _, StackTrace __) {}).whenComplete(() {
      if (identical(_storageQueue, settled)) _storageQueue = null;
    });
    _storageQueue = settled;
    return result;
  }

  Future<void> _saveLocale(Locale locale) async {
    if (!saveLocale) return;
    await _enqueueStorage(() async {
      SharedPreferences? preferences;
      try {
        preferences = await SharedPreferences.getInstance();
        if (!await preferences.setString('locale', locale.toString())) {
          throw StateError('Failed to save locale');
        }
      } catch (error, stackTrace) {
        try {
          await preferences?.reload();
        } catch (_) {
          // Preserve the original storage failure.
        }
        EasyLocalization.onError?.call(error.toString(), stackTrace: stackTrace);
        return Future.error(error, stackTrace);
      }
      _savedLocale = locale;
      EasyLocalization.onVerbose?.call('Locale $locale saved');
    });
  }

  static Future<void> initEasyLocation() => _enqueueStorage(() async {
        final preferences = await SharedPreferences.getInstance();
        await preferences.reload();
        final strLocale = preferences.getString('locale');
        final foundPlatformLocale = await findSystemLocale();
        _savedLocale = strLocale?.toLocale();
        _deviceLocale = foundPlatformLocale.toLocale();
        EasyLocalization.onVerbose?.call('Localization initialized');
      });

  Future<void> deleteSaveLocale() => _enqueueStorage(() async {
        SharedPreferences? preferences;
        try {
          preferences = await SharedPreferences.getInstance();
          if (!await preferences.remove('locale')) throw StateError('Failed to delete saved locale');
        } catch (error, stackTrace) {
          try {
            await preferences?.reload();
          } catch (_) {
            // Preserve the original storage failure.
          }
          EasyLocalization.onError?.call(error.toString(), stackTrace: stackTrace);
          return Future.error(error, stackTrace);
        }
        _savedLocale = null;
        EasyLocalization.onVerbose?.call('Saved locale deleted');
      });

  Locale get deviceLocale => _deviceLocale;
  Locale? get savedLocale => _savedLocale;

  Future<void> resetLocale() async {
    final locale = selectLocaleFrom(_supportedLocales!, deviceLocale, fallbackLocale: _fallbackLocale);

    EasyLocalization.onVerbose
        ?.call('Reset locale to $locale while the platform locale is $_deviceLocale and the fallback locale is $_fallbackLocale');
    await setLocale(locale);
  }
}

class _LocaleResources {
  final Locale locale;
  final Translations translations;
  final Translations? fallbackTranslations;

  _LocaleResources(this.locale, this.translations, this.fallbackTranslations);
}

@visibleForTesting
extension LocaleExtension on Locale {
  bool supports(Locale locale) {
    if (this == locale) {
      return true;
    }
    if (languageCode != locale.languageCode) {
      return false;
    }
    if (countryCode != null && countryCode!.isNotEmpty && countryCode != locale.countryCode) {
      return false;
    }
    if (scriptCode != null && scriptCode != locale.scriptCode) {
      return false;
    }

    return true;
  }
}
