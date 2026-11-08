import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart'
    show AssetLoader, EasyLocalization, EasyLocalizationConfig, JsonLinkedFileResolver, RootBundleFileLoader;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fixtures/generated_keys/locale_keys.g.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('generated keys expose translations without a second extension import', () async {
    final config = EasyLocalizationConfig(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      path: 'unused',
      assetLoader: const _FixtureLoader(),
      saveLocale: false,
    );
    await EasyLocalization.ensureInitialized(config);
    addTearDown(() => EasyLocalization.instance.dispose());

    expect(LocaleKeys.title.tr(), 'Welcome');
    expect(LocaleKeys.items.plural(2), '2 items');
    expect(const Text(LocaleKeys.title).tr().data, 'Welcome');
  });
}

class _FixtureLoader extends AssetLoader {
  const _FixtureLoader()
    : super(
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
        fileLoader: const RootBundleFileLoader(),
      );

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async =>
      jsonDecode(await File('test/fixtures/generated_keys/en.json').readAsString()) as Map<String, dynamic>;
}
