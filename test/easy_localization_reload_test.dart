import 'dart:async';

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MutableLoader extends AssetLoader {
  MutableLoader()
    : super(
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
        fileLoader: const RootBundleFileLoader(),
      );
  final data = <String, Map<String, dynamic>>{
    'en': {
      'value': 'Old',
      'removed': 'Remove',
      'nested': {'key': 'Nested old'},
    },
    'fr': {'value': 'French', 'removed': 'Fallback'},
  };
  final pending = <String, Completer<Map<String, dynamic>?>>{};

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) {
    final gate = pending.remove(locale.languageCode);
    return gate?.future ?? Future.value(data[locale.languageCode]);
  }
}

class TranslationView extends StatelessWidget {
  const TranslationView({super.key});

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.center,
    children: [Text(context.tr('value')), Text(context.tr('nested.key')), Text(context.tr('removed')), Text(context.tr('added'))],
  );
}

void main() {
  Future<void> mount(WidgetTester tester, MutableLoader loader, void Function(BuildContext) capture) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en'), Locale('fr')],
        startLocale: const Locale('en'),
        fallbackLocale: const Locale('fr'),
        useFallbackTranslations: true,
        path: 'unused',
        assetLoader: loader,
        child: Builder(
          builder: (context) => MaterialApp(
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: Builder(
              builder: (context) {
                capture(context);
                return const Scaffold(
                  body: Column(
                    mainAxisSize: MainAxisSize.max,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [TranslationView(), TranslationView(), TextField()],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('reload publishes new resources without losing screen state or writing locale', (tester) async {
    final loader = MutableLoader();
    late BuildContext context;
    await mount(tester, loader, (value) => context = value);
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(
          body: Column(
            mainAxisSize: MainAxisSize.max,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [TranslationView(), TranslationView(), TextField()],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Nested old'), findsNWidgets(2));
    await tester.enterText(find.byType(TextField), 'kept');
    loader.data['en'] = {
      'value': 'New',
      'added': 'Added',
      'nested': {'key': 'Nested new'},
    };
    await context.reloadTranslations();
    await tester.pumpAndSettle();
    expect(context.locale, const Locale('en'));
    expect(find.text('New'), findsNWidgets(2));
    expect(find.text('Nested new'), findsNWidgets(2));
    expect(find.text('Added'), findsNWidgets(2));
    expect(find.text('Fallback'), findsNWidgets(2));
    expect(find.text('kept'), findsOneWidget);
    expect(Navigator.of(context).canPop(), isTrue);
    expect((await SharedPreferences.getInstance()).getString('locale'), isNull);
  });

  for (final failingLocale in ['en', 'fr']) {
    testWidgets('reload preserves the full set on $failingLocale failure and retries', (tester) async {
      final loader = MutableLoader();
      late BuildContext context;
      await mount(tester, loader, (value) => context = value);
      loader.data['en'] = {'value': 'New'};
      final gate = Completer<Map<String, dynamic>?>();
      loader.pending[failingLocale] = gate;
      final reload = context.reloadTranslations();
      if (failingLocale == 'fr') await tester.idle();
      gate.completeError(StateError('failed'));
      await expectLater(reload, throwsA(isA<FlutterError>()));
      await tester.pump();
      expect(find.text('Old'), findsNWidgets(2));
      expect(find.text('Nested old'), findsNWidgets(2));
      await context.reloadTranslations();
      await tester.pumpAndSettle();
      expect(find.text('New'), findsNWidgets(2));
    });
  }

  testWidgets('later selection and disposal supersede reloads and their failures', (tester) async {
    final loader = MutableLoader();
    late BuildContext context;
    await mount(tester, loader, (value) => context = value);
    final old = Completer<Map<String, dynamic>?>();
    loader.pending['en'] = old;
    final reload = context.reloadTranslations();
    await context.setLocale(const Locale('fr'));
    old.completeError(StateError('late'));
    await reload;
    await tester.pumpAndSettle();
    expect(find.text('French'), findsNWidgets(2));
    expect(context.locale, const Locale('fr'));
    final late = Completer<Map<String, dynamic>?>();
    loader.pending['fr'] = late;
    final disposed = context.reloadTranslations();
    await tester.pumpWidget(const SizedBox());
    late.completeError(StateError('disposed'));
    await disposed;
    expect(tester.takeException(), isNull);
  });

  testWidgets('last reload wins and same-locale selection cancels pending reload', (tester) async {
    final loader = MutableLoader();
    late BuildContext context;
    await mount(tester, loader, (value) => context = value);
    final old = Completer<Map<String, dynamic>?>();
    loader.pending['en'] = old;
    final first = context.reloadTranslations();
    loader.data['en'] = {'value': 'Latest'};
    await context.reloadTranslations();
    old.complete({'value': 'Stale'});
    await first;
    await tester.pumpAndSettle();
    expect(find.text('Latest'), findsNWidgets(2));
    final cancelled = Completer<Map<String, dynamic>?>();
    loader.pending['en'] = cancelled;
    final pending = context.reloadTranslations();
    await context.setLocale(const Locale('en'));
    cancelled.complete({'value': 'Cancelled'});
    await pending;
    await tester.pumpAndSettle();
    expect(find.text('Latest'), findsNWidgets(2));
  });
}
