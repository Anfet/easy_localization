import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class DocumentLoader extends AssetLoader {
  DocumentLoader()
      : super(linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()), fileLoader: const RootBundleFileLoader());

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

  Future<EasyLocalizationInstance> initialize({bool rules = false}) => EasyLocalization.initialize(EasyLocalizationConfig(
        supportedLocales: const [Locale('en'), Locale('ru')],
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        path: 'unused',
        assetLoader: loader,
        additionalDelegates: [delegate],
        useFallbackTranslations: true,
        useFallbackTranslationsForEmptyResources: true,
        ignorePluralRules: rules,
        saveLocale: false,
      ));

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
        'count': {'one': 'one', 'two': 'two', 'few': 'few', 'many': 'many', 'other': 'other'}
      },
    });
  });
  tearDown(() {
    try {
      EasyLocalization.instance.dispose();
    } on StateError {/* Already disposed. */}
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
    expect(document.plural('count', 2), 'few');
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
    await owner.reloadTranslations().ready;
    expect(document.tr('value'), 'Русский');
    expect((await owner.translator(const Locale('ru'))).tr('value'), 'Новый');
    owner.dispose();
    final other = await initialize(rules: true);
    final second = await other.translator(const Locale('ru'));
    expect(second.plural('count', 2), 'two');
    expect(document.plural('count', 2), 'few');
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
    await change.ready;
    expect(document.tr('value'), 'second');
    owner.dispose();
    first.complete({'value': 'first'});
    expect((await a).tr('value'), 'first');
    expect(document.tr('value'), 'second');
    expect(() => owner.translator(const Locale('ru')), throwsStateError);
  });
}
