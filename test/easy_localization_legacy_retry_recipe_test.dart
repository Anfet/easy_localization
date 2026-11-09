import 'dart:async';

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RetryLoader extends AssetLoader {
  RetryLoader()
    : super(
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
        fileLoader: const RootBundleFileLoader(),
      );

  final requests = <Completer<Map<String, dynamic>?>>[];

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) {
    final request = Completer<Map<String, dynamic>?>();
    requests.add(request);
    return request.future;
  }
}

class LegacyStartup extends StatefulWidget {
  const LegacyStartup({super.key, required this.loader});
  final RetryLoader loader;

  @override
  State<LegacyStartup> createState() => _LegacyStartupState();
}

class _LegacyStartupState extends State<LegacyStartup> {
  Key rootKey = UniqueKey();

  @override
  Widget build(BuildContext context) => EasyLocalization(
    key: rootKey,
    supportedLocales: const [Locale('en')],
    startLocale: const Locale('en'),
    path: 'unused',
    saveLocale: false,
    assetLoader: widget.loader,
    errorWidget: (_) => MaterialApp(
      home: TextButton(onPressed: () => setState(() => rootKey = UniqueKey()), child: const Text('Retry')),
    ),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        home: Builder(builder: (context) => Text(context.tr('value'))),
      ),
    ),
  );
}

void main() {
  testWidgets('initial load failure can be retried from error widget', (tester) async {
    final loader = RetryLoader();
    await tester.pumpWidget(LegacyStartup(loader: loader));
    loader.requests.single.completeError(StateError('unavailable'));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(() => EasyLocalization.instance, throwsStateError);

    await tester.tap(find.text('Retry'));
    await tester.pump();
    loader.requests.last.complete({'value': 'English'});
    await tester.pumpAndSettle();
    expect(find.text('English'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(() => EasyLocalization.instance, throwsStateError);
  });

  testWidgets('unmount during initialization does not publish a late owner', (tester) async {
    final loader = RetryLoader();
    await tester.pumpWidget(LegacyStartup(loader: loader));
    await tester.pumpWidget(const SizedBox.shrink());
    loader.requests.single.complete({'value': 'English'});
    await tester.pumpAndSettle();
    expect(() => EasyLocalization.instance, throwsStateError);
    expect(tester.takeException(), isNull);
  });
}
