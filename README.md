[![Stand With Palestine](https://raw.githubusercontent.com/TheBSD/StandWithPalestine/main/banner-no-action.svg)](https://thebsd.github.io/StandWithPalestine)

<p align="center"><img src="https://raw.githubusercontent.com/aissat/easy_localization/develop/logo/logo.svg?sanitize=true" width="600"/></p>
<h1 align="center"> 
Easy and Fast internationalization for your Flutter Apps
</h1>

[![Pub Version](https://img.shields.io/pub/v/easy_localization?style=flat-square&logo=dart)](https://pub.dev/packages/easy_localization)
[![likes](https://badges.bar/easy_localization/likes)](https://pub.dev/packages/easy_localization/score)
[![likes](https://badges.bar/easy_localization/popularity)](https://pub.dev/packages/easy_localization/score)
[![likes](https://badges.bar/easy_localization/pub%20points)](https://pub.dev/packages/easy_localization/score)
![Code Climate issues](https://img.shields.io/github/issues/aissat/easy_localization?style=flat-square)
![GitHub closed issues](https://img.shields.io/github/issues-closed/aissat/easy_localization?style=flat-square)
![GitHub contributors](https://img.shields.io/github/contributors/aissat/easy_localization?style=flat-square)
![GitHub repo size](https://img.shields.io/github/repo-size/aissat/easy_localization?style=flat-square)
![GitHub forks](https://img.shields.io/github/forks/aissat/easy_localization?style=flat-square)
![GitHub stars](https://img.shields.io/github/stars/aissat/easy_localization?style=flat-square)
![Coveralls github branch](https://img.shields.io/coveralls/github/aissat/easy_localization/dev?style=flat-square)
![GitHub Workflow Status](https://img.shields.io/github/workflow/status/aissat/easy_localization/Flutter%20Tester?longCache=true&style=flat-square&logo=github)
![CodeFactor Grade](https://img.shields.io/codefactor/grade/github/aissat/easy_localization?style=flat-square)
![GitHub license](https://img.shields.io/github/license/aissat/easy_localization?style=flat-square)
![Sponsors](https://img.shields.io/opencollective/all/flutter_easy_localization?style=flat-square)
![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg?style=flat-square)
[![StandWithPalestine](https://raw.githubusercontent.com/TheBSD/StandWithPalestine/main/badges/StandWithPalestine.svg)](https://github.com/TheBSD/StandWithPalestine/blob/main/docs/README.md)

## Why easy_localization?

- 🚀 Easy translations for many languages
- 🔌 Load translations as JSON, CSV, Yaml, Xml using [Easy Localization Loader](https://github.com/aissat/easy_localization_loader)
- 💾 React and persist to locale changes
- ⚡ Supports plural, gender, nesting, RTL locales and more
- ↩️ Fallback locale keys redirection
- ⁉️ Error widget for missing translations
- ❤️ Extension methods on `Text` and `BuildContext`
- 💻 Code generation for localization files and keys.
- 🛡️ Null safety
- 🖨️ Configurable diagnostic callbacks.

## Getting Started

### 🔩 Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  easy_localization: <last_version>
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

You can use JSON,CSV,HTTP,XML,Yaml files, etc.

See [Easy Localization Loader](https://github.com/aissat/easy_localization_loader) for more info.

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

Add EasyLocalization widget like in example

```dart
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:easy_localization/easy_localization.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  
  runApp(
    EasyLocalization(
      supportedLocales: [Locale('en', 'US'), Locale('de', 'DE')],
      path: 'assets/translations', // <-- change the path of the translation files 
      fallbackLocale: Locale('en', 'US'),
      child: MyApp()
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: MyHomePage()
    );
  }
}
```

[**Full example**](https://github.com/aissat/easy_localization/blob/master/example/lib/main.dart)

### 📜 Easy localization widget properties

| Properties              | Required | Default                   | Description                                                                                                                                                                   |
| ----------------------- | -------- | ------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| key                     | false    |                           | Widget key.                                                                                                                                                                   |
| child                   | true     |                           | Place for your main page widget.                                                                                                                                              |
| supportedLocales        | true     |                           | List of supported locales.                                                                                                                                                    |
| path                    | true     |                           | Path to your folder with localization files.                                                                                                                                  |
| assetLoader             | false    | `RootBundleAssetLoader()` | Class loader for localization files. You can use custom loaders from [Easy Localization Loader](https://github.com/aissat/easy_localization_loader) or create your own class. |
| extraAssetLoaders       | false    | null                      | A List of asset loaders, in case of needing assets being loaded from a different module or package. (e.g. adding a package that uses [Easy Localization Loader]).             |
| fallbackLocale          | false    |                           | Returns the locale when the locale is not in the list `supportedLocales`.                                                                                                     |
| startLocale             | false    |                           | Overrides device locale.                                                                                                                                                      |
| saveLocale              | false    | `true`                    | Save locale in device storage.                                                                                                                                                |
| useFallbackTranslations | false    | `false`                   | If a localization key is not found in the locale file, try to use the fallbackLocale file.                                                                                    |
| useFallbackTranslationsForEmptyResources | false    | `false`                   | If translation is empty in the locale file, try to use the fallbackLocale file. Does not take effect if `useFallbackTranslations` is false.                  |
| useOnlyLangCode         | false    | `false`                   | Trigger for using only language code for reading localization files.</br></br>Example:</br>`en.json //useOnlyLangCode: true`</br>`en-US.json //useOnlyLangCode: false`        |
| errorWidget             | false    | `FutureErrorWidget()`     | Shows a custom error widget when an error occurs.                                                                                                                             |

## Usage

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
await localization.setLocale(const Locale('de')).ready;
runApp(EasyLocalization.withInstance(instance: localization, child: const MyApp()));
```

`initialize` ensures the Flutter binding and completes after all selected resources
and the required startup write. It chooses `startLocale` first, otherwise the saved
choice when `saveLocale: true`, otherwise a supported system locale or the required
fallback. Start and fallback must exactly belong to `supportedLocales`. A supplied
start is saved after loading; reset follows the system and deletes the explicit
choice, and a subsequent startup with start applies and saves it again. System and
fallback choices are never saved as explicit choices. The current startup uses one
system locale; preferred language list and platform event matching are separate work.

Invalid saved data and resource/storage failures throw without silently trying a
different source or deleting the saved value. A valid start overrides old saved data.
With `saveLocale: false`, initialize, set, reset, and delete never access preferences.
The widget constructor retains legacy saved-before-start selection and optional
fallback; `ensureInitialized` below belongs to that legacy startup path.

Commands return a receipt synchronously: `ready` confirms data and persistence
without waiting for Flutter; `applied` describes presentation separately (detached
when no root is attached). A persistence error leaves committed data available and
repeating the same selection retries storage without loading again. Read
`dataTranslator` for an independent snapshot and `state` to observe progress/errors.
The borrowed root leaves its owner alive after unmount; call `dispose` when the
owner is no longer needed. Global access before readiness or after disposal throws
`StateError`. Reusing the same config object reuses initialization; another config
requires disposing the current owner first.

Call `EasyLocalization.ensureInitialized()` in your main before runApp.

```dart
void main() async{
  // ...
  // Needs to be called so that we can await for EasyLocalization.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  await EasyLocalization.ensureInitialized();
  // ...
  runApp(....)
  // ...
}
```

### 🔥 Change or get locale

Easy localization uses extension methods [BuildContext] for access to locale.

It's the easiest way change locale or get parameters 😉.

ℹ️ No breaking changes, you can use old the static method `EasyLocalization.of(context)`

Example:

```dart
await context.setLocale(Locale('en', 'US'));

print(context.locale.toString());
```

`setLocale` waits for translations and its assigned storage operation. A newer choice can supersede an outstanding load; the superseded future completes after that load without applying it. Loading and storage failures complete the future with an error. A storage failure leaves the new language active; choosing it again retries saving without reloading translations. Widgets display the change after the next frame.

After updating the data used by your `AssetLoader`, call `await context.reloadTranslations()` to reload the current language and its fallback. Update any cache owned by your loader before calling it. If a language change is loading, reload waits for it and refreshes the accepted language. A later language change supersedes that deferred reload. The future waits for its work and completes with an error if the current load fails; the previous translations remain available. A later language change or reload supersedes an outstanding refresh. Widgets display the new translations on the next frame.



For an initial loading failure, an `errorWidget` can retry using the same provider:

```dart
errorWidget: (error) => MaterialApp(
  home: Builder(
    builder: (context) => TextButton(
      onPressed: () => context.reloadTranslations(),
      child: const Text('Retry'),
    ),
  ),
),
```

### 🔥 Translate `context.tr()`

Main function for translate your language keys

You can use extension methods of [String] or [Text] widget, you can also use `tr()` as a static function.

```dart
Text(context.tr('title'))
```

In a widget build, pass `context` to subscribe to locale changes, including in const subtrees. Calls without context return a snapshot of the current translation and do not subscribe the widget; use them outside the UI or refresh the value explicitly.


```dart
Text('title').tr(context: context) //Text widget

print('title'.tr()); //String

var title = tr('title') //Static function
```

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
Text('msg').tr(context: context, args: ['Easy localization', 'Dart']),

// namedArgs
Text('msg_named').tr(context: context, namedArgs: {'lang': 'Dart'}),

// args and namedArgs
Text('msg_mixed').tr(context: context, args: ['Easy localization'], namedArgs: {'lang': 'Dart'}),

// gender
Text('gender').tr(context: context, gender: _gender ? "female" : "male"),

```

### 🔥 Plurals `plural()`

You can translate with pluralization.
To insert a number in the translated string, use `{}`. Number formatting supported, for more information read [NumberFormat](https://pub.dev/documentation/intl/latest/intl/NumberFormat-class.html) class documentation.

In UI builds, pass `context` to the String or Text extension or to `plural()`, or use `context.plural()`, to subscribe to locale changes. Without context the result is a snapshot.

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
Text('money').plural(1000000, context: context, format: NumberFormat.compact(locale: context.locale.toString())) // output: You have 1M dollars

//String
print('day'.plural(21)); // output: 21 день

//Static function
var money = plural('money', 10.23) // output: You have 10.23 dollars

//Text widget with plural BuildContext extension
Text(context.plural('money', 10.23))

//Static function with arguments
var money = plural('money_args', 10.23, args: ['John', '10.23'])  // output: John has 10.23 dollars

//Static function with named arguments
var money = plural('money_named_args', 10.23, namedArgs: {'name': 'Jane', 'money': '10.23'})  // output: Jane has 10.23 dollars
var money = plural('money_named_args', 10.23, namedArgs: {'name': 'Jane'}, name: 'money')  // output: Jane has 10.23 dollars
```

### ⚙️ Configuring Plural Rules with `ignorePluralRules`

In some languages, pluralization is simple and only involves using zero, one, two, and other forms, without needing to handle the `few` or `many` categories.  
By default, `easy_localization` ignores the `few` and `many` plural forms and uses just the zero, one, two, and other forms.

If you want to enable the handling of the `few` and `many` plural categories for specific languages, you can configure the `ignorePluralRules` flag to `false` in the `EasyLocalization` initialization.

Here’s how to configure it:

```dart
EasyLocalization(
  ignorePluralRules: false, // Set this line to false to enable 'few' and 'many' plural categories
  supportedLocales: [Locale('en', 'US'), Locale('de', 'DE')],
  path: 'assets/translations',
  fallbackLocale: Locale('en', 'US'),
  child: MyApp()
)
```

Setting `ignorePluralRules: false` will enable the `few` and `many` plural categories, allowing your translations to handle all plural forms, including `few` and `many`, for supported languages.



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
print('dateLogging'.tr(namedArguments: {'currentDate': DateTime.now().toIso8601String()})); //Output: INFO: the date today is 2020-11-27T16:40:42.657.
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

Custom `LinkedFileResolver` implementations with an existing `resolveLinkedFiles` override continue to work.
To handle script-specific locales in a custom resolver, override `resolveLinkedFilesForLocale` and use its
`scriptCode` argument. Existing direct calls to `resolveLinkedFiles` retain their previous paths.

Each linked file must contain a valid object of translation keys (of the file type you are using [Other file types](#-loading-translations-from-other-resources)).  

Don't forget to add your linked files (or linked files folder, here assets/translations/en-US/), to your pubspec.yaml : [See installation](#-installation).

### 🔥 Reset locale `resetLocale()`

`resetLocale` returns to following the system language, including future system changes, and removes the saved selection. A saved selection takes precedence over `startLocale`; either prevents system changes from overriding the selection until reset. If translations fail to load, the current language and selection mode remain active. A storage failure completes the reset future with an error after the language has changed.

Reset locale to device locale

Example:

```dart
RaisedButton(
  onPressed: (){
    context.resetLocale();
  },
  child: Text(LocaleKeys.reset_locale).tr(context: context),
)
```

### 🔥 Get device locale `deviceLocale`

Get device locale

Example:

```dart
print(context.deviceLocale.toString()) // OUTPUT: en_US
```

### 🔥 Delete save locale `deleteSaveLocale()`

Clears a saved locale from device storage

Example:

```dart
RaisedButton(
  onPressed: (){
    context.deleteSaveLocale();
  },
  child: Text(LocaleKeys.reset_locale).tr(context: context),
)
```

### 🔥 Get Easy localization widget properties

At any time, you can take the main [properties](#-easy-localization-widget-properties) of the Easy localization widget using [BuildContext].

Are supported: supportedLocales, fallbackLocale, localizationDelegates.

Example:

```dart
print(context.supportedLocales); // output: [en_US, ar_DZ, de_DE, ru_RU]

print(context.fallbackLocale); // output: en_US
```

## 💻 Code generation

Code generation supports only json files, for more information run in terminal `flutter pub run easy_localization:generate -h`

### Command line arguments

| Arguments                    | Short | Default               | Description                                                                 |
| ---------------------------- | ----- | --------------------- | --------------------------------------------------------------------------- |
| --help                       | -h    |                       | Help info                                                                   |
| --source-dir                 | -S    | resources/langs       | Folder containing localization files                                        |
| --source-file                | -s    | First JSON by name    | File to use for localization                                                |
| --output-dir                 | -O    | lib/generated         | Output folder stores for the generated file                                 |
| --output-file                | -o    | codegen_loader.g.dart | Output file name                                                            |
| --format                     | -f    | json                  | Support json or keys formats                                                |
| --[no-]skip-unnecessary-keys | -u    | false                 | Ignores keys defining nested object except for pluarl(), gender() keywords. |

### 🔌 Localization asset loader class

Steps:

1. Open your terminal in the folder's path containing your project
2. Run in terminal `flutter pub run easy_localization:generate`
3. Change asset loader and past import.

  ```dart
  import 'generated/codegen_loader.g.dart';
  ...
  void main(){
    runApp(EasyLocalization(
      child: MyApp(),
      supportedLocales: [Locale('en', 'US'), Locale('ar', 'DZ')],
      path: 'resources/langs',
      assetLoader: CodegenLoader()
    ));
  }
  ...
  ```
  
4. All done!

### 📦 Localization support for multi module/package project

If you want to add localization support from other modules and packages you can add them via `extraAssetLoaders` parameter:

```dart
  void main(){
    runApp(EasyLocalization(
      child: MyApp(),
      supportedLocales: [Locale('en', 'US'), Locale('ar', 'DZ')],
      path: 'resources/langs',
      assetLoader: CodegenLoader()
      extraAssetLoaders: [
        TranslationsLoader(packageName: 'package_example_1'),
        TranslationsLoader(packageName: 'package_example_2'),
      ],
    ));
  }
```

### 🔑 Localization keys

If you have many localization keys and are confused, key generation will help you. The code editor will automatically prompt keys

Keys are generated from a single JSON file, never combined across languages. By default, the first regular `.json` file
in ordinal filename order is used. Pass `--source-file` to choose a complete fallback language file when another file
does not contain every key. JSON loader generation uses all regular `.json` files in the same filename order unless a
source file is specified.

Steps:
1. Open your terminal in the folder's path containing your project 
2. Run in terminal `flutter pub run easy_localization:generate -f keys -o locale_keys.g.dart`
3. Past import.

```dart
import 'generated/locale_keys.g.dart';
```
4. All done!

How to use generated keys:

```dart
print(LocaleKeys.title.tr()); //String
//or
Text(LocaleKeys.title).tr(context: context); //Widget
```

### ✅ Audit missing keys

If you prefer to not generate keys you can see an audit of your translation keys to see the one present in your app code but not in your translations file by running the audit command.

```
flutter pub run easy_localization:audit
```

If you are not using the default translations folder path (assets/translations) or the lib folder for your code you can specify your custom paths : 

| Arguments                    | Short | Default               | Description                                                                 |
| ---------------------------- | ----- | --------------------- | --------------------------------------------------------------------------- |
| --translations-dir           | -t    | assets/translations   | Folder containing localization files                                        |
| --source-dir                 | -s    | lib                   | Folder containing the app code files                                        |
| --strict                     |       | false                 | Exit with code 2 when a static key is missing                               |

For CI, run `flutter pub run easy_localization:audit --strict`. Exit code 0 means the audit completed without confirmed missing keys (or strict mode is off); 2 means strict mode found a missing static key; 1 means the audit could not complete, such as an invalid option, unreadable input, invalid JSON, or no JSON locales. The report and warnings go to stdout; errors go to stderr.

The audit uses a limited pattern scanner. Interpolated keys are reported as unverified, and calls such as `tr(variable)` are not extracted, so a successful audit does not prove all dynamic keys are present.


## Diagnostic callbacks

Diagnostics are silent by default. Set any of the three independent callbacks before
`ensureInitialized()` to receive messages, including initialization messages:

```dart
WidgetsFlutterBinding.ensureInitialized();
EasyLocalization.onVerbose = (message, {stackTrace}) { /* send to your logger */ };
EasyLocalization.onWarning = (message, {stackTrace}) { /* send to your logger */ };
EasyLocalization.onError = (message, {stackTrace}) { /* send to your logger */ };
await EasyLocalization.ensureInitialized();
```

Each callback runs synchronously in the current zone. Resource errors include their
original stack trace. Set a callback to `null` to disable that category. The application
controls filtering, formatting and output, and is responsible for handling exceptions
in its callbacks; exceptions propagate to the caller.

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


<p align="center">
    <a href="https://gitpod.io/#https://github.com/aissat/easy_localization" target="_blank">
        <img src="https://gitpod.io/button/open-in-gitpod.svg" width=200 />
    </a>
</p>


## Screenshots

| Arabic RTL                                                                                                                  | English LTR                                                                                                                   | Error widget                                                                                                                     |
| --------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------- |
| ![Arabic RTL](https://raw.githubusercontent.com/aissat/easy_localization/master/screenshots/Screenshot_ar.png "Arabic RTL") | ![English LTR](https://raw.githubusercontent.com/aissat/easy_localization/master/screenshots/Screenshot_en.png "English LTR") | ![Error widget](https://raw.githubusercontent.com/aissat/easy_localization/master/screenshots/Screenshot_err.png "Error widget") |

## Donations

We need your support. Projects like this can not be successful without support from the community. If you find this project useful, and would like to support further development and ongoing maintenance, please consider donating.

<p align="center">
  <a href="https://opencollective.com/flutter_easy_localization/donate" target="_blank">
    <img src="https://opencollective.com/flutter_easy_localization/donate/button@2x.png?color=blue" width=300 />
  </a>
</p>

### Sponsors

<img src="https://opencollective.com/flutter_easy_localization/tiers/backer.svg?avatarHeight=48"/>


### Contributors thanks

![contributors](https://contributors-img.firebaseapp.com/image?repo=aissat/easy_localization)
<a href="https://github.com/aissat/easy_localization/graphs/contributors"></a>
