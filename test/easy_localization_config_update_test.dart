import 'dart:async';
import 'dart:ui' as ui;

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Loader extends AssetLoader {
  _Loader([this.gate])
    : super(
        fileLoader: const RootBundleFileLoader(),
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
      );
  final Completer<Map<String, dynamic>>? gate;
  int loads = 0;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) {
    loads++;
    return gate?.future ?? Future.value({'value': 'ok'});
  }
}

void main() {
  testWidgets('rejects changed legacy configuration during bootstrap and after readiness', (tester) async {
    for (final pending in [true, false]) {
      final gate = pending ? Completer<Map<String, dynamic>>() : null;
      final loader = _Loader(gate);
      final locales = [const Locale('en'), const Locale('de')];
      Widget root(String path) => EasyLocalization(
        supportedLocales: locales,
        path: path,
        startLocale: const Locale('en'),
        saveLocale: false,
        assetLoader: loader,
        child: const Text('child', textDirection: ui.TextDirection.ltr),
      );
      await tester.pumpWidget(root('first'));
      if (!pending) await tester.pumpAndSettle();
      locales.add(const Locale('fr'));
      await tester.pumpWidget(root('second'));
      expect(tester.takeException(), isA<StateError>());
      gate?.complete({'value': 'ok'});
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      try {
        EasyLocalization.instance.dispose();
      } on StateError {
        // The root already disposed its owner.
      }
    }
  });

  testWidgets('rejects each changed owner input', (tester) async {
    final loader = _Loader();
    final otherLoader = _Loader();
    for (var change = 0; change < 12; change++) {
      Widget root(bool changed) => EasyLocalization(
        supportedLocales: changed && change == 0 ? [const Locale('en'), const Locale('fr')] : [const Locale('en'), const Locale('de')],
        path: changed && change == 1 ? 'other' : 'first',
        fallbackLocale: changed && change == 2 ? const Locale('de') : const Locale('en'),
        startLocale: changed && change == 3 ? const Locale('de') : const Locale('en'),
        assetLoader: changed && change == 4 ? otherLoader : loader,
        extraAssetLoaders: changed && change == 5 ? [otherLoader] : [],
        useOnlyLangCode: changed && change == 6,
        useFallbackTranslations: changed && change == 7,
        useBaseLanguageFallback: changed && change == 8,
        useFallbackTranslationsForEmptyResources: changed && change == 9,
        saveLocale: changed && change == 10,
        additionalDelegates: changed && change == 11 ? [DefaultWidgetsLocalizations.delegate] : [],
        child: const SizedBox(),
      );
      await tester.pumpWidget(root(false));
      await tester.pumpAndSettle();
      await tester.pumpWidget(root(true));
      expect(tester.takeException(), isA<StateError>(), reason: 'input $change');
      await tester.pumpWidget(const SizedBox());
      try {
        EasyLocalization.instance.dispose();
      } on StateError {
        // The root already disposed its owner.
      }
    }
  });

  testWidgets('equal lists and UI updates retain owner; a new key permits new configuration', (tester) async {
    final loader = _Loader();
    Widget root(Key key, String path, String text) => EasyLocalization(
      key: key,
      supportedLocales: [const Locale('en'), const Locale('de')],
      extraAssetLoaders: [],
      additionalDelegates: [],
      path: path,
      startLocale: const Locale('en'),
      saveLocale: false,
      assetLoader: loader,
      errorWidget: (_) => Text(text, textDirection: ui.TextDirection.ltr),
      child: Text(text, textDirection: ui.TextDirection.ltr),
    );
    await tester.pumpWidget(root(const ValueKey(1), 'first', 'one'));
    await tester.pumpAndSettle();
    final owner = EasyLocalization.instance;
    await tester.pumpWidget(root(const ValueKey(1), 'first', 'two'));
    await tester.pumpAndSettle();
    expect(find.text('two'), findsOneWidget);
    expect(EasyLocalization.instance, same(owner));
    expect(loader.loads, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(root(const ValueKey(2), 'second', 'three'));
    await tester.pumpAndSettle();
    expect(find.text('three'), findsOneWidget);
    expect(EasyLocalization.instance, isNot(same(owner)));
    await tester.pumpWidget(const SizedBox());
  });
}
