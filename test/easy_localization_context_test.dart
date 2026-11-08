import 'dart:io';
import 'dart:ui' as ui;

import 'package:easy_localization_continued/src/translations.dart';

import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class NonlinearScaler extends TextScaler {
  const NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize + 5;
  @override
  double get textScaleFactor => 1.5;
}

late BuildContext _context;

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      locale: context.locale,
      supportedLocales: context.supportedLocales,
      localizationsDelegates: context.localizationDelegates,
      home: const MyWidget(),
    );
  }
}

class MyWidget extends StatelessWidget {
  const MyWidget({Key? key}) : super(key: key);

  @override
  Widget build(context) {
    _context = context;
    return Scaffold(body: Column(children: <Widget>[const Text('test').tr(), const Text('day').plural(1)]));
  }
}

void main() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  await EasyLocalization.ensureInitialized();

  test('Text extensions preserve properties and nonlinear scaling', () {
    Localization.load(
      const Locale('en'),
      translations: Translations({
        'key': 'value',
        'count': {'one': 'one'},
      }),
    );
    const original = Text(
      'key',
      key: ValueKey('text'),
      style: TextStyle(fontSize: 14),
      strutStyle: StrutStyle(fontSize: 12),
      textAlign: TextAlign.center,
      textDirection: ui.TextDirection.ltr,
      locale: Locale('ru'),
      softWrap: false,
      overflow: TextOverflow.ellipsis,
      textScaler: NonlinearScaler(),
      maxLines: 2,
      semanticsLabel: 'label',
      semanticsIdentifier: 'id',
      textWidthBasis: TextWidthBasis.longestLine,
      textHeightBehavior: TextHeightBehavior(applyHeightToFirstAscent: false),
      selectionColor: Color(0xff123456),
    );
    final translated = original.tr();
    expect(translated.data, 'value');
    expect(translated.key, original.key);
    expect(translated.style, original.style);
    expect(translated.strutStyle, original.strutStyle);
    expect(translated.textAlign, original.textAlign);
    expect(translated.textDirection, original.textDirection);
    expect(translated.locale, original.locale);
    expect(translated.softWrap, original.softWrap);
    expect(translated.overflow, original.overflow);
    expect(translated.textScaler, same(original.textScaler));
    expect(translated.maxLines, original.maxLines);
    expect(translated.semanticsLabel, original.semanticsLabel);
    expect(translated.semanticsIdentifier, original.semanticsIdentifier);
    expect(translated.textWidthBasis, original.textWidthBasis);
    expect(translated.textHeightBehavior, original.textHeightBehavior);
    expect(translated.selectionColor, original.selectionColor);
    final plural = const Text('count', textScaler: NonlinearScaler(), semanticsIdentifier: 'id').plural(1);
    expect(plural.data, 'one');
    expect(plural.textScaler, isA<NonlinearScaler>());
    expect(plural.semanticsIdentifier, 'id');
    // ignore: deprecated_member_use
    expect(const Text('key', textScaleFactor: 1.7).tr().textScaleFactor, 1.7);
    // ignore: deprecated_member_use
    expect(const Text('count', textScaleFactor: 1.7).plural(1).textScaleFactor, 1.7);
    Localization.publish(null);
  });

  testWidgets('unscoped context throws even with global translations', (tester) async {
    Localization.load(const Locale('en'));
    late BuildContext context;
    await tester.pumpWidget(
      Builder(
        builder: (value) {
          context = value;
          return const SizedBox();
        },
      ),
    );
    expect(() => tr('key', context: context), throwsA(isA<LocalizationNotFoundException>()));
    expect(() => plural('key', 1, context: context), throwsA(isA<LocalizationNotFoundException>()));
    expect(() => trExists('key', context: context), throwsA(isA<LocalizationNotFoundException>()));
    expect(() => context.locale, throwsA(isA<LocalizationNotFoundException>()));
    expect(() => context.tr('key'), throwsA(isA<LocalizationNotFoundException>()));
    expect(() => const Text.rich(TextSpan(text: 'key')).tr(context: context), throwsArgumentError);
    expect(() => const Text.rich(TextSpan(text: 'key')).plural(1, context: context), throwsArgumentError);
    Localization.publish(null);
  });

  group('BuildContext', () {
    testWidgets('[EasyLocalization] _getFallbackLocale() fallbackLocale!=null test', (WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          EasyLocalization(
            path: '../../i18n',
            saveLocale: false,
            useOnlyLangCode: true,
            supportedLocales: const [Locale('ar')],
            fallbackLocale: const Locale('ar'),
            child: const MyApp(),
          ),
        );
        await tester.idle();
        // The async delegator load will require build on the next frame. Thus, pump
        await tester.pump();

        expect(_context.supportedLocales, [const Locale('ar')]);
        expect(_context.locale, const Locale('ar'));
        expect(_context.fallbackLocale, const Locale('ar'));
      });
    });

    testWidgets('[EasyLocalization] _getFallbackLocale()  fallbackLocale==null test', (WidgetTester tester) async {
      await tester.runAsync(() async {
        await tester.pumpWidget(
          EasyLocalization(
            path: '../../i18n',
            saveLocale: false,
            useOnlyLangCode: true,
            // fallbackLocale:Locale('en') ,
            supportedLocales: const [Locale('ar')], // Locale('en', 'US'), Locale('ar','DZ')
            child: const MyApp(),
          ),
        );
        await tester.idle();
        // The async delegator load will require build on the next frame. Thus, pump
        await tester.pump();

        expect(_context.supportedLocales, [const Locale('ar')]);
        expect(_context.locale, const Locale('ar'));
        expect(_context.fallbackLocale, null);
      });
    });

    group('SharedPreferences deleteSaveLocale()', () {
      setUpAll(() async {
        SharedPreferences.setMockInitialValues({'locale': 'ar_DZ'});
        await EasyLocalization.ensureInitialized();
      });
      testWidgets('[EasyLocalization] deleteSaveLocale  test', (WidgetTester tester) async {
        await tester.runAsync(() async {
          await tester.pumpWidget(
            EasyLocalization(
              path: '../../i18n',
              // fallbackLocale:Locale('en') ,
              supportedLocales: const [Locale('en', 'US'), Locale('ar', 'DZ')], // Locale('en', 'US'), Locale('ar','DZ')
              child: const MyApp(),
            ),
          );
          await tester.idle();
          // The async delegator load will require build on the next frame. Thus, pump
          await tester.pump();

          expect(_context.locale, const Locale('ar', 'DZ'));
          await _context.deleteSaveLocale();
        });
      });

      testWidgets('[EasyLocalization] after deleteSaveLocale test', (WidgetTester tester) async {
        await tester.runAsync(() async {
          await tester.pumpWidget(
            EasyLocalization(
              path: '../../i18n',
              // fallbackLocale:Locale('en') ,
              supportedLocales: const [Locale('en', 'US'), Locale('ar', 'DZ')], // Locale('en', 'US'), Locale('ar','DZ')
              child: const MyApp(),
            ),
          );
          await tester.idle();
          // The async delegator load will require build on the next frame. Thus, pump
          await tester.pump();

          expect(_context.locale, const Locale('en', 'US'));
        });
      });

      testWidgets('[EasyLocalization] device locale  test', (WidgetTester tester) async {
        await tester.runAsync(() async {
          await tester.pumpWidget(
            EasyLocalization(
              path: '../../i18n',
              supportedLocales: const [Locale('en', 'US'), Locale('ar', 'DZ')], // Locale('en', 'US'), Locale('ar','DZ')
              child: const MyApp(),
            ),
          );
          await tester.idle();
          // The async delegator load will require build on the next frame. Thus, pump
          await tester.pump();

          expect(_context.deviceLocale.toString(), Platform.localeName);
        });
      });

      testWidgets('[EasyLocalization] reset device locale  test', (WidgetTester tester) async {
        await tester.runAsync(() async {
          await tester.pumpWidget(
            EasyLocalization(
              path: '../../i18n',
              supportedLocales: const [Locale('en', 'US'), Locale('ar', 'DZ')], // Locale('en', 'US'), Locale('ar','DZ')
              startLocale: const Locale('ar', 'DZ'),
              saveLocale: false,
              child: const MyApp(),
            ),
          );
          await tester.idle();
          // The async delegator load will require build on the next frame. Thus, pump
          await tester.pump();

          expect(_context.locale, const Locale('ar', 'DZ'));
          // reset to device locale
          await _context.resetLocale();
          await tester.pump();
          expect(_context.locale, const Locale('en', 'US'));
        });
      });

      testWidgets('[EasyLocalization] device locale  test', (WidgetTester tester) async {
        await tester.runAsync(() async {
          await tester.pumpWidget(
            EasyLocalization(
              path: '../../i18n',
              supportedLocales: const [Locale('en', 'US'), Locale('ar', 'DZ')], // Locale('en', 'US'), Locale('ar','DZ')
              child: const MyApp(),
            ),
          );
          await tester.idle();
          // The async delegator load will require build on the next frame. Thus, pump
          await tester.pumpAndSettle();

          expect(_context.deviceLocale.toString(), Platform.localeName);
        });
      });

      testWidgets('[EasyLocalization] reset device locale  test', (WidgetTester tester) async {
        await tester.runAsync(() async {
          await tester.pumpWidget(
            EasyLocalization(
              path: '../../i18n',
              supportedLocales: const [Locale('en', 'US'), Locale('ar', 'DZ')], // Locale('en', 'US'), Locale('ar','DZ')
              startLocale: const Locale('ar', 'DZ'),
              saveLocale: false,
              child: const MyApp(),
            ),
          );
          await tester.idle();
          // The async delegator load will require build on the next frame. Thus, pump
          await tester.pumpAndSettle();

          expect(_context.locale, const Locale('ar', 'DZ'));
          // reset to device locale
          await _context.resetLocale();
          await tester.pumpAndSettle();
          expect(_context.locale, const Locale('en', 'US'));
        });
      });
    });
  });
}
