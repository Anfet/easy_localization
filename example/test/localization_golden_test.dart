import 'package:alchemist/alchemist.dart';
import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryLoader extends AssetLoader {
  MemoryLoader(this.translations)
    : super(
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
        fileLoader: const RootBundleFileLoader(),
      );

  final Map<String, dynamic> translations;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.value(translations);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    final loader = FontLoader('Roboto')..addFont(rootBundle.load('packages/alchemist/assets/fonts/Roboto/Roboto-Regular.ttf'));
    await loader.load();
  });

  AlchemistConfig.runWithConfig(
    config: AlchemistConfig(
      platformGoldensConfig: PlatformGoldensConfig(platforms: {HostPlatform.windows}),
      ciGoldensConfig: CiGoldensConfig(enabled: false),
    ),
    run: () {
      for (final locale in [const Locale('en'), const Locale('ru')]) {
        final isEnglish = locale.languageCode == 'en';
        goldenTest(
          '${locale.languageCode} translations are ready for the golden',
          fileName: 'localization_${locale.languageCode}',
          builder: () => Builder(
            builder: (context) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [Text(tr('title')), Text('items'.plural(2))],
            ),
          ),
          pumpWidget: (tester, widget) async {
            final owner = await EasyLocalization.initialize(
              EasyLocalizationConfig(
                supportedLocales: [locale],
                fallbackLocale: locale,
                startLocale: locale,
                path: 'unused',
                saveLocale: false,
                assetLoader: MemoryLoader({
                  'title': isEnglish ? 'Hello' : 'Привет',
                  'items': isEnglish
                      ? {'one': '{} item', 'other': '{} items'}
                      : {'one': '{} предмет', 'few': '{} предмета', 'many': '{} предметов', 'other': '{} предмета'},
                }),
              ),
            );
            addTearDown(() async {
              await tester.pumpWidget(const SizedBox.shrink());
              owner.dispose();
            });
            await tester.pumpWidget(
              EasyLocalization.withInstance(
                instance: owner,
                child: MaterialApp(
                  locale: owner.presentationLocale,
                  supportedLocales: owner.supportedLocales,
                  localizationsDelegates: owner.delegates,
                  theme: ThemeData(fontFamily: 'Roboto'),
                  home: widget,
                ),
              ),
            );
          },
          whilePerforming: (tester) async {
            expect(find.text(isEnglish ? 'Hello' : 'Привет'), findsOneWidget);
            expect(find.text(isEnglish ? '2 items' : '2 предмета'), findsOneWidget);
            return null;
          },
        );
      }
    },
  );
}
