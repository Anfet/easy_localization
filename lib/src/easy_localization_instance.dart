part of 'easy_localization_app.dart';

enum LocalizationApplyOutcome { applied, superseded, detached, failed, disposed }

enum LocalizationErrorStage { resources, persistence, flutterDelegates }

/// Immutable inputs for localization before runApp.
///
/// [fallbackLocale] and [startLocale] must belong exactly to [supportedLocales].
/// Startup chooses start, then saved (when [saveLocale]), then the system locale
/// or the required fallback. A selected source's failure never tries another.
/// Translation defaults follow language plural rules and disable base fallback.
@immutable
class EasyLocalizationConfig {
  final List<Locale> supportedLocales;
  final String path;
  final Locale fallbackLocale;
  final Locale? startLocale;
  final AssetLoader assetLoader;
  final List<AssetLoader> extraAssetLoaders;
  final List<LocalizationsDelegate<dynamic>> additionalDelegates;
  final bool useOnlyLangCode;
  final bool useFallbackTranslations;
  final bool useBaseLanguageFallback;
  final bool useFallbackTranslationsForEmptyResources;
  final bool saveLocale;

  EasyLocalizationConfig({
    required List<Locale> supportedLocales,
    required this.path,
    required this.fallbackLocale,
    this.startLocale,
    this.assetLoader = const RootBundleAssetLoader(
      fileLoader: RootBundleFileLoader(),
      linkedFileResolver: JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
    ),
    List<AssetLoader> extraAssetLoaders = const [],
    List<LocalizationsDelegate<dynamic>> additionalDelegates = const [],
    this.useOnlyLangCode = false,
    this.useFallbackTranslations = false,
    this.useBaseLanguageFallback = false,
    this.useFallbackTranslationsForEmptyResources = false,
    this.saveLocale = true,
  }) : supportedLocales = List.unmodifiable(supportedLocales),
       extraAssetLoaders = List.unmodifiable(extraAssetLoaders),
       additionalDelegates = List.unmodifiable(additionalDelegates);

  void _validate() {
    if (supportedLocales.isEmpty) throw ArgumentError.value(supportedLocales, 'supportedLocales', 'Must not be empty');
    if (path.isEmpty) throw ArgumentError.value(path, 'path', 'Must not be empty');
    if (!supportedLocales.contains(fallbackLocale)) throw ArgumentError.value(fallbackLocale, 'fallbackLocale', 'Must be supported');
    final start = startLocale;
    if (start != null && !supportedLocales.contains(start)) throw ArgumentError.value(start, 'startLocale', 'Must be supported');
  }

  bool _matches(EasyLocalization widget) {
    final extras = widget.extraAssetLoaders ?? const <AssetLoader>[];
    if (extras.length != extraAssetLoaders.length) return false;
    for (var index = 0; index < extras.length; index++) {
      if (!identical(extras[index], extraAssetLoaders[index])) return false;
    }
    return listEquals(supportedLocales, widget.supportedLocales) &&
        path == widget.path &&
        fallbackLocale == widget.fallbackLocale &&
        startLocale == widget.startLocale &&
        identical(assetLoader, widget.assetLoader) &&
        useOnlyLangCode == widget.useOnlyLangCode &&
        useFallbackTranslations == widget.useFallbackTranslations &&
        useBaseLanguageFallback == widget.useBaseLanguageFallback &&
        useFallbackTranslationsForEmptyResources == widget.useFallbackTranslationsForEmptyResources &&
        saveLocale == widget.saveLocale &&
        listEquals(additionalDelegates, widget.additionalDelegates);
  }
}

/// Observable operation state. Committed data remains usable after an error.
@immutable
class LocalizationState {
  final Locale locale;
  final Locale? appliedLocale;
  final bool isSystemMode;
  final bool isLoading;
  final Object? error;
  final LocalizationErrorStage? errorStage;

  const LocalizationState({
    required this.locale,
    this.appliedLocale,
    required this.isSystemMode,
    this.isLoading = false,
    this.error,
    this.errorStage,
  });
}

/// Owns resources and commands independently of any Flutter widget lifecycle.
///
/// Obtain with [EasyLocalization.initialize]. Await commands for resources and
/// storage; no frame or BuildContext is required. A borrowed
/// root can unmount without disposing this owner. Captured [dataTranslator]
/// snapshots remain usable after subsequent changes and disposal.
class EasyLocalizationInstance with WidgetsBindingObserver {
  EasyLocalizationConfig get config => _config;
  Locale get locale => _controller.locale;
  bool get isSystemMode => _controller.isSystemMode;
  Localization get dataTranslator => _data ?? (throw StateError('Call EasyLocalization.initialize before accessing translations'));
  ValueListenable<LocalizationState> get state => _state;

  /// Loads a fresh, independent translator without changing the current locale.
  /// A started load and its result remain usable after this owner is disposed.
  Future<Localization> translator(Locale locale) {
    _checkLive();
    final config = _config;
    if (!config.supportedLocales.contains(locale)) throw ArgumentError.value(locale, 'locale', 'Must be supported');
    return _controller.loadSnapshot(locale, useFallbackForEmpty: config.useFallbackTranslationsForEmptyResources);
  }

  /// Loads and saves a locale; unsupported locales throw immediately.
  Future<void> setLocale(Locale locale) {
    _checkLive();
    if (!_config.supportedLocales.contains(locale)) throw ArgumentError.value(locale, 'locale', 'Must be supported');
    return _change(locale, () => _controller.setLocale(locale), committed: locale == this.locale && _data != null && !isSystemMode);
  }

  /// Follows the system after loading successfully, then removes explicit storage.
  Future<void> resetLocale() {
    _checkLive();
    final target = _controller.systemTarget;
    return _change(target, _controller.resetLocale, committed: target == locale && isSystemMode && _data != null);
  }

  /// Reloads resources while retaining the explicit/system selection mode.
  Future<void> reloadTranslations() {
    _checkLive();
    return _change(_controller.requestedLocale, () => _controller.reloadTranslations(supersede: true));
  }

  /// Deletes the saved choice without changing mode. Disabled storage does no I/O.
  Future<void> deleteSaveLocale() {
    _checkLive();
    return _controller.deleteSaveLocale();
  }

  /// Waits for presentation of the currently committed snapshot.
  Future<LocalizationApplyOutcome> waitForPresentation() {
    if (_disposed) return Future.value(LocalizationApplyOutcome.disposed);
    if (!_attached) return Future.value(LocalizationApplyOutcome.detached);
    if (identical(_data, _presentedData)) return Future.value(LocalizationApplyOutcome.applied);
    final presentation = _presentation;
    if (presentation != null) return presentation;
    final pending = _LocalizationPending(_committedRevision, locale)..committed = true;
    pending.ready.complete();
    _pending.add(pending);
    return _presentation = pending.applied.future;
  }

  /// Idempotently closes commands and outstanding operations. Held snapshots live on.
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    if (_controller.strictErrors) WidgetsBinding.instance.removeObserver(this);
    _attachment = null;
    _controller.removeListener(_didCommit);
    _controller.dispose();
    for (final pending in _pending.toList()) {
      pending.finish(StateError('Localization is disposed'), LocalizationApplyOutcome.disposed);
    }
    _pending.clear();
    _state.dispose();
    if (identical(_instance, this)) {
      _instance = null;
      _initializing = null;
      _initializingConfig = null;
      Localization.publish(null);
    }
  }

  EasyLocalizationInstance._(this._config, this._controller)
    : _state = ValueNotifier(LocalizationState(locale: _controller.locale, isSystemMode: _controller.isSystemMode)) {
    _controller.addListener(_didCommit);
    if (_controller.strictErrors) WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    _applySystemLocales(locales ?? WidgetsBinding.instance.platformDispatcher.locales);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) didChangeLocales(null);
  }

  Future<void> _applySystemLocales(List<Locale> locales) => _startSystemTransition(() => _controller.updateDeviceLocales(locales));

  Future<void> _startSystemTransition(Future<void> Function() operation) {
    final request = _controller.requestRevision;
    final transition = operation();
    final pending = _active;
    if (request != _controller.requestRevision && pending != null && !pending.ready.isCompleted && !pending.committed) {
      pending.finish(const LocalizationOperationSupersededException(), LocalizationApplyOutcome.superseded);
      _pending.remove(pending);
      _active = null;
      _publish();
    }
    return _reportSystemTransition(transition);
  }

  Future<void> _reportSystemTransition(Future<void> transition) async {
    try {
      await transition;
    } on FlutterError {
      // The controller has already reported this load failure.
    } catch (error, stackTrace) {
      if (_data != null) FlutterError.reportError(FlutterErrorDetails(exception: error, stack: stackTrace));
    }
  }

  static Future<EasyLocalizationInstance> _initialize(EasyLocalizationConfig config) {
    final current = _instance;
    final pending = _initializing;
    if (pending != null) {
      if (!identical(_initializingConfig, config)) throw StateError('Another localization config is already initialized or initializing');
      return pending;
    }
    if (current != null) {
      if (identical(current.config, config) && current._data != null) {
        _initializingConfig = config;
        return _initializing = Future.value(current);
      }
      throw StateError('A localization owner is already active');
    }
    WidgetsFlutterBinding.ensureInitialized();
    config._validate();
    _initializingConfig = config;
    final result = _bootstrap(config);
    _initializing = result;
    return result;
  }

  static Future<EasyLocalizationInstance> _bootstrap(EasyLocalizationConfig config) async {
    EasyLocalizationInstance? owner;
    try {
      final start = config.startLocale;
      final saved = start == null && config.saveLocale ? await EasyLocalizationController.readSavedLocale(config.supportedLocales) : null;
      final explicit = start ?? saved;
      final target =
          explicit ??
          EasyLocalizationController.selectPreferredLocale(
            config.supportedLocales,
            WidgetsBinding.instance.platformDispatcher.locales,
            config.fallbackLocale,
          );
      final controller = EasyLocalizationController(
        supportedLocales: config.supportedLocales,
        fallbackLocale: config.fallbackLocale,
        forceLocale: target,
        forceSystemMode: explicit == null,
        strictErrors: true,
        useFallbackTranslations: config.useFallbackTranslations,
        useBaseLanguageFallback: config.useBaseLanguageFallback,
        saveLocale: config.saveLocale,
        assetLoader: config.assetLoader,
        extraAssetLoaders: config.extraAssetLoaders,
        path: config.path,
        useOnlyLangCode: config.useOnlyLangCode,
        onLoadError: (_) {},
      );
      controller.observeDeviceLocales(WidgetsBinding.instance.platformDispatcher.locales);
      final initialized = EasyLocalizationInstance._(config, controller);
      owner = initialized;
      if (explicit == null) {
        await controller.loadCurrentSystemTranslations();
      } else {
        await controller.loadTranslations();
      }
      if (start != null) await controller.saveCurrentLocale();
      _instance = initialized;
      Localization.publish(initialized.dataTranslator);
      return initialized;
    } catch (_) {
      owner?.dispose();
      _initializing = null;
      _initializingConfig = null;
      rethrow;
    }
  }

  void _checkLive() {
    if (_disposed) throw StateError('Localization is disposed; call EasyLocalization.initialize again');
  }

  Future<void> _change(Locale target, AsyncCallback operation, {bool committed = false}) {
    final previous = _active;
    if (previous != null && !previous.committed) {
      previous.finish(const LocalizationOperationSupersededException(), LocalizationApplyOutcome.superseded);
      _pending.remove(previous);
    }
    _error = null;
    _errorStage = null;
    final pending = _LocalizationPending(++_revision, target);
    pending.committed = committed;
    if (committed && !identical(_data, _presentedData)) _presentation = pending.applied.future;
    _active = pending;
    _pending.add(pending);
    _publish();
    _run(pending, operation);
    return pending.ready.future;
  }

  Future<void> _run(_LocalizationPending pending, AsyncCallback operation) async {
    try {
      await operation();
      if (_disposed || pending.ready.isCompleted) return;
      if (!identical(_active, pending) && !pending.committed) {
        pending.finish(const LocalizationOperationSupersededException(), LocalizationApplyOutcome.superseded);
        return;
      }
      // A same-locale command may only retry persistence, with no resource load.
      if (identical(_active, pending)) {
        _publish();
      }
      pending.ready.complete();
      if (identical(_active, pending) && _attached && _data == _presentedData && !pending.applied.isCompleted) {
        pending.applied.complete(LocalizationApplyOutcome.applied);
        _publish();
      }
      if (!_attached && !pending.applied.isCompleted) {
        _publish();
        pending.applied.complete(LocalizationApplyOutcome.detached);
      }
    } catch (error, stackTrace) {
      if (_disposed || pending.ready.isCompleted) return;
      if (identical(_active, pending)) {
        _publish(error: error, errorStage: pending.committed ? LocalizationErrorStage.persistence : LocalizationErrorStage.resources);
      }
      pending.ready.completeError(error, stackTrace);
      if (pending.applied.isCompleted) return;
      if (!pending.committed) {
        pending.applied.complete(LocalizationApplyOutcome.failed);
      } else if (!_attached) {
        pending.applied.complete(LocalizationApplyOutcome.detached);
      } else if (_data == _presentedData) {
        pending.applied.complete(LocalizationApplyOutcome.applied);
        _publish();
      }
    } finally {
      if (!_disposed && _controller.strictErrors) _startSystemTransition(_controller.replaySystemLocale);
      if (pending.applied.isCompleted) _pending.remove(pending);
      final active = _active;
      if (!_disposed && (identical(active, pending) || (active != null && active.ready.isCompleted && active.applied.isCompleted))) {
        _publish();
      }
    }
  }

  void _didCommit() {
    final translations = _controller.translations;
    if (translations == null || _disposed) return;
    _data = Localization.snapshot(
      locale,
      translations: translations,
      fallbackTranslations: _controller.fallbackTranslations,
      baseTranslations: _controller.baseTranslations,
      baseLocale: _controller.baseLocale,
      fallbackLocale: _controller.fallbackLocale,
      useFallbackTranslationsForEmptyResources: _config.useFallbackTranslationsForEmptyResources,
    );
    final active = _active;
    final committed = active != null && !active.ready.isCompleted && !(_controller.strictErrors && _controller.lastCommitWasSystemEvent);
    for (final pending in _pending.toList()) {
      if (!(committed && identical(pending, active)) && pending.committed && !pending.applied.isCompleted) {
        pending.applied.complete(LocalizationApplyOutcome.superseded);
      }
      if (pending.ready.isCompleted && pending.applied.isCompleted) _pending.remove(pending);
    }
    if (committed) {
      active.committed = true;
      _committedRevision = active.revision;
      _presentation = active.applied.future;
    } else {
      _committedRevision = ++_revision;
      _active = null;
      _presentation = null;
      if (_attached) {
        final pending = _LocalizationPending(_committedRevision, locale)..committed = true;
        pending.ready.complete();
        _pending.add(pending);
        _presentation = pending.applied.future;
      }
    }
    if (!_attached && identical(_instance, this)) Localization.publish(_data);
    _publish();
  }

  void _publish({Object? error, LocalizationErrorStage? errorStage}) {
    if (error != null) {
      _error = error;
      _errorStage = errorStage;
    }
    final value = LocalizationState(
      locale: locale,
      appliedLocale: _appliedLocale,
      isSystemMode: isSystemMode,
      isLoading: _pending.any((pending) => !pending.ready.isCompleted || (pending.committed && !pending.applied.isCompleted)),
      error: _error,
      errorStage: _errorStage,
    );
    // Controller commits can happen during a legacy delegate's build/load.
    // Listeners are always notified outside that synchronous build stack.
    scheduleMicrotask(() {
      if (!_disposed) _state.value = value;
    });
  }

  bool _canPresent(int revision) =>
      !_disposed && revision == _committedRevision && (_active == null || _active?.committed == true || _active?.ready.isCompleted == true);

  void _didApply(int revision, Locale locale) {
    _presentedData = _data;
    _appliedLocale = locale;
    for (final pending in _pending.toList()) {
      if (pending.committed && !pending.applied.isCompleted) pending.applied.complete(LocalizationApplyOutcome.applied);
      if (pending.ready.isCompleted) _pending.remove(pending);
    }
    _publish();
  }

  void _failedPresentation(Object error) {
    for (final pending in _pending.toList()) {
      if (pending.committed && !pending.applied.isCompleted) pending.applied.complete(LocalizationApplyOutcome.failed);
      if (pending.ready.isCompleted) _pending.remove(pending);
    }
    _publish(error: error, errorStage: LocalizationErrorStage.flutterDelegates);
  }

  void _attach(Object attachment) {
    _checkLive();
    if (_attached) throw StateError('Only one localization presentation root may attach');
    _attachment = attachment;
    final pending = _LocalizationPending(_committedRevision, locale)..committed = true;
    pending.ready.complete();
    _pending.add(pending);
    _presentation = pending.applied.future;
    _publish();
  }

  void _detach() {
    _attachment = null;
    _presentation = null;
    _presentedData = null;
    _appliedLocale = null;
    for (final pending in _pending.toList()) {
      if (!pending.applied.isCompleted) {
        pending.applied.complete(LocalizationApplyOutcome.detached);
        if (pending.ready.isCompleted) _pending.remove(pending);
      }
    }
    if (!_disposed && _data != null && identical(_instance, this)) Localization.publish(_data);
    if (!_disposed && _data != null) _publish();
  }

  final EasyLocalizationConfig _config;
  final EasyLocalizationController _controller;
  final ValueNotifier<LocalizationState> _state;
  final Set<_LocalizationPending> _pending = {};
  Localization? _data;
  Localization? _presentedData;
  _LocalizationPending? _active;
  int _revision = 0;
  int _committedRevision = 0;
  Locale? _appliedLocale;
  Future<LocalizationApplyOutcome>? _presentation;
  Object? _error;
  LocalizationErrorStage? _errorStage;
  bool _disposed = false;
  Object? _attachment;
  bool get _attached => _attachment != null;
  static EasyLocalizationInstance? _instance;
  static EasyLocalizationConfig? _initializingConfig;
  static Future<EasyLocalizationInstance>? _initializing;
}

class _LocalizationPending {
  final int revision;
  final Locale target;
  final Completer<void> ready = Completer();
  final Completer<LocalizationApplyOutcome> applied = Completer();
  bool committed = false;

  _LocalizationPending(this.revision, this.target);

  void finish(Object error, LocalizationApplyOutcome presentation) {
    if (!ready.isCompleted) ready.completeError(error);
    if (!applied.isCompleted) applied.complete(presentation);
  }
}
