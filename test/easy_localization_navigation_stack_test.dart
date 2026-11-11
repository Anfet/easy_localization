import 'dart:ui' as ui;

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  for (final legacy in [false, true]) {
    testWidgets('A B C retained routes update from C, legacy=$legacy', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await EasyLocalization.ensureInitialized();
      EasyLocalizationInstance? owner;
      final keys = List.generate(3, (_) => GlobalKey<_ScreenState>());
      final app = _App(
        first: _Screen(
          key: keys[0],
          name: 'A',
          next: _Screen(
            key: keys[1],
            name: 'B',
            next: _Screen(key: keys[2], name: 'C'),
          ),
        ),
      );
      try {
        if (legacy) {
          await tester.pumpWidget(
            EasyLocalization(
              supportedLocales: const [Locale('en'), Locale('ar')],
              fallbackLocale: const Locale('en'),
              startLocale: const Locale('en'),
              path: 'unused',
              saveLocale: false,
              assetLoader: const _Loader(),
              child: app,
            ),
          );
        } else {
          owner = await EasyLocalization.initialize(
            EasyLocalizationConfig(
              supportedLocales: const [Locale('en'), Locale('ar')],
              fallbackLocale: const Locale('en'),
              startLocale: const Locale('en'),
              path: 'unused',
              saveLocale: false,
              assetLoader: const _Loader(),
            ),
          );
          await tester.pumpWidget(EasyLocalization.withInstance(instance: owner, child: app));
        }
        await tester.pumpAndSettle();
        for (final name in ['A', 'B', 'C']) {
          await tester.enterText(find.byType(TextField), 'input $name');
          await tester.tap(find.text('increment'));
          await tester.pump();
          if (name != 'C') {
            await tester.tap(find.text('next'));
            await tester.pumpAndSettle();
          }
        }
        final states = keys.map((key) => key.currentState).toList();
        final activeOwner = EasyLocalization.instance;
        await activeOwner.setLocale(const Locale('ar'));
        final presentation = activeOwner.waitForPresentation();
        await tester.pumpAndSettle();
        expect(await presentation, LocalizationApplyOutcome.applied);
        // Observe covered routes before pop can rebuild them.
        for (final name in ['A', 'B', 'C']) {
          expect(
            find.descendant(
              of: find.byKey(keys[['A', 'B', 'C'].indexOf(name)], skipOffstage: false),
              matching: find.text('ar', skipOffstage: false),
              skipOffstage: false,
            ),
            findsOneWidget,
          );
        }
        expect(find.text('en', skipOffstage: false), findsNothing);
        for (var index = 0; index < keys.length; index++) {
          expect(keys[index].currentState, same(states[index]));
        }
        for (final name in ['C', 'B', 'A']) {
          expect(find.text('ar'), findsOneWidget);
          expect(find.text('count 1'), findsOneWidget);
          expect(tester.widget<TextField>(find.byType(TextField)).controller?.text, 'input $name');
          expect(Localizations.localeOf(tester.element(find.text('ar'))), const Locale('ar'));
          expect(Directionality.of(tester.element(find.text('ar'))), ui.TextDirection.rtl);
          if (name != 'A') {
            Navigator.of(tester.element(find.text('ar'))).pop();
            await tester.pumpAndSettle();
          }
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        owner?.dispose();
      }
    });
  }
}

class _App extends StatelessWidget {
  const _App({required this.first});
  final Widget first;

  @override
  Widget build(BuildContext context) => MaterialApp(
    locale: context.locale,
    supportedLocales: context.supportedLocales,
    localizationsDelegates: context.localizationDelegates,
    home: first,
  );
}

class _Screen extends StatefulWidget {
  const _Screen({super.key, required this.name, this.next});
  final String name;
  final Widget? next;

  @override
  State<_Screen> createState() => _ScreenState();
}

class _ScreenState extends State<_Screen> {
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.name),
        const _Leaf(),
        TextField(controller: input),
        Text('count $count'),
        TextButton(onPressed: () => setState(() => count++), child: const Text('increment')),
        if (widget.next != null)
          TextButton(
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => widget.next ?? const SizedBox.shrink())),
            child: const Text('next'),
          ),
      ],
    ),
  );

  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  final input = TextEditingController();
  int count = 0;
}

class _Leaf extends StatelessWidget {
  const _Leaf();

  @override
  Widget build(BuildContext context) => Text('value'.tr());
}

class _Loader extends AssetLoader {
  const _Loader();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async => {'value': locale.languageCode};
}
