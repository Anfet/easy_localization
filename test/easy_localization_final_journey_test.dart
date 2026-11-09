import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ready owner keeps retained UI and document consistent through changes, failures and reset', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
    final loader = _Loader();
    final extra = _Extra();
    final delegate = _Delegate();
    final instance = await EasyLocalization.initialize(
      EasyLocalizationConfig(
        supportedLocales: const [Locale('en'), Locale('de'), Locale('ar')],
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        path: 'unused',
        saveLocale: true,
        assetLoader: loader,
        extraAssetLoaders: [extra],
        additionalDelegates: [delegate],
      ),
    );
    final document = await instance.translator(const Locale('de'));
    final initial = instance.dataTranslator;
    final navigator = GlobalKey<NavigatorState>();
    final page = GlobalKey<_PageState>();
    final scroll = ScrollController();
    final focus = FocusNode();
    final input = TextEditingController();
    try {
      await tester.pumpWidget(
        EasyLocalization.withInstance(
          instance: instance,
          child: _App(
            navigator: navigator,
            home: _Page(key: page, scroll: scroll, focus: focus, input: input),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final retained = page.currentState;
      await tester.enterText(find.byType(TextField), 'retained input');
      focus.requestFocus();
      scroll.jumpTo(100);
      await tester.pump();
      navigator.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: _Leaf(label: 'route')),
        ),
      );
      await tester.pumpAndSettle();
      showDialog<void>(
        context: tester.element(find.text('en-v1 route')),
        builder: (_) => const Dialog(child: _Leaf(label: 'dialog')),
      );
      await tester.pumpAndSettle();
      var elements = 0;
      void count(Element element) {
        elements++;
        element.visitChildren(count);
      }

      tester.element(find.byType(EasyLocalization)).visitChildren(count);
      expect(elements, greaterThan(0));
      final gate = Completer<_Resource>();
      delegate.gate = gate;
      final change = instance.setLocale(const Locale('ar'));
      await change;
      final changePresentation = instance.waitForPresentation();
      await tester.pump();
      expect(instance.dataTranslator.tr('value'), 'ar-v1');
      expect(tr('value'), 'en-v1');
      expect(find.text('en-v1 dialog'), findsOneWidget);
      final oldResources = tester.element(find.text('en-v1 dialog'));
      expect(Localizations.localeOf(oldResources), const Locale('en'));
      expect(Directionality.of(oldResources), ui.TextDirection.ltr);
      expect(MaterialLocalizations.of(oldResources).cancelButtonLabel, 'Cancel');
      expect(CupertinoLocalizations.of(oldResources).copyButtonLabel, isNotEmpty);
      expect(Localizations.of<_Resource>(oldResources, _Resource)?.locale, const Locale('en'));
      gate.complete(const _Resource(Locale('ar')));
      await tester.pumpAndSettle();
      expect(await changePresentation, LocalizationApplyOutcome.applied);

      expect(find.text('ar-v1 dialog'), findsOneWidget);
      expect(find.text('ar-v1 route', skipOffstage: false), findsOneWidget);
      expect(find.text('ar-v1 home', skipOffstage: false), findsOneWidget);
      final resources = tester.element(find.text('ar-v1 dialog'));
      expect(Directionality.of(resources), ui.TextDirection.rtl);
      expect(MaterialLocalizations.of(resources).cancelButtonLabel, isNot('Cancel'));
      expect(CupertinoLocalizations.of(resources).copyButtonLabel, isNotEmpty);
      expect(Localizations.of<_Resource>(resources, _Resource)?.locale, const Locale('ar'));
      expect(page.currentState, same(retained));
      expect(input.text, 'retained input');
      expect(scroll.offset, 100);
      delegate.gate = null;
      loader.version = 2;
      extra.version = 2;
      final before = _Leaf.builds;
      final reload = instance.reloadTranslations();
      await reload;
      final reloadPresentation = instance.waitForPresentation();
      await tester.pumpAndSettle();
      expect(await reloadPresentation, LocalizationApplyOutcome.applied);

      expect(_Leaf.builds - before, 3);
      expect(find.text('ar-v2 dialog'), findsOneWidget);
      expect(find.text('ar-v2 route', skipOffstage: false), findsOneWidget);
      expect(find.text('ar-v2 home', skipOffstage: false), findsOneWidget);
      expect(tr('nested.message', namedArgs: {'name': r'$1\x'}), r'ar-extra2 $1\x');
      expect(tr('nested.base'), 'ar-base2');
      expect(page.currentState, same(retained));
      expect(input.text, 'retained input');
      expect(scroll.offset, 100);
      navigator.currentState?.pop();
      await tester.pumpAndSettle();
      navigator.currentState?.pop();
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      expect(tester.widget<TextField>(find.byType(TextField)).decoration?.hintText, 'ar-v2 hint');
      expect(find.text('ar-v2 button'), findsOneWidget);
      final focusedBefore = _Leaf.builds;
      final focusedReload = instance.reloadTranslations();
      await focusedReload;
      final focusedReloadPresentation = instance.waitForPresentation();
      await tester.pumpAndSettle();
      expect(await focusedReloadPresentation, LocalizationApplyOutcome.applied);
      expect(_Leaf.builds - focusedBefore, 1);
      expect(focus.hasFocus, isTrue);
      loader.lastMap?['value'] = 'mutated';
      final nested = loader.lastMap?['nested'] as Map<String, dynamic>;
      nested['base'] = 'mutated';
      expect(tr('nested.base'), 'ar-base2');
      expect(initial.tr('value'), 'en-v1');
      expect(document.tr('value'), 'de-v1');
      expect(instance.dataTranslator.tr('value'), 'ar-v2');
      final lateGate = Completer<Map<String, dynamic>>();
      loader.gate = lateGate;
      final late = instance.reloadTranslations();
      final cancelled = expectLater(late, throwsA(isA<LocalizationOperationSupersededException>()));
      loader.gate = null;
      final de = instance.setLocale(const Locale('de'));
      await de;
      final dePresentation = instance.waitForPresentation();
      await tester.pumpAndSettle();
      expect(await dePresentation, LocalizationApplyOutcome.applied);
      lateGate.complete({'value': 'late'});
      await cancelled;
      await tester.pumpAndSettle();
      expect(find.text('de-v2 home'), findsOneWidget);
      loader.fail = true;
      final failed = instance.reloadTranslations();
      await expectLater(failed, throwsA(isA<StateError>()));

      expect(find.text('de-v2 home'), findsOneWidget);
      expect(page.currentState, same(retained));
      loader.fail = false;
      loader.version = 3;
      final retry = instance.reloadTranslations();
      await retry;
      final retryPresentation = instance.waitForPresentation();
      await tester.pumpAndSettle();
      expect(await retryPresentation, LocalizationApplyOutcome.applied);
      expect(find.text('de-v3 home'), findsOneWidget);
      tester.binding.platformDispatcher.localesTestValue = const [Locale('fr'), Locale('ar')];
      await tester.pumpAndSettle();
      expect(instance.locale, const Locale('de'));
      expect((await SharedPreferences.getInstance()).getString('locale'), 'de');
      final reset = instance.resetLocale();
      await reset;
      final resetPresentation = instance.waitForPresentation();
      await tester.pumpAndSettle();
      expect(await resetPresentation, LocalizationApplyOutcome.applied);
      expect(instance.locale, const Locale('ar'));

      expect((await SharedPreferences.getInstance()).getString('locale'), isNull);
      expect(document.tr('value'), 'de-v1');
      expect(initial.tr('value'), 'en-v1');
    } finally {
      await tester.pumpWidget(const SizedBox());
      instance.dispose();
      tester.binding.platformDispatcher.clearLocalesTestValue();
      scroll.dispose();
      focus.dispose();
      input.dispose();
    }
  });
}

class _Loader extends AssetLoader {
  _Loader()
    : super(
        fileLoader: const RootBundleFileLoader(),
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
      );
  int version = 1;
  bool fail = false;
  Completer<Map<String, dynamic>>? gate;
  Map<String, dynamic>? lastMap;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    if (fail) throw StateError('resources failed');
    final pending = gate;
    if (pending != null) return pending.future;
    return lastMap = {
      'value': '${locale.languageCode}-v$version',
      'nested': {'base': '${locale.languageCode}-base$version', 'message': 'base'},
    };
  }
}

class _Extra extends AssetLoader {
  _Extra()
    : super(
        fileLoader: const RootBundleFileLoader(),
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
      );
  int version = 1;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {
    'nested': {'message': '${locale.languageCode}-extra$version {name}'},
  };
}

class _Resource {
  const _Resource(this.locale);
  final Locale locale;
}

class _Delegate extends LocalizationsDelegate<_Resource> {
  Completer<_Resource>? gate;
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<_Resource> load(Locale locale) => gate?.future ?? SynchronousFuture(_Resource(locale));
  @override
  bool shouldReload(_Delegate old) => false;
}

class _App extends StatelessWidget {
  const _App({required this.navigator, required this.home});
  final GlobalKey<NavigatorState> navigator;
  final Widget home;
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    locale: context.locale,
    supportedLocales: context.supportedLocales,
    localizationsDelegates: context.localizationDelegates,
    home: home,
  );
}

class _Leaf extends StatelessWidget {
  const _Leaf({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    builds++;
    return Text('${tr('value')} $label');
  }

  static int builds = 0;
}

class _Page extends StatefulWidget {
  const _Page({super.key, required this.scroll, required this.focus, required this.input});
  final ScrollController scroll;
  final FocusNode focus;
  final TextEditingController input;
  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      controller: widget.scroll,
      children: [
        const SizedBox(height: 100),
        const _Leaf(label: 'home'),
        TextField(
          controller: widget.input,
          focusNode: widget.focus,
          decoration: InputDecoration(hintText: '${tr('value')} hint'),
        ),
        TextButton(onPressed: () {}, child: Text('${tr('value')} button')),
        const SizedBox(height: 1500),
      ],
    ),
  );
}
