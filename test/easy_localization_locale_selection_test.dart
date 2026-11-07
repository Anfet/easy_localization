import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/easy_localization_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecordingLoader extends AssetLoader {
  RecordingLoader()
      : super(linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()), fileLoader: const RootBundleFileLoader());
  final locales = <Locale>[];

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    locales.add(locale);
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
          fallbackLocale: fallback);
      await controller.loadTranslations();
      expect(controller.locale, expected);
      expect(loader.locales, [expected]);
      controller.dispose();
    }

    await check(const [Locale('en'), Locale('de')], const Locale('fr', 'FR'), const Locale('fr'), const Locale('en'));
    await check(const [Locale('en'), Locale('en', 'US')], const Locale('en', 'US'), null, const Locale('en', 'US'));
    await check(const [Locale('zh'), Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')],
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'), null, const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'));
    await check(const [Locale('de', 'DE'), Locale('en')], const Locale('de', 'AT'), const Locale('en'), const Locale('de', 'DE'));
    await check(const [Locale('en'), Locale('de')], const Locale('fr'), const Locale('de'), const Locale('de'));
  });
}
