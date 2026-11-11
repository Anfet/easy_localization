import 'package:easy_localization_continued/easy_localization.dart';
import 'package:example/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('loads linked English translations from the root bundle', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en', 'US')];
    final assetManifest = await tester.runAsync(() => AssetManifest.loadFromAssetBundle(rootBundle));
    if (assetManifest == null) fail('Asset manifest was not loaded from the root bundle.');
    expect(assetManifest.listAssets(), contains('resources/langs/en-US/clicked.json'));

    final localization = await tester.runAsync(() => EasyLocalization.initialize(localizationConfig));
    if (localization == null) throw StateError('Localization initialization failed');
    try {
      await tester.pumpWidget(EasyLocalization.withInstance(instance: localization, child: MyApp()));
      await tester.pumpAndSettle();
      expect(find.text("You didn't click yet!"), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      localization.dispose();
      tester.binding.platformDispatcher.clearLocalesTestValue();
    }
  });
}
