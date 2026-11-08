import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/easy_localization_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ResourceLoader extends AssetLoader {
  ResourceLoader(this.data)
      : super(linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()), fileLoader: const RootBundleFileLoader());

  final Map<String, Map<String, dynamic>> data;
  bool failEnglish = false;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    if (failEnglish && locale.languageCode == 'en') throw StateError('fallback failed');
    return data[locale.toString()];
  }
}

EasyLocalizationController controller(ResourceLoader main, ResourceLoader extra, {Locale locale = const Locale('de', 'AT')}) =>
    EasyLocalizationController(
      forceLocale: locale,
      supportedLocales: [locale, const Locale('en')],
      fallbackLocale: const Locale('en'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: main,
      extraAssetLoaders: [extra],
      path: 'unused',
      useOnlyLangCode: false,
      onLoadError: (_) {},
    );

void main() {
  test('dynamically typed nested maps merge and remain independent of their sources', () async {
    final firstSection = <dynamic, dynamic>{'first': 'one', 'shared': 'old', 'unread': 'original'};
    final listEntry = <dynamic, dynamic>{'value': 'original'};
    final secondSection = <dynamic, dynamic>{'second': 'two', 'shared': 'new'};
    final first = <String, dynamic>{
      'section': firstSection,
      'list': [listEntry]
    };
    final second = <String, dynamic>{'section': secondSection};
    final subject = controller(ResourceLoader({'de_AT': first}), ResourceLoader({'de_AT': second}));
    addTearDown(subject.dispose);
    final result = await subject.loadTranslationData(const Locale('de', 'AT'));
    expect(result['section'], {'first': 'one', 'shared': 'new', 'unread': 'original', 'second': 'two'});
    expect(firstSection, {'first': 'one', 'shared': 'old', 'unread': 'original'});
    expect(secondSection, {'second': 'two', 'shared': 'new'});
    expect(listEntry, {'value': 'original'});
    await subject.loadTranslations();
    firstSection['unread'] = 'changed';
    secondSection['shared'] = 'changed';
    listEntry['value'] = 'changed';
    expect(subject.translations?.get('section.unread'), 'original');
    expect(subject.translations?.get('section.shared'), 'new');
    expect((result['list'] as List).first['value'], 'original');
  });

  test('nested const loaders merge into owned maps and lists', () async {
    const first = <String, dynamic>{
      'section': {'first': 'one', 'shared': 'old'},
      'list': [
        {'value': 'original'}
      ],
    };
    const second = <String, dynamic>{
      'section': {'second': 'two', 'shared': 'new'}
    };
    final subject = controller(ResourceLoader({'de_AT': first}), ResourceLoader({'de_AT': second}));
    addTearDown(subject.dispose);
    final result = await subject.loadTranslationData(const Locale('de', 'AT'));
    expect(result['section'], {'first': 'one', 'second': 'two', 'shared': 'new'});
    (result['list'] as List).first['value'] = 'changed';
    (result['section'] as Map)['first'] = 'changed';
    expect(first['list'], [
      {'value': 'original'}
    ]);
    expect(first['section'], {'first': 'one', 'shared': 'old'});
    expect(second['section'], {'second': 'two', 'shared': 'new'});
  });

  test('failed reload keeps cached and unread values, then retry publishes the complete set', () async {
    final main = ResourceLoader({
      'de_AT': {
        'section': {'cached': 'old cached', 'unread': 'old unread'}
      },
      'de': {},
      'en': {},
    });
    final extra = ResourceLoader({'de_AT': <String, dynamic>{}});
    final subject = controller(main, extra);
    addTearDown(subject.dispose);
    await subject.loadTranslations();
    final accepted = subject.translations;
    expect(accepted?.get('section.cached'), 'old cached');
    extra.data['de_AT'] = {
      'section': {'cached': 'new cached', 'unread': 'new unread', 'added': 'new'}
    };
    main.failEnglish = true;
    await expectLater(subject.reloadTranslations(), throwsA(isA<FlutterError>()));
    expect(subject.translations, same(accepted));
    expect(subject.translations?.get('section.cached'), 'old cached');
    expect(subject.translations?.get('section.unread'), 'old unread');
    main.failEnglish = false;
    await subject.reloadTranslations();
    expect(subject.translations?.get('section.cached'), 'new cached');
    expect(subject.translations?.get('section.unread'), 'new unread');
    expect(subject.translations?.get('section.added'), 'new');
  });

  test('base language supplements fallback while main and extra retain priority', () async {
    final main = ResourceLoader({
      'en': {
        'section': {'english': 'English', 'base': 'English base', 'main': 'English main', 'extra': 'English extra'}
      },
      'de': {
        'section': {'base': 'Deutsch', 'main': 'Deutsch main', 'extra': 'Deutsch extra'}
      },
      'de_AT': {
        'section': {'main': 'Austria', 'extra': 'Austria main'}
      },
    });
    final extra = ResourceLoader({
      'de': {
        'section': {'base': 'Deutsch extra'}
      },
      'de_AT': {
        'section': {'extra': 'Austria extra'}
      },
    });
    final subject = controller(main, extra);
    addTearDown(subject.dispose);
    await subject.loadTranslations();
    Localization.load(subject.locale, translations: subject.translations, fallbackTranslations: subject.fallbackTranslations);
    expect(Localization.instance.tr('section.english'), 'English');
    expect(Localization.instance.tr('section.base'), 'Deutsch extra');
    expect(Localization.instance.tr('section.main'), 'Austria');
    expect(Localization.instance.tr('section.extra'), 'Austria extra');
  });
}
