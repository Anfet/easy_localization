import 'package:easy_localization_continued/easy_localization.dart';
import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'locale_wait.dart';

class FailingLoader extends AssetLoader {
  FailingLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    if (locale.languageCode == 'ru') throw StateError('deliberate loader failure');
    return {'title': 'Hello'};
  }
}

void main() {
  setUp(rootBundle.clear);
  tearDown(rootBundle.clear);

  testWidgets('starts in English, switches to Russian and resets', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    final localization = await EasyLocalization.initialize(localizationConfig);
    try {
      await tester.pumpWidget(EasyLocalization.withInstance(instance: localization, child: MyApp()));
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(find.textContaining('€0.00'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Русский'));
      await waitForLocale(tester, localization, const Locale('ru', 'RU'));
      expect(find.text('Привет!'), findsOneWidget);
      expect(find.textContaining('0,00'), findsOneWidget);
      await tester.tap(find.text('Сбросить язык'));
      await waitForLocale(tester, localization, const Locale('en', 'US'));
      expect(find.text('Hello'), findsOneWidget);
      expect(find.textContaining('€0.00'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      localization.dispose();
      tester.binding.platformDispatcher.clearLocalesTestValue();
    }
  });

  testWidgets('reports a loader failure while waiting for the locale', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final localization = await EasyLocalization.initialize(
      EasyLocalizationConfig(
        supportedLocales: [const Locale('en', 'US'), const Locale('ru', 'RU')],
        fallbackLocale: const Locale('en', 'US'),
        startLocale: const Locale('en', 'US'),
        path: 'unused',
        saveLocale: false,
        assetLoader: FailingLoader(),
      ),
    );
    try {
      await tester.pumpWidget(EasyLocalization.withInstance(instance: localization, child: MyApp()));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Русский'));
      await expectLater(
        () => waitForLocale(tester, localization, const Locale('ru', 'RU')),
        throwsA(isA<StateError>().having((e) => e.toString(), 'cause', contains('deliberate loader failure'))),
      );
      await tester.pump();
    } finally {
      await tester.pumpWidget(const SizedBox());
      localization.dispose();
    }
  });
}
