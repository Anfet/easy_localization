import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/easy_localization_controller.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class FailingStore extends SharedPreferencesStorePlatform {
  @override
  Future<Map<String, Object>> getAll() async => throw StateError('storage unavailable');
  @override
  Future<bool> clear() async => true;
  @override
  Future<bool> remove(String key) async => true;
  @override
  Future<bool> setValue(String valueType, String key, Object value) async => true;
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  test('device locale is available before init and after storage failure', () async {
    final original = SharedPreferencesStorePlatform.instance;
    final expected = binding.platformDispatcher.locale;
    EasyLocalizationController createController() => EasyLocalizationController(
          supportedLocales: [expected],
          useFallbackTranslations: false,
          saveLocale: true,
          assetLoader: RootBundleAssetLoader.fromRootBundle(),
          path: '',
          useOnlyLangCode: false,
          onLoadError: (_) {},
        );
    final before = createController();
    expect(before.deviceLocale, expected);
    expect(before.locale, expected);
    before.dispose();
    SharedPreferencesStorePlatform.instance = FailingStore();
    SharedPreferences.resetStatic();
    try {
      await expectLater(EasyLocalization.ensureInitialized(), throwsA(isA<StateError>()));
      final after = createController();
      expect(after.deviceLocale, expected);
      expect(after.locale, expected);
      after.dispose();
    } finally {
      SharedPreferencesStorePlatform.instance = original;
      SharedPreferences.resetStatic();
    }
  });

  test('saved locale takes priority and system selection does not write', () async {
    SharedPreferences.setMockInitialValues({'locale': 'de'});
    await EasyLocalization.ensureInitialized();
    final saved = EasyLocalizationController(
      supportedLocales: const [Locale('en'), Locale('de')],
      useFallbackTranslations: false,
      saveLocale: true,
      assetLoader: RootBundleAssetLoader.fromRootBundle(),
      path: '',
      useOnlyLangCode: false,
      onLoadError: (_) {},
      startLocale: const Locale('en'),
    );
    expect(saved.locale, const Locale('de'));
    final device = saved.deviceLocale;
    final original = SharedPreferencesStorePlatform.instance;
    SharedPreferencesStorePlatform.instance = FailingStore();
    SharedPreferences.resetStatic();
    try {
      await expectLater(EasyLocalization.ensureInitialized(), throwsA(isA<StateError>()));
      expect(saved.savedLocale, const Locale('de'));
      expect(saved.deviceLocale, device);
    } finally {
      SharedPreferencesStorePlatform.instance = original;
      SharedPreferences.resetStatic();
      saved.dispose();
    }
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    final system = EasyLocalizationController(
      supportedLocales: const [Locale('en'), Locale('de')],
      useFallbackTranslations: false,
      saveLocale: true,
      assetLoader: RootBundleAssetLoader.fromRootBundle(),
      path: '',
      useOnlyLangCode: false,
      onLoadError: (_) {},
    );
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('locale'), isNull);
    system.dispose();
  });
}
