import 'dart:async';
import 'dart:developer';

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:easy_localization_continued/src/easy_localization_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'utils/test_asset_loaders.dart';

class CallbackLoader extends AssetLoader {
  CallbackLoader(this.callback)
    : super(
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
        fileLoader: const RootBundleFileLoader(),
      );

  final Future<Map<String, dynamic>?> Function() callback;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => callback();
}

void main() {
  group('ExtraAssetLoaders', () {
    for (final syncPrimary in [false, true]) {
      test('handles synchronous and late failures with syncPrimary=$syncPrimary', () async {
        final unhandled = <Object>[];
        final finished = Completer<void>();
        runZonedGuarded(
          () async {
            final gate = Completer<Map<String, dynamic>?>();
            final syncError = StateError('synchronous failure');
            final lateError = StateError('late failure');
            var failing = true;
            final syncLoader = CallbackLoader(() {
              if (failing) throw syncError;
              return Future.value({'sync': 'ok'});
            });
            final lateLoader = CallbackLoader(() => failing ? gate.future : Future.value({'late': 'ok'}));
            final controller = EasyLocalizationController(
              forceLocale: const Locale('en'),
              path: 'unused',
              supportedLocales: const [Locale('en')],
              useOnlyLangCode: false,
              useFallbackTranslations: false,
              saveLocale: false,
              onLoadError: (_) {},
              assetLoader: syncPrimary ? syncLoader : lateLoader,
              extraAssetLoaders: [syncPrimary ? lateLoader : syncLoader],
            );
            final command = controller.loadTranslationData(const Locale('en'));
            final result = command.then<Object?>((_) => null, onError: (Object error, StackTrace stack) => error);
            await Future<void>.delayed(Duration.zero);
            expect(await result, same(syncError));
            gate.completeError(lateError);
            await Future<void>.delayed(Duration.zero);
            expect(unhandled, isEmpty);
            failing = false;
            expect(await controller.loadTranslationData(const Locale('en')), {'sync': 'ok', 'late': 'ok'});
            controller.dispose();
            finished.complete();
          },
          (error, stack) {
            unhandled.add(error);
            if (!finished.isCompleted) finished.completeError(error, stack);
          },
        );
        await finished.future;
      });
    }

    test('preserves the single loader error and stack', () async {
      final error = StateError('loader failure');
      final stack = StackTrace.fromString('original loader stack');
      final controller = EasyLocalizationController(
        forceLocale: const Locale('en'),
        path: 'unused',
        supportedLocales: const [Locale('en')],
        useOnlyLangCode: false,
        useFallbackTranslations: false,
        saveLocale: false,
        onLoadError: (_) {},
        assetLoader: CallbackLoader(() => Future.error(error, stack)),
        extraAssetLoaders: [
          CallbackLoader(() => Future.value({'extra': 'ok'})),
        ],
      );
      try {
        await controller.loadTranslationData(const Locale('en'));
        fail('Expected loader failure');
      } catch (caught, trace) {
        expect(caught, same(error));
        expect(trace.toString(), contains('original loader stack'));
      }
      controller.dispose();
    });
    test('should work normal if no extraAssetLoaders is provided', () async {
      final EasyLocalizationController controller = EasyLocalizationController(
        forceLocale: const Locale('en'),
        path: 'path/en.json',
        supportedLocales: const [Locale('en')],
        useOnlyLangCode: true,
        useFallbackTranslations: false,
        saveLocale: false,
        onLoadError: (FlutterError e) {
          log(e.toString());
        },
        assetLoader: const ImmutableJsonAssetLoader(),
        extraAssetLoaders: null,
      );

      var result = await controller.loadTranslationData(const Locale('en'));

      expect(result, {'test': 'test'});
      expect(result.entries.length, 1);
    });

    test('load assets from external loader and merge with asset loader', () async {
      final EasyLocalizationController controller = EasyLocalizationController(
        forceLocale: const Locale('en'),
        path: 'path/en.json',
        supportedLocales: const [Locale('en')],
        useOnlyLangCode: true,
        useFallbackTranslations: false,
        saveLocale: false,
        onLoadError: (FlutterError e) {
          log(e.toString());
        },
        assetLoader: const ImmutableJsonAssetLoader(),
        extraAssetLoaders: [ExternalAssetLoader()],
      );

      final Map<String, dynamic> result = await controller.loadTranslationData(const Locale('en'));

      expect(result, {
        'test': 'test',
        'package_value_01': 'package_value_01',
        'package_value_02': 'package_value_02',
        'package_value_03': 'package_value_03',
      });
      expect(result.entries.length, 4);
    });

    test('load assets from external loader with nested translations and merge with asset loader', () async {
      final EasyLocalizationController controller = EasyLocalizationController(
        forceLocale: const Locale('en'),
        path: 'path/en.json',
        supportedLocales: const [Locale('en')],
        useOnlyLangCode: true,
        useFallbackTranslations: false,
        saveLocale: false,
        onLoadError: (FlutterError e) {
          log(e.toString());
        },
        assetLoader: const ImmutableJsonAssetLoader(),
        extraAssetLoaders: [NestedAssetLoader()],
      );

      final Map<String, dynamic> result = await controller.loadTranslationData(const Locale('en'));

      expect(result, {
        'test': 'test',
        'nested': {
          'super': {
            'duper': {'nested': 'nested.super.duper.nested'},
          },
        },
      });
      expect(result.entries.length, 2);
    });

    test('load assets from external loader and merge duplicates with asset loader', () async {
      final EasyLocalizationController controller = EasyLocalizationController(
        forceLocale: const Locale('en'),
        path: 'path/en.json',
        supportedLocales: const [Locale('en')],
        useOnlyLangCode: true,
        useFallbackTranslations: false,
        saveLocale: false,
        onLoadError: (FlutterError e) {
          log(e.toString());
        },
        assetLoader: const ImmutableJsonAssetLoader(),
        extraAssetLoaders: [const ImmutableJsonAssetLoader()],
      );

      final Map<String, dynamic> result = await controller.loadTranslationData(const Locale('en'));

      expect(result, {'test': 'test'});
      expect(result.entries.length, 1);
    });
  });
}
