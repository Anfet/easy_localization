import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/easy_localization_controller.dart';
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class ResourceLoader extends AssetLoader {
  ResourceLoader(this.resources)
    : super(
        fileLoader: const RootBundleFileLoader(),
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
      );
  final Map<String, Object?> resources;
  final calls = <String>[];
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    calls.add(locale.toString());
    final value = resources[locale.toString()];
    if (value is Error) throw value;
    if (value is Exception) throw value;
    return value == null ? null : Map<String, dynamic>.from(value as Map);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const region = Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn', countryCode: 'RS');
  const base = Locale.fromSubtags(languageCode: 'sr', scriptCode: 'Latn');
  const fallback = Locale('en');
  EasyLocalizationController controller(
    ResourceLoader loader, {
    bool enabled = true,
    bool onlyLanguage = false,
    Locale fallbackLocale = fallback,
    List<AssetLoader>? extras,
    bool strict = true,
  }) => EasyLocalizationController(
    supportedLocales: const [region, fallback],
    useFallbackTranslations: true,
    saveLocale: false,
    assetLoader: loader,
    path: 'unused',
    useOnlyLangCode: onlyLanguage,
    useBaseLanguageFallback: enabled,
    strictErrors: strict,
    extraAssetLoaders: extras,
    forceLocale: region,
    fallbackLocale: fallbackLocale,
    onLoadError: (_) {},
  );
  Future<Localization> snapshot(EasyLocalizationController c) => c.loadSnapshot(region, useFallbackForEmpty: false);

  test('plural chooses a source before applying its locale rules', () async {
    final vi = Localization.snapshot(
      const Locale('vi'),
      translations: Translations({
        'p': {'other': 'vi other'},
      }),
      fallbackTranslations: Translations({
        'p': {'one': 'en one', 'other': 'en other'},
      }),
      fallbackLocale: const Locale('en'),
    );
    expect(vi.plural('p', 1), 'vi other');
    final c = EasyLocalizationController(
      supportedLocales: const [Locale('ru', 'RU'), Locale('en')],
      useFallbackTranslations: true,
      useBaseLanguageFallback: true,
      saveLocale: false,
      assetLoader: ResourceLoader({
        'ru_RU': {},
        'ru': {
          'p': {'one': 'ru one', 'other': 'ru other'},
        },
        'en': {
          'p': {'one': 'en one', 'other': 'en other'},
          'q': {'one': 'en one', 'other': 'en other'},
        },
      }),
      path: 'unused',
      useOnlyLangCode: false,
      strictErrors: true,
      forceLocale: const Locale('ru', 'RU'),
      fallbackLocale: const Locale('en'),
      onLoadError: (_) {},
    );
    final result = await c.loadSnapshot(const Locale('ru', 'RU'), useFallbackForEmpty: false);
    expect(result.plural('p', 21), 'ru one');
    expect(result.plural('q', 21), 'en other');
    expect(result.plural('missing', 5), 'missing.other');
    c.dispose();
  });

  test('base is optional, script is retained, and layer priority is preserved', () async {
    final loader = ResourceLoader({
      'sr_Latn_RS': {'primary': 'P'},
      'sr_Latn': {'primary': 'B', 'base': 'B'},
      'en': {'base': 'F', 'fallback': 'F'},
    });
    final c = controller(loader);
    final result = await snapshot(c);
    expect([result.tr('primary'), result.tr('base'), result.tr('fallback')], ['P', 'B', 'F']);
    expect(loader.calls, ['sr_Latn_RS', 'sr_Latn', 'en']);
    c.dispose();
    final off = controller(loader, enabled: false);
    loader.calls.clear();
    await snapshot(off);
    expect(loader.calls, ['sr_Latn_RS', 'en']);
    off.dispose();
    loader.resources['sr_Latn'] = null;
    final missing = controller(loader);
    expect((await snapshot(missing)).tr('base'), 'F');
    missing.dispose();
  });

  test('legacy base drops script and catches FlutterError', () async {
    final loader = ResourceLoader({
      'sr_Latn_RS': {'key': 'primary'},
      'sr': FlutterError('missing'),
      'en': {'key2': 'fallback'},
    });
    final c = controller(loader, strict: false);
    expect((await snapshot(c)).tr('key2'), 'fallback');
    expect(loader.calls, ['sr_Latn_RS', 'sr', 'en']);
    c.dispose();
  });

  test('extra null preserves data and strict errors are propagated', () async {
    final primary = ResourceLoader({
      'sr_Latn_RS': {'key': 'value'},
      'sr_Latn': null,
      'en': {},
    });
    final extra = ResourceLoader({});
    final c = controller(primary, extras: [extra]);
    expect((await snapshot(c)).tr('key'), 'value');
    for (final error in [TimeoutException('timeout'), const FormatException('bad'), FlutterError('missing')]) {
      primary.resources['sr_Latn'] = error;
      await expectLater(snapshot(c), throwsA(same(error)));
    }
    c.dispose();
  });

  test('required missing fails, empty succeeds and duplicate normalized resource loads once', () async {
    final loader = ResourceLoader({'sr_Latn_RS': {}, 'en': null, 'sr_Latn': {}});
    final c = controller(loader, enabled: false);
    await expectLater(snapshot(c), throwsStateError);
    loader.resources['en'] = {};
    loader.resources['sr_Latn_RS'] = null;
    await expectLater(snapshot(c), throwsStateError);
    loader.resources['sr_Latn_RS'] = {};
    await snapshot(c);
    c.dispose();
    final duplicate = controller(loader, onlyLanguage: true, fallbackLocale: base);
    loader.calls.clear();
    await snapshot(duplicate);
    expect(loader.calls, ['sr_Latn']);
    loader.resources['sr_Latn'] = null;
    await expectLater(snapshot(duplicate), throwsStateError);
    duplicate.dispose();
    loader.resources['sr_Latn_RS'] = {};
    final requiredBase = controller(loader, fallbackLocale: base);
    await expectLater(snapshot(requiredBase), throwsStateError);
    requiredBase.dispose();
  });
}
