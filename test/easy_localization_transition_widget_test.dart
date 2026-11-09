import 'dart:async';
import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class Loader extends AssetLoader {
  Loader() : super(linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()), fileLoader: const RootBundleFileLoader());
  final requests = <String, Completer<Map<String, dynamic>?>>{};
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => requests.putIfAbsent(locale.languageCode, () => Completer()).future;
}

class Store extends SharedPreferencesStorePlatform {
  final gate = Completer<bool>();
  @override
  Future<Map<String, Object>> getAll() async => {};
  @override
  Future<bool> setValue(String valueType, String key, Object value) => gate.future;
  @override
  Future<bool> remove(String key) async => true;
  @override
  Future<bool> clear() async => true;
}

void main() {
  for (final initialFirst in [true, false]) {
    testWidgets('explicit choice before delegate load survives ${initialFirst ? 'initial' : 'selected'} resource completing first', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      final loader = Loader();
      Future<void>? selection;
      late BuildContext context;
      await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('de')],
        startLocale: const Locale('en'),
        path: 'unused',
        assetLoader: loader,
        child: Builder(builder: (c) {
          return MaterialApp(
              locale: c.locale,
              supportedLocales: c.supportedLocales,
              localizationsDelegates: c.localizationDelegates,
              home: Builder(builder: (c) {
                context = c;
                return Text(c.tr('value'));
              }));
        }),
      ));
      selection = tester.element(find.byType(SizedBox)).setLocale(const Locale('de'));
      if (initialFirst) {
        loader.requests['en']!.complete({'value': 'English'});
        await tester.pump();
        loader.requests['de']!.complete({'value': 'Deutsch'});
      } else {
        loader.requests['de']!.complete({'value': 'Deutsch'});
        await tester.pump();
        loader.requests['en']!.complete({'value': 'English'});
      }
      await selection;
      await tester.pumpAndSettle();
      expect(context.locale, const Locale('de'));
      expect(context.savedLocale, const Locale('de'));
      expect(find.text('Deutsch'), findsOneWidget);
      expect((await SharedPreferences.getInstance()).getString('locale'), 'de');
    });
  }

  testWidgets('transition waits for loading, retains state on failure, and ignores disposal', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    final loader = Loader();
    late BuildContext context;
    await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('de')],
        startLocale: const Locale('en'),
        saveLocale: false,
        path: 'unused',
        assetLoader: loader,
        child: Builder(
            builder: (c) => MaterialApp(
                locale: c.locale,
                supportedLocales: c.supportedLocales,
                localizationsDelegates: c.localizationDelegates,
                home: Builder(builder: (c) {
                  context = c;
                  return Text(c.tr('value'));
                })))));
    loader.requests['en']!.complete({'value': 'English'});
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    var completed = false;
    final change = context.setLocale(const Locale('de')).then((_) {
      completed = true;
    });
    await tester.pump();
    expect(completed, false);
    loader.requests['de']!.completeError(StateError('bad'));
    await expectLater(change, throwsA(isA<FlutterError>()));
    await tester.pump();
    expect(find.text('English'), findsOneWidget);
    loader.requests.remove('de');
    final retry = context.setLocale(const Locale('de'));
    loader.requests['de']!.complete({'value': 'Deutsch'});
    await retry;
    await tester.pumpAndSettle();
    expect(find.text('Deutsch'), findsOneWidget);
    expect(context.locale, const Locale('de'));
    loader.requests.remove('en');
    final pending = context.setLocale(const Locale('en'));
    await tester.pumpWidget(const SizedBox());
    loader.requests['en']!.completeError(StateError('late'));
    await pending;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
  testWidgets('context future waits for storage without waiting for a frame', (tester) async {
    final original = SharedPreferencesStorePlatform.instance;
    final store = Store();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    try {
      await EasyLocalization.ensureInitialized();
      final loader = Loader();
      late BuildContext context;
      await tester.pumpWidget(EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('de')],
        startLocale: const Locale('en'),
        path: 'unused',
        assetLoader: loader,
        child: Builder(
            builder: (c) => MaterialApp(
                locale: c.locale,
                supportedLocales: c.supportedLocales,
                localizationsDelegates: c.localizationDelegates,
                home: Builder(builder: (c) {
                  context = c;
                  return Text(c.tr('value'));
                }))),
      ));
      loader.requests['en']!.complete({'value': 'English'});
      await tester.pumpAndSettle();
      var done = false;
      final change = context.setLocale(const Locale('de')).then((_) {
        done = true;
      });
      loader.requests['de']!.complete({'value': 'Deutsch'});
      await tester.idle();
      expect(done, false);
      store.gate.complete(true);
      await change;
      expect(done, true);
      await tester.pumpAndSettle();
      expect(find.text('Deutsch'), findsOneWidget);
      await tester.runAsync(() => EasyLocalization.ensureInitialized());
    } finally {
      SharedPreferencesStorePlatform.instance = original;
      SharedPreferences.resetStatic();
    }
  });
}
