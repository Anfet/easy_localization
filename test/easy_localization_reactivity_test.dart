import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('context translations update const subtrees while route and state survive', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
    await tester.pumpWidget(EasyLocalization(
      supportedLocales: const [Locale('en'), Locale('de')],
      startLocale: const Locale('en'),
      saveLocale: false,
      path: 'unused',
      assetLoader: const _Loader(),
      child: const _App(),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('increment'));
    await tester.pump();
    final state = tester.state(find.byType(_Page));
    expect(find.text('en context'), findsOneWidget);
    expect(find.text('en string'), findsOneWidget);
    expect(find.text('en text'), findsOneWidget);
    expect(find.text('en plural'), findsOneWidget);
    expect(find.text('en snapshot'), findsOneWidget);
    expect(find.text('count 1'), findsOneWidget);

    await tester.tap(find.text('change'));
    await tester.pumpAndSettle();
    expect(find.text('de context'), findsOneWidget);
    expect(find.text('de string'), findsOneWidget);
    expect(find.text('de text'), findsOneWidget);
    expect(find.text('de plural'), findsOneWidget);
    expect(find.text('de snapshot'), findsOneWidget);
    expect(find.text('count 1'), findsOneWidget);
    expect(tester.state(find.byType(_Page)), same(state));
    expect(ModalRoute.of(tester.element(find.byType(_Page)))?.isCurrent, isTrue);
  });
}

class _Loader extends AssetLoader {
  const _Loader()
      : super(linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()), fileLoader: const RootBundleFileLoader());

  @override
  Future<Map<String, dynamic>> load(String fullPath, Locale locale) async => {
        'context': '${locale.languageCode} context',
        'string': '${locale.languageCode} string',
        'text': '${locale.languageCode} text',
        'plural': {'other': '${locale.languageCode} plural'},
        'snapshot': '${locale.languageCode} snapshot',
      };
}

class _App extends StatelessWidget {
  const _App();

  @override
  Widget build(BuildContext context) => MaterialApp(
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const _Page())),
                      child: const Text('open'),
                    ))),
      );
}

class _Page extends StatefulWidget {
  const _Page();

  @override
  State<_Page> createState() => _PageState();
}

class _PageState extends State<_Page> {
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _First(),
            const _Second(),
            const _Snapshot(),
            Text('count $count'),
            TextButton(onPressed: () => setState(() => count++), child: const Text('increment')),
            TextButton(onPressed: () => context.setLocale(const Locale('de')), child: const Text('change')),
          ],
        ),
      );

  int count = 0;
}

class _First extends StatelessWidget {
  const _First();
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Text(context.tr('context')), Text('string'.tr(context: context))],
      );
}

class _Second extends StatelessWidget {
  const _Second();
  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [const Text('text').tr(context: context), const Text('plural').plural(2, context: context)],
      );
}

class _Snapshot extends StatelessWidget {
  const _Snapshot();
  @override
  Widget build(BuildContext context) => Text(tr('snapshot'));
}
