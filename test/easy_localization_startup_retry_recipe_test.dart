import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class RetryLoader extends AssetLoader {
  RetryLoader()
    : super(
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
        fileLoader: const RootBundleFileLoader(),
      );

  bool available = false;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    if (!available) throw StateError('Resource unavailable');
    return {'title': 'Hello'};
  }
}

class Startup extends StatefulWidget {
  const Startup({super.key, required this.config});
  final EasyLocalizationConfig config;

  @override
  State<Startup> createState() => _StartupState();
}

class _StartupState extends State<Startup> {
  late Future<EasyLocalizationInstance> startup;
  EasyLocalizationInstance? owner;

  @override
  void initState() {
    super.initState();
    startup = EasyLocalization.initialize(widget.config);
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<EasyLocalizationInstance>(
    future: startup,
    builder: (context, snapshot) {
      if (snapshot.hasError) {
        return MaterialApp(
          home: TextButton(
            onPressed: () => setState(() {
              startup = EasyLocalization.initialize(widget.config);
            }),
            child: const Text('Retry'),
          ),
        );
      }
      if (!snapshot.hasData) return const MaterialApp(home: CircularProgressIndicator());
      owner = snapshot.data;
      return EasyLocalization.withInstance(instance: snapshot.requireData, child: const MyApp());
    },
  );

  @override
  void dispose() {
    owner?.dispose();
    super.dispose();
  }
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final owner = EasyLocalization.instance;
    return MaterialApp(
      locale: owner.presentationLocale,
      supportedLocales: owner.supportedLocales,
      localizationsDelegates: owner.delegates,
      home: Scaffold(body: Text('title'.tr())),
    );
  }
}

void main() {
  testWidgets('retries startup after the resource becomes available', (tester) async {
    final loader = RetryLoader();
    final config = EasyLocalizationConfig(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      path: 'unused',
      saveLocale: false,
      assetLoader: loader,
    );
    await tester.pumpWidget(Startup(config: config));
    await tester.pumpAndSettle();
    expect(find.text('Retry'), findsOneWidget);
    expect(() => EasyLocalization.instance, throwsStateError);

    loader.available = true;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(() => EasyLocalization.instance, throwsStateError);
  });
}
