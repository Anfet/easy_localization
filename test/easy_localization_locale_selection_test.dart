import 'package:easy_localization_continued/easy_localization.dart';
import 'package:easy_localization_continued/src/easy_localization_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingLoader extends AssetLoader {
  RecordingLoader();
  final locales = <Locale>[];

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    locales.add(locale);
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('preferred locales honor language priority and specificity', () {
    const ru = Locale('ru');
    const de = Locale('de');
    const hant = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant');
    const hansTw = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'TW');
    const exact = Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn', countryCode: 'RS');
    Locale select(List<Locale> supported, List<Locale> preferred) => EasyLocalizationController.selectPreferredLocale(supported, preferred, ru);
    const hantHk = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'HK');
    const hantTw = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW');
    const hansCn = Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN');
    const zhCn = Locale('zh', 'CN');
    expect(select([hansCn, hantTw], [hantHk, hansCn]), hantTw);
    expect(select([zhCn, hantTw], [hantHk, zhCn]), hantTw);
    expect(select([hansCn], [hantHk, hansCn]), hansCn);
    expect(select([hantTw, hansCn], [hantHk, hansCn, hantTw]), hantTw);
    expect(select([ru, de], [const Locale('fr', 'FR'), const Locale('de', 'DE')]), de);
    expect(select([ru, de], []), ru);
    expect(select([], [const Locale('de', 'DE')]), ru);
    expect(select([ru, de], [const Locale('fr')]), ru);
    expect(select([const Locale('zh'), hant, hansTw], [const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW')]), hant);
    expect(select([const Locale('de', 'DE'), const Locale('en')], [const Locale('de', 'AT')]), const Locale('de', 'DE'));
    expect(select(const [Locale('en', 'AU'), Locale('en', 'US')], const [Locale('en', 'GB'), Locale('en', 'US')]), const Locale('en', 'US'));
    expect(select(const [Locale('en', 'GB'), Locale('en', 'US')], const [Locale('en', 'GB'), Locale('en', 'US')]), const Locale('en', 'GB'));
    expect(
      select(
        const [Locale('en', 'AU'), Locale('fr', 'FR'), Locale('en', 'US'), Locale('en', 'CA')],
        const [Locale('en', 'GB'), Locale('fr', 'FR'), Locale('en', 'CA'), Locale('en', 'US')],
      ),
      const Locale('en', 'CA'),
    );
    expect(select(const [Locale('de', 'DE'), Locale('en')], const [Locale('de', 'AT'), Locale('en', 'US')]), const Locale('de', 'DE'));
    expect(select([const Locale('sr'), const Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn'), exact], [exact]), exact);
    expect(select([const Locale('de', 'DE'), const Locale('en')], [const Locale('de', 'AT'), const Locale('en')]), const Locale('de', 'DE'));
    expect(select([const Locale('de', 'DE'), const Locale('de', 'CH')], [const Locale('de', 'AT')]), const Locale('de', 'DE'));
  });

  test('start selects a supported locale before loading', () async {
    Future<void> check(List<Locale> supported, Locale start, Locale? fallback, Locale expected) async {
      final loader = RecordingLoader();
      final controller = EasyLocalizationController(
        supportedLocales: supported,
        useFallbackTranslations: false,
        saveLocale: false,
        assetLoader: loader,
        path: '',
        useOnlyLangCode: false,
        onLoadError: (_) {},
        startLocale: start,
        fallbackLocale: fallback,
      );
      await controller.loadTranslations();
      expect(controller.locale, expected);
      expect(loader.locales, [expected]);
      controller.dispose();
    }

    await check(const [Locale('en'), Locale('de')], const Locale('fr', 'FR'), const Locale('fr'), const Locale('en'));
    await check(const [Locale('en'), Locale('en', 'US')], const Locale('en', 'US'), null, const Locale('en', 'US'));
    await check(
      const [Locale('zh'), Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')],
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
      null,
      const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
    );
    await check(const [Locale('de', 'DE'), Locale('en')], const Locale('de', 'AT'), const Locale('en'), const Locale('de', 'DE'));
    await check(const [Locale('en'), Locale('de')], const Locale('fr'), const Locale('de'), const Locale('de'));
  });
}
