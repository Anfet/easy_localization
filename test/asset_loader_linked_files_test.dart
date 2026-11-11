import 'dart:convert';
import 'dart:developer';

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:easy_localization_continued/src/easy_localization_controller.dart';
import '../bin/io_file_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() async {
  // Initialize the test environment
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  await EasyLocalization.ensureInitialized();

  group('Linked resolver contracts', () {
    test('limits wide linked roots before the next file read', () async {
      final files = _Files({
        'i18n/en/common.json': {'value': 'ok'},
      });
      final resolver = JsonLinkedFileResolver(fileLoader: files);
      final atLimit = {for (var i = 0; i < 4096; i++) '$i': ':/common.json'};
      expect((await resolver.resolveLinkedFiles(basePath: 'i18n', languageCode: 'en', baseJson: atLimit)).length, 4096);
      await expectLater(
        resolver.resolveLinkedFiles(basePath: 'i18n', languageCode: 'en', baseJson: {...atLimit, 'overflow': ':/missing.json'}),
        throwsA(predicate((error) => error.toString().contains('4096') && error.toString().contains('overflow'))),
      );
    });
    test('resolves independent and diamond references and restores ancestors', () async {
      final files = _Files({
        'i18n/en/common.json': {'value': 'shared'},
        'i18n/en/left.json': {'common': ':/common.json'},
        'i18n/en/right.json': {'common': ':/common.json'},
      });
      final resolver = JsonLinkedFileResolver(fileLoader: files);
      final ancestors = <String>{'ancestor'};
      final result = await resolver.resolveLinkedFiles(
        basePath: 'i18n',
        languageCode: 'en',
        visited: ancestors,
        baseJson: {'one': ':/common.json', 'two': ':/common.json', 'left': ':/left.json', 'right': ':/right.json'},
      );
      expect(result, {
        'one': {'value': 'shared'},
        'two': {'value': 'shared'},
        'left': {
          'common': {'value': 'shared'},
        },
        'right': {
          'common': {'value': 'shared'},
        },
      });
      expect(ancestors, {'ancestor'});
    });

    test('nested load failure keeps one context and the original stack', () async {
      final files = _Files({
        'i18n/en/first.json': {'child': ':/missing.json'},
      });
      try {
        await JsonLinkedFileResolver(
          fileLoader: files,
        ).resolveLinkedFiles(basePath: 'i18n', languageCode: 'en', baseJson: {'parent': ':/first.json'});
        fail('Expected a linked file error');
      } catch (error, stack) {
        expect(error, isA<StateError>());
        expect('Error resolving'.allMatches(error.toString()).length, 1);
        expect(error.toString(), contains('missing.json'));
        expect(stack.toString(), contains('_Files.loadString'));
      }
    });

    test('detects a cycle and restores the active stack after an error', () async {
      final files = _Files({
        'i18n/en/a.json': {'next': ':/b.json'},
        'i18n/en/b.json': {'next': ':/a.json'},
      });
      final ancestors = <String>{'ancestor'};
      await expectLater(
        JsonLinkedFileResolver(
          fileLoader: files,
        ).resolveLinkedFiles(basePath: 'i18n', languageCode: 'en', baseJson: {'next': ':/a.json'}, visited: ancestors),
        throwsA(isA<StateError>().having((e) => e.toString(), 'message', contains('Cyclic linked files'))),
      );
      expect(ancestors, {'ancestor'});
    });

    test('allows 32 file transitions, but rejects the next; maps do not increase depth', () async {
      final files = _Files({
        for (var i = 1; i <= 33; i++)
          'i18n/en/$i.json': i == 33
              ? {'value': 'end'}
              : {
                  'map': {'next': ':/${i + 1}.json'},
                },
      });
      final resolver = JsonLinkedFileResolver(fileLoader: files);
      await expectLater(resolver.resolveLinkedFiles(basePath: 'i18n', languageCode: 'en', baseJson: {'next': ':/2.json'}), completes);
      await expectLater(
        resolver.resolveLinkedFiles(basePath: 'i18n', languageCode: 'en', baseJson: {'next': ':/1.json'}),
        throwsA(isA<StateError>().having((e) => e.toString(), 'message', contains('Maximum linked files depth (32)'))),
      );
    });

    test('uses exact locale paths throughout nested links and does not fall back', () async {
      final locales = <Locale>[
        const Locale('en'),
        const Locale('en', 'US'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant'),
        const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN'),
      ];
      final names = ['en', 'en-US', 'zh-Hans', 'zh-Hant', 'zh-Hans-CN'];
      final files = _Files({
        for (final name in names) 'i18n/$name.json': {'link': ':/first.json'},
        for (final name in names) 'i18n/$name/first.json': {'nested': ':/second.json'},
        for (final name in names) 'i18n/$name/second.json': {'locale': name},
      });
      final loader = RootBundleAssetLoader(
        fileLoader: files,
        linkedFileResolver: JsonLinkedFileResolver(fileLoader: files),
      );
      for (var i = 0; i < locales.length; i++) {
        expect(await loader.load('i18n', locales[i]), {
          'link': {
            'nested': {'locale': names[i]},
          },
        });
      }
      files.contents.remove('i18n/zh-Hant/second.json');
      await expectLater(loader.load('i18n', locales[3]), throwsA(isA<StateError>()));
      expect(files.paths.last, 'i18n/zh-Hant/second.json');
    });

    test('legacy JSON override transforms nested maps and linked files through loader and direct API', () async {
      final files = _Files({
        'i18n/en.json': {
          'nested': {'value': 'map'},
          'linked': ':/item.json',
        },
        'i18n/en/item.json': {'value': 'file'},
      });
      final resolver = _TransformingLegacyJsonResolver(files);
      final loader = RootBundleAssetLoader(fileLoader: files, linkedFileResolver: resolver);
      final expected = {
        'nested': {'value': 'map', 'transformed': true},
        'linked': {'value': 'file', 'transformed': true},
        'transformed': true,
      };

      expect(await loader.load('i18n', const Locale('en')), expected);
      expect(resolver.calls, 3);
      resolver.calls = 0;
      expect(
        await resolver.resolveLinkedFiles(
          basePath: 'i18n',
          languageCode: 'en',
          baseJson: {
            'nested': {'value': 'map'},
            'linked': ':/item.json',
          },
        ),
        expected,
      );
      expect(resolver.calls, 3);
    });

    test('legacy overrides receive loader calls and direct API keeps legacy path', () async {
      final files = _Files({
        'i18n/en.json': {},
        'i18n/en-US.json': {},
        'i18n/en-US/item.json': {'ok': true},
      });
      final legacy = _LegacyResolver(files);
      final jsonLegacy = _LegacyJsonResolver(files);
      for (final resolver in [legacy, jsonLegacy]) {
        final loader = RootBundleAssetLoader(fileLoader: files, linkedFileResolver: resolver);
        await loader.load('i18n', const Locale('en'));
        await loader.load('i18n', const Locale('en', 'US'));
      }
      expect(legacy.calls, 2);
      expect(jsonLegacy.calls, 2);
      expect(
        await JsonLinkedFileResolver(
          fileLoader: files,
        ).resolveLinkedFiles(basePath: 'i18n', languageCode: 'en', countryCode: 'US', baseJson: {'item': ':/item.json'}),
        {
          'item': {'ok': true},
        },
      );
    });
  });

  group('Asset Loader - Linked Translation Files', () {
    group('RootBundleAssetLoader with linked files', () {
      test('should load single linked file', () async {
        final controller = EasyLocalizationController(
          forceLocale: const Locale('en', 'linked'),
          path: 'i18n',
          supportedLocales: const [Locale('en', 'linked')],
          useOnlyLangCode: false,
          useFallbackTranslations: false,
          saveLocale: false,
          onLoadError: (FlutterError e) {
            log(e.toString());
          },
          assetLoader: const RootBundleAssetLoader(
            linkedFileResolver: JsonLinkedFileResolver(fileLoader: IOFileLoader()),
            fileLoader: IOFileLoader(),
          ),
        );

        await controller.loadTranslations();
        final result = await controller.loadTranslationData(const Locale('en', 'linked'));

        expect(result['hello'], 'Hello');
        expect(result['app']['name'], 'Test App');
        expect(result['app']['errors']['not_found'], 'Resource not found');
        expect(result['app']['errors']['server_error'], 'Internal server error');
        expect(result['app']['errors']['invalid_input'], 'Invalid input provided');
      });

      test('should load multiple linked files', () async {
        final controller = EasyLocalizationController(
          forceLocale: const Locale('en', 'linked'),
          path: 'i18n',
          supportedLocales: const [Locale('en', 'linked')],
          useOnlyLangCode: false,
          useFallbackTranslations: false,
          saveLocale: false,
          onLoadError: (FlutterError e) {
            log(e.toString());
          },
          assetLoader: const RootBundleAssetLoader(
            linkedFileResolver: JsonLinkedFileResolver(fileLoader: IOFileLoader()),
            fileLoader: IOFileLoader(),
          ),
        );

        await controller.loadTranslations();
        final result = await controller.loadTranslationData(const Locale('en', 'linked'));

        // Check validation linked file
        expect(result['validation']['required'], 'This field is required');
        expect(result['validation']['email'], 'Please enter a valid email address');
        expect(result['validation']['min_length'], 'Minimum length is {min} characters');

        // Check multiple references to same file work
        expect(result['multiple']['errors']['not_found'], 'Multiple resource not found');
        expect(result['multiple']['validation']['required'], 'Multiple field is required');
      });

      test('should load nested linked files', () async {
        final controller = EasyLocalizationController(
          forceLocale: const Locale('en', 'linked'),
          path: 'i18n',
          supportedLocales: const [Locale('en', 'linked')],
          useOnlyLangCode: false,
          useFallbackTranslations: false,
          saveLocale: false,
          onLoadError: (FlutterError e) {
            log(e.toString());
          },
          assetLoader: const RootBundleAssetLoader(
            linkedFileResolver: JsonLinkedFileResolver(fileLoader: IOFileLoader()),
            fileLoader: IOFileLoader(),
          ),
        );

        await controller.loadTranslations();
        final result = await controller.loadTranslationData(const Locale('en', 'linked'));

        // Check nested folder structure
        expect(result['nested']['module']['messages']['welcome'], 'Welcome to our app');
        expect(result['nested']['module']['messages']['goodbye'], 'Thank you for using our app');
        expect(result['nested']['module']['messages']['info'], 'This is a nested message file');
      });

      test('should load deeply nested linked files', () async {
        final controller = EasyLocalizationController(
          forceLocale: const Locale('en', 'linked'),
          path: 'i18n',
          supportedLocales: const [Locale('en', 'linked')],
          useOnlyLangCode: false,
          useFallbackTranslations: false,
          saveLocale: false,
          onLoadError: (FlutterError e) {
            log(e.toString());
          },
          assetLoader: const RootBundleAssetLoader(
            linkedFileResolver: JsonLinkedFileResolver(fileLoader: IOFileLoader()),
            fileLoader: IOFileLoader(),
          ),
        );

        await controller.loadTranslations();
        final result = await controller.loadTranslationData(const Locale('en', 'linked'));

        // Check deep nesting (file linking to another file)
        expect(result['deep_nested']['level1_value'], 'This is level 1');
        expect(result['deep_nested']['level2']['level2_value'], 'This is level 2');
        expect(result['deep_nested']['level2']['final_message'], 'Deep nesting works!');
      });

      test('should preserve original structure with linked files', () async {
        final controller = EasyLocalizationController(
          forceLocale: const Locale('en', 'linked'),
          path: 'i18n',
          supportedLocales: const [Locale('en', 'linked')],
          useOnlyLangCode: false,
          useFallbackTranslations: false,
          saveLocale: false,
          onLoadError: (FlutterError e) {
            log(e.toString());
          },
          assetLoader: const RootBundleAssetLoader(
            linkedFileResolver: JsonLinkedFileResolver(fileLoader: IOFileLoader()),
            fileLoader: IOFileLoader(),
          ),
        );

        await controller.loadTranslations();
        final result = await controller.loadTranslationData(const Locale('en', 'linked'));

        // Verify that the original structure is preserved
        expect(result['test'], 'test_linked_en');
        expect(result['hello'], 'Hello');
        expect(result.containsKey('app'), true);
        expect(result['app'].containsKey('name'), true);
        expect(result['app'].containsKey('errors'), true);

        // The linked reference should be replaced with actual content
        expect(result['app']['errors'] is Map, true);
        expect(result['app']['errors'] is String, false);
      });
    });

    group('Error handling for linked files', () {
      test('should throw error for cyclic linked files', () async {
        final controller = EasyLocalizationController(
          forceLocale: const Locale('en', 'cyclic'),
          path: 'i18n',
          supportedLocales: const [Locale('en', 'cyclic')],
          useOnlyLangCode: false,
          useFallbackTranslations: false,
          saveLocale: false,
          onLoadError: (FlutterError e) {
            // Don't just log, rethrow the error so we can catch it in tests
            throw e;
          },
          assetLoader: const RootBundleAssetLoader(
            linkedFileResolver: JsonLinkedFileResolver(fileLoader: IOFileLoader()),
            fileLoader: IOFileLoader(),
          ),
        );

        try {
          await controller.loadTranslations();
          fail('Expected StateError to be thrown');
        } catch (e) {
          expect(e, isA<FlutterError>());
          expect(e.toString(), contains('Cyclic linked files detected'));
        }
      });

      test('should throw error for missing linked file', () async {
        final controller = EasyLocalizationController(
          forceLocale: const Locale('en', 'missing'),
          path: 'i18n',
          supportedLocales: const [Locale('en', 'missing')],
          useOnlyLangCode: false,
          useFallbackTranslations: false,
          saveLocale: false,
          onLoadError: (FlutterError e) {
            // Don't just log, rethrow the error so we can catch it in tests
            throw e;
          },
          assetLoader: const RootBundleAssetLoader(
            linkedFileResolver: JsonLinkedFileResolver(fileLoader: IOFileLoader()),
            fileLoader: IOFileLoader(),
          ),
        );

        try {
          await controller.loadTranslations();
          fail('Expected FlutterError to be thrown');
        } catch (e) {
          expect(e, isA<FlutterError>());
        }
      });
    });

    group('Edge cases for linked files', () {
      test('should work with useOnlyLangCode setting', () async {
        // Test with a simple locale using useOnlyLangCode
        final controller = EasyLocalizationController(
          forceLocale: const Locale('en'),
          path: 'i18n',
          supportedLocales: const [Locale('en')],
          useOnlyLangCode: true,
          useFallbackTranslations: false,
          saveLocale: false,
          onLoadError: (FlutterError e) {
            log(e.toString());
          },
          assetLoader: const RootBundleAssetLoader(
            linkedFileResolver: JsonLinkedFileResolver(fileLoader: IOFileLoader()),
            fileLoader: IOFileLoader(),
          ),
        );

        await controller.loadTranslations();
        final result = await controller.loadTranslationData(const Locale('en'));

        // Should successfully load the en.json file
        expect(result['test'], 'test_en');
        expect(result.containsKey('hats'), true);
        expect((result['hats'] as Map<String, dynamic>).containsKey('zero'), true);
      });
    });
  });
}

class _Files implements FileLoader {
  _Files(this.contents);
  final Map<String, Map<String, dynamic>> contents;
  final List<String> paths = [];

  @override
  Future<String> loadString(String path) async {
    paths.add(path);
    final content = contents[path];
    if (content == null) throw StateError('Missing $path');
    return json.encode(content);
  }
}

class _LegacyResolver extends LinkedFileResolver {
  _LegacyResolver(FileLoader files) : super(fileLoader: files);
  int calls = 0;

  @override
  Future<Map<String, dynamic>> resolveLinkedFiles({
    required String basePath,
    required String languageCode,
    required Map<String, dynamic> baseJson,
    Set<String>? visited,
    int depth = 0,
    String? scriptCode,
    String? countryCode,
  }) async {
    calls++;
    return baseJson;
  }
}

class _LegacyJsonResolver extends JsonLinkedFileResolver {
  _LegacyJsonResolver(FileLoader files) : super(fileLoader: files);
  int calls = 0;

  @override
  Future<Map<String, dynamic>> resolveLinkedFiles({
    required String basePath,
    required String languageCode,
    required Map<String, dynamic> baseJson,
    Set<String>? visited,
    int depth = 0,
    String? scriptCode,
    String? countryCode,
  }) {
    calls++;
    return super.resolveLinkedFiles(
      basePath: basePath,
      languageCode: languageCode,
      baseJson: baseJson,
      visited: visited,
      depth: depth,
      scriptCode: scriptCode,
      countryCode: countryCode,
    );
  }
}

class _TransformingLegacyJsonResolver extends JsonLinkedFileResolver {
  _TransformingLegacyJsonResolver(FileLoader files) : super(fileLoader: files);
  int calls = 0;

  @override
  Future<Map<String, dynamic>> resolveLinkedFiles({
    required String basePath,
    required String languageCode,
    required Map<String, dynamic> baseJson,
    Set<String>? visited,
    int depth = 0,
    String? scriptCode,
    String? countryCode,
  }) async {
    calls++;
    final resolved = await super.resolveLinkedFiles(
      basePath: basePath,
      languageCode: languageCode,
      baseJson: baseJson,
      visited: visited,
      depth: depth,
      scriptCode: scriptCode,
      countryCode: countryCode,
    );
    resolved['transformed'] = true;
    return resolved;
  }
}
