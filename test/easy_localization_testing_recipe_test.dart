import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
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
  testWidgets('English title and plural use the first owner', (tester) async {
    final owner = await EasyLocalization.initialize(
      EasyLocalizationConfig(
        supportedLocales: const [Locale('en')],
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        path: 'unused',
        saveLocale: false,
        assetLoader: MemoryLoader({
          'title': 'Hello',
          'items': {'one': '{} item', 'other': '{} items'},
        }),
      ),
    );
    try {
      await tester.pumpWidget(
        EasyLocalization.withInstance(
          instance: owner,
          child: MaterialApp(
            locale: owner.presentationLocale,
            supportedLocales: owner.supportedLocales,
            localizationsDelegates: owner.delegates,
            home: Scaffold(
              body: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [Text(tr('title')), Text('items'.plural(2))],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      owner.dispose();
    }
  });

  testWidgets('German title and plural use a fresh owner', (tester) async {
    final owner = await EasyLocalization.initialize(
      EasyLocalizationConfig(
        supportedLocales: const [Locale('de')],
        fallbackLocale: const Locale('de'),
        startLocale: const Locale('de'),
        path: 'unused',
        saveLocale: false,
        assetLoader: MemoryLoader({
          'title': 'Hallo',
          'items': {'one': '{} Artikel', 'other': '{} Artikel'},
        }),
      ),
    );
    try {
      await tester.pumpWidget(
        EasyLocalization.withInstance(
          instance: owner,
          child: MaterialApp(
            locale: owner.presentationLocale,
            supportedLocales: owner.supportedLocales,
            localizationsDelegates: owner.delegates,
            home: Scaffold(
              body: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [Text(tr('title')), Text('items'.plural(2))],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hallo'), findsOneWidget);
      expect(find.text('2 Artikel'), findsOneWidget);
      expect(find.text('Hello'), findsNothing);
      expect(find.text('2 items'), findsNothing);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      owner.dispose();
    }
  });
}
