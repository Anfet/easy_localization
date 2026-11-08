import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  Future<EasyLocalizationInstance> owner(_Loader loader, [_Delegate? delegate, bool saveLocale = false]) => EasyLocalization.initialize(
    EasyLocalizationConfig(
      supportedLocales: const [Locale('en'), Locale('de'), Locale('ar')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      path: 'unused',
      saveLocale: saveLocale,
      assetLoader: loader,
      additionalDelegates: [if (delegate != null) delegate, if (delegate != null) _DuplicateDelegate()],
    ),
  );

  testWidgets('reset presentation remains independent of subsequent system replay', (tester) async {
    for (final failReplay in [false, true]) {
      final loader = _Loader();
      tester.binding.platformDispatcher.localesTestValue = const [Locale('de')];
      final instance = await owner(loader);
      try {
        await tester.pumpWidget(
          EasyLocalization.withInstance(
            instance: instance,
            child: const _App(home: _Leaf(label: 'home')),
          ),
        );
        await tester.pumpAndSettle();
        final resetGate = Completer<Map<String, dynamic>>();
        final replayGate = Completer<Map<String, dynamic>>();
        loader.gates['de'] = resetGate;
        loader.gates['ar'] = replayGate;
        final reset = instance.resetLocale();
        tester.binding.platformDispatcher.localesTestValue = const [Locale('ar')];
        resetGate.complete({'value': 'reset'});
        await reset;
        final resetPresentation = instance.waitForPresentation();
        if (failReplay) {
          replayGate.completeError(FlutterError('replay failure'));
        } else {
          replayGate.complete({'value': 'replay'});
        }
        await tester.pumpAndSettle();
        expect(await resetPresentation, failReplay ? LocalizationApplyOutcome.applied : LocalizationApplyOutcome.superseded);

        expect(instance.locale, failReplay ? const Locale('de') : const Locale('ar'));
      } finally {
        await tester.pumpWidget(const SizedBox());
        instance.dispose();
        tester.binding.platformDispatcher.clearLocalesTestValue();
      }
    }
  });

  testWidgets('system updates reach presentation and survive detach and remount', (tester) async {
    final loader = _Loader();
    tester.binding.platformDispatcher.localesTestValue = const [Locale('en')];
    final instance = await EasyLocalization.initialize(
      EasyLocalizationConfig(
        supportedLocales: const [Locale('en'), Locale('de'), Locale('ar')],
        fallbackLocale: const Locale('en'),
        path: 'unused',
        saveLocale: false,
        assetLoader: loader,
      ),
    );
    try {
      await tester.pumpWidget(
        EasyLocalization.withInstance(
          instance: instance,
          child: const _App(home: _Leaf(label: 'home')),
        ),
      );
      await tester.pumpAndSettle();
      tester.binding.platformDispatcher.localesTestValue = const [Locale('fr'), Locale('de')];
      await tester.pumpAndSettle();
      expect(find.text('de-2 home'), findsOneWidget);
      expect(Localizations.localeOf(tester.element(find.text('de-2 home'))), const Locale('de'));
      await tester.pumpWidget(const SizedBox());
      tester.binding.platformDispatcher.localesTestValue = const [Locale('ar')];
      await tester.pumpAndSettle();
      expect(instance.locale, const Locale('ar'));
      await tester.pumpWidget(
        EasyLocalization.withInstance(
          instance: instance,
          child: const _App(home: _Leaf(label: 'home')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ar-3 home'), findsOneWidget);
      expect(loader.loads, 3);
    } finally {
      await tester.pumpWidget(const SizedBox());
      instance.dispose();
      tester.binding.platformDispatcher.clearLocalesTestValue();
    }
  });

  testWidgets('retained home route and dialog update ordinary translations with focus input scroll and resource types intact', (tester) async {
    final loader = _Loader();
    final delegate = _Delegate();
    final instance = await owner(loader, delegate);
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
      await tester.enterText(find.byType(TextField), 'kept input');
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
        context: tester.element(find.text('en-1 route')),
        builder: (_) => const Dialog(child: _Leaf(label: 'dialog')),
      );
      await tester.pumpAndSettle();
      final change = instance.setLocale(const Locale('ar'));
      await change;
      final changePresentation = instance.waitForPresentation();
      var applied = false;
      changePresentation.then((_) => applied = true);
      expect(applied, isFalse);
      await tester.pumpAndSettle();
      expect(await changePresentation, LocalizationApplyOutcome.applied);
      expect(find.text('ar-2 dialog'), findsOneWidget);
      expect(find.text('ar-2 route', skipOffstage: false), findsOneWidget);
      expect(find.text('ar-2 home', skipOffstage: false), findsOneWidget);
      expect(page.currentState, same(retained));
      expect(input.text, 'kept input');
      expect(scroll.offset, 100);
      final resources = tester.element(find.text('ar-2 dialog'));
      expect(Localizations.localeOf(resources), const Locale('ar'));
      expect(Directionality.of(resources), ui.TextDirection.rtl);
      expect(MaterialLocalizations.of(resources).cancelButtonLabel, isNot('Cancel'));
      expect(CupertinoLocalizations.of(resources).copyButtonLabel, isNotEmpty);
      expect(Localizations.of<_Resource>(resources, _Resource)?.locale, const Locale('ar'));
      navigator.currentState?.pop();
      await tester.pumpAndSettle();
      navigator.currentState?.pop();
      await tester.pumpAndSettle();
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isTrue);
      final reload = instance.reloadTranslations();
      await reload;
      final reloadPresentation = instance.waitForPresentation();
      await tester.pumpAndSettle();
      expect(await reloadPresentation, LocalizationApplyOutcome.applied);
      expect(find.text('ar-3 home'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).decoration?.hintText, 'ar-3 hint');
      expect(find.text('ar-3 button'), findsOneWidget);
      expect(page.currentState, same(retained));
      expect(input.text, 'kept input');
      expect(focus.hasFocus, isTrue);
      expect(scroll.offset, 100);
      navigator.currentState?.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: _Leaf(label: 'lazy')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('ar-3 lazy'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      instance.dispose();
      scroll.dispose();
      focus.dispose();
      input.dispose();
    }
  });

  testWidgets('slow and failed delegates preserve whole presentation and late superseded resources cannot apply', (tester) async {
    for (final useOwner in [false, true]) {
      final delegate = _Delegate();
      final instance = await owner(_Loader(), delegate);
      try {
        await tester.pumpWidget(
          EasyLocalization.withInstance(
            instance: instance,
            child: _App(
              instance: useOwner ? instance : null,
              home: const _Leaf(label: 'home'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final gate = Completer<_Resource>();
        delegate.gates['de'] = gate;
        final de = instance.setLocale(const Locale('de'));
        await de;
        final dePresentation = instance.waitForPresentation();
        await tester.pump();
        expect(instance.dataTranslator.tr('value'), 'de-2');
        expect(instance.presentationLocale, const Locale('en'));
        expect(instance.supportedLocales, contains(const Locale('ar')));
        expect(instance.fallbackLocale, const Locale('en'));
        expect(tr('value'), 'en-1');
        expect(find.text('en-1 home'), findsOneWidget);
        expect(instance.state.value.isLoading, isTrue);
        final ar = instance.setLocale(const Locale('ar'));
        await ar;
        final arPresentation = instance.waitForPresentation();
        await tester.pumpAndSettle();
        expect(await dePresentation, LocalizationApplyOutcome.superseded);
        expect(await arPresentation, LocalizationApplyOutcome.applied);
        gate.complete(const _Resource(Locale('de')));
        await tester.pumpAndSettle();
        expect(find.text('ar-3 home'), findsOneWidget);
        expect(tr('value'), 'ar-3');
        expect(instance.presentationLocale, const Locale('ar'));
        final current = tester.element(find.text('ar-3 home'));
        expect(Localizations.localeOf(current), const Locale('ar'));
        expect(Directionality.of(current), ui.TextDirection.rtl);
        expect(Localizations.of<_Resource>(current, _Resource)?.locale, const Locale('ar'));
        delegate.gates.remove('de');
        delegate.fail = true;
        final failed = instance.setLocale(const Locale('de'));
        await failed;
        final failedPresentation = instance.waitForPresentation();
        await tester.pumpAndSettle();
        expect(await failedPresentation, LocalizationApplyOutcome.failed);
        expect(instance.state.value.errorStage, LocalizationErrorStage.flutterDelegates);
        expect(tr('value'), 'ar-3');
        expect(instance.presentationLocale, const Locale('ar'));
        expect(Localizations.localeOf(tester.element(find.text('ar-3 home'))), const Locale('ar'));
        delegate.fail = false;
        final retry = instance.setLocale(const Locale('de'));
        await retry;
        final retryPresentation = instance.waitForPresentation();
        await tester.pumpAndSettle();
        expect(await retryPresentation, LocalizationApplyOutcome.applied);
        expect(find.text('de-4 home'), findsOneWidget);
        expect(instance.state.value.error, isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        instance.dispose();
      }
    }
  });

  testWidgets('two ready changes before frame rebuild const leaf once and storage-only same locale does not preflight', (tester) async {
    final delegate = _Delegate();
    final instance = await owner(_Loader(), delegate);
    _Leaf.builds = 0;
    try {
      await tester.pumpWidget(
        EasyLocalization.withInstance(
          instance: instance,
          child: const _App(home: _Leaf(label: 'home')),
        ),
      );
      await tester.pumpAndSettle();
      final before = _Leaf.builds;
      final de = instance.setLocale(const Locale('de'));
      await de;
      final dePresentation = instance.waitForPresentation();
      final ar = instance.setLocale(const Locale('ar'));
      await ar;
      final arPresentation = instance.waitForPresentation();
      await tester.pumpAndSettle();
      expect(await dePresentation, LocalizationApplyOutcome.superseded);
      expect(await arPresentation, LocalizationApplyOutcome.applied);
      expect(_Leaf.builds - before, 1);
      expect(find.text('ar-3 home'), findsOneWidget);
      final loads = delegate.loads;
      final builds = _Leaf.builds;
      final unchanged = instance.setLocale(const Locale('ar'));
      await unchanged;
      final unchangedPresentation = instance.waitForPresentation();
      expect(await unchangedPresentation, LocalizationApplyOutcome.applied);
      await tester.pumpAndSettle();
      expect(delegate.loads, loads);
      expect(_Leaf.builds, builds);
    } finally {
      await tester.pumpWidget(const SizedBox());
      instance.dispose();
    }
  });

  testWidgets('storage-only retry completes applied receipt without loading or rebuilding the presented snapshot', (tester) async {
    final original = SharedPreferencesStorePlatform.instance;
    final store = _RetryStore();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
    final delegate = _Delegate();
    final loader = _Loader();
    final instance = await owner(loader, delegate, true);
    try {
      await tester.pumpWidget(
        EasyLocalization.withInstance(
          instance: instance,
          child: const _App(home: _Leaf(label: 'home')),
        ),
      );
      await tester.pumpAndSettle();
      store.fail = true;
      final failed = instance.setLocale(const Locale('de'));
      await expectLater(failed, throwsStateError);
      final failedPresentation = instance.waitForPresentation();
      await tester.pumpAndSettle();
      expect(await failedPresentation, LocalizationApplyOutcome.applied);
      expect(instance.state.value.errorStage, LocalizationErrorStage.persistence);
      final loads = delegate.loads;
      final resources = loader.loads;
      final builds = _Leaf.builds;
      store.fail = false;
      final retry = instance.setLocale(const Locale('de'));
      await retry;
      final retryPresentation = instance.waitForPresentation();
      expect(await retryPresentation, LocalizationApplyOutcome.applied);
      await tester.pumpAndSettle();
      expect(delegate.loads, loads);
      expect(loader.loads, resources);
      expect(_Leaf.builds, builds);
      expect(instance.state.value.isLoading, isFalse);
      expect(instance.state.value.error, isNull);
      expect(store.values['flutter.locale'], 'de');
    } finally {
      await tester.pumpWidget(const SizedBox());
      instance.dispose();
      SharedPreferencesStorePlatform.instance = original;
      SharedPreferences.resetStatic();
    }
  });

  for (final failure in [false, true]) {
    testWidgets('busy waits for storage after presentation ${failure ? 'fails' : 'succeeds'}', (tester) async {
      final original = SharedPreferencesStorePlatform.instance;
      final store = _RetryStore();
      SharedPreferencesStorePlatform.instance = store;
      SharedPreferences.resetStatic();
      final delegate = _Delegate();
      final instance = await owner(_Loader(), delegate, true);
      try {
        await tester.pumpWidget(
          EasyLocalization.withInstance(
            instance: instance,
            child: const _App(home: _Leaf(label: 'home')),
          ),
        );
        await tester.pumpAndSettle();
        final gate = Completer<void>();
        store.gate = gate;
        delegate.fail = failure;
        final change = instance.setLocale(Locale(failure ? 'ar' : 'de'));
        var ready = false;
        change.then((_) => ready = true);
        await tester.pumpAndSettle();
        final changePresentation = instance.waitForPresentation();
        expect(await changePresentation, failure ? LocalizationApplyOutcome.failed : LocalizationApplyOutcome.applied);
        expect(ready, isFalse);
        expect(instance.state.value.isLoading, isTrue);
        if (failure) expect(instance.state.value.errorStage, LocalizationErrorStage.flutterDelegates);
        gate.complete();
        await change;
        await tester.pump();
        expect(instance.state.value.isLoading, isFalse);
      } finally {
        final gate = store.gate;
        if (gate != null && !gate.isCompleted) gate.complete();
        await tester.pumpWidget(const SizedBox());
        instance.dispose();
        SharedPreferencesStorePlatform.instance = original;
        SharedPreferences.resetStatic();
      }
    });
  }

  testWidgets('first mount waits for all delegates and recovers from preflight failure without changing data', (tester) async {
    final delegate = _Delegate()..fail = true;
    final instance = await owner(_Loader(), delegate);
    try {
      await tester.pumpWidget(
        EasyLocalization.withInstance(
          instance: instance,
          child: const _App(home: _Leaf(label: 'home')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(_App), findsNothing);
      expect(instance.state.value.errorStage, LocalizationErrorStage.flutterDelegates);
      expect(await instance.waitForPresentation(), LocalizationApplyOutcome.failed);

      delegate.fail = false;
      final retry = instance.setLocale(const Locale('en'));
      await retry;
      final retryPresentation = instance.waitForPresentation();
      await tester.pumpAndSettle();
      expect(await retryPresentation, LocalizationApplyOutcome.applied);
      expect(find.text('en-1 home'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox());
      instance.dispose();
    }
  });

  testWidgets('mount after resource failure presents the latest committed snapshot and retains the operation error', (tester) async {
    final loader = _Loader();
    final instance = await owner(loader);
    try {
      loader.fail = true;
      final failed = instance.setLocale(const Locale('de'));
      await expectLater(failed, throwsStateError);
      await tester.pumpWidget(
        EasyLocalization.withInstance(
          instance: instance,
          child: const _App(home: _Leaf(label: 'home')),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('en-1 home'), findsOneWidget);
      expect(instance.state.value.appliedLocale, const Locale('en'));
      expect(instance.state.value.errorStage, LocalizationErrorStage.resources);
    } finally {
      await tester.pumpWidget(const SizedBox());
      instance.dispose();
    }
  });

  testWidgets('detach and remount isolate pending preflight and terminal receipts while disposal closes an attached command', (tester) async {
    final delegate = _Delegate();
    final instance = await owner(_Loader(), delegate);
    Widget root() => EasyLocalization.withInstance(
      instance: instance,
      child: const _App(home: _Leaf(label: 'home')),
    );
    await tester.pumpWidget(root());
    await tester.pumpAndSettle();
    final gate = Completer<_Resource>();
    delegate.gates['de'] = gate;
    final change = instance.setLocale(const Locale('de'));
    await change;
    final changePresentation = instance.waitForPresentation();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(await changePresentation, LocalizationApplyOutcome.detached);
    delegate.gates.remove('de');
    await tester.pumpWidget(root());
    await tester.pumpAndSettle();
    expect(find.text('de-2 home'), findsOneWidget);
    expect(instance.state.value.appliedLocale, const Locale('de'));
    expect(await changePresentation, LocalizationApplyOutcome.detached);
    gate.complete(const _Resource(Locale('de')));
    await tester.pumpAndSettle();
    final pending = Completer<_Resource>();
    delegate.gates['ar'] = pending;
    final disposed = instance.setLocale(const Locale('ar'));
    await disposed;
    final disposedPresentation = instance.waitForPresentation();
    await tester.pump();
    instance.dispose();
    expect(await disposedPresentation, LocalizationApplyOutcome.disposed);
    pending.complete(const _Resource(Locale('ar')));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

class _Loader extends AssetLoader {
  _Loader()
    : super(
        fileLoader: const RootBundleFileLoader(),
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
      );
  int loads = 0;
  bool fail = false;
  final gates = <String, Completer<Map<String, dynamic>>>{};
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    if (fail) throw StateError('resources failed');
    final count = ++loads;
    final gate = gates[locale.languageCode];
    if (gate != null) return gate.future;
    return {'value': '${locale.languageCode}-$count'};
  }
}

class _Resource {
  final Locale locale;
  const _Resource(this.locale);
}

class _Delegate extends LocalizationsDelegate<_Resource> {
  final gates = <String, Completer<_Resource>>{};
  bool fail = false;
  int loads = 0;
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<_Resource> load(Locale locale) {
    loads++;
    if (fail) throw StateError('delegate failed');
    return gates[locale.languageCode]?.future ?? SynchronousFuture(_Resource(locale));
  }

  @override
  bool shouldReload(_Delegate old) => false;
}

class _DuplicateDelegate extends LocalizationsDelegate<_Resource> {
  @override
  bool isSupported(Locale locale) => throw StateError('duplicate delegate must be skipped before isSupported');
  @override
  Future<_Resource> load(Locale locale) => throw StateError('first delegate wins');
  @override
  bool shouldReload(_DuplicateDelegate old) => false;
}

class _App extends StatelessWidget {
  final Widget home;
  final GlobalKey<NavigatorState>? navigator;
  final EasyLocalizationInstance? instance;
  const _App({required this.home, this.navigator, this.instance});
  @override
  Widget build(BuildContext context) => MaterialApp(
    navigatorKey: navigator,
    locale: instance?.presentationLocale ?? context.locale,
    supportedLocales: instance?.supportedLocales ?? context.supportedLocales,
    localizationsDelegates: instance?.delegates ?? context.localizationDelegates,
    home: home,
  );
}

class _Leaf extends StatelessWidget {
  final String label;
  const _Leaf({required this.label});
  static int builds = 0;
  @override
  Widget build(BuildContext context) {
    builds++;
    return Text('${tr('value')} $label');
  }
}

class _Page extends StatefulWidget {
  final ScrollController scroll;
  final FocusNode focus;
  final TextEditingController input;
  const _Page({Key? key, required this.scroll, required this.focus, required this.input}) : super(key: key);
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

class _RetryStore extends SharedPreferencesStorePlatform {
  bool fail = false;
  Completer<void>? gate;
  final values = <String, Object>{};
  @override
  Future<Map<String, Object>> getAll() async => Map.of(values);
  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (fail) return false;
    await gate?.future;
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    values.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    values.clear();
    return true;
  }
}
