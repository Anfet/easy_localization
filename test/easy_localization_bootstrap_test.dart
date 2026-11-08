import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'easy_localization_instance_test.dart' show InstanceLoader;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('no-arg shim leaves translations unavailable; config loads before a frame', () async {
    await EasyLocalization.ensureInitialized();
    expect(() => tr('value'), throwsStateError);
    final config = EasyLocalizationConfig(
      supportedLocales: const [Locale('ru')],
      fallbackLocale: const Locale('ru'),
      startLocale: const Locale('ru'),
      path: 'unused',
      assetLoader: InstanceLoader(),
      saveLocale: false,
    );
    await EasyLocalization.ensureInitialized(config);
    expect(tr('value'), 'ru');
    expect('value'.tr(), 'ru');
    expect(plural('count', 2), 'two');
    expect(Text('value').tr().data, 'ru');
    EasyLocalization.instance.dispose();
    expect(() => tr('value'), throwsStateError);
  });
}
