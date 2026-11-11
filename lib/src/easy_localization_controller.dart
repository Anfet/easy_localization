import 'dart:async';

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:easy_localization_continued/src/diagnostics.dart';
import 'package:flutter/foundation.dart' show DiagnosticsProperty;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class EasyLocalizationController extends ChangeNotifier {
  @visibleForTesting
  static void Function()? onReloadPreparedForTesting;
  static Locale? _savedLocale;
  static Future<void>? _storageQueue;
  int _request = 0;
  bool _disposed = false;
  bool _loading = false;
  bool _systemBootstrap = false;
  Completer<void>? _bootstrapChanged;
  bool _systemMode = false;
  bool _lastCommitWasSystemEvent = false;
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
  List<Locale>? _observedDeviceLocales;

  late Locale _locale;
  Locale? _fallbackLocale;
  late final List<Locale> _supportedLocales;

  final Function(FlutterError e) onLoadError;
  final AssetLoader assetLoader;
  final String path;
  final bool useFallbackTranslations;
  final bool useBaseLanguageFallback;
  final bool saveLocale;
  final bool useOnlyLangCode;
  List<AssetLoader>? extraAssetLoaders;
  Translations? _translations, _baseTranslations, _fallbackTranslations;
  Locale? _baseLocale;
  Translations? get baseTranslations => _baseTranslations;
  Locale? get baseLocale => _baseLocale;
  Locale? get fallbackLocale => _fallbackLocale;
  Translations? get translations => _translations;
  Translations? get fallbackTranslations => _fallbackTranslations;

  EasyLocalizationController({
    required List<Locale> supportedLocales,
    required this.useFallbackTranslations,
    this.useBaseLanguageFallback = true,
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
  }) {
    _fallbackLocale = fallbackLocale;
    _supportedLocales = supportedLocales;
    if (forceLocale != null) {
      _locale = forceLocale;
      _systemMode = forceSystemMode;
    } else if ((!saveLocale || _savedLocale == null) && startLocale != null) {
      _locale = selectLocaleFrom(supportedLocales, startLocale, fallbackLocale: fallbackLocale);
      reportLocalizationDiagnostic(EasyLocalization.onVerbose, 'Start locale loaded ${_locale.toString()}');
    }
    // If saved locale then get
    else if (saveLocale && _savedLocale != null) {
      reportLocalizationDiagnostic(EasyLocalization.onVerbose, 'Saved locale loaded ${_savedLocale.toString()}');
      _locale = selectLocaleFrom(supportedLocales, _savedLocale!, fallbackLocale: fallbackLocale);
    } else {
      _systemMode = true;
      // From Device Locale
      _locale = selectLocaleFrom(supportedLocales, deviceLocale, fallbackLocale: fallbackLocale);
    }
  }

  static Locale selectLocaleFrom(List<Locale> supportedLocales, Locale deviceLocale, {Locale? fallbackLocale}) {
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

  static Locale selectPreferredLocale(List<Locale> supported, List<Locale> preferred, Locale fallback) {
    for (var index = 0; index < preferred.length; index++) {
      final candidate = preferred[index];
      final sameLanguage = supported.where((locale) => locale.languageCode == candidate.languageCode);
      for (final locale in sameLanguage) {
        if (locale == candidate) return locale;
      }
      for (final later in preferred.skip(index + 1)) {
        if (later.languageCode != candidate.languageCode) continue;
        for (final locale in sameLanguage) {
          if (locale == later) return locale;
        }
      }
      if (candidate.scriptCode != null) {
        for (final locale in sameLanguage) {
          if (locale.scriptCode == candidate.scriptCode) return locale;
        }
      }
      if (candidate.countryCode != null) {
        for (final locale in sameLanguage) {
          if (locale.countryCode == candidate.countryCode) return locale;
        }
      }
      if (sameLanguage.isNotEmpty) return sameLanguage.first;
    }
    return fallback;
  }

  Locale get systemTarget => selectPreferredLocale(
    _supportedLocales,
    _observedDeviceLocales ?? WidgetsBinding.instance.platformDispatcher.locales,
    _fallbackLocale ?? _supportedLocales.first,
  );

  void observeDeviceLocales(List<Locale> locales) => _observedDeviceLocales = List.unmodifiable(locales);

  Future<void> loadCurrentSystemTranslations() async {
    _systemBootstrap = true;
    final initial = _loadLocale(_locale, initial: true);
    _activeTransition = initial;
    Future<void> current = initial;
    try {
      while (true) {
        final changed = Completer<void>();
        _bootstrapChanged = changed;
        try {
          await Future.any<void>([current, changed.future]);
        } catch (_) {
          if (identical(current, _activeTransition)) rethrow;
        }
        final active = _activeTransition;
        if (active == null || identical(current, active)) break;
        current = active;
      }
    } finally {
      _bootstrapChanged = null;
      _systemBootstrap = false;
      if (identical(_activeTransition, current)) _activeTransition = null;
    }
  }

  Future<void> loadTranslations() => _loadLocale(_locale, initial: true);

  Future<void> _loadLocale(
    Locale target, {
    bool initial = false,
    bool refresh = false,
    bool system = false,
    bool reset = false,
    bool systemEvent = false,
    Future<void> Function()? prepareCommit,
    void Function()? commitPrepared,
  }) async {
    final supersededInitial = initial && _loading && _activeTransition != null;
    final request = supersededInitial ? _request - 1 : ++_request;
    if (!supersededInitial) {
      _loading = true;
      _requestedLocale = target;
      _requestedSystem = system;
      _requestedReset = reset;
      _requestedRefresh = refresh;
    }
    return (() async {
      late _LocaleResources resources;
      try {
        resources = await _loadResources(target);
        if (prepareCommit != null) await prepareCommit();
        if (prepareCommit != null) onReloadPreparedForTesting?.call();
        if (_disposed || request != _request) return;
        commitPrepared?.call();
      } catch (error, stackTrace) {
        if (_disposed || request != _request) return;
        _loading = false;
        final failure = error is FlutterError
            ? error
            : FlutterError.fromParts([ErrorSummary(error.toString()), DiagnosticsProperty<Object>('cause', error)]);
        try {
          reportLocalizationDiagnostic(EasyLocalization.onError, error.toString(), stackTrace: stackTrace);
        } finally {
          if (!_disposed && request == _request) onLoadError(failure);
        }
        if (_disposed || request != _request) return;
        return Future.error(error, stackTrace);
      }
      if (_disposed || request != _request) return;
      _loading = false;
      _locale = resources.locale;
      _lastCommitWasSystemEvent = systemEvent;
      _translations = resources.translations;
      _baseTranslations = resources.baseTranslations;
      _baseLocale = resources.baseLocale;
      _fallbackTranslations = resources.fallbackTranslations;
      _acceptedRequest = request;
      if (!initial && !refresh) _systemMode = system || reset;
      final saving = initial || refresh || system
          ? Future<void>.value()
          : reset
          ? deleteSaveLocale()
          : _saveLocale(target);
      notifyListeners();
      if (!initial && !refresh) reportLocalizationDiagnostic(EasyLocalization.onVerbose, 'Locale $target changed');
      await saving;
    })();
  }

  /// Loads an independent snapshot without changing controller state.
  Future<Localization> loadSnapshot(Locale locale, {required bool useFallbackForEmpty}) async {
    final resources = await _loadResources(locale);
    return Localization.snapshot(
      locale,
      translations: resources.translations,
      fallbackTranslations: resources.fallbackTranslations,
      useFallbackTranslationsForEmptyResources: useFallbackForEmpty,
      baseTranslations: resources.baseTranslations,
      baseLocale: resources.baseLocale,
      fallbackLocale: _fallbackLocale,
    );
  }

  Future<_LocaleResources> _loadResources(Locale target) async {
    final loads = <Locale, Future<Map<String, dynamic>?>>{};
    Locale normalized(Locale locale) =>
        useOnlyLangCode ? Locale.fromSubtags(languageCode: locale.languageCode, scriptCode: locale.scriptCode) : locale;
    Future<Map<String, dynamic>?> load(Locale locale) => loads.putIfAbsent(
      normalized(locale),
      () => _combineAssetLoaders(
        path: path,
        locale: locale,
        assetLoader: assetLoader,
        useOnlyLangCode: useOnlyLangCode,
        extraAssetLoaders: extraAssetLoaders,
      ),
    );
    Future<Map<String, dynamic>> requiredResource(Locale locale, String layer) async {
      final result = await load(locale);
      if (result == null) throw StateError('Missing $layer translations for $locale');
      return Map<String, dynamic>.from(result);
    }

    final data = await requiredResource(target, 'primary');
    Translations? fallback;
    Translations? baseTranslations;
    Locale? loadedBaseLocale;
    final configured = _fallbackLocale;
    if (useFallbackTranslations && configured != null) {
      Map<String, dynamic>? base;
      if (useBaseLanguageFallback && target.countryCode != null && target.countryCode!.isNotEmpty) {
        final baseLocale = Locale.fromSubtags(languageCode: target.languageCode, scriptCode: target.scriptCode);
        loadedBaseLocale = baseLocale;
        base = await load(baseLocale);
      }
      final fallbackData = await requiredResource(configured, 'fallback');
      if (base != null) baseTranslations = Translations(base);
      fallback = Translations(fallbackData);
    }
    return _LocaleResources(target, Translations(data), baseTranslations, loadedBaseLocale, fallback);
  }

  @override
  void dispose() {
    _disposed = true;
    _request++;
    super.dispose();
  }

  Future<Map<String, dynamic>> loadTranslationData(Locale locale) async =>
      (await _combineAssetLoaders(
        path: path,
        locale: locale,
        assetLoader: assetLoader,
        useOnlyLangCode: useOnlyLangCode,
        extraAssetLoaders: extraAssetLoaders,
      )) ??
      {};

  Future<Map<String, dynamic>?> _combineAssetLoaders({
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

    List<AssetLoader> loaders = [assetLoader, ...?extraAssetLoaders];

    for (final loader in loaders) {
      loaderFutures.add(Future.sync(() => loader.load(path, desiredLocale)));
    }

    var present = false;
    await Future.wait(loaderFutures, eagerError: true).then((List<Map<String, dynamic>?> value) {
      for (final Map<String, dynamic>? map in value) {
        if (map != null) {
          present = true;
          result.addAllRecursive(map);
        }
      }
    });

    return present ? result : null;
  }

  Locale get locale => _locale;
  int get requestRevision => _request;
  bool get lastCommitWasSystemEvent => _lastCommitWasSystemEvent;
  Locale get requestedLocale => _loading ? _requestedLocale ?? _locale : _locale;
  bool get isSystemMode => _systemMode;

  /// Persists a bootstrap override even when a previous owner cached this locale.
  Future<void> saveCurrentLocale() async {
    try {
      await _saveLocale(_locale);
    } catch (_) {
      _savedLocale = null;
      rethrow;
    }
  }

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
      _savedLocale = null;
      reportLocalizationDiagnostic(EasyLocalization.onWarning, 'Saved locale $value ignored: invalid format');
      return;
    }
    final restored = value.toLocale();
    if (!supportedLocales.contains(restored)) {
      _savedLocale = null;
      reportLocalizationDiagnostic(EasyLocalization.onWarning, 'Saved locale $value ignored: not supported');
      return;
    }
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
      await _saveLocale(locale, skipIfSaved: true);
      return;
    }
    final userTransition = Object();
    _userTransition = userTransition;
    final transition = _loadLocale(locale);
    _activeTransition = transition;
    await _finishUserTransition(userTransition, transition);
  }

  /// Reloads the displayed locale after the asset loader's data has changed.
  /// The future completes after acceptance, or with an error if the current
  /// load fails. An active language load finishes first; a later request can
  /// supersede the refresh. Widgets update next frame.
  Future<void> reloadTranslations({bool supersede = false, Future<void> Function()? prepareCommit, void Function()? commitPrepared}) async {
    if (_disposed) return;
    final active = _activeTransition;
    if (supersede && _loading && active != null) {
      final userTransition = _userTransition == null ? null : Object();
      if (userTransition != null) _userTransition = userTransition;
      final transition = _loadLocale(
        requestedLocale,
        refresh: _requestedRefresh,
        system: _requestedSystem,
        reset: _requestedReset,
        prepareCommit: prepareCommit,
        commitPrepared: commitPrepared,
      );
      _refreshRequest = _request;
      _activeTransition = transition;
      if (userTransition != null) return _finishUserTransition(userTransition, transition);
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
    final transition = _loadLocale(_locale, refresh: true, prepareCommit: prepareCommit, commitPrepared: commitPrepared);
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
    settled = result.then<void>((_) {}, onError: (Object _, StackTrace _) {}).whenComplete(() {
      if (identical(_storageQueue, settled)) _storageQueue = null;
    });
    _storageQueue = settled;
    return result;
  }

  Future<void> _saveLocale(Locale locale, {bool skipIfSaved = false}) async {
    if (!saveLocale) return;
    await _enqueueStorage(() async {
      if (skipIfSaved && _savedLocale == locale) return;
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
        reportLocalizationDiagnostic(EasyLocalization.onError, error.toString(), stackTrace: stackTrace);
        return Future.error(error, stackTrace);
      }
      _savedLocale = locale;
      reportLocalizationDiagnostic(EasyLocalization.onVerbose, 'Locale $locale saved');
    });
  }

  Future<void> deleteSaveLocale() => !saveLocale
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
            reportLocalizationDiagnostic(EasyLocalization.onError, error.toString(), stackTrace: stackTrace);
            return Future.error(error, stackTrace);
          }
          _savedLocale = null;
          reportLocalizationDiagnostic(EasyLocalization.onVerbose, 'Saved locale deleted');
        });

  Locale get deviceLocale {
    final locales = _observedDeviceLocales ?? WidgetsBinding.instance.platformDispatcher.locales;
    return locales.isEmpty ? const Locale('und') : locales.first;
  }

  Locale? get savedLocale => saveLocale ? _savedLocale : null;

  /// Returns to following the system locale and removes the saved selection.
  /// A failed resource load keeps the current language and selection mode.
  Future<void> resetLocale() async {
    if (_disposed) return;
    final target = systemTarget;
    if (_systemMode && target == _locale && _translations != null) {
      _request++;
      _loading = false;
      _userTransition = null;
      _activeTransition = null;
      await deleteSaveLocale();
      return;
    }
    final userTransition = Object();
    _userTransition = userTransition;
    final transition = _loadLocale(target, reset: true);
    _activeTransition = transition;
    await _finishUserTransition(userTransition, transition);
  }

  Future<void> _finishUserTransition(Object userTransition, Future<void> transition) async {
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
    }
    if (failure != null) return Future.error(failure, failureStack ?? StackTrace.current);
  }

  Future<void> replaySystemLocale() => updateDeviceLocales(_observedDeviceLocales ?? WidgetsBinding.instance.platformDispatcher.locales);

  Future<void> updateDeviceLocales(List<Locale> locales) async {
    if (_disposed) return;
    observeDeviceLocales(locales);
    if (!_systemMode || _userTransition != null) return;
    final target = systemTarget;
    if (target == _locale && _translations != null) {
      if (_loading && _requestedSystem) {
        _request++;
        _loading = false;
      }
      return;
    }
    if (_loading && (_requestedSystem || _systemBootstrap) && _requestedLocale == target) return _activeTransition;
    final transition = _loadLocale(target, system: true, systemEvent: true);
    _activeTransition = transition;
    final changed = _bootstrapChanged;
    if (changed != null && !changed.isCompleted) changed.complete();
    try {
      await transition;
    } finally {
      if (!_systemBootstrap && identical(_activeTransition, transition)) _activeTransition = null;
    }
  }

  /// Updates the observed system locale and applies it while following the system.
  Future<void> updateDeviceLocale(Locale locale) async {
    if (_disposed) return;
    observeDeviceLocales([locale]);
    if (!_systemMode || _userTransition != null) return;
    final target = systemTarget;
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
  final Translations? baseTranslations, fallbackTranslations;
  final Locale? baseLocale;

  _LocaleResources(this.locale, this.translations, this.baseTranslations, this.baseLocale, this.fallbackTranslations);
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
