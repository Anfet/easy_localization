import 'package:easy_localization_continued/easy_localization.dart';
import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:ui' as ui;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'locale_wait.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> translationAssets;
  setUpAll(() async {
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    translationAssets = manifest.listAssets().where((asset) => asset.startsWith('resources/langs/') && asset.endsWith('.json')).toList();
    for (final asset in translationAssets) {
      await rootBundle.loadString(asset);
    }
    final loader = FontLoader('Roboto')..addFont(rootBundle.load('packages/alchemist/assets/fonts/Roboto/Roboto-Regular.ttf'));
    await loader.load();
  });
  tearDownAll(() {
    for (final asset in translationAssets) {
      rootBundle.evict(asset);
    }
  });

  testWidgets('large German text keeps language and reset actions reachable; Arabic is RTL', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    tester.binding.platformDispatcher.localesTestValue = const [Locale('de', 'DE')];
    final localization = await tester.runAsync(() => EasyLocalization.initialize(localizationConfig));
    if (localization == null) throw StateError('Localization initialization failed');
    try {
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: EasyLocalization.withInstance(instance: localization, child: MyApp()),
        ),
      );
      await tester.pumpAndSettle();
      expect(MediaQuery.textScalerOf(tester.element(find.byType(Scaffold).first)), const TextScaler.linear(2));
      expect(localization.presentationLocale, const Locale('de', 'DE'));
      expect(tester.takeException(), isNull);
      final language = find.byIcon(Icons.language);
      expect(language.hitTestable(), findsOneWidget);
      await tester.tap(language);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('عربي').hitTestable(), findsOneWidget);
      await tester.tap(find.byType(CloseButton));
      await tester.pumpAndSettle();
      final reset = find.byType(ElevatedButton);
      await tester.ensureVisible(reset);
      expect(reset.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(language);
      await tester.pumpAndSettle();
      await tester.tap(find.text('عربي'));
      await waitForLocale(tester, localization, const Locale('ar', 'DZ'));
      expect(Directionality.of(tester.element(find.byType(Scaffold).first)), ui.TextDirection.rtl);
    } finally {
      await tester.pumpWidget(const SizedBox());
      localization.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.platformDispatcher.clearLocalesTestValue();
    }
  });
}
