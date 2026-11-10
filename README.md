<p align="center"><img src="https://raw.githubusercontent.com/Anfet/easy_localization/develop/logo/logo.svg?sanitize=true" width="600"/></p>
<h1 align="center"> 
Easy and Fast internationalization for your Flutter Apps
</h1>

[![Pub Version](https://img.shields.io/pub/v/easy_localization_continued?style=flat-square&logo=dart)](https://pub.dev/packages/easy_localization_continued)
[![likes](https://img.shields.io/pub/likes/easy_localization_continued)](https://pub.dev/packages/easy_localization_continued/score)
[![pub points](https://img.shields.io/pub/points/easy_localization_continued)](https://pub.dev/packages/easy_localization_continued/score)
![GitHub issues](https://img.shields.io/github/issues/Anfet/easy_localization?style=flat-square)
![GitHub contributors](https://img.shields.io/github/contributors/Anfet/easy_localization?style=flat-square)
![GitHub stars](https://img.shields.io/github/stars/Anfet/easy_localization?style=flat-square)
![GitHub license](https://img.shields.io/github/license/Anfet/easy_localization?style=flat-square)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)

This repository is a community-maintained fork of [aissat/easy_localization](https://github.com/aissat/easy_localization). It continues development of the Easy Localization library. The original project is credited under its MIT license; see [LICENSE](LICENSE).

## Why easy_localization?

- 🚀 Easy translations for many languages
- 🔌 Load JSON translations or implement a custom asset loader for other sources
- 💾 React and persist to locale changes
- ⚡ Supports plural, gender, nesting, RTL locales and more
- ↩️ Fallback locale keys redirection
- ⁉️ Error widget for missing translations
- ❤️ Extension methods on `Text` and `BuildContext`
- 💻 Code generation for localization files and keys.
- 🛡️ Null safety
- 🖨️ Configurable diagnostic callbacks, silent by default.
- 🔄 A shared localization owner for startup, locale changes, explicit resource reloads, and translations outside the widget tree.

## Version 4.0.0 highlights

Version 4.0.0 requires Dart 3.12 and Flutter 3.44. It adds a single localization owner that can initialize before `runApp`, awaitable locale changes with separate data and presentation outcomes, explicit translation reloads, strict missing-key auditing, and JavaScript/WASM browser locale support. The new owner also changes plural and base-language fallback defaults, and replaces the removed logger API with optional diagnostic callbacks.

Existing apps should review [Compatibility and migration](#compatibility-and-migration-to-400) before upgrading. The guide covers legacy behavior, loader requirements, errors, and the migration from `EasyLocalization.logger` and the synchronous locale setter.

## Getting Started

### 🔩 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  easy_localization_continued: ^4.0.0
```

Create folder and add translation files like this

```
assets
└── translations
    ├── {languageCode}.{ext}                  //only language code
    └── {languageCode}-{countryCode}.{ext}    //or full locale code
```

Example:

```
assets
└── translations
    ├── en.json
    └── en-US.json 
```

Declare your assets localization directory in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/translations/
```



### 🔌 Loading translations from other resources

The built-in loader reads JSON assets. Implement a custom `AssetLoader` for other sources. The upstream [Easy Localization Loader](https://github.com/aissat/easy_localization_loader) depends on `easy_localization` 3.x and cannot be used directly with this package; its loaders require porting.

### ⚠️ Note on **iOS**

For translation to work on **iOS** you need to add supported locales to 
`ios/Runner/Info.plist` as described [here](https://flutter.dev/docs/development/accessibility-and-localization/internationalization#specifying-supportedlocales).

Example:

```xml
<key>CFBundleLocalizations</key>
<array>
	<string>en</string>
	<string>nb</string>
</array>
```

### ⚙️ Configuration app

Initialize once before `runApp` and use the same owner for the root and Flutter resources:

```dart
import 'package:flutter/material.dart';
import 'package:easy_localization_continued/easy_localization.dart';

void main() async {
  final owner = await EasyLocalization.initialize(EasyLocalizationConfig(
    supportedLocales: const [Locale('en', 'US'), Locale('de', 'DE')],
    fallbackLocale: const Locale('en', 'US'),
    path: 'assets/translations',
  ));
  runApp(EasyLocalization.withInstance(instance: owner, child: const MyApp()));
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
```

[**Full example**](example/lib/main.dart)

### 📜 Easy localization widget properties

| Properties              | Required | Default                   | Description                                                                                                                                                                   |
| ----------------------- | -------- | ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| key                     | false    |                           | Widget key.                                                                                                                                                                   |
| child                   | true     |                           | Place for your main page widget.                                                                                                                                              |
| supportedLocales        | true     |                           | List of supported locales.                                                                                                                                                    |
| path                    | true     |                           | Path to your folder with localization files.                                                                                                                                  |
| assetLoader             | false    | `const RootBundleAssetLoader(fileLoader: RootBundleFileLoader(), linkedFileResolver: JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()))` | Class loader for localization files. Use `RootBundleAssetLoader.fromRootBundle()` for an equivalent loader, or implement a custom loader for other sources. |
| extraAssetLoaders       | false    | null                      | A list of compatible asset loaders for additional modules or packages.             |
| fallbackLocale          | false    |                           | Returns the locale when the locale is not in the list `supportedLocales`.                                                                                                     |
| startLocale             | false    |                           | Overrides device locale.                                                                                                                                                      |
| saveLocale              | false    | `true`                    | Save locale in device storage.                                                                                                                                                |
| useFallbackTranslations | false    | `false`                   | If a localization key is not found in the locale file, try to use the fallbackLocale file.                                                                                    |
| useBaseLanguageFallback | false | `false` | Load a base language before the configured fallback when fallback translations are enabled. |
| useFallbackTranslationsForEmptyResources | false    | `false`                   | Treat empty strings as missing, even when no fallback resource is loaded; try any loaded base and fallback resources.                  |
| useOnlyLangCode         | false    | `false`                   | Trigger for using only language code for reading localization files.</br></br>Example:</br>`en.json //useOnlyLangCode: true`</br>`en-US.json //useOnlyLangCode: false`        |
| errorWidget             | false    | `ErrorWidget`     | Shows a custom error widget when an error occurs.                                                                                                                             |

## Usage

### Testing

Initialize a fresh owner before pumping the widget, and unmount the root before
disposing it. This in-memory loader returns a completed future, so this example
needs neither `runAsync` nor asset bundle access:

```dart
import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryLoader extends AssetLoader {
  MemoryLoader(this.translations)
    : super(
        linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
        fileLoader: const RootBundleFileLoader(),
      );

  final Map<String, dynamic> translations;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.value(translations);
}

void main() {
  testWidgets('English title and plural use the first owner', (tester) async {
    final owner = await EasyLocalization.initialize(
      EasyLocalizationConfig(
        supportedLocales: const [Locale('en')],
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        path: 'unused',
        saveLocale: false,
        assetLoader: MemoryLoader({
          'title': 'Hello',
          'items': {'one': '{} item', 'other': '{} items'},
        }),
      ),
    );
    try {
      await tester.pumpWidget(
        EasyLocalization.withInstance(
          instance: owner,
          child: Builder(builder: (context) => MaterialApp(
            locale: owner.presentationLocale,
            supportedLocales: owner.supportedLocales,
            localizationsDelegates: owner.delegates,
            home: Scaffold(
              body: Column(
                mainAxisSize: MainAxisSize.max,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [Text(tr('title')), Text('items'.plural(2))],
              ),
            ),
          )),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('2 items'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      owner.dispose();
    }
  });
}
```

The [runnable recipe](test/easy_localization_testing_recipe_test.dart) includes a
second independent test with another locale and dictionary. Real bundle or plugin
operations can require `tester.runAsync`; this memory loader does not. If you use
`saveLocale: true`, set up mock preferences before initializing the owner.

For [Alchemist](https://pub.dev/packages/alchemist), use its [custom pumping](https://github.com/Betterment/alchemist#custom-pumping-behavior) to initialize a fresh owner before the golden subtree. With `MemoryLoader` above and `alchemist` in dev dependencies:

```dart
import 'package:alchemist/alchemist.dart';

goldenTest(
  'translated title',
  fileName: 'translated_title',
  builder: () => Builder(builder: (_) => Text(tr('title'))),
  pumpWidget: (tester, widget) async {
    final owner = await EasyLocalization.initialize(EasyLocalizationConfig(
      supportedLocales: const [Locale('en')],
      fallbackLocale: const Locale('en'),
      startLocale: const Locale('en'),
      path: 'unused',
      saveLocale: false,
      assetLoader: MemoryLoader({'title': 'Hello'}),
    ));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      owner.dispose();
    });
    await tester.pumpWidget(EasyLocalization.withInstance(
      instance: owner,
      child: Builder(builder: (context) => MaterialApp(
        locale: owner.presentationLocale,
        supportedLocales: owner.supportedLocales,
        localizationsDelegates: owner.delegates,
        home: widget,
      )),
    ));
  },
  whilePerforming: (tester) async {
    expect(find.text('Hello'), findsOneWidget);
    return null;
  },
);
```

Register this inside `main()`. The [complete Windows example](example/test/localization_golden_test.dart) loads Roboto, checks English and Russian plurals, and compares readable platform goldens. From `example`, run `flutter pub get`, then `flutter test --no-pub test/localization_golden_test.dart`; add `--update-goldens` to regenerate the baselines.

### 🔥 Initialize library

For translations before `runApp`, initialize one owner with an explicit supported
fallback. No `BuildContext`, frame, or separate locale copy is needed:

```dart
final config = EasyLocalizationConfig(
  supportedLocales: const [Locale('en'), Locale('de')],
  fallbackLocale: const Locale('en'),
  path: 'assets/translations',
);
final localization = await EasyLocalization.initialize(config);
final initialText = tr('title');
await localization.setLocale(const Locale('de'));
runApp(EasyLocalization.withInstance(instance: localization, child: const MyApp()));
```

The root prepares every Flutter delegate before publishing a presentation. Register
custom delegates in `EasyLocalizationConfig(additionalDelegates: [MyDelegate()])`
(or the legacy constructor's `additionalDelegates`). Wire all three provider values:

```dart
// In MyApp.build, under EasyLocalization.withInstance:
return MaterialApp(
  locale: localization.presentationLocale,
  supportedLocales: localization.supportedLocales,
  localizationsDelegates: localization.delegates,
  home: const MyHomePage(),
);
// In build: ordinary widgets update even in retained const subtrees and routes.
Text('title'.tr());
TextField(decoration: InputDecoration(hintText: 'hint'.tr()));
TextButton(onPressed: submit, child: Text('submit'.tr()));
```

Build MaterialApp in a widget under the root so it is recreated on presentation changes. A MaterialApp created before that build captures its parameters and will not update. A widget rebuilt under the root can use `localization.presentationLocale`,
`localization.supportedLocales`, and `localization.delegates` as the corresponding
MaterialApp values. `localization.locale` reflects committed data and may advance
while the Flutter resources are still loading.

Keep custom asynchronous delegates inside that config to include them in the same
atomic presentation. While they load, Flutter resources and global `tr`/`plural`
keep showing the previous presentation; `dataTranslator` already reads committed
data. Delegate errors preserve the previous presentation and appear in
`localization.state` with `errorStage == LocalizationErrorStage.flutterDelegates`.
Issue another command to retry. A `ValueListenableBuilder<LocalizationState>` can
show progress while `state.isLoading` and display errors.

Await a command for resources and storage, then await `localization.waitForPresentation()` when visible completion matters. Its outcome can be `applied`, `superseded`, `detached`, `failed`, or `disposed`; `applied` confirms root publication when the consumer is wired as above; it does not inspect an arbitrary MaterialApp. Borrowed owners survive root removal. Strings computed outside build remain captured values. For a local scope use a scoped adapter or an explicit translator.

`initialize` ensures the Flutter binding and completes after all selected resources
and the required startup write. It chooses `startLocale` first, otherwise the saved
choice when `saveLocale: true`, otherwise a supported system locale or the required
fallback. Start and fallback must exactly belong to `supportedLocales`. A supplied
start is saved after loading; reset follows the system and deletes the explicit
choice, and a subsequent startup with start applies and saves it again. System and
fallback choices are never saved as explicit choices. The instance follows the engine’s ordered preferred locale list at startup, on locale events,
and on resume. For each preferred locale it first selects an exact supported match. If that region is unsupported, it checks later preferred locales for the first exact supported region of the same language before applying the existing script, country, or first-supported match. The engine may supply a default `en_US`; the library adds no English default.
Resume reads the engine list and does not force a browser language refresh or guarantee iOS per-app events.

Invalid, unsupported, or unreadable saved data is ignored with a warning, without deleting it.
Resource failures throw. A startup write failure leaves translations available and reports a persistence error in state; selecting the language again retries the write. A valid start overrides old saved data.
With `saveLocale: false`, initialize, set, reset, and delete never access preferences.
To restore a manual selection, omit `startLocale` on subsequent launches. The stored `locale` key and existing language/script/country forms remain compatible; no storage migration is needed.
The legacy widget constructor uses the same startup priority and defaults the fallback to the first supported locale; both paths disable base-language fallback by default. Its configuration must remain unchanged while the root is mounted, including during startup. To change it, completely unmount the old root and finish that frame, then mount a new root with a new key in a later frame. Supported locale lists are compared by value, loaders by identity, and delegates by `==`; create loaders and delegates once outside `build` or use `const`.

A ready root can be replaced in one frame with a new key when it uses the same configuration, or the same borrowed owner. A legacy-owned root passes ownership to the replacement. A waiter for presentation receives `detached` during the replacement. To use a different legacy configuration, render a placeholder for one frame before mounting the new root with a new key.

Commands return `Future<void>`. A persistence error may leave committed data available; repeating the selection retries storage. Read `dataTranslator` for a snapshot and `state` for progress and errors. Dispose the owner when no longer needed. Global access before readiness or after disposal throws `StateError`. Reusing the same config object reuses initialization; another config requires disposing the current owner first.

`await EasyLocalization.ensureInitialized(config)` is a facade for initialization; obtain the owner with `EasyLocalization.instance`. The no-argument compatibility call only prepares Flutter and does not load translations.

### 🔥 Change or get locale

Use the owner to change or inspect the locale:

```dart
await localization.setLocale(const Locale('en', 'US'));
final outcome = await localization.waitForPresentation();
if (outcome == LocalizationApplyOutcome.applied) {
  // The new language is visible.
}
```

Handle command errors and non-applied outcomes. A newer command can supersede an outstanding load. A storage failure can leave the new data active; selecting it again retries persistence.

After updating your `AssetLoader` data and its cache, call `await localization.reloadTranslations()`. It reloads the requested language and its fallback, superseding any outstanding locale change or reload. The superseded command completes with `LocalizationOperationSupersededException`. A later command can supersede the reload in turn. A failed reload leaves the previous translations available. Await `localization.waitForPresentation()` and check for `LocalizationApplyOutcome.applied` when the updated widgets must be visible.

For an initial loading failure, keep the same config outside the localization root and retry initialization from a startup screen. The root is created only after initialization succeeds:

```dart
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
        return MaterialApp(home: TextButton(
          onPressed: () => setState(() { startup = EasyLocalization.initialize(widget.config); }),
          child: const Text('Retry'),
        ));
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
```

Call `runApp(Startup(config: config))`. Ensure the startup widget stays mounted until initialization completes; dispose a successfully initialized owner when it is no longer needed.

For the legacy `EasyLocalization` root, an initial loading error is shown before a localization owner or provider is ready. Keep the root key in its parent and create a new key to retry; do not call context or global localization APIs from the error widget. `reloadTranslations()` is for an owner that has already initialized.

```dart
class LegacyStartup extends StatefulWidget {
  const LegacyStartup({super.key});

  @override
  State<LegacyStartup> createState() => _LegacyStartupState();
}

class _LegacyStartupState extends State<LegacyStartup> {
  Key rootKey = UniqueKey();

  @override
  Widget build(BuildContext context) => EasyLocalization(
    key: rootKey,
    supportedLocales: const [Locale('en')],
    path: 'assets/translations',
    errorWidget: (_) => MaterialApp(
      home: TextButton(
        onPressed: () => setState(() => rootKey = UniqueKey()),
        child: const Text('Retry'),
      ),
    ),
    child: const MyApp(),
  );
}
```

### 🔥 Translate with `tr()`

```dart
Text(tr('title'));
Text('title'.tr());
```

Ordinary widgets under the root rebuild when presentation changes. `Text('title').tr()` is optional sugar that preserves Text properties and uses the ordinary rebuild; it has no separate subscription. Values computed outside build are snapshots.

#### Arguments:

| Name      | Type                  | Description                                                                         |
| --------- | --------------------- | ----------------------------------------------------------------------------------- |
| args      | `List<String>`        | List of localized strings. Replaces `{}` left to right                              |
| namedArgs | `Map<String, String>` | Map of localized strings. Replaces the name keys `{key_name}` according to its name |
| gender    | `String`              | Gender switcher. Changes the localized string based on gender string                |

Example:

``` json
{
   "msg":"{} are written in the {} language",
   "msg_named":"Easy localization is written in the {lang} language",
   "msg_mixed":"{} are written in the {lang} language",
   "gender":{
      "male":"Hi man ;) {}",
      "female":"Hello girl :) {}",
      "other":"Hello {}"
   }
}
```

```dart
// args
Text('msg'.tr(args: ['Easy localization', 'Dart'])),

// namedArgs
Text('msg_named'.tr(namedArgs: {'lang': 'Dart'})),

// args and namedArgs
Text('msg_mixed'.tr(args: ['Easy localization'], namedArgs: {'lang': 'Dart'})),

// gender
Text('gender'.tr(gender: _gender ? 'female' : 'male')),

```

### 🔥 Plurals `plural()`

You can translate with pluralization.
To insert a number in the translated string, use `{}`. Number formatting supported, for more information read [NumberFormat](https://pub.dev/documentation/intl/latest/intl/NumberFormat-class.html) class documentation.

A `plural()` or `.plural()` call made during a widget build under the localization root is recalculated when the root publishes a new presentation, even in retained routes; passing `context` is not required for this root rebuild. A result saved outside build is a snapshot and does not update. Use a scoped adapter or explicit translator for a local scope.

#### Arguments:

| Name      | Type                  | Description                                                                                                                  |
| --------- | --------------------- | ---------------------------------------------------------------------------------------------------------------------------- |
| value     | `num`                 | Number value for pluralization                                                                                               |
| args      | `List<String>`        | List of localized strings. Replaces `{}` left to right                                                                       |
| namedArgs | `Map<String, String>` | Map of localized strings. Replaces the name keys `{key_name}` according to its name                                          |
| name      | `String`              | Name of number value. Replaces `{$name}` to value                                                                            |
| format    | `NumberFormat`        | Formats a numeric value using a [NumberFormat](https://pub.dev/documentation/intl/latest/intl/NumberFormat-class.html) class |

Example:

``` json
{
  "day": {
    "zero":"{} дней",
    "one": "{} день",
    "two": "{} дня",
    "few": "{} дня",
    "many": "{} дней",
    "other": "{} дней"
  },
  "money": {
    "zero": "You not have money",
    "one": "You have {} dollar",
    "many": "You have {} dollars",
    "other": "You have {} dollars"
  },
  "money_args": {
    "zero": "{} has no money",
    "one": "{} has {} dollar",
    "many": "{} has {} dollars",
    "other": "{} has {} dollars"
  },
  "money_named_args": {
    "zero": "{name} has no money",
    "one": "{name} has {money} dollar",
    "many": "{name} has {money} dollars",
    "other": "{name} has {money} dollars"
  }
}
```
⚠️ Key "other" required!

```dart
//Text widget with format
Text('money'.plural(1000000, format: NumberFormat.compact(locale: localization.presentationLocale.toString()))) // output: You have 1M dollars

//String
print('day'.plural(21)); // output: 21 день

//Static function
var money = plural('money', 10.23) // output: You have 10.23 dollars

// Force a supported, preloaded locale without changing the UI language
Text(plural('money', 10.23, locale: const Locale('de')))

//Static function with arguments
var money = plural('money_args', 10.23, args: ['John', '10.23'])  // output: John has 10.23 dollars

//Static function with named arguments
var money = plural('money_named_args', 10.23, namedArgs: {'name': 'Jane', 'money': '10.23'})  // output: Jane has 10.23 dollars
var money = plural('money_named_args', 10.23, namedArgs: {'name': 'Jane'}, name: 'money')  // output: Jane has 10.23 dollars
```

### ⚙️ Plural rules

The package uses `Intl.pluralLogic` with the full locale. If present, `zero`, `one`, and `two` are selected for exact 0, 1, and 2; these explicit cases extend CLDR. Otherwise the locale's CLDR category is used, then `other`. For the TWO category, a missing `two` falls back to `few` then `other`.

For English, 3, 4, and 5 use `other` even when `few` or `many` are present. Russian uses `one`, `few`, and `many` for 21, 22, and 5. Each language's own forms are tried before base and fallback translations, using each source locale's rules.

### 🔥 Linked translations:

If there's a translation key that will always have the same concrete text as another one you can just link to it. To link to another translation key, all you have to do is to prefix its contents with an `@:` sign followed by the full name of the translation key including the namespace you want to link to.

Example:
```json
{
  ...
  "example": {
    "hello": "Hello",
    "world": "World!",
    "helloWorld": "@:example.hello @:example.world"
  }
  ...
}
```

```dart
print('example.helloWorld'.tr()); //Output: Hello World!
```

You can also do nested anonymous and named arguments inside the linked messages.

Example:

```json
{
  ...
  "date": "{currentDate}.",
  "dateLogging": "INFO: the date today is @:date"
  ...
}
```
```dart
print('dateLogging'.tr(namedArgs: {'currentDate': DateTime.now().toIso8601String()})); //Output: INFO: the date today is 2020-11-27T16:40:42.657.
```

#### Formatting linked translations:

Formatting linked locale messages
If the language distinguishes cases of character, you may need to control the case of the linked locale messages. Linked messages can be formatted with modifier `@.modifier:key`

The below modifiers are available currently.

- `upper`: Uppercase all characters in the linked message.
- `lower`: Lowercase all characters in the linked message.
- `capitalize`: Capitalize the first character in the linked message.

Example:

```json
{
  ...
  "example": {
    "fullName": "Full Name",
    "emptyNameError": "Please fill in your @.lower:example.fullName"
  }
  ...
}
```

Output:

```dart
print('example.emptyNameError'.tr()); //Output: Please fill in your full name
```

### 🔥 Linked files:

You can split translations for a single locale into multiple files by using linked files. This helps keep your JSON clean and maintainable.

To link an external file, set the key’s value to a path prefixed with `:/`, relative to your translations directory. For example, with default path `assets/translations` and locale `en-US`:

```json
{
  "errors": ":/errors.json",
  "validation": ":/validation.json",
  "notifications": ":/notifications.json"
}
```

At runtime, Easy Localization will load:
```
assets
└── translations
    └── en-US
        ├── errors.json 
        ├── validation.json  
        └── notifications.json  
```

The built-in JSON resolver uses `language[-Script][-COUNTRY]/file.json`: for example,
`en/errors.json`, `en-US/errors.json`, `zh-Hans/errors.json`, `zh-Hant/errors.json`, and
`zh-Hans-CN/errors.json`. A missing script-specific file is an error; another script is not used as a fallback.
The same file may be linked from separate branches, while cycles and chains deeper than 32 links are errors.

Custom `LinkedFileResolver` subclasses must add the optional `String? scriptCode` parameter to their `resolveLinkedFiles` override and forward it to `super.resolveLinkedFiles` when applicable. Overrides of `getLinkedLocalePath` must also accept `scriptCode`. Replace `resolveLinkedFilesForLocale` overrides and calls with `resolveLinkedFiles`.

Each linked file must contain a valid object of translation keys (of the file type you are using [Other file types](#-loading-translations-from-other-resources)).  

Don't forget to add your linked files (or linked files folder, here assets/translations/en-US/), to your pubspec.yaml : [See installation](#-installation).

### 🔥 Reset locale `resetLocale()`

`resetLocale` returns to following the system language, including future system changes, and removes the saved selection. `startLocale` takes precedence over a saved selection; either prevents system changes from overriding the selection until reset. If translations fail to load, the current language and selection mode remain active. A storage failure completes the reset future with an error after the language has changed.

```dart
await localization.resetLocale();
final outcome = await localization.waitForPresentation();
// Treat only LocalizationApplyOutcome.applied as visible success.
```

### 🔥 Get device locale `deviceLocale`

Get device locale

Example:

```dart
print(localization.deviceLocale.toString()) // OUTPUT: en_US
```

### 🔥 Delete save locale `deleteSaveLocale()`

Clears a saved locale without changing the current selection mode:

```dart
await localization.deleteSaveLocale();
```

### 🔥 Get Easy localization widget properties

At any time, you can take the main [properties](#-easy-localization-widget-properties) of the Easy localization widget using [BuildContext].

Are supported: supportedLocales, fallbackLocale, localizationDelegates.

Example:

```dart
print(localization.supportedLocales); // output: [en_US, ar_DZ, de_DE, ru_RU]

print(localization.fallbackLocale); // output: en_US
```

## 💻 Code generation

Code generation supports only json files, for more information run in terminal `dart run easy_localization_continued:generate -h`

### Command line arguments

| Arguments                    | Short | Default               | Description                                                                 |
| ---------------------------- | ----- | --------------------- | --------------------------------------------------------------------------- |
| --help                       | -h    |                       | Help info                                                                   |
| --source-dir                 | -S    | assets/translations  | Folder containing localization files                                        |
| --source-file                | -s    | First JSON by name    | File to use for localization                                                |
| --output-dir                 | -O    | lib/generated         | Output folder stores for the generated file                                 |
| --output-file                | -o    | codegen_loader.g.dart | Output file name                                                            |
| --format                     | -f    | json                  | Support json or keys formats                                                |
| --[no-]skip-unnecessary-keys | -u    | false                 | Ignores keys defining nested object except for pluarl(), gender() keywords. |

### 🔌 Localization asset loader class

Steps:

1. Open your terminal in the folder's path containing your project
2. Run in terminal `dart run easy_localization_continued:generate`
3. Change asset loader and past import.

  ```dart
  import 'generated/codegen_loader.g.dart';
  ...
  void main() async {
    final owner = await EasyLocalization.initialize(EasyLocalizationConfig(
      supportedLocales: const [Locale('en', 'US'), Locale('ar', 'DZ')],
      fallbackLocale: const Locale('en', 'US'),
      path: 'assets/translations',
      assetLoader: CodegenLoader(),
    ));
    runApp(EasyLocalization.withInstance(instance: owner, child: const MyApp()));
  }
  ...
  ```
  
4. All done!

### 📦 Localization support for multi module/package project

If you want to add localization support from other modules and packages you can add them via `extraAssetLoaders` parameter:

```dart
  void main() async {
    final owner = await EasyLocalization.initialize(EasyLocalizationConfig(
      supportedLocales: const [Locale('en', 'US'), Locale('ar', 'DZ')],
      fallbackLocale: const Locale('en', 'US'),
      path: 'assets/translations',
      assetLoader: CodegenLoader(),
      extraAssetLoaders: [
        FeatureOneLoader(), // Your AssetLoader subclasses.
        FeatureTwoLoader(),
      ],
    ));
    runApp(EasyLocalization.withInstance(instance: owner, child: const MyApp()));
  }
```

### 🔑 Localization keys

If you have many localization keys and are confused, key generation will help you. The code editor will automatically prompt keys

Keys are generated from a single JSON file, never combined across languages. By default, the first regular `.json` file
in ordinal filename order is used. Pass `--source-file` to choose a complete fallback language file when another file
does not contain every key. JSON loader generation uses all regular `.json` files in the same filename order unless a
source file is specified. JSON loader filenames must have a nonempty locale name using only ASCII letters, digits, underscores, and hyphens. Hyphens become underscores, so names such as `en-US.json` and `en_US.json` cannot be used together. Linked JSON files are resolved during generation for both formats, so generated loaders do not read them at runtime. Missing or invalid sources and broken links produce exit code 1 and leave the existing output untouched.

Steps:
1. Open your terminal in the folder's path containing your project 
2. Run in terminal `dart run easy_localization_continued:generate -f keys -o locale_keys.g.dart`
3. Past import.

```dart
import 'generated/locale_keys.g.dart';
```
4. All done!

How to use generated keys:

```dart
Text(LocaleKeys.title.tr());
// Optionally, use the Text extension:
Text(LocaleKeys.title).tr();
```

String leaves, including plural and gender forms, have generated constants; `-u` only controls parent constants. Generated identifiers must be public Dart identifiers (they cannot start with `_`) and must not be reserved words or collide after nested paths are joined with underscores. For example, `auth.login`, `bad-key`, `class`, and the combination of `a_b` with nested `a.b` cannot be generated. The command reports an error and preserves the existing output. Direct runtime translation keys can still contain dots.

Since 4.0.0, generated keys re-export the translation extensions. The keys output is a Flutter-facing artifact and is not a standalone Dart library.

### ✅ Audit missing keys

If you prefer to not generate keys you can see an audit of your translation keys to see the one present in your app code but not in your translations file by running the audit command.

```
dart run easy_localization_continued:audit
```

If you are not using the default translations folder path (assets/translations) or the lib folder for your code you can specify your custom paths : 

| Arguments                    | Short | Default               | Description                                                                 |
| ---------------------------- | ----- | --------------------- | --------------------------------------------------------------------------- |
| --translations-dir           | -t    | assets/translations   | Folder containing localization files                                        |
| --source-dir                 | -s    | lib                   | Folder containing the app code files                                        |
| --strict                     |       | false                 | Exit with code 2 when a static key is missing or a plural lacks `other`      |

For CI, run `dart run easy_localization_continued:audit --strict`. Exit code 0 means the audit completed without confirmed missing keys (or strict mode is off); 2 means strict mode found a missing static key or a plural without `other`; 1 means the audit could not complete, such as an invalid option, unreadable input, invalid JSON, or no JSON locales. The report and warnings go to stdout; errors go to stderr.

The audit uses a limited pattern scanner for literal keys in `tr` and `plural` calls, including literal or `LocaleKeys` String receivers, Text with named arguments, and bare or prefixed calls such as `loc.tr` and `EasyLocalization.instance.dataTranslator.tr`. It scans executable expressions inside string interpolation while ignoring ordinary string examples and comments. It reads literal `static const` values for `LocaleKeys` from Dart files in the source directory. Conflicting values, interpolated keys, dynamic expressions and unresolved constants are unverified; receiver types are not resolved, and complex Dart syntax can exceed the scanner's limits; this is not a full Dart parser.

Each JSON locale is checked independently, without app configuration or fallback. A translation must be a string; plural calls need at least one string plural form, and a missing `other` is reported as a warning and fails strict mode. A top-level literal gender checks that form, while a dynamic gender remains unverified; named arguments inside nested helpers do not affect the outer call. The audit does not determine which plural form a particular locale and value will select. For static calls, it follows links reachable from the selected string, literal gender form, and available string plural forms, reporting missing or non-string targets with their paths. Cycles and dynamic calls remain unverified; this does not verify the entire application.


## Diagnostic callbacks

Diagnostics are silent by default. Set any of the three independent callbacks before
`ensureInitialized(config)` to receive messages, including initialization messages:

```dart
WidgetsFlutterBinding.ensureInitialized();
EasyLocalization.onVerbose = (message, {stackTrace}) { /* send to your logger */ };
EasyLocalization.onWarning = (message, {stackTrace}) { /* send to your logger */ };
EasyLocalization.onError = (message, {stackTrace}) { /* send to your logger */ };
final config = EasyLocalizationConfig(
  supportedLocales: const [Locale('en', 'US')],
  fallbackLocale: const Locale('en', 'US'),
  path: 'assets/translations',
);
await EasyLocalization.ensureInitialized(config);
```

Each callback runs synchronously in the current zone. Resource errors include their
original stack trace. Set a callback to `null` to disable that category. The application
controls filtering, formatting and output, and receives callback exceptions through `FlutterError.reportError`; callback exceptions do not affect localization work. The application remains responsible for handling those reported errors.

This replaces the incompatible `EasyLocalization.logger` API:

| Previous API | Migration |
| --- | --- |
| `logger` | Set `onVerbose`, `onWarning` and/or `onError`. |
| `enableLevels` | Set only the callbacks for levels you need. Debug and info use `onVerbose`. |
| `enableBuildModes` | Apply build-mode filtering in your application. |
| `printer` | Forward each callback to your own logging function. |

## ➕ Extensions helpers

### String to locale

```dart
'en_US'.toLocale(); // Locale('en', 'US')

//with custom separator
'en|US'.toLocale(separator: '|') // Locale('en', 'US')
```
### Locale to String with separator

```dart
Locale('en', 'US').toStringWithSeparator(separator: '|') // en|US
```


## Screenshots

| Arabic RTL                                                                                                                  | English LTR                                                                                                                   | Error widget                                                                                                                     |
| --------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| ![Arabic RTL](https://raw.githubusercontent.com/Anfet/easy_localization/develop/screenshots/Screenshot_ar.png "Arabic RTL") | ![English LTR](https://raw.githubusercontent.com/Anfet/easy_localization/develop/screenshots/Screenshot_en.png "English LTR") | ![Error widget](https://raw.githubusercontent.com/Anfet/easy_localization/develop/screenshots/Screenshot_err.png "Error widget") |

### Contributors thanks

![contributors](https://contributors-img.firebaseapp.com/image?repo=Anfet/easy_localization)
<a href="https://github.com/Anfet/easy_localization/graphs/contributors"></a>

### Translating a document in another language

An independent translator keeps its language and resources while the interface changes:

```dart
final document = await EasyLocalization.instance.translators.once(const Locale('ru'));
final title = document.tr('invoice.title');
final items = document.plural('invoice.items', 3);

// Load again when the document should use the latest resources.
final refreshedDocument = await EasyLocalization.instance.translators.once(document.locale);
```

The requested locale must be in `supportedLocales`. A translator remains usable after the owner is disposed.


## Compatibility and migration to 4.0.0

Replace the `easy_localization` dependency with `easy_localization_continued: ^4.0.0`, change imports from `package:easy_localization/easy_localization.dart` to `package:easy_localization_continued/easy_localization.dart`, and regenerate keys and loaders using `dart run easy_localization_continued:generate` with your existing arguments. Replace `easy_localization:generate` and `easy_localization:audit` in scripts with `easy_localization_continued:generate` and `easy_localization_continued:audit`. The entrypoint filename and current API calls remain the same; this does not promise full 3.x API compatibility. Constraints such as `^3.0.8` do not automatically select 4.0.0.

Migrate apps and shared packages together so they use the same library. The upstream `easy_localization_loader` depends on `easy_localization: ^3.0.8`: changing a dependency key or override does not make its `AssetLoader` the new package's type. Port each upstream loader to the new import and the current required `AssetLoader` super constructor (`fileLoader` and `linkedFileResolver`), including its missing-resource and error contract described below.

The minimum SDKs are Dart 3.12 and Flutter 3.44. In 3.x, a saved locale took precedence over `startLocale`; in 4.0, `startLocale` is applied and saved on every launch. Omit `startLocale` to preserve the user's saved choice. Remove the `ignorePluralRules` argument when migrating; all constructors use the plural rules described above.

`fallbackLocale` selects a supported startup locale; it does not enable key fallback. Enable `useFallbackTranslations` separately. Both startup paths disable `useBaseLanguageFallback` by default. When enabled for a region, strict owners load primary, then one language-and-script base, then configured fallback. A custom loader must return null only for confirmed missing resources, return `{}` for a successful empty resource, and throw for failures. A missing optional base is skipped; missing primary or configured fallback throws before commit. RootBundle loader throws on missing assets, so opt in only when the base asset exists or a custom loader reports confirmed absence. Duplicate normalized resources are loaded once per operation.

`trExists(key)` checks primary strings only. `includeFallback: true` also checks already loaded fallback strings; with `useFallbackTranslationsForEmptyResources: true`, empty strings do not count. Non-string values never count. This does not load resources or resolve links/plurals. `Text.tr` and `Text.plural` preserve Text properties; translate each `TextSpan` string with `String.tr` for rich text.

For a Russian-only application, `supportedLocales: [Locale('ru')]` and `fallbackLocale: Locale('ru')` are sufficient. No English locale is required. Context calls require their own scope and throw `LocalizationNotFoundException`; global calls before readiness or after disposal throw `StateError`. A missing key in a ready dictionary still returns the key and invokes the warning callback if set.

| Consumer migration | Action |
| --- | --- |
| App UI passing context, completers or delays for localization | After installing the owner, remove UI context passing, completers, delays, reassemble calls and duplicate current UI locale state where they only coordinate localization. |
| Business and network | Keep server/guest language as business data, and choose the network-to-asset fallback policy explicitly. Use `translators.once(locale)` for a document in another language. |
| App operations | Propagate errors from awaited locale changes to the pending action; do not report success from `finally`. |

This fork has an `AssetLoader` constructor with `fileLoader` and `linkedFileResolver`; it differs from upstream `easy_localization_loader`. The removed `easy_logger`/`logger` integration is replaced by optional `onVerbose`, `onWarning`, and `onError` callbacks, silent by default. Await command futures and handle exceptions; await `waitForPresentation()` before treating a change as visible.

`setLocale`, `context.setLocale` and the deprecated locale setter can fail with `LocalizationOperationSupersededException` when superseded, or with a storage error. Replace the deprecated setter with `setLocale` or `context.setLocale`, await the returned future and handle errors in `onTap`. Calling a change without awaiting can produce an unhandled asynchronous error; a setter assignment cannot await its underlying operation.


| Earlier API | 4.0 migration |
| --- | --- |
| Change receipts and revisions | Await the command Future, observe `state`, then await `waitForPresentation()` for visible completion. |
| Context translation extensions | Use `tr`, `String.tr` and owner commands; use a scoped adapter or explicit translator for local overrides. |
| `ignorePluralRules` | Remove it; the unified plural rules apply. |

`translators.once(locale)` loads an independent immutable snapshot. `translators` also manages cached snapshots; held snapshots survive reload, cache eviction and owner disposal. Load a locale before forcing it in global calls:

```dart
await localization.translators.load([const Locale('de')]);
final title = tr('title', locale: const Locale('de'));
final snapshot = localization.translators[const Locale('de')];
localization.translators.unload(const Locale('de'));
```

`preloadLocales` loads snapshots during initialization; `loadAll()` loads all supported locales. Unloading removes the cache reference, not a snapshot already held by the caller.
