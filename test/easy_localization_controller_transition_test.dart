import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/easy_localization_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class Loader extends AssetLoader {
  Loader() : super(linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()), fileLoader: const RootBundleFileLoader());
  final pending = <String, Completer<Map<String, dynamic>?>>{};
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => pending.putIfAbsent(locale.toString(), () => Completer()).future;
  void complete(String locale) => pending[locale]!.complete({'value': locale});
}

class Store extends SharedPreferencesStorePlatform {
  final data = <String, Object>{};
  final operations = <String>[];
  final gates = <Completer<bool>>[];
  bool fail = false;
  @override
  Future<Map<String, Object>> getAll() async => Map.of(data);
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    operations.add('set:$value');
    if (gates.isNotEmpty && !await gates.removeAt(0).future) return false;
    if (fail) {
      fail = false;
      return false;
    }
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    operations.add('remove');
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform original;
  late Store store;
  setUp(() async {
    original = SharedPreferencesStorePlatform.instance;
    store = Store();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    await EasyLocalizationController.initEasyLocation();
  });
  tearDown(() {
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
    EasyLocalization.onError = null;
  });
  EasyLocalizationController controller(Loader loader, {bool save = false, void Function(FlutterError)? onError}) => EasyLocalizationController(
      supportedLocales: const [Locale('en'), Locale('de'), Locale('fr')],
      useFallbackTranslations: false,
      saveLocale: save,
      assetLoader: loader,
      path: '',
      useOnlyLangCode: false,
      onLoadError: onError ?? (_) {},
      forceLocale: const Locale('en'));

  test('latest load wins and selecting displayed locale cancels pending load', () async {
    final loader = Loader();
    final c = controller(loader);
    final initial = c.loadTranslations();
    loader.complete('en');
    await initial;
    final de = c.setLocale(const Locale('de'));
    final fr = c.setLocale(const Locale('fr'));
    loader.complete('fr');
    await fr;
    loader.complete('de');
    await de;
    expect(c.locale, const Locale('fr'));
    expect(c.translations?.get('value'), 'fr');
    loader.pending.remove('de');
    final again = c.setLocale(const Locale('de'));
    await c.setLocale(const Locale('fr'));
    loader.complete('de');
    await again;
    expect(c.locale, const Locale('fr'));
    expect(c.translations?.get('value'), 'fr');
    c.dispose();
  });
  test('fallback is published only after the complete latest load and stale failures are ignored', () async {
    final loader = Loader();
    var errors = 0;
    final c = EasyLocalizationController(
      supportedLocales: const [Locale('en'), Locale('de'), Locale('fr')],
      useFallbackTranslations: true,
      fallbackLocale: const Locale('en'),
      saveLocale: false,
      assetLoader: loader,
      path: '',
      useOnlyLangCode: false,
      onLoadError: (_) {
        errors++;
      },
      forceLocale: const Locale('en'),
    );
    final initial = c.loadTranslations();
    loader.complete('en');
    await initial;
    loader.pending.remove('en');
    final stale = c.setLocale(const Locale('de'));
    final latest = c.setLocale(const Locale('fr'));
    loader.complete('fr');
    await Future<void>.delayed(Duration.zero);
    expect(c.locale, const Locale('en'));
    loader.complete('en');
    await latest;
    expect(c.locale, const Locale('fr'));
    expect(c.translations?.get('value'), 'fr');
    expect(c.fallbackTranslations?.get('value'), 'en');
    loader.pending['de']!.completeError(StateError('late'));
    await stale;
    expect(errors, 0);
    expect(c.translations?.get('value'), 'fr');
    c.dispose();
  });
  test('current failure preserves resources and can be retried', () async {
    final loader = Loader();
    var errors = 0;
    var diagnostics = 0;
    EasyLocalization.onError = (message, {stackTrace}) {
      diagnostics++;
    };
    final c = controller(loader, onError: (_) {
      errors++;
    });
    final initial = c.loadTranslations();
    loader.complete('en');
    await initial;
    final failed = c.setLocale(const Locale('de'));
    loader.pending['de']!.completeError(StateError('bad'));
    await expectLater(failed, throwsA(isA<FlutterError>()));
    expect(c.locale, const Locale('en'));
    expect(c.translations?.get('value'), 'en');
    expect(errors, 1);
    expect(diagnostics, 1);
    loader.pending.remove('de');
    final retry = c.setLocale(const Locale('de'));
    loader.complete('de');
    await retry;
    expect(c.locale, const Locale('de'));
    c.dispose();
  });
  test('disabled persistence leaves confirmed locale and storage unchanged', () async {
    final loader = Loader();
    final c = controller(loader);
    final initial = c.loadTranslations();
    loader.complete('en');
    await initial;
    final change = c.setLocale(const Locale('de'));
    loader.complete('de');
    await change;
    expect(c.locale, const Locale('de'));
    expect(c.savedLocale, isNull);
    expect(store.operations, isEmpty);
    c.dispose();
  });

  test('storage operations are ordered and failed write does not poison queue', () async {
    final loader = Loader();
    final c = controller(loader, save: true);
    final initial = c.loadTranslations();
    loader.complete('en');
    await initial;
    final gate = Completer<bool>();
    store.gates.add(gate);
    final b = c.setLocale(const Locale('de'));
    loader.complete('de');
    await Future<void>.delayed(Duration.zero);
    final next = c.setLocale(const Locale('fr'));
    loader.complete('fr');
    await Future<void>.delayed(Duration.zero);
    final clear = c.deleteSaveLocale();
    expect(store.operations, ['set:de']);
    gate.complete(true);
    await Future.wait([b, next, clear]);
    expect(store.operations, ['set:de', 'set:fr', 'remove']);
    expect(c.savedLocale, isNull);
    store.fail = true;
    loader.pending.remove('de');
    final failed = c.setLocale(const Locale('de'));
    loader.complete('de');
    await expectLater(failed, throwsStateError);
    expect(c.locale, const Locale('de'));
    expect(c.savedLocale, isNull);
    expect((await SharedPreferences.getInstance()).getString('locale'), isNull);
    loader.pending.remove('fr');
    final retry = c.setLocale(const Locale('fr'));
    loader.complete('fr');
    await retry;
    expect(c.savedLocale, const Locale('fr'));
    await EasyLocalizationController.initEasyLocation();
    expect(c.savedLocale, const Locale('fr'));
    c.dispose();
  });
}
