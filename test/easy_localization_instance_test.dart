import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

class InstanceLoader extends AssetLoader {
  InstanceLoader()
      : super(linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()), fileLoader: const RootBundleFileLoader());

  final calls = <Locale>[];
  final data = <String, Map<String, dynamic>>{};
  final gates = <String, List<Completer<Map<String, dynamic>?>>>{};
  Object? failure;
  StackTrace? failureStack;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    calls.add(locale);
    final error = failure;
    if (error != null) return Future.error(error, failureStack);
    final queued = gates[locale.toString()];
    if (queued != null && queued.isNotEmpty) return queued.removeAt(0).future;
    return data[locale.toString()] ??
        {
          'value': locale.toString(),
          'count': {'one': 'one', 'two': 'two', 'few': 'few', 'other': 'other'}
        };
  }
}

class InstanceStore extends SharedPreferencesStorePlatform {
  final data = <String, Object>{};
  final operations = <String>[];
  bool failRead = false;
  bool failWrite = false;
  bool failRemove = false;
  Completer<bool>? writeGate;
  Completer<void>? writeStarted;

  @override
  Future<Map<String, Object>> getAll() async {
    operations.add('read');
    if (failRead) throw StateError('read failed');
    return Map.of(data);
  }

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    operations.add('set:$value');
    final started = writeStarted;
    writeStarted = null;
    started?.complete();
    final gate = writeGate;
    writeGate = null;
    if (gate != null && !await gate.future) return false;
    if (failWrite) return false;
    data[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    operations.add('remove');
    if (failRemove) return false;
    data.remove(key);
    return true;
  }

  @override
  Future<bool> clear() async {
    data.clear();
    return true;
  }
}

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  late SharedPreferencesStorePlatform original;
  late InstanceStore store;
  late InstanceLoader loader;

  EasyLocalizationConfig config(
          {Locale? start, bool save = true, List<Locale>? supported, Locale fallback = const Locale('ru'), bool rules = true}) =>
      EasyLocalizationConfig(
        supportedLocales: supported ?? const [Locale('de'), Locale('ru')],
        fallbackLocale: fallback,
        path: 'unused',
        startLocale: start,
        assetLoader: loader,
        saveLocale: save,
        ignorePluralRules: rules,
      );

  setUp(() {
    original = SharedPreferencesStorePlatform.instance;
    store = InstanceStore();
    loader = InstanceLoader();
    SharedPreferencesStorePlatform.instance = store;
    SharedPreferences.resetStatic();
  });

  tearDown(() {
    try {
      EasyLocalization.instance.dispose();
    } on StateError {
      // Failed initialization deliberately has no published owner.
    }
    binding.platformDispatcher.clearLocalesTestValue();
    SharedPreferencesStorePlatform.instance = original;
    SharedPreferences.resetStatic();
  });

  test('config defaults use language rules and translator inherits them', () async {
    final input = EasyLocalizationConfig(
        supportedLocales: const [Locale('ru')],
        fallbackLocale: const Locale('ru'),
        startLocale: const Locale('ru'),
        path: 'unused',
        assetLoader: loader,
        saveLocale: false);
    expect(input.ignorePluralRules, isFalse);
    expect(input.useBaseLanguageFallback, isFalse);
    final owner = await EasyLocalization.initialize(input);
    expect(owner.dataTranslator.plural('count', 21), 'one');
    expect(owner.dataTranslator.plural('count', 22), 'few');
    expect((await owner.translator(const Locale('ru'))).plural('count', 22), 'few');
    expect(EasyLocalization(supportedLocales: const [Locale('ru')], path: 'unused', child: const SizedBox()).ignorePluralRules, isTrue);
  });

  test('ready before runApp exposes data, plural, mode and state without a frame', () async {
    expect(() => EasyLocalization.instance, throwsStateError);
    expect(() => tr('value'), throwsStateError);
    expect(() => plural('count', 2), throwsStateError);
    final owner = await EasyLocalization.initialize(config(start: const Locale('ru'), save: false, rules: false));
    expect(EasyLocalization.instance, same(owner));
    expect(tr('value'), 'ru');
    expect(plural('count', 2), 'few');
    expect(owner.locale, const Locale('ru'));
    expect(owner.isSystemMode, isFalse);
    expect(owner.state.value.committedLocale, const Locale('ru'));
    expect(() => owner.setLocale(const Locale('fr')), throwsArgumentError);
    final change = owner.setLocale(const Locale('de'));
    expect(await change.ready, LocalizationDataOutcome.committed);
    expect(await change.applied, LocalizationApplyOutcome.detached);
    expect(tr('value'), 'de');
    expect(owner.state.value.phase, LocalizationPhase.idle);
  });

  test('owner follows preferred lists without a root and retains explicit choice until reset', () async {
    binding.platformDispatcher.localesTestValue = const [Locale('fr'), Locale('de')];
    final owner = await EasyLocalization.initialize(config(save: false));
    expect(owner.locale, const Locale('de'));
    binding.platformDispatcher.localesTestValue = const [Locale('fr'), Locale('ru')];
    await Future<void>.delayed(Duration.zero);
    expect(owner.locale, const Locale('ru'));
    await owner.setLocale(const Locale('de')).ready;
    binding.platformDispatcher.localesTestValue = const [Locale('fr'), Locale('ru')];
    await Future<void>.delayed(Duration.zero);
    expect(owner.locale, const Locale('de'));
    await owner.resetLocale().ready;
    expect(owner.locale, const Locale('ru'));
    expect(store.operations, isEmpty);
    owner.dispose();
    final count = loader.calls.length;
    binding.platformDispatcher.localesTestValue = const [Locale('de')];
    await Future<void>.delayed(Duration.zero);
    expect(loader.calls.length, count);
  });

  test('initial load waits for latest system list and ignores stale result', () async {
    final first = Completer<Map<String, dynamic>?>();
    final latest = Completer<Map<String, dynamic>?>();
    loader.gates['de'] = [first];
    loader.gates['ru'] = [latest];
    binding.platformDispatcher.localesTestValue = const [Locale('de')];
    final pending = EasyLocalization.initialize(config(save: false));
    binding.platformDispatcher.localesTestValue = const [Locale('fr'), Locale('ru')];
    first.complete({'value': 'old'});
    await Future<void>.delayed(Duration.zero);
    latest.complete({'value': 'new'});
    final owner = await pending;
    expect(owner.locale, const Locale('ru'));
    expect(owner.dataTranslator.tr('value'), 'new');
  });

  test('latest startup failure cleans observer and permits retry', () async {
    final first = Completer<Map<String, dynamic>?>();
    final latest = Completer<Map<String, dynamic>?>();
    loader.gates['de'] = [first];
    loader.gates['ru'] = [latest];
    binding.platformDispatcher.localesTestValue = const [Locale('de')];
    final pending = EasyLocalization.initialize(config(save: false));
    var completed = false;
    final failed = expectLater(pending, throwsStateError).then((_) => completed = true);
    binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    latest.completeError(StateError('latest failed'));
    await Future<void>.delayed(Duration.zero);
    if (!completed) first.complete({'value': 'stale'});
    expect(completed, isTrue, reason: 'latest failure must not wait for the stale loader');
    await failed;
    final count = loader.calls.length;
    binding.platformDispatcher.localesTestValue = const [Locale('de')];
    await Future<void>.delayed(Duration.zero);
    expect(loader.calls.length, count);
    final owner = await EasyLocalization.initialize(config(save: false));
    expect(owner.locale, const Locale('de'));
    if (!first.isCompleted) first.complete({'value': 'stale'});
  });

  test('explicit choice supersedes slow system load and reset follows latest list', () async {
    binding.platformDispatcher.localesTestValue = const [Locale('ru')];
    final owner = await EasyLocalization.initialize(config(save: false));
    final gate = Completer<Map<String, dynamic>?>();
    loader.gates['de'] = [gate];
    binding.platformDispatcher.localesTestValue = const [Locale('de')];
    await owner.setLocale(const Locale('ru')).ready;
    gate.complete({'value': 'stale'});
    await Future<void>.delayed(Duration.zero);
    expect(owner.locale, const Locale('ru'));
    expect(owner.isSystemMode, isFalse);
    await owner.resetLocale().ready;
    expect(owner.locale, const Locale('de'));
    owner.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);
    expect(owner.locale, const Locale('de'));
  });

  test('reset receipt stays independent of later system replay success and failure', () async {
    for (final failReplay in [false, true]) {
      binding.platformDispatcher.localesTestValue = const [Locale('de')];
      final owner = await EasyLocalization.initialize(config(start: const Locale('ru'), save: false));
      final resetGate = Completer<Map<String, dynamic>?>();
      final replayGate = Completer<Map<String, dynamic>?>();
      loader.gates['de'] = [resetGate];
      loader.gates['ru'] = [replayGate];
      final revisions = <int>[];
      void record() => revisions.add(owner.state.value.committedRevision);
      owner.state.addListener(record);
      final reset = owner.resetLocale();
      binding.platformDispatcher.localesTestValue = const [Locale('fr'), Locale('ru')];
      var ready = false;
      reset.ready.then((_) => ready = true, onError: (Object _) => ready = true);
      resetGate.complete({'value': 'reset'});
      await Future<void>.delayed(Duration.zero);
      if (!ready) replayGate.complete({'value': 'cleanup'});
      expect(ready, isTrue, reason: 'reset must finish before replay');
      expect(await reset.ready, LocalizationDataOutcome.committed);
      expect(await reset.applied, LocalizationApplyOutcome.detached);
      expect(owner.state.value.committedRevision, reset.revision);
      if (failReplay) {
        replayGate.completeError(FlutterError('replay failure'));
      } else {
        replayGate.complete({'value': 'replay'});
      }
      await Future<void>.delayed(Duration.zero);
      expect(revisions, contains(reset.revision));
      if (failReplay) {
        expect(owner.locale, const Locale('de'));
        expect(owner.state.value.committedRevision, reset.revision);
      } else {
        expect(owner.locale, const Locale('ru'));
        expect(owner.state.value.committedRevision, greaterThan(reset.revision));
      }
      owner.state.removeListener(record);
      owner.dispose();
    }
  });

  test('system load supersedes an uncommitted reload and owns its revision', () async {
    binding.platformDispatcher.localesTestValue = const [Locale('de')];
    final owner = await EasyLocalization.initialize(config(save: false));
    final reloadGate = Completer<Map<String, dynamic>?>();
    final systemGate = Completer<Map<String, dynamic>?>();
    loader.gates['de'] = [reloadGate];
    loader.gates['ru'] = [systemGate];
    final reload = owner.reloadTranslations();
    binding.platformDispatcher.localesTestValue = const [Locale('fr'), Locale('ru')];
    systemGate.complete({'value': 'system'});
    await Future<void>.delayed(Duration.zero);
    reloadGate.complete({'value': 'stale reload'});
    expect(await reload.ready, LocalizationDataOutcome.superseded);
    expect(await reload.applied, LocalizationApplyOutcome.superseded);
    await Future<void>.delayed(Duration.zero);
    expect(owner.locale, const Locale('ru'));
    expect(owner.dataTranslator.tr('value'), 'system');
    expect(owner.state.value.committedRevision, greaterThan(reload.revision));
  });

  test('unchanged system candidate leaves an active reload intact', () async {
    binding.platformDispatcher.localesTestValue = const [Locale('de')];
    final owner = await EasyLocalization.initialize(config(save: false));
    final reloadGate = Completer<Map<String, dynamic>?>();
    loader.gates['de'] = [reloadGate];
    final reload = owner.reloadTranslations();
    owner.didChangeLocales(const [Locale('fr'), Locale('de')]);
    reloadGate.complete({'value': 'reloaded'});
    expect(await reload.ready, LocalizationDataOutcome.committed);
    expect(await reload.applied, LocalizationApplyOutcome.detached);
    expect(owner.dataTranslator.tr('value'), 'reloaded');
    expect(owner.state.value.committedRevision, reload.revision);
  });

  test('startup matrix chooses only start, saved, supported system or required fallback', () async {
    final cases = <Map<String, dynamic>>[
      {'start': const Locale('de'), 'saved': 'ru', 'system': const Locale('ru'), 'expected': const Locale('de'), 'write': true, 'explicit': true},
      {'start': const Locale('de'), 'expected': const Locale('de'), 'write': true, 'explicit': true},
      {'saved': 'ru', 'expected': const Locale('ru'), 'explicit': true},
      {'system': const Locale('de'), 'expected': const Locale('de')},
      {'system': const Locale('fr'), 'expected': const Locale('ru')},
      {
        'supported': const [Locale('ru')],
        'system': const Locale('fr'),
        'expected': const Locale('ru')
      },
      {'start': const Locale('de'), 'saved': 42, 'expected': const Locale('de'), 'write': true, 'explicit': true},
    ];
    for (final row in cases) {
      store.data.clear();
      store.operations.clear();
      loader.calls.clear();
      final saved = row['saved'];
      if (saved != null) store.data['flutter.locale'] = saved;
      SharedPreferences.resetStatic();
      binding.platformDispatcher.localesTestValue = [row['system'] as Locale? ?? const Locale('fr')];
      final owner = await EasyLocalization.initialize(config(start: row['start'] as Locale?, supported: row['supported'] as List<Locale>?));
      expect(owner.locale, row['expected'], reason: '$row');
      expect(owner.isSystemMode, row['explicit'] != true, reason: '$row');
      expect(loader.calls, [row['expected']], reason: '$row');
      expect(store.operations.where((op) => op.startsWith('set:')), row['write'] == true ? ['set:de'] : isEmpty, reason: '$row');
      owner.dispose();
    }
  });

  test('invalid start and fallback fail before loading or touching preferences', () async {
    for (final invalid in [config(start: const Locale('fr')), config(fallback: const Locale('en')), config(supported: [])]) {
      expect(() => EasyLocalization.initialize(invalid), throwsArgumentError);
    }
    expect(store.operations, isEmpty);
    expect(loader.calls, isEmpty);
  });

  test('invalid or unsupported saved selections fail without deletion or fallback', () async {
    for (final value in [42, '', 'ru____RU', 'fr', 'ru-Latn-RU']) {
      store.data['flutter.locale'] = value;
      SharedPreferences.resetStatic();
      await expectLater(EasyLocalization.initialize(config()), throwsA(anyOf(isA<FormatException>(), isA<StateError>())));
      expect(() => EasyLocalization.instance, throwsStateError);
      expect(store.data['flutter.locale'], value);
    }
    expect(loader.calls, isEmpty);
    expect(store.operations.where((op) => op == 'remove' || op.startsWith('set:')), isEmpty);
  });

  test('legacy language, country and script storage forms restore exactly', () async {
    const locales = [
      Locale('ru'),
      Locale('ru', 'RU'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
      Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant', countryCode: 'TW')
    ];
    for (final locale in locales) {
      store.data['flutter.locale'] = locale.toString();
      SharedPreferences.resetStatic();
      final owner = await EasyLocalization.initialize(config(supported: locales, fallback: const Locale('ru')));
      expect(owner.locale, locale);
      expect(owner.isSystemMode, isFalse);
      owner.dispose();
    }
  });

  test('selected source errors keep original stack, never load fallback and allow retry', () async {
    store.data['flutter.locale'] = 'ru';
    final failure = StateError('loader unavailable');
    final stack = StackTrace.fromString('original loader stack');
    loader.failure = failure;
    loader.failureStack = stack;
    final inputs = config(start: const Locale('de'));
    try {
      await EasyLocalization.initialize(inputs);
      fail('initialization should fail');
    } catch (error, trace) {
      expect(error, same(failure));
      expect(trace.toString(), contains('original loader stack'));
    }
    expect(loader.calls, [const Locale('de')]);
    expect(store.data['flutter.locale'], 'ru');
    expect(store.operations, isEmpty);
    expect(() => tr('value'), throwsStateError);
    loader.failure = null;
    final owner = await EasyLocalization.initialize(inputs);
    expect(owner.locale, const Locale('de'));
    expect(store.data['flutter.locale'], 'de');
  });

  test('restore read and start write failures never publish a ready owner', () async {
    store.failRead = true;
    await expectLater(EasyLocalization.initialize(config()), throwsStateError);
    expect(loader.calls, isEmpty);
    expect(() => EasyLocalization.instance, throwsStateError);
    store.failRead = false;
    store.failWrite = true;
    await expectLater(EasyLocalization.initialize(config(start: const Locale('de'))), throwsStateError);
    expect(() => EasyLocalization.instance, throwsStateError);
    expect(() => tr('value'), throwsStateError);
    store.failWrite = false;
    final owner = await EasyLocalization.initialize(config(start: const Locale('de')));
    expect(owner.locale, const Locale('de'));
    expect(store.data['flutter.locale'], 'de');
  });

  test('saved, system and fallback load failures never try a different source', () async {
    loader.failure = StateError('selected source failed');
    for (final saved in ['de', null]) {
      for (final system in [const Locale('de'), const Locale('fr')]) {
        store.data.clear();
        store.operations.clear();
        loader.calls.clear();
        if (saved != null) store.data['flutter.locale'] = saved;
        SharedPreferences.resetStatic();
        binding.platformDispatcher.localesTestValue = [system];
        await expectLater(EasyLocalization.initialize(config()), throwsStateError);
        expect(loader.calls, [saved != null || system == const Locale('de') ? const Locale('de') : const Locale('ru')]);
        expect(store.operations.where((operation) => operation == 'remove' || operation.startsWith('set:')), isEmpty);
        expect(store.data['flutter.locale'], saved);
        expect(() => EasyLocalization.instance, throwsStateError);
      }
    }
  });

  test('start initialization waits for confirmed persistence before publishing', () async {
    final gate = Completer<bool>();
    final started = Completer<void>();
    store.writeGate = gate;
    store.writeStarted = started;
    final pending = EasyLocalization.initialize(config(start: const Locale('de')));
    await started.future;
    expect(() => EasyLocalization.instance, throwsStateError);
    expect(() => tr('value'), throwsStateError);
    gate.complete(true);
    final owner = await pending;
    expect(owner.locale, const Locale('de'));
    expect(store.data['flutter.locale'], 'de');
  });

  test('save false makes no preferences calls through init, set, reset or delete', () async {
    store.failRead = true;
    store.data['flutter.locale'] = 42;
    binding.platformDispatcher.localesTestValue = [const Locale('ru')];
    final owner = await EasyLocalization.initialize(config(start: const Locale('de'), save: false));
    await owner.setLocale(const Locale('ru')).ready;
    await owner.resetLocale().ready;
    await owner.deleteSaveLocale();
    expect(owner.isSystemMode, isTrue);
    expect(store.operations, isEmpty);
    expect(store.data['flutter.locale'], 42);
  });

  test('reset deletes explicit choice and restart reapplies start or follows system', () async {
    binding.platformDispatcher.localesTestValue = [const Locale('ru')];
    final withStart = config(start: const Locale('de'));
    var owner = await EasyLocalization.initialize(withStart);
    await owner.resetLocale().ready;
    expect(owner.locale, const Locale('ru'));
    expect(owner.isSystemMode, isTrue);
    expect(store.data.containsKey('flutter.locale'), isFalse);
    owner.dispose();
    owner = await EasyLocalization.initialize(withStart);
    expect(owner.locale, const Locale('de'));
    expect(store.data['flutter.locale'], 'de');
    await owner.resetLocale().ready;
    owner.dispose();
    owner = await EasyLocalization.initialize(config());
    expect(owner.locale, const Locale('ru'));
    expect(owner.isSystemMode, isTrue);
    expect(store.data.containsKey('flutter.locale'), isFalse);
  });

  test('pending initialize deduplicates config identity and dispose permits a new owner', () async {
    final gate = Completer<Map<String, dynamic>?>();
    loader.gates['de'] = [gate];
    final inputs = config(start: const Locale('de'), save: false);
    final first = EasyLocalization.initialize(inputs);
    expect(EasyLocalization.initialize(inputs), same(first));
    expect(() => EasyLocalization.initialize(config()), throwsStateError);
    expect(() => EasyLocalization.instance, throwsStateError);
    gate.complete({'value': 'de'});
    final owner = await first;
    expect(await EasyLocalization.initialize(inputs), same(owner));
    final captured = owner.dataTranslator;
    owner.dispose();
    owner.dispose();
    expect(() => owner.setLocale(const Locale('ru')), throwsStateError);
    expect(() => owner.resetLocale(), throwsStateError);
    expect(() => owner.reloadTranslations(), throwsStateError);
    expect(() => owner.deleteSaveLocale(), throwsStateError);
    expect(() => EasyLocalization.instance, throwsStateError);
    expect(() => tr('value'), throwsStateError);
    expect(captured.tr('value'), 'de');
    expect(await EasyLocalization.initialize(inputs), isNot(same(owner)));
  });

  test('config owns ordered lists independently of the callers lists', () async {
    final supported = [const Locale('ru'), const Locale('de')];
    final extra = <AssetLoader>[];
    final delegates = <LocalizationsDelegate<dynamic>>[];
    final inputs = EasyLocalizationConfig(
      supportedLocales: supported,
      fallbackLocale: const Locale('ru'),
      path: 'unused',
      assetLoader: loader,
      extraAssetLoaders: extra,
      additionalDelegates: delegates,
      saveLocale: false,
    );
    supported.clear();
    extra.add(loader);
    delegates.add(DefaultWidgetsLocalizations.delegate);
    final owner = await EasyLocalization.initialize(inputs);
    expect(owner.config.supportedLocales, const [Locale('ru'), Locale('de')]);
    expect(owner.config.extraAssetLoaders, isEmpty);
    expect(owner.config.additionalDelegates, isEmpty);
    expect(() => owner.config.supportedLocales.clear(), throwsUnsupportedError);
  });

  test('newest locale and reload reserve revisions and discard late resources', () async {
    final owner = await EasyLocalization.initialize(config(start: const Locale('ru'), save: false));
    final old = Completer<Map<String, dynamic>?>();
    final middle = Completer<Map<String, dynamic>?>();
    final fresh = Completer<Map<String, dynamic>?>();
    loader.gates['de'] = [old, middle, fresh];
    final first = owner.setLocale(const Locale('de'));
    final second = owner.reloadTranslations();
    final reload = owner.reloadTranslations();
    expect(reload.revision, greaterThan(first.revision));
    expect(await first.ready, LocalizationDataOutcome.superseded);
    expect(await first.applied, LocalizationApplyOutcome.superseded);
    expect(await second.ready, LocalizationDataOutcome.superseded);
    fresh.complete({'value': 'fresh de'});
    expect(await reload.ready, LocalizationDataOutcome.committed);
    old.complete({'value': 'stale de'});
    middle.complete({'value': 'middle de'});
    expect(tr('value'), 'fresh de');
    final late = Completer<Map<String, dynamic>?>();
    loader.gates['ru'] = [late];
    final slow = owner.setLocale(const Locale('ru'));
    final latest = owner.setLocale(const Locale('de'));
    expect(await slow.ready, LocalizationDataOutcome.superseded);
    expect(await latest.ready, LocalizationDataOutcome.committed);
    late.complete({'value': 'stale ru'});
    expect(owner.locale, const Locale('de'));
  });

  test('committed snapshots isolate deep source maps, fallback and plural options', () async {
    final section = <dynamic, dynamic>{'value': 'original'};
    loader.data['ru'] = {
      'nested': section,
      'count': {'few': 'ru few', 'two': 'ru two', 'other': 'ru other'}
    };
    loader.data['de'] = {'fallback': 'fallback original'};
    final owner = await EasyLocalization.initialize(EasyLocalizationConfig(
      supportedLocales: const [Locale('ru'), Locale('de')],
      fallbackLocale: const Locale('de'),
      startLocale: const Locale('ru'),
      path: 'unused',
      assetLoader: loader,
      saveLocale: false,
      useFallbackTranslations: true,
      ignorePluralRules: false,
    ));
    final snapshot = owner.dataTranslator;
    section['value'] = 'mutated';
    loader.data['de'] = {
      'fallback': 'new fallback',
      'count': {'two': 'new two', 'other': 'new other'}
    };
    await owner.setLocale(const Locale('de')).ready;
    expect(snapshot.tr('nested.value'), 'original');
    expect(snapshot.tr('fallback'), 'fallback original');
    Localization.load(const Locale('de'), ignorePluralRules: true);
    expect(snapshot.tr('nested.value'), 'original');
    expect(snapshot.plural('count', 2), 'ru few');
    owner.dispose();
    expect(snapshot.tr('fallback'), 'fallback original');
  });

  test('storage errors retain committed data and retry without loading resources', () async {
    binding.platformDispatcher.localesTestValue = [const Locale('ru')];
    final owner = await EasyLocalization.initialize(config(start: const Locale('ru')));
    store.failWrite = true;
    final failed = owner.setLocale(const Locale('de'));
    await expectLater(failed.ready, throwsStateError);
    expect(tr('value'), 'de');
    expect(owner.state.value.errorStage, LocalizationErrorStage.persistence);
    expect(store.data['flutter.locale'], 'ru');
    final calls = loader.calls.length;
    store.failWrite = false;
    await owner.setLocale(const Locale('de')).ready;
    expect(loader.calls.length, calls);
    expect(store.data['flutter.locale'], 'de');
    store.failRemove = true;
    await expectLater(owner.resetLocale().ready, throwsStateError);
    expect(owner.isSystemMode, isTrue);
    expect(owner.locale, const Locale('ru'));
    final afterReset = loader.calls.length;
    store.failRemove = false;
    await owner.resetLocale().ready;
    expect(loader.calls.length, afterReset);
    expect(store.data.containsKey('flutter.locale'), isFalse);
    expect(owner.state.value.error, isNull);
  });

  test('already started storage writes finish in order and ready awaits confirmation', () async {
    final owner = await EasyLocalization.initialize(config(start: const Locale('ru')));
    final gate = Completer<bool>();
    final started = Completer<void>();
    store.writeGate = gate;
    store.writeStarted = started;
    final first = owner.setLocale(const Locale('de'));
    await started.future;
    var firstReady = false;
    first.ready.then((_) => firstReady = true);
    final second = owner.setLocale(const Locale('ru'));
    expect(firstReady, isFalse);
    gate.complete(true);
    expect(await first.ready, LocalizationDataOutcome.committed);
    expect(await second.ready, LocalizationDataOutcome.committed);
    expect(store.data['flutter.locale'], 'ru');
  });

  test('resource errors report the stage and disposal closes pending receipts', () async {
    final owner = await EasyLocalization.initialize(config(start: const Locale('ru'), save: false));
    final failure = StateError('resource failure');
    loader.failure = failure;
    final failed = owner.setLocale(const Locale('de'));
    await expectLater(failed.ready, throwsA(same(failure)));
    expect(await failed.applied, LocalizationApplyOutcome.failed);
    expect(owner.locale, const Locale('ru'));
    expect(owner.state.value.errorStage, LocalizationErrorStage.resources);
    loader.failure = null;
    final gate = Completer<Map<String, dynamic>?>();
    loader.gates['de'] = [gate];
    final pending = owner.setLocale(const Locale('de'));
    owner.dispose();
    expect(await pending.ready, LocalizationDataOutcome.disposed);
    expect(await pending.applied, LocalizationApplyOutcome.disposed);
    gate.complete({'value': 'late'});
  });
}
