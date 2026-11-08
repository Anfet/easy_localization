import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/easy_localization_controller.dart';
import 'package:easy_localization/src/file_loaders/file_loader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_asset_loaders.dart';

class FailingLoader extends AssetLoader {
  FailingLoader(this.error, this.stackTrace)
    : super(
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
        fileLoader: const RootBundleFileLoader(),
      );

  final Object error;
  final StackTrace stackTrace;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.error(error, stackTrace);
}

class ConstantFileLoader implements FileLoader {
  const ConstantFileLoader();

  @override
  Future<String> loadString(String path) async => '{"value":"loaded"}';
}

class MissingBaseLoader extends AssetLoader {
  const MissingBaseLoader()
    : super(
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
        fileLoader: const RootBundleFileLoader(),
      );

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    if (locale == const Locale('en')) throw FlutterError('missing base');
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() {
    EasyLocalization.onVerbose = null;
    EasyLocalization.onWarning = null;
    EasyLocalization.onError = null;
  });

  EasyLocalizationController controller(AssetLoader loader, void Function(FlutterError) onLoadError, {List<AssetLoader>? extraLoaders}) =>
      EasyLocalizationController(
        forceLocale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        path: 'path',
        useOnlyLangCode: false,
        useFallbackTranslations: false,
        saveLocale: false,
        assetLoader: loader,
        extraAssetLoaders: extraLoaders,
        onLoadError: onLoadError,
      );

  testWidgets('default diagnostics do not print during initialization, widget loading or missing key', (tester) async {
    final output = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) output.add(message);
    };
    try {
      await runZoned(() async {
        await EasyLocalization.ensureInitialized();
        await tester.pumpWidget(
          EasyLocalization(path: 'path', supportedLocales: const [Locale('en')], assetLoader: const JsonAssetLoader(), child: const SizedBox()),
        );
        await tester.pump();
        final loaded = controller(const JsonAssetLoader(), (_) {});
        await loaded.loadTranslations();
        Localization.load(const Locale('en'), translations: loaded.translations);
        Localization.instance.tr('absent');
      }, zoneSpecification: ZoneSpecification(print: (self, parent, zone, message) => output.add(message)));
    } finally {
      debugPrint = previousDebugPrint;
    }
    expect(output, isEmpty);
  });

  test('independent callbacks receive messages and original resource stack', () async {
    final verbose = <String>[];
    final warnings = <String>[];
    final errors = <String>[];
    final stack = StackTrace.fromString('original stack');
    StackTrace? receivedStack;
    var loadErrors = 0;
    EasyLocalization.onVerbose = (message, {stackTrace}) => verbose.add(message);
    EasyLocalization.onWarning = (message, {stackTrace}) => warnings.add(message);
    EasyLocalization.onError = (message, {stackTrace}) {
      errors.add(message);
      receivedStack = stackTrace;
    };
    await EasyLocalization.ensureInitialized();
    final loaded = controller(const JsonAssetLoader(), (_) {});
    await loaded.loadTranslations();
    Localization.load(const Locale('en'), translations: loaded.translations);
    Localization.instance.tr('absent');
    await controller(FailingLoader(StateError('resource failed'), stack), (_) => loadErrors++).loadTranslations();
    expect(verbose, contains('Localization initialized'));
    expect(warnings, contains('Localization key [absent] not found'));
    expect(errors.single, contains('resource failed'));
    expect(receivedStack, same(stack));
    expect(loadErrors, 1);
    EasyLocalization.onVerbose = null;
    Localization.instance.tr('still absent');
    expect(warnings.last, contains('still absent'));
  });

  test('callback exceptions are reported without changing resource results', () async {
    final callbackError = StateError('callback failed');
    final reported = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    try {
      EasyLocalization.onVerbose = (message, {stackTrace}) => throw callbackError;
      final loaded = controller(
        const RootBundleAssetLoader(
          linkedFileResolver: JsonLinkedFileResolver(fileLoader: ConstantFileLoader()),
          fileLoader: ConstantFileLoader(),
        ),
        (_) {},
      );
      await expectLater(loaded.loadTranslations(), completes);
      expect(loaded.translations, isNotNull);
      expect(reported, hasLength(1));
      expect(reported.single.exception, same(callbackError));
      expect(reported.single.library, 'easy_localization');
    } finally {
      FlutterError.onError = previousHandler;
    }
  });

  test('error callback failure is reported and onLoadError still runs once', () async {
    final callbackError = StateError('callback failed');
    final reported = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    var loadErrors = 0;
    EasyLocalization.onError = (message, {stackTrace}) => throw callbackError;
    try {
      final resourceError = StateError('resource failed');
      final loaded = EasyLocalizationController(
        forceLocale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        path: 'path',
        useOnlyLangCode: false,
        useFallbackTranslations: false,
        saveLocale: false,
        assetLoader: FailingLoader(resourceError, StackTrace.current),
        onLoadError: (_) => loadErrors++,
        strictErrors: true,
      );
      await expectLater(loaded.loadTranslations(), throwsA(same(resourceError)));
      loaded.dispose();
      expect(loadErrors, 1);
      expect(reported, hasLength(1));
      expect(reported.single.exception, same(callbackError));
    } finally {
      FlutterError.onError = previousHandler;
    }
  });

  test('verbose and warning callback exceptions are reported without escaping', () async {
    final callbackError = StateError('callback failed');
    final reported = <FlutterErrorDetails>[];
    final previousHandler = FlutterError.onError;
    FlutterError.onError = reported.add;
    EasyLocalization.onVerbose = (message, {stackTrace}) => throw callbackError;
    try {
      await expectLater(controller(RootBundleAssetLoader.fromRootBundle(), (_) {}).loadTranslations(), completes);
      EasyLocalization.onVerbose = null;
      EasyLocalization.onWarning = (message, {stackTrace}) => throw callbackError;
      await expectLater(
        EasyLocalizationController(
          forceLocale: const Locale('en', 'US'),
          supportedLocales: const [Locale('en', 'US')],
          path: 'path',
          useOnlyLangCode: false,
          useFallbackTranslations: true,
          fallbackLocale: const Locale('fr'),
          saveLocale: false,
          assetLoader: const MissingBaseLoader(),
          onLoadError: (_) {},
        ).loadTranslations(),
        completes,
      );
      expect(reported, hasLength(2));
      expect(reported.map((details) => details.exception), everyElement(same(callbackError)));
    } finally {
      FlutterError.onError = previousHandler;
    }
  });
}
