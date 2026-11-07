import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization/src/easy_localization_controller.dart';
import 'package:easy_localization/src/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'utils/test_asset_loaders.dart';

class FailingLoader extends AssetLoader {
  FailingLoader(this.error, this.stackTrace)
      : super(linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()), fileLoader: const RootBundleFileLoader());

  final Object error;
  final StackTrace stackTrace;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.error(error, stackTrace);
}

class MissingBaseLoader extends AssetLoader {
  const MissingBaseLoader()
      : super(linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()), fileLoader: const RootBundleFileLoader());

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

  EasyLocalizationController controller(AssetLoader loader, void Function(FlutterError) onLoadError) => EasyLocalizationController(
        forceLocale: const Locale('en'),
        supportedLocales: const [Locale('en')],
        path: 'path',
        useOnlyLangCode: false,
        useFallbackTranslations: false,
        saveLocale: false,
        assetLoader: loader,
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
            EasyLocalization(path: 'path', supportedLocales: const [Locale('en')], assetLoader: const JsonAssetLoader(), child: const SizedBox()));
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

  test('throwing error callback propagates and still calls onLoadError once', () async {
    final callbackError = StateError('callback failed');
    var errors = 0;
    var loadErrors = 0;
    EasyLocalization.onError = (message, {stackTrace}) {
      errors++;
      throw callbackError;
    };
    await expectLater(controller(FailingLoader(StateError('resource failed'), StackTrace.current), (_) => loadErrors++).loadTranslations(),
        throwsA(same(callbackError)));
    expect(errors, 1);
    expect(loadErrors, 1);
  });
  test('verbose and warning callback exceptions propagate in the caller zone', () async {
    final callbackError = StateError('callback failed');
    var errors = 0;
    var loadErrors = 0;
    final callerZone = Zone.current;
    EasyLocalization.onError = (message, {stackTrace}) => errors++;
    EasyLocalization.onVerbose = (message, {stackTrace}) {
      expect(Zone.current, same(callerZone));
      throw callbackError;
    };
    await expectLater(controller(RootBundleAssetLoader.fromRootBundle(), (_) => loadErrors++).loadTranslations(), throwsA(same(callbackError)));
    EasyLocalization.onVerbose = null;
    EasyLocalization.onWarning = (message, {stackTrace}) {
      expect(Zone.current, same(callerZone));
      throw callbackError;
    };
    final fallback = EasyLocalizationController(
      forceLocale: const Locale('en', 'US'),
      supportedLocales: const [Locale('en', 'US')],
      path: 'path',
      useOnlyLangCode: false,
      useFallbackTranslations: true,
      fallbackLocale: const Locale('fr'),
      saveLocale: false,
      assetLoader: const MissingBaseLoader(),
      onLoadError: (_) => loadErrors++,
    );
    await expectLater(fallback.loadTranslations(), throwsA(same(callbackError)));
    expect(errors, 0);
    expect(loadErrors, 0);
  });
}
