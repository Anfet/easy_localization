import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/easy_localization_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class LocaleLoader extends AssetLoader {
  LocaleLoader()
    : super(
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
        fileLoader: const RootBundleFileLoader(),
      );
  final pending = <String, Completer<Map<String, dynamic>?>>{};
  final held = <String>{};
  final failures = <String>{};

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final lang = locale.languageCode;
    if (failures.remove(lang)) throw StateError('failed $lang');
    if (held.contains(lang)) return pending.putIfAbsent(lang, () => Completer()).future;
    return {'first': '$lang first', 'second': '$lang second'};
  }
}

class GatedStore extends SharedPreferencesStorePlatform {
  final data = <String, Object>{'flutter.locale': 'de'};
  final removeStarted = Completer<void>();
  final removeGate = Completer<bool>();

  @override
  Future<Map<String, Object>> getAll() async => Map.of(data);
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    removeStarted.complete();
    final result = await removeGate.future;
    if (result) data.remove(key);
    return result;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late BuildContext appContext;
  late LocaleLoader loader;

  Future<void> start(WidgetTester tester, {Locale? startLocale, Map<String, Object> saved = const {}}) async {
    SharedPreferences.setMockInitialValues(saved);
    await EasyLocalization.ensureInitialized();
    loader = LocaleLoader();
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('fr'), Locale('de')],
        fallbackLocale: const Locale('en'),
        startLocale: startLocale,
        path: 'unused',
        assetLoader: loader,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Builder(
              builder: (context) {
                appContext = context;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [Text(context.tr('first')), Text(context.tr('second'))],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> system(WidgetTester tester, String lang) async {
    tester.binding.platformDispatcher.localesTestValue = [Locale(lang)];
    await tester.pumpAndSettle();
  }

  tearDown(() {
    TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.clearLocalesTestValue();
    EasyLocalization.onError = null;
  });

  testWidgets('system changes update translations and use supported fallback', (tester) async {
    await start(tester);
    await system(tester, 'fr');
    expect(appContext.locale, const Locale('fr'));
    expect(find.text('fr first'), findsOneWidget);
    expect(find.text('fr second'), findsOneWidget);
    await system(tester, 'es');
    expect(appContext.locale, const Locale('en'));
    expect(appContext.deviceLocale, const Locale('es'));
  });

  for (final saved in [false, true]) {
    testWidgets('${saved ? 'saved selection' : 'start locale'} survives system changes and reset returns to system', (tester) async {
      await start(tester, startLocale: saved ? null : const Locale('de'), saved: saved ? {'locale': 'de'} : {});
      expect(appContext.locale, const Locale('de'));
      await system(tester, 'fr');
      expect(appContext.locale, const Locale('de'));
      expect(appContext.deviceLocale, const Locale('fr'));
      await appContext.resetLocale();
      await tester.pumpAndSettle();
      expect(appContext.locale, const Locale('fr'));
      expect((await SharedPreferences.getInstance()).getString('locale'), isNull);
      await system(tester, 'de');
      expect(appContext.locale, const Locale('de'));
      await tester.pumpWidget(const SizedBox());
      final persisted = (await SharedPreferences.getInstance()).getKeys().isEmpty
          ? <String, Object>{}
          : {'locale': (await SharedPreferences.getInstance()).getString('locale')!};
      await start(tester, saved: persisted);
      await system(tester, 'fr');
      expect(appContext.locale, const Locale('fr'));
    });
  }

  testWidgets('same-language explicit selection and resume preserve user intent', (tester) async {
    await start(tester);
    await appContext.setLocale(const Locale('en'));
    await system(tester, 'fr');
    expect(appContext.locale, const Locale('en'));
    expect((await SharedPreferences.getInstance()).getString('locale'), 'en');
    await appContext.resetLocale();
    await tester.pumpAndSettle();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(appContext.locale, const Locale('fr'));
  });

  testWidgets('failed reset keeps explicit choice and can be retried', (tester) async {
    await start(tester, saved: {'locale': 'de'});
    await system(tester, 'fr');
    loader.failures.add('fr');
    await expectLater(appContext.resetLocale(), throwsA(isA<StateError>()));
    expect(appContext.locale, const Locale('de'));
    expect((await SharedPreferences.getInstance()).getString('locale'), 'de');
    await system(tester, 'en');
    expect(appContext.locale, const Locale('de'));
    await appContext.resetLocale();
    await tester.pumpAndSettle();
    expect(appContext.locale, const Locale('en'));
    expect((await SharedPreferences.getInstance()).getString('locale'), isNull);
  });

  test('system change during failed explicit choice is applied', () async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    final controlled = LocaleLoader()..held.add('fr');
    final controller = EasyLocalizationController(
      supportedLocales: const [Locale('en'), Locale('fr'), Locale('de')],
      fallbackLocale: const Locale('en'),
      useFallbackTranslations: false,
      saveLocale: true,
      assetLoader: controlled,
      path: 'unused',
      useOnlyLangCode: false,
      onLoadError: (_) {},
    );
    await controller.loadTranslations();
    final choice = controller.setLocale(const Locale('fr'));
    final result = choice.then<Object?>((_) => null, onError: (Object error) => error);
    await controller.updateDeviceLocale(const Locale('de'));
    controlled.pending['fr']?.completeError(StateError('choice failed'));
    expect(await result, isA<StateError>());
    await controller.replaySystemLocale();
    expect(controller.locale, const Locale('de'));
    expect(controller.translations?.get('first'), 'de first');
    controller.dispose();
  });

  test('system change during failed reset storage is applied', () async {
    final original = SharedPreferencesStorePlatform.instance;
    final store = GatedStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    try {
      await EasyLocalizationController.readSavedLocale(const [Locale('en'), Locale('fr'), Locale('de')]);
      final controller = EasyLocalizationController(
        supportedLocales: const [Locale('en'), Locale('fr'), Locale('de')],
        useFallbackTranslations: false,
        saveLocale: true,
        assetLoader: LocaleLoader(),
        path: 'unused',
        useOnlyLangCode: false,
        onLoadError: (_) {},
      );
      await controller.loadTranslations();
      await controller.updateDeviceLocale(const Locale('fr'));
      final reset = controller.resetLocale();
      final result = reset.then<Object?>((_) => null, onError: (Object error) => error);
      await store.removeStarted.future;
      await controller.updateDeviceLocale(const Locale('de'));
      store.removeGate.complete(false);
      expect(await result, isA<StateError>());
      await controller.replaySystemLocale();
      expect(controller.locale, const Locale('de'));
      expect(controller.translations?.get('first'), 'de first');
      controller.dispose();
    } finally {
      SharedPreferencesStorePlatform.instance = original;
      SharedPreferences.resetStatic();
    }
  });

  for (final removeSucceeds in [true, false]) {
    test('newer explicit selection survives ${removeSucceeds ? 'delayed' : 'failed'} reset storage', () async {
      final original = SharedPreferencesStorePlatform.instance;
      final store = GatedStore();
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      try {
        await EasyLocalization.ensureInitialized();
        final controller = EasyLocalizationController(
          supportedLocales: const [Locale('en'), Locale('fr'), Locale('de')],
          useFallbackTranslations: false,
          saveLocale: true,
          assetLoader: LocaleLoader(),
          path: 'unused',
          useOnlyLangCode: false,
          onLoadError: (_) {},
        );
        await controller.loadTranslations();
        await controller.updateDeviceLocale(const Locale('fr'));
        final reset = controller.resetLocale();
        final resetResult = reset.then<Object?>((_) => null, onError: (Object error) => error);
        await store.removeStarted.future;
        final choice = controller.setLocale(const Locale('en'));
        store.removeGate.complete(removeSucceeds);
        final resetError = await resetResult;
        if (!removeSucceeds) expect(resetError, isA<StateError>());
        await choice;
        expect(controller.locale, const Locale('en'));
        expect(store.data['flutter.locale'], 'en');
        await controller.updateDeviceLocale(const Locale('de'));
        expect(controller.locale, const Locale('en'));
        controller.dispose();
      } finally {
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
      }
    });
  }

  testWidgets('failed and stale system loads preserve resources and a later transition succeeds', (tester) async {
    await start(tester);
    loader.failures.add('fr');
    await system(tester, 'fr');
    expect(appContext.locale, const Locale('en'));
    expect(find.text('en first'), findsOneWidget);
    expect(EasyLocalization.instance.state.value.error, isA<StateError>());
    expect(EasyLocalization.instance.state.value.errorStage, LocalizationErrorStage.resources);
    loader.held.add('fr');
    tester.binding.platformDispatcher.localesTestValue = const [Locale('fr')];
    await tester.pump();
    await system(tester, 'de');
    loader.pending['fr']?.complete({'first': 'stale', 'second': 'stale'});
    await tester.pumpAndSettle();
    expect(appContext.locale, const Locale('de'));
    expect(find.text('de first'), findsOneWidget);
    expect(EasyLocalization.instance.state.value.error, isNull);
    loader.held.remove('fr');
    await system(tester, 'fr');
    expect(appContext.locale, const Locale('fr'));
    loader.held.add('de');
    tester.binding.platformDispatcher.localesTestValue = const [Locale('de')];
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    loader.pending['de']?.complete({'first': 'late', 'second': 'late'});
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
