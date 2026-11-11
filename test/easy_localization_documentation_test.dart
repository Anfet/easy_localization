import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RecipeLoader extends AssetLoader {
  RecipeLoader();
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async => {};
}

void main() {
  test('documented configurations supply a supported fallback', () {
    final codegen = EasyLocalizationConfig(
      supportedLocales: const [Locale('en', 'US'), Locale('ar', 'DZ')],
      fallbackLocale: const Locale('en', 'US'),
      path: 'assets/translations',
      assetLoader: RecipeLoader(),
    );
    final modules = EasyLocalizationConfig(
      supportedLocales: const [Locale('en', 'US'), Locale('ar', 'DZ')],
      fallbackLocale: const Locale('en', 'US'),
      path: 'assets/translations',
      assetLoader: RecipeLoader(),
      extraAssetLoaders: [RecipeLoader(), RecipeLoader()],
    );
    final diagnostics = EasyLocalizationConfig(
      supportedLocales: const [Locale('en', 'US')],
      fallbackLocale: const Locale('en', 'US'),
      path: 'assets/translations',
    );
    for (final config in [codegen, modules, diagnostics]) {
      expect(config.supportedLocales, contains(config.fallbackLocale));
    }
  });
}
