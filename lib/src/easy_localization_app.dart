import 'dart:async';

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:easy_localization_continued/src/easy_localization_controller.dart';
import 'package:easy_localization_continued/src/diagnostics.dart' show LocalizationLogCallback, reportLocalizationDiagnostic;
export 'package:easy_localization_continued/src/diagnostics.dart' show LocalizationLogCallback;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show AsyncCallback, ValueListenable, SynchronousFuture, listEquals;
import 'package:flutter_localizations/flutter_localizations.dart';

part 'utils.dart';
part 'easy_localization_instance.dart';
part 'locale_translators.dart';

/// Provides localization to a widget tree using a ready owner or legacy setup.
///
/// Initialize an owner with [initialize] and attach it with
/// [EasyLocalization.withInstance]. Custom asset loaders must implement this
/// package's [AssetLoader] contract; upstream loaders require porting.
class EasyLocalization extends StatefulWidget {
  /// Initializes translations and persistence before runApp. Reusing the same
  /// immutable config returns the same pending future or ready owner. Dispose
  /// the owner before initializing with another config. Failed startup is retryable.
  static Future<EasyLocalizationInstance> initialize(EasyLocalizationConfig config) => EasyLocalizationInstance._initialize(config);

  /// The ready owner. Throws StateError until initialize succeeds or after dispose.
  static EasyLocalizationInstance get instance {
    final owner = EasyLocalizationInstance._instance;
    if (owner == null || owner._data == null) throw StateError('Call EasyLocalization.initialize before accessing the localization instance');
    return owner;
  }

  /// Borrows a ready owner. Removing this root leaves the owner usable.
  EasyLocalization.withInstance({super.key, required EasyLocalizationInstance instance, required this.child})
    : _providedInstance = instance,
      supportedLocales = instance.config.supportedLocales,
      path = instance.config.path,
      fallbackLocale = instance.config.fallbackLocale,
      startLocale = instance.config.startLocale,
      useOnlyLangCode = instance.config.useOnlyLangCode,
      useFallbackTranslations = instance.config.useFallbackTranslations,
      useBaseLanguageFallback = instance.config.useBaseLanguageFallback,
      useFallbackTranslationsForEmptyResources = instance.config.useFallbackTranslationsForEmptyResources,
      assetLoader = instance.config.assetLoader,
      extraAssetLoaders = instance.config.extraAssetLoaders,
      additionalDelegates = instance.config.additionalDelegates,
      saveLocale = instance.config.saveLocale,
      errorWidget = null;

  final EasyLocalizationInstance? _providedInstance;

  /// Place for your main page widget.
  final Widget child;

  /// List of supported locales.
  /// {@macro flutter.widgets.widgetsApp.supportedLocales}
  final List<Locale> supportedLocales;

  /// Locale when the locale is not in the list
  final Locale? fallbackLocale;

  /// Overrides device locale.
  final Locale? startLocale;

  /// Trigger for using only language code for reading localization files.
  /// @Default value false
  /// Example:
  /// ```
  /// en.json //useOnlyLangCode: true
  /// en-US.json //useOnlyLangCode: false
  /// ```
  final bool useOnlyLangCode;

  /// If a localization key is not found in the locale file, try to use the fallbackLocale file.
  /// @Default value false
  /// Example:
  /// ```
  /// useFallbackTranslations: true
  /// ```
  final bool useFallbackTranslations;

  /// Loads a base-language resource before the configured fallback.
  final bool useBaseLanguageFallback;

  /// Treats empty translation strings as missing, even without a loaded fallback.
  /// Any loaded base or fallback resource is checked for a non-empty value.
  /// @Default value false
  /// Example:
  /// ```
  /// useFallbackTranslationsForEmptyResources: true
  /// ```
  final bool useFallbackTranslationsForEmptyResources;

  /// Path to your folder with localization files.
  /// Example:
  /// ```dart
  /// path: 'assets/translations',
  /// path: 'assets/translations/lang.csv',
  /// ```
  final String path;

  /// Class loader for localization files.
  /// Implement this package's [AssetLoader]; upstream loaders require porting.
  /// Defaults to `RootBundleAssetLoader.fromRootBundle()`.
  // ignore: prefer_typing_uninitialized_variables
  final AssetLoader assetLoader;

  /// Class loader for localization files that belong to other packages.
  /// Implement this package's [AssetLoader]; upstream loaders require porting.
  /// Defaults to `null`.
  final List<AssetLoader>? extraAssetLoaders;

  /// Registers all custom Flutter delegates for atomic preparation before apply.
  final List<LocalizationsDelegate<dynamic>> additionalDelegates;

  /// Save locale in device storage.
  /// @Default value true
  final bool saveLocale;

  /// Shows a custom error widget when an error is encountered instead of the default error widget.
  /// @Default value `errorWidget = ErrorWidget()`
  final Widget Function(FlutterError? message)? errorWidget;

  EasyLocalization({
    super.key,
    required this.child,
    required this.supportedLocales,
    required this.path,
    this.fallbackLocale,
    this.startLocale,
    this.useOnlyLangCode = false,
    this.useFallbackTranslations = false,
    this.useBaseLanguageFallback = false,
    this.useFallbackTranslationsForEmptyResources = false,
    this.assetLoader = const RootBundleAssetLoader(
      fileLoader: RootBundleFileLoader(),
      linkedFileResolver: JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
    ),
    this.extraAssetLoaders,
    this.additionalDelegates = const [],
    this.saveLocale = true,
    this.errorWidget,
  }) : _providedInstance = null,
       assert(supportedLocales.isNotEmpty),
       assert(path.isNotEmpty) {
    reportLocalizationDiagnostic(EasyLocalization.onVerbose, 'Start');
  }

  @override
  // ignore: library_private_types_in_public_api
  _EasyLocalizationState createState() => _EasyLocalizationState();

  // ignore: library_private_types_in_public_api
  static _EasyLocalizationProvider? of(BuildContext context) => _EasyLocalizationProvider.of(context);

  /// Prepares Flutter, and loads translations when a config is supplied.
  static Future<void> ensureInitialized([EasyLocalizationConfig? config]) async {
    WidgetsFlutterBinding.ensureInitialized();
    if (config != null) await initialize(config);
  }

  /// Optional diagnostic handlers, invoked synchronously in the current zone.
  static LocalizationLogCallback? onVerbose;
  static LocalizationLogCallback? onWarning;
  static LocalizationLogCallback? onError;
}

class _EasyLocalizationState extends State<EasyLocalization> {
  @override
  Widget build(BuildContext context) {
    if (!_rootAttached) {
      final error = translationsLoadError;
      return error == null ? const SizedBox.shrink() : widget.errorWidget?.call(error) ?? ErrorWidget(error);
    }
    if (_failedRequest != null && _failedRequest != _owner._revision) {
      _failedRequest = null;
      _preparingRevision = -1;
    }
    _prepare();
    final prepared = _prepared;
    if (prepared != null && _owner._canPresent(prepared.revision) && !identical(prepared, _owner._publishedPresentation)) {
      _owner._publishedPresentation = prepared;
      _prepared = null;
      Localization.publish(prepared.snapshot);
      // Mark retained descendants before updateChild; keys, Elements and State survive.
      void rebuild(Element element) {
        element.markNeedsBuild();
        element.visitChildren(rebuild);
      }

      (context as Element).visitChildren(rebuild);
      final attachment = _attachment;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            identical(attachment, _owner._attachment) &&
            identical(_owner._publishedPresentation, prepared) &&
            _owner._canPresent(prepared.revision)) {
          _owner._didApply(prepared.revision, prepared.locale);
        }
      });
    }
    final presentation = _owner._publishedPresentation;
    final loadError = translationsLoadError;
    return _EasyLocalizationProvider(
      widget,
      localizationController,
      _owner,
      presentation: presentation,
      child: loadError != null
          ? widget.errorWidget?.call(loadError) ?? ErrorWidget(loadError)
          : presentation == null
          ? const SizedBox.shrink()
          : widget.child,
    );
  }

  @override
  void initState() {
    reportLocalizationDiagnostic(EasyLocalization.onVerbose, 'Init state');
    super.initState();
    final provided = widget._providedInstance;
    final ready = EasyLocalizationInstance._instance;
    if (provided != null || ready != null) {
      final owner = provided ?? ready;
      if (owner == null) throw StateError('Call EasyLocalization.initialize first');
      if (provided == null && !owner.config._matches(widget)) throw StateError('The legacy root config differs from the ready localization owner');
      _attachOwner(owner);
      return;
    }
    final config = EasyLocalizationConfig(
      supportedLocales: widget.supportedLocales,
      path: widget.path,
      fallbackLocale: widget.fallbackLocale ?? widget.supportedLocales.first,
      startLocale: widget.startLocale,
      assetLoader: widget.assetLoader,
      extraAssetLoaders: widget.extraAssetLoaders ?? const [],
      additionalDelegates: widget.additionalDelegates,
      useOnlyLangCode: widget.useOnlyLangCode,
      useFallbackTranslations: widget.useFallbackTranslations,
      useBaseLanguageFallback: widget.useBaseLanguageFallback,
      useFallbackTranslationsForEmptyResources: widget.useFallbackTranslationsForEmptyResources,
      saveLocale: widget.saveLocale,
    );
    _ownsInstance = true;
    _initializeLegacy(config);
  }

  Future<void> _initializeLegacy(EasyLocalizationConfig config) async {
    final pending = EasyLocalizationInstance._initializing;
    if (pending != null) {
      try {
        await pending;
      } catch (_) {
        // The previous root reports its own bootstrap failure.
      }
      if (!mounted) return;
    }
    try {
      final owner = await EasyLocalization.initialize(config);
      if (!mounted) {
        owner.dispose();
        return;
      }
      setState(() => _attachOwner(owner));
    } catch (error) {
      if (mounted) setState(() => translationsLoadError = error is FlutterError ? error : FlutterError(error.toString()));
    }
  }

  void _attachOwner(EasyLocalizationInstance owner) {
    _owner = owner;
    localizationController = owner._controller;
    owner._attach(_attachment);
    _rootAttached = true;
    localizationController.addListener(_resourcesChanged);
    owner.state.addListener(_ownerChanged);
  }

  @override
  void didUpdateWidget(EasyLocalization oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(widget._providedInstance, oldWidget._providedInstance)) {
      throw StateError('Unmount the root before replacing its localization owner');
    }
  }

  @override
  void dispose() {
    if (_rootAttached) {
      localizationController.removeListener(_resourcesChanged);
      if (!_owner._disposed) _owner.state.removeListener(_ownerChanged);
      _owner._detach();
      if (_ownsInstance) _owner.dispose();
    }
    super.dispose();
  }

  void _resourcesChanged() {
    if (mounted) {
      translationsLoadError = null;
      setState(() {});
    }
  }

  void _ownerChanged() {
    if (_owner._disposed || !mounted) return;
    setState(() {});
  }

  Future<void> _prepare() async {
    final snapshot = _owner._data;
    final revision = _owner._committedRevision;
    final locale = _owner.locale;
    if (snapshot == null || revision == _preparingRevision || !_owner._canPresent(revision)) return;
    _preparingRevision = revision;
    try {
      final delegates = <LocalizationsDelegate<dynamic>>[
        ..._owner.config.additionalDelegates,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ];
      final selected = <Type>{Localization};
      final adapters = <LocalizationsDelegate<dynamic>>[_PreparedDelegate(type: Localization, value: snapshot, revision: revision)];
      for (final delegate in delegates) {
        if (!selected.contains(delegate.type) && delegate.isSupported(locale)) {
          selected.add(delegate.type);
          final value = await delegate.load(locale);
          adapters.add(_PreparedDelegate(type: delegate.type, value: value, revision: revision));
        }
      }
      if (!mounted || !_owner._canPresent(revision)) {
        if (_preparingRevision == revision) _preparingRevision = -1;
        return;
      }
      _prepared = _PreparedLocalization(snapshot, locale, revision, adapters);
      setState(() => translationsLoadError = null);
    } catch (error, stack) {
      if (!mounted || !_owner._canPresent(revision)) {
        if (_preparingRevision == revision) _preparingRevision = -1;
        return;
      }
      reportLocalizationDiagnostic(EasyLocalization.onError, 'Flutter localization delegate failed: $error', stackTrace: stack);
      _failedRequest = _owner._revision;
      _owner._failedPresentation(error);
      if (_owner._publishedPresentation == null) setState(() => translationsLoadError = FlutterError(error.toString()));
    }
  }

  _PreparedLocalization? _prepared;
  int _preparingRevision = -1;
  final Object _attachment = Object();
  int? _failedRequest;
  late EasyLocalizationController localizationController;
  late EasyLocalizationInstance _owner;
  bool _ownsInstance = false;
  bool _rootAttached = false;
  FlutterError? translationsLoadError;
}

/// A complete Flutter resource set for one immutable data revision.
class _PreparedLocalization {
  final Localization snapshot;
  final Locale locale;
  final int revision;
  final List<LocalizationsDelegate<dynamic>> delegates;

  _PreparedLocalization(this.snapshot, this.locale, this.revision, List<LocalizationsDelegate<dynamic>> delegates)
    : delegates = List.unmodifiable(delegates);
}

/// Preserves the original delegate's resource type, including custom types.
class _PreparedDelegate extends LocalizationsDelegate<dynamic> {
  @override
  final Type type;
  final dynamic value;
  final int revision;

  const _PreparedDelegate({required this.type, required this.value, required this.revision});

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<dynamic> load(Locale locale) => SynchronousFuture<dynamic>(value);

  @override
  bool shouldReload(_PreparedDelegate old) => old.revision != revision || !identical(old.value, value);
}

class _EasyLocalizationProvider extends InheritedWidget {
  final EasyLocalization parent;
  final EasyLocalizationController _localeState;
  final EasyLocalizationInstance _owner;
  final Locale? currentLocale;
  final _PreparedLocalization? presentation;

  /// {@macro flutter.widgets.widgetsApp.localizationsDelegates}
  /// Includes the internal snapshot, configured custom resources and standard
  /// Material, Widgets and Cupertino resources, all prepared for this presentation.
  List<LocalizationsDelegate> get delegates => presentation?.delegates ?? const [];

  /// Get List of supported locales
  List<Locale> get supportedLocales => parent.supportedLocales;

  _EasyLocalizationProvider(this.parent, this._localeState, this._owner, {required this.presentation, required super.child})
    : currentLocale = presentation?.locale ?? _localeState.locale;

  /// Get current locale
  Locale get locale => currentLocale ?? _localeState.locale;

  /// Get fallback locale
  Locale? get fallbackLocale => parent.fallbackLocale;

  // Locale get startLocale => parent.startLocale;

  /// Change app locale
  Future<void> setLocale(Locale locale) async {
    assert(parent.supportedLocales.contains(locale));
    await _owner.setLocale(locale);
  }

  /// Reloads resources for the currently displayed locale.
  Future<void> reloadTranslations() async {
    await _owner.reloadTranslations();
  }

  /// Clears a saved locale from device storage
  Future<void> deleteSaveLocale() async {
    await _owner.deleteSaveLocale();
  }

  /// Getting device locale from platform
  Locale get deviceLocale => _localeState.deviceLocale;
  Locale? get savedLocale => _localeState.savedLocale;

  /// Follow the platform locale and remove the saved selection.
  Future<void> resetLocale() async {
    await _owner.resetLocale();
  }

  @override
  bool updateShouldNotify(_EasyLocalizationProvider oldWidget) {
    return !identical(oldWidget.presentation, presentation);
  }

  static _EasyLocalizationProvider? of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_EasyLocalizationProvider>();
}
