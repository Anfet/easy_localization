part of 'easy_localization_app.dart';

/// Owner-scoped cache of immutable translators for explicitly selected locales.
class LocaleTranslators {
  LocaleTranslators._(this._owner);

  /// Loads all requested locales atomically, sharing concurrent loads.
  Future<void> load(Iterable<Locale> locales) async {
    _owner._checkLive();
    final requested = locales.toSet();
    for (final locale in requested) {
      _validate(locale);
    }
    final missing = requested.where((locale) => !_ready.containsKey(locale)).toList();
    final epoch = _loadEpoch;
    final generations = {for (final locale in requested) locale: _generation[locale] ?? 0};
    final snapshots = await Future.wait(missing.map(_loadShared), eagerError: true);
    _owner._checkLive();
    if (_loadEpoch != epoch) throw const LocalizationOperationSupersededException();
    for (final locale in requested.difference(missing.toSet())) {
      if ((_generation[locale] ?? 0) != generations[locale]) throw const LocalizationOperationSupersededException();
    }
    for (var i = 0; i < missing.length; i++) {
      final locale = missing[i];
      if ((_generation[locale] ?? 0) != generations[locale] && !identical(_ready[locale], snapshots[i])) {
        throw const LocalizationOperationSupersededException();
      }
    }
    for (var i = 0; i < missing.length; i++) {
      final locale = missing[i];
      if (!identical(_ready[locale], snapshots[i])) {
        _ready[locale] = snapshots[i];
        _generation[locale] = (_generation[locale] ?? 0) + 1;
      }
    }
  }

  /// Loads all supported locales.
  Future<void> loadAll() => load(_owner.supportedLocales);

  /// Returns a ready cached snapshot, or null when it has not been loaded.
  Localization? operator [](Locale locale) {
    _owner._checkLive();
    _validate(locale);
    return _ready[locale];
  }

  /// Removes the cache reference and invalidates in-flight loads.
  void unload(Locale locale) {
    _owner._checkLive();
    _validate(locale);
    _ready.remove(locale);
    _generation[locale] = (_generation[locale] ?? 0) + 1;
    _pending.remove(locale)?.cancel();
  }

  /// Loads an independent snapshot that remains usable after disposal.
  Future<Localization> once(Locale locale) {
    _owner._checkLive();
    _validate(locale);
    return _snapshot(locale);
  }

  void _validate(Locale locale) {
    if (!_owner.supportedLocales.contains(locale)) throw ArgumentError.value(locale, 'locale', 'Must be supported');
  }

  Future<Localization> _snapshot(Locale locale) =>
      _owner._controller.loadSnapshot(locale, useFallbackForEmpty: _owner.config.useFallbackTranslationsForEmptyResources);

  Future<Localization> _loadShared(Locale locale) {
    final existing = _pending[locale];
    if (existing != null) return existing.future;
    final pending = _TranslatorLoad();
    _pending[locale] = pending;
    _snapshot(locale).then(pending.complete, onError: pending.fail);
    pending.future.then<void>(
      (_) {
        if (identical(_pending[locale], pending)) _pending.remove(locale);
      },
      onError: (Object _, StackTrace _) {
        if (identical(_pending[locale], pending)) _pending.remove(locale);
      },
    );
    return pending.future;
  }

  Future<_TranslatorReload> _stageReload(Map<Locale, Future<Map<String, dynamic>?>> loads) async {
    _loadEpoch++;
    for (final pending in _pending.values) {
      pending.cancel();
    }
    _pending.clear();
    final locales = _ready.keys.toList();
    final generations = {for (final locale in locales) locale: _generation[locale] ?? 0};
    final snapshots = await Future.wait(
      locales.map(
        (locale) =>
            _owner._controller.loadSnapshot(locale, useFallbackForEmpty: _owner.config.useFallbackTranslationsForEmptyResources, reloadLoads: loads),
      ),
      eagerError: true,
    );
    _owner._checkLive();
    for (final locale in locales) {
      if ((_generation[locale] ?? 0) != generations[locale]) throw const LocalizationOperationSupersededException();
    }
    return _TranslatorReload({for (var i = 0; i < locales.length; i++) locales[i]: snapshots[i]}, generations);
  }

  void _publishReload(_TranslatorReload staged) {
    _owner._checkLive();
    for (final locale in staged.snapshots.keys) {
      if ((_generation[locale] ?? 0) != staged.generations[locale]) throw const LocalizationOperationSupersededException();
    }
    _ready.addAll(staged.snapshots);
  }

  void _dispose() {
    for (final pending in _pending.values) {
      pending.cancel(disposed: true);
    }
    _pending.clear();
    _ready.clear();
  }

  final EasyLocalizationInstance _owner;
  final Map<Locale, Localization> _ready = {};
  final Map<Locale, _TranslatorLoad> _pending = {};
  final Map<Locale, int> _generation = {};
  int _loadEpoch = 0;
}

class _TranslatorLoad {
  final Completer<Localization> _completer = Completer<Localization>();
  Future<Localization> get future => _completer.future;
  void complete(Localization value) {
    if (!_completer.isCompleted) _completer.complete(value);
  }

  void fail(Object error, StackTrace stack) {
    if (!_completer.isCompleted) _completer.completeError(error, stack);
  }

  void cancel({bool disposed = false}) {
    if (!_completer.isCompleted) {
      _completer.completeError(disposed ? StateError('Localization is disposed') : const LocalizationOperationSupersededException());
    }
  }
}

class _TranslatorReload {
  _TranslatorReload(this.snapshots, this.generations);
  final Map<Locale, Localization> snapshots;
  final Map<Locale, int> generations;
}
