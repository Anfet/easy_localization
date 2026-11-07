import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show DiagnosticsProperty;
import 'package:flutter/material.dart';
import 'package:intl/intl_standalone.dart'
    if (dart.library.html) 'package:intl/intl_browser.dart'
    if (dart.library.js_interop) 'package:intl/intl_browser.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translations.dart';

class EasyLocalizationController extends ChangeNotifier {
  static Locale? _savedLocale;
  static Future<void>? _storageQueue;
  int _request = 0;
  bool _disposed = false;
  bool _loading = false;
  bool _systemMode = false;
  Locale? _requestedLocale;
  bool _requestedSystem = false;
  bool _requestedReset = false;
  bool _requestedRefresh = false;
  Object? _userTransition;
  Future<void>? _activeTransition;
  Future<void>? _deferredReload;
  int? _deferredReloadRequest;
  int? _acceptedRequest;
  int? _refreshRequest;
  static Locale? _deviceLocale;
  Locale? _observedDeviceLocale;

  late Locale _locale;
  Locale? _fallbackLocale;
  late final List<Locale> _supportedLocales;

  final Function(FlutterError e) onLoadError;
  final AssetLoader assetLoader;
  final String path;
  final bool useFallbackTranslations;
  final bool saveLocale;
  final bool useOnlyLangCode;
  final bool strictErrors;
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
    bool forceSystemMode = false,
    this.strictErrors = false,
  }) {
    _fallbackLocale = fallbackLocale;
    _supportedLocales = supportedLocales;
    if (forceLocale != null) {
      _locale = forceLocale;
      _systemMode = forceSystemMode;
    } else if ((!saveLocale || _savedLocale == null) && startLocale != null) {
      _locale = selectLocaleFrom(supportedLocales, startLocale, fallbackLocale: fallbackLocale);
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
      _systemMode = true;
      // From Device Locale
      _locale = selectLocaleFrom(
        supportedLocales,
        deviceLocale,
        fallbackLocale: fallbackLocale,
      );
    }
  }

  static Locale selectLocaleFrom(
    List<Locale> supportedLocales,
    Locale deviceLocale, {
    Locale? fallbackLocale,
  }) {
    for (final locale in supportedLocales) {
      if (locale == deviceLocale) return locale;
    }
    for (final locale in supportedLocales) {
      if (locale.supports(deviceLocale)) return locale;
    }
    for (final locale in supportedLocales) {
      if (locale.languageCode == deviceLocale.languageCode) return locale;
    }
    if (fallbackLocale != null && supportedLocales.contains(fallbackLocale)) return fallbackLocale;
    return supportedLocales.first;
  }

  Future<void> loadTranslations() => _loadLocale(_locale, initial: true);

  Future<void> _loadLocale(Locale target, {bool initial = false, bool refresh = false, bool system = false, bool reset = false}) async {
    final supersededInitial = initial && _loading && _activeTransition != null;
    final request = supersededInitial ? _request - 1 : ++_request;
    if (!supersededInitial) {
      _loading = true;
      _requestedLocale = target;
      _requestedSystem = system;
      _requestedReset = reset;
      _requestedRefresh = refresh;
    }
    final callbackErrors = <AsyncError>[];
    final callbackZone = Zone.current;
    return runZoned(() async {
      late _LocaleResources resources;
      try {
        resources = await _loadResources(target);
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
        if (strictErrors) return Future.error(error, stackTrace);
        if (!initial) return Future.error(failure, stackTrace);
        return;
      }
      if (_disposed || request != _request) return;
      _loading = false;
      _locale = resources.locale;
      _translations = resources.translations;
      _fallbackTranslations = resources.fallbackTranslations;
      _acceptedRequest = request;
      if (!initial && !refresh) _systemMode = system || reset;
      final saving = initial || refresh || system
          ? Future<void>.value()
          : reset
              ? deleteSaveLocale()
              : _saveLocale(target);
      notifyListeners();
      if (!initial && !refresh) EasyLocalization.onVerbose?.call('Locale $target changed');
      await saving;
    }, zoneValues: {#easyLocalizationCallbackErrors: callbackErrors, #easyLocalizationCallbackZone: callbackZone});
  }

  /// Loads an independent snapshot without changing controller state.
  Future<Localization> loadSnapshot(Locale locale, {required bool useFallbackForEmpty, required bool ignorePluralRules}) async {
    final resources = await _loadResources(locale);
    return Localization.snapshot(locale,
        translations: resources.translations,
        fallbackTranslations: resources.fallbackTranslations,
        useFallbackTranslationsForEmptyResources: useFallbackForEmpty,
        ignorePluralRules: ignorePluralRules);
  }

  Future<_LocaleResources> _loadResources(Locale target) async {
    final data = Map<String, dynamic>.from(await loadTranslationData(target));
    Translations? fallback;
    if (useFallbackTranslations && _fallbackLocale != null) {
      Map<String, dynamic>? baseLangData;
      if (target.countryCode != null && target.countryCode!.isNotEmpty) {
        baseLangData = await loadBaseLangTranslationData(Locale(target.languageCode));
      }
      final fallbackData = Map<String, dynamic>.from(await loadTranslationData(_fallbackLocale!));
      if (baseLangData != null) fallbackData.addAllRecursive(baseLangData);
      fallback = Translations(fallbackData);
    }
    return _LocaleResources(target, Translations(data), fallback);
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
  Locale get requestedLocale => _loading ? _requestedLocale ?? _locale : _locale;
  bool get isSystemMode => _systemMode;

  /// Persists a bootstrap override even when a previous owner cached this locale.
  Future<void> saveCurrentLocale() => _saveLocale(_locale);

  /// Restores the explicit selection for the standalone bootstrap only.
  /// Invalid data is reported without deleting the original preference.
  static Future<Locale?> readSavedLocale(List<Locale> supportedLocales) => _enqueueStorage(() async {
        final preferences = await SharedPreferences.getInstance();
        await preferences.reload();
        final value = preferences.get('locale');
        if (value == null) {
          _savedLocale = null;
          return;
        }
        if (value is! String || !RegExp(r'^[a-zA-Z]{2,8}(?:_[a-zA-Z]{4})?(?:_(?:[a-zA-Z]{2}|[0-9]{3}))?$').hasMatch(value)) {
          throw FormatException('Invalid saved locale', value);
        }
        final restored = value.toLocale();
        if (!supportedLocales.contains(restored)) throw StateError('Saved locale $value is not supported');
        _savedLocale = restored;
      }).then((_) => _savedLocale);

  /// Applies a locale after its resources load and waits for its storage operation.
  /// A superseded request completes after its own loading without applying it.
  /// Loading or storage errors complete this future with an error; storage errors
  /// leave the applied locale in place. Choosing it again retries a failed save.
  /// Widgets update on a subsequent frame.
  Future<void> setLocale(Locale locale) async {
    if (_disposed) return;
    if (locale == _locale && _translations != null && !_systemMode) {
      if (_loading) {
        _request++;
        _loading = false;
      }
      if (saveLocale && _savedLocale != locale) await _saveLocale(locale);
      return;
    }
    final userTransition = Object();
    _userTransition = userTransition;
    final transition = _loadLocale(locale);
    _activeTransition = transition;
    await _finishUserTransition(userTransition, transition, _request);
  }

  /// Reloads the displayed locale after the asset loader's data has changed.
  /// The future completes after acceptance, or with an error if the current
  /// load fails. An active language load finishes first; a later request can
  /// supersede the refresh. Widgets update next frame.
  Future<void> reloadTranslations({bool supersede = false}) async {
    if (_disposed) return;
    final active = _activeTransition;
    if (supersede && _loading && active != null) {
      final transition = _loadLocale(requestedLocale, refresh: _requestedRefresh, system: _requestedSystem, reset: _requestedReset);
      _refreshRequest = _request;
      _activeTransition = transition;
      try {
        await transition;
      } finally {
        if (identical(_activeTransition, transition)) _activeTransition = null;
      }
      return;
    }
    if (_loading && active != null && _refreshRequest != _request) {
      final request = _request;
      final pendingReload = _deferredReload;
      if (_deferredReloadRequest == request && pendingReload != null) return pendingReload;
      final deferred = _reloadAfterTransition(active, request);
      _deferredReloadRequest = request;
      _deferredReload = deferred;
      try {
        await deferred;
      } finally {
        if (identical(_deferredReload, deferred)) {
          _deferredReload = null;
          _deferredReloadRequest = null;
        }
      }
      return;
    }
    final transition = _loadLocale(_locale, refresh: true);
    _refreshRequest = _request;
    _activeTransition = transition;
    try {
      await transition;
    } finally {
      if (identical(_activeTransition, transition)) _activeTransition = null;
    }
  }

  Future<void> _reloadAfterTransition(Future<void> transition, int request) async {
    try {
      await transition;
    } catch (error, stackTrace) {
      if (_disposed || request != _request) return;
      if (_acceptedRequest != request) return Future.error(error, stackTrace);
    }
    if (_disposed || request != _request || _acceptedRequest != request) return;
    await reloadTranslations();
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

  Future<void> deleteSaveLocale() => !saveLocale && strictErrors
      ? Future<void>.value()
      : _enqueueStorage(() async {
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

  Locale get deviceLocale => strictErrors
      ? _observedDeviceLocale ?? WidgetsBinding.instance.platformDispatcher.locale
      : _deviceLocale ?? WidgetsBinding.instance.platformDispatcher.locale;
  Locale? get savedLocale => _savedLocale;

  /// Returns to following the system locale and removes the saved selection.
  /// A failed resource load keeps the current language and selection mode.
  Future<void> resetLocale() async {
    if (_disposed) return;
    final target = selectLocaleFrom(_supportedLocales, deviceLocale, fallbackLocale: _fallbackLocale);
    if (strictErrors && _systemMode && target == _locale && _translations != null) {
      _request++;
      _loading = false;
      await deleteSaveLocale();
      return;
    }
    final userTransition = Object();
    _userTransition = userTransition;
    final transition = _loadLocale(target, reset: true);
    _activeTransition = transition;
    await _finishUserTransition(userTransition, transition, _request);
  }

  Future<void> _finishUserTransition(Object userTransition, Future<void> transition, int request) async {
    Object? failure;
    StackTrace? failureStack;
    try {
      await transition;
    } catch (error, stackTrace) {
      failure = error;
      failureStack = stackTrace;
    }
    if (identical(_activeTransition, transition)) _activeTransition = null;
    if (identical(_userTransition, userTransition)) {
      _userTransition = null;
      if (!_disposed &&
          request == _request &&
          _systemMode &&
          selectLocaleFrom(_supportedLocales, deviceLocale, fallbackLocale: _fallbackLocale) != _locale) {
        try {
          await updateDeviceLocale(deviceLocale);
        } catch (error, stackTrace) {
          if (failure == null) {
            failure = error;
            failureStack = stackTrace;
          } else if (error is! FlutterError) {
            FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stackTrace));
          }
        }
      }
    }
    if (failure != null) return Future.error(failure, failureStack ?? StackTrace.current);
  }

  /// Updates the observed system locale and applies it while following the system.
  Future<void> updateDeviceLocale(Locale locale) async {
    if (_disposed) return;
    if (strictErrors) {
      _observedDeviceLocale = locale;
    } else {
      _deviceLocale = locale;
    }
    if (!_systemMode || _userTransition != null) return;
    final target = selectLocaleFrom(_supportedLocales, locale, fallbackLocale: _fallbackLocale);
    if (target == _locale && _translations != null && !_loading) return;
    final transition = _loadLocale(target, system: true);
    _activeTransition = transition;
    try {
      await transition;
    } finally {
      if (identical(_activeTransition, transition)) _activeTransition = null;
    }
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
