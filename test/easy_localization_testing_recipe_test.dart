import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryLoader extends AssetLoader {
  MemoryLoader(this.translations);

  final Map<String, dynamic> translations;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.value(translations);
}

void main() {
  testWidgets('rebuilt app keeps state and agrees after locale change and reload', (tester) async {
    final translations = <String, dynamic>{'title': 'Hello'};
    final owner = await EasyLocalization.initialize(
      EasyLocalizationConfig(
        supportedLocales: const [Locale('en'), Locale('de')],
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        path: 'unused',
        saveLocale: false,
        assetLoader: MemoryLoader(translations),
      ),
    );
    final key = GlobalKey<_RecipeState>();
    try {
      await tester.pumpWidget(
        EasyLocalization.withInstance(
          instance: owner,
          child: Builder(
            builder: (context) => MaterialApp(
              locale: owner.presentationLocale,
              supportedLocales: owner.supportedLocales,
              localizationsDelegates: owner.delegates,
              home: _Recipe(key: key),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = key.currentState;
      translations['title'] = 'Hallo';
      await owner.setLocale(const Locale('de'));
      final changed = owner.waitForPresentation();
      await tester.pumpAndSettle();
      expect(await changed, LocalizationApplyOutcome.applied);
      expect(tr('title'), 'Hallo');
      expect(find.text('Hallo/de'), findsOneWidget);
      expect(key.currentState, same(state));
      translations['title'] = 'Guten Tag';
      await owner.reloadTranslations();
      final reloaded = owner.waitForPresentation();
      await tester.pumpAndSettle();
      expect(await reloaded, LocalizationApplyOutcome.applied);
      expect(tr('title'), 'Guten Tag');
      expect(find.text('Guten Tag/de'), findsOneWidget);
      expect(key.currentState, same(state));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      owner.dispose();
    }
  });

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
          child: Builder(
            builder: (context) => MaterialApp(
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
          child: Builder(
            builder: (context) => MaterialApp(
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

class _Recipe extends StatefulWidget {
  const _Recipe({super.key});
  @override
  State<_Recipe> createState() => _RecipeState();
}

class _RecipeState extends State<_Recipe> {
  @override
  Widget build(BuildContext context) => Text('${context.tr('title')}/${Localizations.localeOf(context).languageCode}');
}
