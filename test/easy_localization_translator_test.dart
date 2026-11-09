import 'dart:async';

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class DocumentLoader extends AssetLoader {
  DocumentLoader()
    : super(
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
        fileLoader: const RootBundleFileLoader(),
      );

  final data = <String, Map<String, dynamic>>{};
  final pending = <String, List<Completer<Map<String, dynamic>?>>>{};
  int calls = 0;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) {
    calls++;
    final queue = pending[locale.toString()];
    if (queue != null && queue.isNotEmpty) return queue.removeAt(0).future;
    return Future.value(data[locale.toString()] ?? {});
  }
}

class DocumentDelegate extends LocalizationsDelegate<String> {
  int calls = 0;
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<String> load(Locale locale) async {
    calls++;
    return locale.toString();
  }

  @override
  bool shouldReload(DocumentDelegate old) => false;
}

class DocumentStore extends SharedPreferencesStorePlatform {
  int calls = 0;
  @override
  Future<Map<String, Object>> getAll() async {
    calls++;
    return {};
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    calls++;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    calls++;
    return true;
  }

  @override
  Future<bool> clear() async {
    calls++;
    return true;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform original;
  late DocumentStore store;
  late DocumentLoader loader;
  late DocumentDelegate delegate;

  Future<EasyLocalizationInstance> initialize() => EasyLocalization.initialize(
    EasyLocalizationConfig(
      supportedLocales: const [Locale('en'), Locale('ru')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      path: 'unused',
      assetLoader: loader,
      additionalDelegates: [delegate],
      useFallbackTranslations: true,
      useFallbackTranslationsForEmptyResources: true,
      saveLocale: false,
    ),
  );

  setUp(() {
    original = SharedPreferencesStorePlatform.instance;
    store = DocumentStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    loader = DocumentLoader();
    delegate = DocumentDelegate();
    loader.data.addAll({
      'en': {'value': 'English', 'fallback': 'fallback', 'empty': 'filled'},
      'ru': {
        'value': 'Русский',
        'welcome': 'Привет {name} {}',
        'link': '@:value',
        'empty': '',
        'gender': {'female': 'она'},
        'count': {'one': 'one', 'two': 'two', 'few': 'few', 'many': 'many', 'other': 'other'},
      },
    });
  });
  tearDown(() {
    try {
      EasyLocalization.instance.dispose();
    } on StateError {
      /* Already disposed. */
    }
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
  });

  test('document snapshot uses captured resources and options without side effects', () async {
    final owner = await initialize();
    final state = owner.state.value;
    final frames = binding.transientCallbackCount;
    var notifications = 0;
    owner.state.addListener(() => notifications++);
    final calls = store.calls;
    final document = await owner.translator(const Locale('ru'));
    expect(document.locale, const Locale('ru'));
    expect(document.tr('welcome', namedArgs: {'name': 'Мир'}, args: ['!']), 'Привет Мир !');
    expect(document.tr('gender', gender: 'female'), 'она');
    expect(document.tr('link'), 'Русский');
    expect(document.tr('fallback'), 'fallback');
    expect(document.tr('empty'), 'filled');
    expect(document.exists('fallback'), isFalse);
    expect(document.exists('fallback', includeFallback: true), isTrue);
    expect(document.plural('count', 2), 'two');
    expect(owner.locale, const Locale('en'));
    expect(owner.state.value, same(state));
    expect(notifications, 0);
    expect(delegate.calls, 0);
    expect(store.calls, calls);
    expect(binding.transientCallbackCount, frames);
    expect(tr('value'), 'English');
    final loaderCalls = loader.calls;
    expect(() => owner.translator(const Locale('fr')), throwsArgumentError);
    expect(loader.calls, loaderCalls);
    loader.data['ru']!['value'] = 'Новый';
    await owner.reloadTranslations();
    expect(document.tr('value'), 'Русский');
    expect((await owner.translator(const Locale('ru'))).tr('value'), 'Новый');
    owner.dispose();
    final other = await initialize();
    final second = await other.translator(const Locale('ru'));
    expect(second.plural('count', 2), 'two');
    expect(document.plural('count', 2), 'two');
  });

  test('concurrent requests, failure, UI change and disposal are independent', () async {
    final owner = await initialize();
    final first = Completer<Map<String, dynamic>?>();
    final second = Completer<Map<String, dynamic>?>();
    final failure = Completer<Map<String, dynamic>?>();
    loader.pending['ru'] = [first, second, failure];
    final a = owner.translator(const Locale('ru'));
    final b = owner.translator(const Locale('ru'));
    final c = owner.translator(const Locale('ru'));
    final error = StateError('loader failed');
    final failed = expectLater(c, throwsA(same(error)));
    second.complete({'value': 'second'});
    final document = await b;
    failure.completeError(error);
    await failed;
    expect(owner.locale, const Locale('en'));
    final change = owner.setLocale(const Locale('ru'));
    await change;
    expect(document.tr('value'), 'second');
    owner.dispose();
    first.complete({'value': 'first'});
    expect((await a).tr('value'), 'first');
    expect(document.tr('value'), 'second');
    expect(() => owner.translator(const Locale('ru')), throwsStateError);
  });
  test('preloaded recipient and search use explicit language without changing UI', () async {
    final owner = await EasyLocalization.initialize(
      EasyLocalizationConfig(
        supportedLocales: const [Locale('en'), Locale('ru')],
        fallbackLocale: const Locale('ru'),
        startLocale: const Locale('ru'),
        preloadLocales: const [Locale('en')],
        path: 'unused',
        assetLoader: loader,
        saveLocale: false,
      ),
    );
    expect(tr('value'), 'Русский');
    expect(tr('value', locale: const Locale('en')), 'English');
    expect('value'.tr(locale: const Locale('en')), 'English');
    expect(const Text('value').tr(locale: const Locale('en')).data, 'English');
    expect('value'.trExists(locale: const Locale('en')), isTrue);
    expect([const Locale('ru'), const Locale('en')].map((l) => tr('value', locale: l)), ['Русский', 'English']);
    expect(owner.locale, const Locale('ru'));
    expect(store.calls, 0);
    expect(owner.translators[const Locale('en')]?.tr('value'), 'English');
  });

  test('cache batches share loads, invalidate pending work and preserve held snapshots', () async {
    final owner = await initialize();
    expect(() => tr('value', locale: const Locale('ru')), throwsStateError);
    final gate = Completer<Map<String, dynamic>?>();
    loader.pending['ru'] = [gate];
    final before = loader.calls;
    final first = owner.translators.load([const Locale('ru')]);
    final second = owner.translators.load([const Locale('ru')]);
    expect(loader.calls, before + 1);
    gate.complete({'value': 'cached'});
    await Future.wait([first, second]);
    final held = owner.translators[const Locale('ru')];
    expect(held?.tr('value'), 'cached');
    owner.translators.unload(const Locale('ru'));
    final next = Completer<Map<String, dynamic>?>();
    loader.pending['ru'] = [next];
    final loading = owner.translators.load([const Locale('ru')]);
    final cancelled = expectLater(loading, throwsA(isA<LocalizationOperationSupersededException>()));
    owner.translators.unload(const Locale('ru'));
    await cancelled;
    next.complete({'value': 'late'});
    await Future<void>.delayed(Duration.zero);
    expect(owner.translators[const Locale('ru')], isNull);
    owner.dispose();
    expect(held?.tr('value'), 'cached');
  });
  test('batch failure keeps ready cache and publishes none of its new snapshots', () async {
    final owner = await initialize();
    await owner.translators.load([const Locale('ru')]);
    final held = owner.translators[const Locale('ru')];
    final failure = Completer<Map<String, dynamic>?>();
    loader.pending['en'] = [failure];
    final loading = owner.translators.load([const Locale('en'), const Locale('ru')]);
    final check = expectLater(loading, throwsStateError);
    failure.completeError(StateError('failed'));
    await check;
    expect(owner.translators[const Locale('en')], isNull);
    expect(owner.translators[const Locale('ru')], same(held));
    await expectLater(owner.translators.load([const Locale('fr')]), throwsArgumentError);
  });
  test('batch checks ready participants before publishing new snapshots', () async {
    final owner = await initialize();
    await owner.translators.load([const Locale('ru')]);
    final held = owner.translators[const Locale('ru')];
    final first = Completer<Map<String, dynamic>?>();
    loader.pending['en'] = [first];
    final loading = owner.translators.load([const Locale('ru'), const Locale('en')]);
    final cancelled = expectLater(loading, throwsA(isA<LocalizationOperationSupersededException>()));
    owner.translators.unload(const Locale('ru'));
    first.complete({'value': 'English'});
    await cancelled;
    expect(owner.translators[const Locale('ru')], isNull);
    expect(owner.translators[const Locale('en')], isNull);
    expect(held?.tr('value'), 'Русский');

    await owner.translators.load([const Locale('ru')]);
    final ready = owner.translators[const Locale('ru')];
    final second = Completer<Map<String, dynamic>?>();
    loader.pending['en'] = [second];
    final successful = owner.translators.load([const Locale('ru'), const Locale('en')]);
    second.complete({'value': 'new English'});
    await successful;
    expect(owner.translators[const Locale('ru')], same(ready));
    expect(owner.translators[const Locale('en')]?.tr('value'), 'new English');
  });

  test('older overlapping batch cannot replace a newer snapshot or publish its other locale', () async {
    final owner = await EasyLocalization.initialize(
      EasyLocalizationConfig(
        supportedLocales: const [Locale('en'), Locale('ru'), Locale('fr')],
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        path: 'unused',
        assetLoader: loader,
        saveLocale: false,
      ),
    );
    final oldRu = Completer<Map<String, dynamic>?>();
    final oldFr = Completer<Map<String, dynamic>?>();
    final newRu = Completer<Map<String, dynamic>?>();
    loader.pending['ru'] = [oldRu, newRu];
    loader.pending['fr'] = [oldFr];
    final oldBatch = owner.translators.load([const Locale('ru'), const Locale('fr')]);
    final cancelled = expectLater(oldBatch, throwsA(isA<LocalizationOperationSupersededException>()));
    oldRu.complete({'value': 'old'});
    await Future<void>.delayed(Duration.zero);
    final fresh = owner.translators.load([const Locale('ru')]);
    newRu.complete({'value': 'fresh'});
    await fresh;
    oldFr.complete({'value': 'old fr'});
    await cancelled;
    expect(owner.translators[const Locale('ru')]?.tr('value'), 'fresh');
    expect(owner.translators[const Locale('fr')], isNull);
  });

  test('failed reload cancels older cache load and leaves ready and once snapshots intact', () async {
    final owner = await EasyLocalization.initialize(
      EasyLocalizationConfig(
        supportedLocales: const [Locale('en'), Locale('ru'), Locale('fr')],
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        path: 'unused',
        assetLoader: loader,
        saveLocale: false,
      ),
    );
    await owner.translators.load([const Locale('ru')]);
    final ready = owner.translators[const Locale('ru')];
    final current = owner.dataTranslator;
    final old = Completer<Map<String, dynamic>?>();
    final independent = Completer<Map<String, dynamic>?>();
    final failure = Completer<Map<String, dynamic>?>();
    loader.pending['fr'] = [old, independent];
    loader.pending['en'] = [failure];
    final loading = owner.translators.load([const Locale('fr')]);
    final cancelled = expectLater(loading, throwsA(isA<LocalizationOperationSupersededException>()));
    final once = owner.translators.once(const Locale('fr'));
    final reload = owner.reloadTranslations();
    final failed = expectLater(reload, throwsStateError);
    failure.completeError(StateError('failed reload'));
    await failed;
    await cancelled;
    old.complete({'value': 'late'});
    independent.complete({'value': 'independent'});
    expect((await once).tr('value'), 'independent');
    await Future<void>.delayed(Duration.zero);
    expect(owner.translators[const Locale('fr')], isNull);
    expect(owner.translators[const Locale('ru')], same(ready));
    expect(owner.dataTranslator, same(current));
  });
  testWidgets('explicit locale takes precedence over scoped context for String and Text', (tester) async {
    final owner = await initialize();
    await owner.translators.load([const Locale('ru')]);
    late BuildContext scoped;
    await tester.pumpWidget(
      EasyLocalization.withInstance(
        instance: owner,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Builder(
              builder: (context) {
                scoped = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect('value'.tr(context: scoped), 'English');
    expect('value'.tr(context: scoped, locale: const Locale('ru')), 'Русский');
    expect(const Text('value').tr(context: scoped, locale: const Locale('ru')).data, 'Русский');
    expect('count'.plural(2, context: scoped, locale: const Locale('ru')), 'two');
    expect(const Text('count').plural(2, context: scoped, locale: const Locale('ru')).data, 'two');
    await tester.pumpWidget(const SizedBox());
  });
}
