import 'package:easy_localization/easy_localization.dart';
//import 'package:easy_localization_loader/easy_localization_loader.dart'; // import custom loaders
import 'package:flutter/material.dart';

import 'generated/locale_keys.g.dart';
import 'lang_view.dart';

final localizationConfig = EasyLocalizationConfig(
  supportedLocales: [Locale('en', 'US'), Locale('ar', 'DZ'), Locale('de', 'DE'), Locale('ru', 'RU')],
  fallbackLocale: Locale('en', 'US'),
  path: 'resources/langs',
  // Register every custom Flutter delegate here, e.g. additionalDelegates: [MyDelegate()].
  // startLocale: Locale('de', 'DE'),
  // saveLocale: false,
  // useOnlyLangCode: true,
  // useBaseLanguageFallback: true, // Requires base assets or a loader that returns null for confirmed absence.

  // optional assetLoader default used is RootBundleAssetLoader which uses flutter's assetloader
  // install easy_localization_loader for enable custom loaders
  // assetLoader: RootBundleAssetLoader()
  // assetLoader: HttpAssetLoader()
  // assetLoader: FileAssetLoader()
  // assetLoader: CsvAssetLoader()
  // assetLoader: YamlAssetLoader() //multiple files
  // assetLoader: YamlSingleAssetLoader() //single file
  // assetLoader: XmlAssetLoader() //multiple files
  // assetLoader: XmlSingleAssetLoader() //single file
  // assetLoader: CodegenLoader()
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localization = await EasyLocalization.initialize(localizationConfig);
  // A ValueListenableBuilder on localization.state can show loading/error in the UI.
  // Commands wait for data/storage; waitForPresentation observes the root.
  // Data commands also work here, before a widget exists:
  // await localization.setLocale(const Locale('de', 'DE'));
  runApp(EasyLocalization.withInstance(instance: localization, child: MyApp()));
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final localization = EasyLocalization.instance;
    return MaterialApp(
      localizationsDelegates: localization.delegates,
      supportedLocales: localization.supportedLocales,
      locale: localization.presentationLocale,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue)),
      home: MyHomePage(title: 'Easy localization'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  int counter = 0;
  bool _gender = true;
  bool _resetting = false;

  void incrementCounter() {
    setState(() {
      counter++;
    });
  }

  void switchGender(bool val) {
    setState(() {
      _gender = val;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(LocaleKeys.title.tr()),
        actions: <Widget>[
          IconButton(
            onPressed: () {
              Navigator.push(context, MaterialPageRoute(builder: (_) => LanguageView(), fullscreenDialog: true));
            },
            icon: Icon(Icons.language),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Spacer(flex: 1),
            Text(
              LocaleKeys.gender_with_arg.tr(args: ['aissat'], gender: _gender ? 'female' : 'male'),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 19, fontWeight: FontWeight.bold),
            ),
            Text(
              tr(LocaleKeys.gender, gender: _gender ? 'female' : 'male'),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 15, fontWeight: FontWeight.bold),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(Icons.male),
                Switch(value: _gender, onChanged: switchGender),
                Icon(Icons.female),
              ],
            ),
            Spacer(flex: 1),
            Text(LocaleKeys.msg.tr(args: ['aissat', 'Flutter'])),
            Text(LocaleKeys.msg_named.tr(namedArgs: {'lang': 'Dart'}, args: ['Easy localization'])),
            Text(LocaleKeys.clicked.plural(counter)),
            TextButton(
              onPressed: () {
                incrementCounter();
              },
              child: Text(LocaleKeys.clickMe.tr()),
            ),
            SizedBox(height: 15),
            Text(
              plural(
                LocaleKeys.amount,
                counter,
                format: NumberFormat.currency(locale: EasyLocalization.instance.presentationLocale.toString(), symbol: '€'),
              ),
              style: TextStyle(color: Colors.grey.shade900, fontSize: 18, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 20),
            ValueListenableBuilder<LocalizationState>(
              valueListenable: EasyLocalization.instance.state,
              builder: (context, state, _) => ElevatedButton(
                onPressed: state.isLoading || _resetting
                    ? null
                    : () async {
                        setState(() => _resetting = true);
                        try {
                          final localization = EasyLocalization.instance;
                          await localization.resetLocale();
                          final outcome = await localization.waitForPresentation();
                          if (outcome != LocalizationApplyOutcome.applied && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Language reset was not applied: $outcome')));
                          }
                        } catch (error) {
                          if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Language reset failed: $error')));
                        } finally {
                          if (mounted) setState(() => _resetting = false);
                        }
                      },
                child: _resetting ? const CircularProgressIndicator() : Text(LocaleKeys.reset_locale.tr()),
              ),
            ),
            Spacer(flex: 1),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(onPressed: incrementCounter, child: Text('+1')),
    );
  }
}
