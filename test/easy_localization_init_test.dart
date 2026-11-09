import 'dart:async';

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'easy_localization_context_test.dart';
import 'easy_localization_instance_test.dart' show InstanceLoader;
import 'utils/test_asset_loaders.dart';

Future<void> main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  await EasyLocalization.ensureInitialized();

  testWidgets('Ensure that loading the translations will update its depending widgets', (WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('de')],
          path: '../../i18n',
          fallbackLocale: const Locale('en'),
          child: const I18nObserver(child: MyApp()),
        ),
      );
      await tester.pump();
    });
  });

  testWidgets('borrowed owner survives detach and remount while legacy-owned owner is disposed', (tester) async {
    final loader = InstanceLoader();
    final config = EasyLocalizationConfig(
      supportedLocales: const [Locale('en'), Locale('de')],
      fallbackLocale: const Locale('en'),
      path: 'unused',
      saveLocale: false,
      assetLoader: loader,
    );
    final owner = await EasyLocalization.initialize(config);
    Widget root() => EasyLocalization.withInstance(instance: owner, child: const SizedBox());
    await tester.pumpWidget(root());
    final gate = Completer<Map<String, dynamic>?>();
    loader.gates['de'] = [gate];
    final changing = owner.setLocale(const Locale('de'));
    await tester.pumpWidget(const SizedBox());
    gate.complete({'value': 'de'});
    await changing;

    expect(EasyLocalization.instance, same(owner));
    await tester.pumpWidget(root());
    expect(owner.locale, const Locale('de'));
    await tester.pumpWidget(const SizedBox());
    owner.dispose();

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'unused',
        saveLocale: false,
        assetLoader: const ImmutableJsonAssetLoader(),
        child: const MyApp(),
      ),
    );
    await tester.pump();
    final legacy = EasyLocalization.instance;
    final snapshot = legacy.dataTranslator;
    await tester.pumpWidget(const SizedBox());
    expect(() => EasyLocalization.instance, throwsStateError);
    expect(() => legacy.setLocale(const Locale('en')), throwsStateError);
    expect(snapshot.tr('test'), 'test');
  });

  testWidgets('legacy root remounts while the previous bootstrap is loading', (tester) async {
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
    addTearDown(tester.binding.platformDispatcher.clearLocalesTestValue);
    final loader = InstanceLoader();
    final gate = Completer<Map<String, dynamic>?>();
    loader.gates['en'] = [gate];
    Widget root() => EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('de')],
      path: 'unused',
      saveLocale: false,
      assetLoader: loader,
      child: MaterialApp(home: Builder(builder: (_) => Text(tr('value')))),
    );

    await tester.pumpWidget(root());
    await tester.pump();
    expect(loader.calls, [const Locale('en')]);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(root());
    expect(tester.takeException(), isNull);
    gate.complete({'value': 'loaded'});
    await tester.pumpAndSettle();
    expect(find.text('en'), findsOneWidget);
    final owner = EasyLocalization.instance;
    await tester.pumpWidget(const SizedBox());
    expect(() => EasyLocalization.instance, throwsStateError);
    expect(() => owner.setLocale(const Locale('en')), throwsStateError);
    final callsAfterDispose = loader.calls.length;
    tester.binding.platformDispatcher.localesTestValue = const [Locale('de')];
    await tester.pumpAndSettle();
    expect(loader.calls.length, callsAfterDispose);
  });

  testWidgets('legacy and borrowed roots select the same saved language', (tester) async {
    SharedPreferences.setMockInitialValues({'locale': 'de'});
    final loader = InstanceLoader();
    final config = EasyLocalizationConfig(
      supportedLocales: const [Locale('en'), Locale('de')],
      fallbackLocale: const Locale('en'),
      path: 'unused',
      assetLoader: loader,
    );
    final owner = await EasyLocalization.initialize(config);
    await tester.pumpWidget(EasyLocalization.withInstance(instance: owner, child: const SizedBox()));
    expect(owner.locale, const Locale('de'));
    await tester.pumpWidget(const SizedBox());
    owner.dispose();
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: config.supportedLocales,
        fallbackLocale: config.fallbackLocale,
        path: config.path,
        assetLoader: loader,
        child: const SizedBox(),
      ),
    );
    await tester.pumpAndSettle();
    expect(EasyLocalization.instance.locale, const Locale('de'));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('matching legacy root borrows ready owner and incompatible root is rejected', (tester) async {
    final config = EasyLocalizationConfig(
      supportedLocales: const [Locale('en'), Locale('de')],
      fallbackLocale: const Locale('en'),
      path: 'unused',
      startLocale: const Locale('de'),
      saveLocale: false,
      assetLoader: const ImmutableJsonAssetLoader(),
    );
    final owner = await EasyLocalization.initialize(config);
    try {
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: config.supportedLocales,
          fallbackLocale: config.fallbackLocale,
          path: config.path,
          startLocale: config.startLocale,
          saveLocale: config.saveLocale,
          useBaseLanguageFallback: config.useBaseLanguageFallback,
          assetLoader: config.assetLoader,
          child: const SizedBox(),
        ),
      );
      await tester.pumpWidget(const SizedBox());
      expect(EasyLocalization.instance, same(owner));
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('de'), Locale('en')],
          fallbackLocale: config.fallbackLocale,
          path: config.path,
          startLocale: config.startLocale,
          saveLocale: config.saveLocale,
          useBaseLanguageFallback: config.useBaseLanguageFallback,
          assetLoader: config.assetLoader,
          child: const SizedBox(),
        ),
      );
      expect(tester.takeException(), isA<StateError>());
      await tester.pumpWidget(const SizedBox());
      await owner.setLocale(const Locale('en'));
    } finally {
      await tester.pumpWidget(const SizedBox());
      owner.dispose();
    }
  });

  testWidgets('a second presentation root is rejected without detaching the first', (tester) async {
    final owner = await EasyLocalization.initialize(
      EasyLocalizationConfig(
        supportedLocales: const [Locale('en')],
        fallbackLocale: const Locale('en'),
        path: 'unused',
        saveLocale: false,
        assetLoader: const ImmutableJsonAssetLoader(),
      ),
    );
    try {
      await tester.pumpWidget(
        EasyLocalization.withInstance(
          instance: owner,
          child: EasyLocalization.withInstance(instance: owner, child: const SizedBox()),
        ),
      );
      expect(tester.takeException(), isA<StateError>());
      await tester.pumpWidget(const SizedBox());
      await owner.reloadTranslations();
      await tester.pumpWidget(EasyLocalization.withInstance(instance: owner, child: const SizedBox()));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      owner.dispose();
    }
  });
}

class I18nObserver extends StatefulWidget {
  final Widget child;

  const I18nObserver({super.key, required this.child});

  @override
  State<I18nObserver> createState() => _I18nObserverState();
}

class _I18nObserverState extends State<I18nObserver> {
  var _firstUpdate = true;

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void didChangeDependencies() {
    // use the dependOnInheritedWidgetOfExactType pattern
    EasyLocalization.of(context);

    super.didChangeDependencies();

    if (_firstUpdate) {
      _firstUpdate = false;
      expect(() => 'test'.tr(), throwsStateError, reason: 'Translations are unavailable until the legacy root has loaded');
    } else {
      expect(
        'test'.tr(),
        'test_en',
        reason:
            'The translation should be loaded on the second call '
            'of didChangeDependencies()',
      );
    }
  }
}
