import 'package:easy_localization_continued/easy_localization.dart';
import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('starts in English, switches to Russian and resets', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    final localization = await tester.runAsync(() => EasyLocalization.initialize(localizationConfig));
    if (localization == null) throw StateError('Localization initialization failed');
    try {
      await tester.pumpWidget(EasyLocalization.withInstance(instance: localization, child: MyApp()));
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(find.textContaining('€0.00'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.language));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Русский'));
      await tester.runAsync(() async {
        while (localization.locale != const Locale('ru', 'RU')) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Привет!'), findsOneWidget);
      expect(find.textContaining('0,00'), findsOneWidget);

      await tester.tap(find.text('Сбросить язык'));
      await tester.runAsync(() async {
        while (localization.locale != const Locale('en', 'US')) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      });
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(find.textContaining('€0.00'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      localization.dispose();
      tester.binding.platformDispatcher.clearLocalesTestValue();
    }
  });
}
