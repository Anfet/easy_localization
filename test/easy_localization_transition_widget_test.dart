import 'dart:async';
import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class Loader extends AssetLoader {
  Loader();
  final requests = <String, Completer<Map<String, dynamic>?>>{};
  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => requests.putIfAbsent(locale.languageCode, () => Completer()).future;
}

class Store extends SharedPreferencesStorePlatform {
  final gate = Completer<bool>();
  var writes = 0;
  @override
  Future<Map<String, Object>> getAll() async => {};
  @override
  Future<bool> setValue(String valueType, String key, Object value) => ++writes == 1 ? Future.value(true) : gate.future;
  @override
  Future<bool> remove(String key) async => true;
  @override
  Future<bool> clear() async => true;
}

void main() {
  for (final initialFirst in [true, false]) {
    testWidgets('explicit choice ${initialFirst ? 'before' : 'after'} attachment retains selected resources', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      final loader = Loader();
      final initialization = EasyLocalization.initialize(
        EasyLocalizationConfig(
          supportedLocales: const [Locale('en'), Locale('de')],
          fallbackLocale: const Locale('en'),
          startLocale: const Locale('en'),
          path: 'unused',
          assetLoader: loader,
        ),
      );
      await tester.idle();
      loader.requests['en']!.complete({'value': 'English'});
      final owner = await initialization;
      addTearDown(owner.dispose);
      late BuildContext context;
      final selection = owner.setLocale(const Locale('de'));
      await tester.idle();
      if (initialFirst) {
        loader.requests['de']!.complete({'value': 'Deutsch'});
        await selection;
      }
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('de')],
          startLocale: const Locale('en'),
          path: 'unused',
          assetLoader: loader,
          child: Builder(
            builder: (c) => MaterialApp(
              locale: c.locale,
              supportedLocales: c.supportedLocales,
              localizationsDelegates: c.localizationDelegates,
              home: Builder(
                builder: (c) {
                  context = c;
                  return Text(c.tr('value'));
                },
              ),
            ),
          ),
        ),
      );
      if (!initialFirst) loader.requests['de']!.complete({'value': 'Deutsch'});
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
    await tester.pumpWidget(
      EasyLocalization(
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
            home: Builder(
              builder: (c) {
                context = c;
                return Text(c.tr('value'));
              },
            ),
          ),
        ),
      ),
    );
    await tester.idle();
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
    await expectLater(change, throwsA(isA<StateError>()));
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
    final pendingResult = expectLater(pending, throwsA(isA<StateError>()));
    await tester.pumpWidget(const SizedBox());
    loader.requests['en']!.completeError(StateError('late'));
    await pendingResult;
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
      await tester.pumpWidget(
        EasyLocalization(
          supportedLocales: const [Locale('en'), Locale('de')],
          startLocale: const Locale('en'),
          path: 'unused',
          assetLoader: loader,
          child: Builder(
            builder: (c) => MaterialApp(
              locale: c.locale,
              supportedLocales: c.supportedLocales,
              localizationsDelegates: c.localizationDelegates,
              home: Builder(
                builder: (c) {
                  context = c;
                  return Text(c.tr('value'));
                },
              ),
            ),
          ),
        ),
      );
      await tester.idle();
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
