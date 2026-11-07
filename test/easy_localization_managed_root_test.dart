import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

void main() {
  Future<EasyLocalizationInstance> owner(_Loader loader, [_Delegate? delegate, bool saveLocale = false]) =>
      EasyLocalization.initialize(EasyLocalizationConfig(
        supportedLocales: const [Locale('en'), Locale('de'), Locale('ar')],
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        path: 'unused',
        saveLocale: saveLocale,
        assetLoader: loader,
        additionalDelegates: [if (delegate != null) delegate, if (delegate != null) _DuplicateDelegate()],
      ));

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
      await tester.pumpWidget(EasyLocalization.withInstance(
        instance: instance,
        child: _App(navigator: navigator, home: _Page(key: page, scroll: scroll, focus: focus, input: input)),
      ));
      await tester.pumpAndSettle();
      final retained = page.currentState;
      await tester.enterText(find.byType(TextField), 'kept input');
      focus.requestFocus();
      scroll.jumpTo(100);
      await tester.pump();
      navigator.currentState?.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: _Leaf(label: 'route'))));
      await tester.pumpAndSettle();
      showDialog<void>(context: tester.element(find.text('en-1 route')), builder: (_) => const Dialog(child: _Leaf(label: 'dialog')));
      await tester.pumpAndSettle();
      final change = instance.setLocale(const Locale('ar'));
      expect(await change.ready, LocalizationDataOutcome.committed);
      var applied = false;
      change.applied.then((_) => applied = true);
      expect(applied, isFalse);
      await tester.pumpAndSettle();
      expect(await change.applied, LocalizationApplyOutcome.applied);
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
      await reload.ready;
      await tester.pumpAndSettle();
      expect(await reload.applied, LocalizationApplyOutcome.applied);
      expect(find.text('ar-3 home'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).decoration?.hintText, 'ar-3 hint');
      expect(find.text('ar-3 button'), findsOneWidget);
      expect(page.currentState, same(retained));
      expect(input.text, 'kept input');
      expect(focus.hasFocus, isTrue);
      expect(scroll.offset, 100);
      navigator.currentState?.push(MaterialPageRoute<void>(builder: (_) => const Scaffold(body: _Leaf(label: 'lazy'))));
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
    final delegate = _Delegate();
    final instance = await owner(_Loader(), delegate);
    try {
      await tester.pumpWidget(EasyLocalization.withInstance(instance: instance, child: const _App(home: _Leaf(label: 'home'))));
      await tester.pumpAndSettle();
      final gate = Completer<_Resource>();
      delegate.gates['de'] = gate;
      final de = instance.setLocale(const Locale('de'));
      await de.ready;
      await tester.pump();
      expect(instance.dataTranslator.tr('value'), 'de-2');
      expect(tr('value'), 'en-1');
      expect(find.text('en-1 home'), findsOneWidget);
      expect(instance.state.value.phase, isNot(LocalizationPhase.idle));
      final ar = instance.setLocale(const Locale('ar'));
      await ar.ready;
      await tester.pumpAndSettle();
      expect(await de.applied, LocalizationApplyOutcome.superseded);
      expect(await ar.applied, LocalizationApplyOutcome.applied);
      gate.complete(const _Resource(Locale('de')));
      await tester.pumpAndSettle();
      expect(find.text('ar-3 home'), findsOneWidget);
      expect(tr('value'), 'ar-3');
      delegate.gates.remove('de');
      delegate.fail = true;
      final failed = instance.setLocale(const Locale('de'));
      await failed.ready;
      await tester.pumpAndSettle();
      expect(await failed.applied, LocalizationApplyOutcome.failed);
      expect(instance.state.value.errorStage, LocalizationErrorStage.flutterDelegates);
      expect(tr('value'), 'ar-3');
      expect(Localizations.localeOf(tester.element(find.text('ar-3 home'))), const Locale('ar'));
      delegate.fail = false;
      final retry = instance.setLocale(const Locale('de'));
      await retry.ready;
      await tester.pumpAndSettle();
      expect(await retry.applied, LocalizationApplyOutcome.applied);
      expect(find.text('de-4 home'), findsOneWidget);
      expect(instance.state.value.error, isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      instance.dispose();
    }
  });

  testWidgets('two ready changes before frame rebuild const leaf once and storage-only same locale does not preflight', (tester) async {
    final delegate = _Delegate();
    final instance = await owner(_Loader(), delegate);
    _Leaf.builds = 0;
    try {
      await tester.pumpWidget(EasyLocalization.withInstance(instance: instance, child: const _App(home: _Leaf(label: 'home'))));
      await tester.pumpAndSettle();
      final before = _Leaf.builds;
      final de = instance.setLocale(const Locale('de'));
      await de.ready;
      final ar = instance.setLocale(const Locale('ar'));
      await ar.ready;
      await tester.pumpAndSettle();
      expect(await de.applied, LocalizationApplyOutcome.superseded);
      expect(await ar.applied, LocalizationApplyOutcome.applied);
      expect(_Leaf.builds - before, 1);
      expect(find.text('ar-3 home'), findsOneWidget);
      final loads = delegate.loads;
      final builds = _Leaf.builds;
      final unchanged = instance.setLocale(const Locale('ar'));
      await unchanged.ready;
      expect(await unchanged.applied, LocalizationApplyOutcome.applied);
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
      await tester.pumpWidget(EasyLocalization.withInstance(instance: instance, child: const _App(home: _Leaf(label: 'home'))));
      await tester.pumpAndSettle();
      store.fail = true;
      final failed = instance.setLocale(const Locale('de'));
      await expectLater(failed.ready, throwsStateError);
      await tester.pumpAndSettle();
      expect(await failed.applied, LocalizationApplyOutcome.applied);
      expect(instance.state.value.errorStage, LocalizationErrorStage.persistence);
      final loads = delegate.loads;
      final resources = loader.loads;
      final builds = _Leaf.builds;
      store.fail = false;
      final retry = instance.setLocale(const Locale('de'));
      await retry.ready;
      expect(await retry.applied, LocalizationApplyOutcome.applied);
      await tester.pumpAndSettle();
      expect(delegate.loads, loads);
      expect(loader.loads, resources);
      expect(_Leaf.builds, builds);
      expect(instance.state.value.phase, LocalizationPhase.idle);
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
        await tester.pumpWidget(EasyLocalization.withInstance(instance: instance, child: const _App(home: _Leaf(label: 'home'))));
        await tester.pumpAndSettle();
        final gate = Completer<void>();
        store.gate = gate;
        delegate.fail = failure;
        final change = instance.setLocale(Locale(failure ? 'ar' : 'de'));
        var ready = false;
        change.ready.then((_) => ready = true);
        await tester.pumpAndSettle();
        expect(await change.applied, failure ? LocalizationApplyOutcome.failed : LocalizationApplyOutcome.applied);
        expect(ready, isFalse);
        expect(instance.state.value.phase, isNot(LocalizationPhase.idle));
        if (failure) expect(instance.state.value.errorStage, LocalizationErrorStage.flutterDelegates);
        gate.complete();
        expect(await change.ready, LocalizationDataOutcome.committed);
        await tester.pump();
        expect(instance.state.value.phase, LocalizationPhase.idle);
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
      await tester.pumpWidget(EasyLocalization.withInstance(instance: instance, child: const _App(home: _Leaf(label: 'home'))));
      await tester.pumpAndSettle();
      expect(find.byType(_App), findsNothing);
      expect(instance.state.value.errorStage, LocalizationErrorStage.flutterDelegates);
      expect(instance.state.value.appliedRevision, isNull);
      delegate.fail = false;
      final retry = instance.setLocale(const Locale('en'));
      await retry.ready;
      await tester.pumpAndSettle();
      expect(await retry.applied, LocalizationApplyOutcome.applied);
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
      await expectLater(failed.ready, throwsStateError);
      await tester.pumpWidget(EasyLocalization.withInstance(instance: instance, child: const _App(home: _Leaf(label: 'home'))));
      await tester.pumpAndSettle();
      expect(find.text('en-1 home'), findsOneWidget);
      expect(instance.state.value.appliedLocale, const Locale('en'));
      expect(instance.state.value.errorStage, LocalizationErrorStage.resources);
      expect(await failed.applied, LocalizationApplyOutcome.failed);
    } finally {
      await tester.pumpWidget(const SizedBox());
      instance.dispose();
    }
  });

  testWidgets('detach and remount isolate pending preflight and terminal receipts while disposal closes an attached command', (tester) async {
    final delegate = _Delegate();
    final instance = await owner(_Loader(), delegate);
    Widget root() => EasyLocalization.withInstance(instance: instance, child: const _App(home: _Leaf(label: 'home')));
    await tester.pumpWidget(root());
    await tester.pumpAndSettle();
    final gate = Completer<_Resource>();
    delegate.gates['de'] = gate;
    final change = instance.setLocale(const Locale('de'));
    await change.ready;
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    expect(await change.applied, LocalizationApplyOutcome.detached);
    delegate.gates.remove('de');
    await tester.pumpWidget(root());
    await tester.pumpAndSettle();
    expect(find.text('de-2 home'), findsOneWidget);
    expect(instance.state.value.appliedLocale, const Locale('de'));
    expect(await change.applied, LocalizationApplyOutcome.detached);
    gate.complete(const _Resource(Locale('de')));
    await tester.pumpAndSettle();
    final pending = Completer<_Resource>();
    delegate.gates['ar'] = pending;
    final disposed = instance.setLocale(const Locale('ar'));
    await disposed.ready;
    await tester.pump();
    instance.dispose();
    expect(await disposed.applied, LocalizationApplyOutcome.disposed);
    pending.complete(const _Resource(Locale('ar')));
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}

class _Loader extends AssetLoader {
  _Loader() : super(fileLoader: const RootBundleFileLoader(), linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()));
  int loads = 0;
  bool fail = false;
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    if (fail) throw StateError('resources failed');
    return {'value': '${locale.languageCode}-${++loads}'};
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
  const _App({required this.home, this.navigator});
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
        body: ListView(controller: widget.scroll, children: [
          const SizedBox(height: 100),
          const _Leaf(label: 'home'),
          TextField(controller: widget.input, focusNode: widget.focus, decoration: InputDecoration(hintText: '${tr('value')} hint')),
          TextButton(onPressed: () {}, child: Text('${tr('value')} button')),
          const SizedBox(height: 1500),
        ]),
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
