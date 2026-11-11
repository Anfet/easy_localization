<p align="center"><img src="https://raw.githubusercontent.com/Anfet/easy_localization/develop/logo/logo.svg?sanitize=true" width="600"/></p>

<h1 align="center">Easy Localization Continued</h1>

[![Pub Version](https://img.shields.io/pub/v/easy_localization_continued?style=flat-square&logo=dart)](https://pub.dev/packages/easy_localization_continued) [![Likes](https://img.shields.io/pub/likes/easy_localization_continued)](https://pub.dev/packages/easy_localization_continued/score) [![Pub points](https://img.shields.io/pub/points/easy_localization_continued)](https://pub.dev/packages/easy_localization_continued/score) ![GitHub license](https://img.shields.io/github/license/Anfet/easy_localization?style=flat-square)

Easy Localization Continued is a maintained fork of [aissat/easy_localization](https://github.com/aissat/easy_localization) 3.0.9, published as `easy_localization_continued`. It keeps the upstream `tr()` and `plural()` API and adds one localization owner, awaitable locale changes, strict key auditing, and JavaScript/WASM browser support. The original project is credited under its MIT license; see [LICENSE](LICENSE).

Version 4.0.0 requires Dart 3.12 and Flutter 3.44.

```yaml
dependencies:
  easy_localization_continued: ^4.0.0
```

```dart
import 'package:flutter/material.dart';
import 'package:easy_localization_continued/easy_localization.dart';

void main() async {
  final owner = await EasyLocalization.initialize(EasyLocalizationConfig(
    supportedLocales: const [Locale('en'), Locale('de')],
    fallbackLocale: const Locale('en'),
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

Coming from `easy_localization` 3.x? The package and import names change, and the upstream loaders need porting. See [Migrating from 3.x](#migrating-from-3x).

## Contents

- [What is this](#what-is-this)
- [Quick start](#quick-start)
- [Core usage](#core-usage)
- [Configuration](#configuration)
- [Custom loaders and multiple modules](#custom-loaders-and-multiple-modules)
- [Tooling (CLI)](#tooling-cli)
- [Diagnostics and errors](#diagnostics-and-errors)
- [Testing](#testing)
- [Platform support and limitations](#platform-support-and-limitations)
- [FAQ](#faq)
- [Migrating from 3.x](#migrating-from-3x)
- [Legacy widget root](#legacy-widget-root)
- [About this fork](#about-this-fork)

## What is this

Easy Localization Continued keeps the upstream translation model: one JSON file per locale, `tr()` and `plural()` with `{}`, named and gender arguments, nested keys, linked translations, and generated keys and loaders.

Version 4.0.0 adds:

- one `EasyLocalizationInstance` owner that initializes before `runApp` and serves the root, the Flutter resources, and global `tr()` and `plural()`;
- awaitable locale commands with separate data and presentation outcomes;
- explicit translation reloads and independent translator snapshots;
- `audit --strict` for CI;
- JavaScript/WASM browser locale support;
- optional diagnostic callbacks, silent by default, in place of the removed `EasyLocalization.logger`.

The package is not a drop-in replacement for 3.x. Upstream loaders depend on `easy_localization` 3.x and must be ported to this package's `AssetLoader`.

The library has two entrypoints that export the same API: `package:easy_localization_continued/easy_localization.dart`, whose filename is kept on purpose, and `package:easy_localization_continued/easy_localization_continued.dart`.

## Quick start

### Installation

Add the dependency as shown at the top of this page.

Create a translations folder:

```
assets
└── translations
    ├── {languageCode}.{ext}                  //only language code
    └── {languageCode}-{countryCode}.{ext}    //or full locale code
```

For example:

```
assets
└── translations
    ├── en.json
    └── en-US.json
```

Declare the folder in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/translations/
```

### iOS

For translations to work on iOS, list the supported locales in `ios/Runner/Info.plist`, as described in the [Flutter internationalization guide](https://flutter.dev/docs/development/accessibility-and-localization/internationalization#specifying-supportedlocales):

```xml
<key>CFBundleLocalizations</key>
<array>
	<string>en</string>
	<string>nb</string>
</array>
```

### Initialize and wire the app

The example at the top of this page shows the whole setup. The full application is in [example/lib/main.dart](example/lib/main.dart). The three `MaterialApp` values come from the same owner:

- `locale: owner.presentationLocale` is the locale whose resources are published;
- `supportedLocales: owner.supportedLocales`;
- `localizationsDelegates: owner.delegates` contains the package delegates and any `additionalDelegates`.

Build `MaterialApp` in a widget under the root so that it is recreated when the presentation changes. A `MaterialApp` created before that build keeps the parameters it captured and does not update.

Translate with `tr('title')` or `'title'.tr()`.

## Core usage

### Initialize before runApp

For translations before `runApp`, initialize one owner with a supported fallback. No `BuildContext`, frame, or separate locale copy is needed:

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

Register custom delegates in the configuration with `additionalDelegates: [MyDelegate()]`, or with the same parameter of the legacy widget. The root prepares every Flutter delegate before it publishes a presentation. Widgets built under the root update even when they are retained in a `const` subtree or in a route.

Keep custom asynchronous delegates inside the configuration so that they join the same atomic presentation. While they load, Flutter resources and global `tr()` and `plural()` keep showing the previous presentation. `dataTranslator` already reads the committed data. A delegate error keeps the previous presentation and appears in `localization.state` with `errorStage == LocalizationErrorStage.flutterDelegates`. Issue another command to retry. A `ValueListenableBuilder<LocalizationState>` can show progress while `state.isLoading` and display errors.

Await a command for resources and storage. Then await `localization.waitForPresentation()` when a visible result matters. It waits for the currently committed snapshot, not for a particular command. When commands compete, compare `localization.presentationLocale` with the locale you expect. The outcome is one of `applied`, `superseded`, `detached`, `failed`, or `disposed`. `applied` confirms that the root published the presentation when the consumer is wired as shown above; it does not inspect an arbitrary `MaterialApp`.

A borrowed owner survives the removal of its root. Strings computed outside `build` remain captured values. A `Localizations.override` can load Flutter resources for its own locale. For a scoped plugin dictionary, use a scoped adapter or an explicit translator. Global `tr()` and `plural()` continue to follow the root.

### Translate with tr()

```dart
Text(tr('title'));
Text('title'.tr());
```

Ordinary widgets under the root rebuild when the presentation changes. `Text('title').tr()` is optional sugar. It keeps the Text properties and uses the same rebuild. Values computed outside `build` are snapshots.

Example translation file:

```json
{
  "msg": "{} are written in the {} language",
  "msg_named": "Easy localization is written in the {lang} language",
  "msg_mixed": "{} are written in the {lang} language",
  "gender": {
    "male": "Hi man ;) {}",
    "female": "Hello girl :) {}",
    "other": "Hello {}"
  }
}
```

Arguments:

| Name      | Type                  | Description                                                                         |
| --------- | --------------------- | ----------------------------------------------------------------------------------- |
| args      | `List<String>`        | Replaces `{}` placeholders from left to right.                                      |
| namedArgs | `Map<String, String>` | Replaces the named placeholders `{key_name}` by name.                               |
| gender    | `String`              | Selects the form of the translation that matches the gender string.                 |

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

Checking whether a key exists: `trExists(key)` checks primary strings only. `includeFallback: true` also checks fallback strings that are already loaded. With `useFallbackTranslationsForEmptyResources: true`, empty strings do not count. Non-string values never count. The check loads no resources and resolves neither links nor plurals.

`Text.tr` and `Text.plural` keep the Text properties. For rich text, translate each `TextSpan` string with `String.tr`.

### Plurals with plural()

Use `{}` for the number. Number formatting is supported; see the [NumberFormat](https://pub.dev/documentation/intl/latest/intl/NumberFormat-class.html) documentation.

A `plural()` or `.plural()` call made during a widget build under the localization root is recalculated when the root publishes a new presentation, even in retained routes. Passing `context` is not required for this. A result saved outside `build` is a snapshot and does not update. For a local scope, use a scoped adapter or an explicit translator.

Arguments:

| Name      | Type                  | Description                                                                                          |
| --------- | --------------------- | ---------------------------------------------------------------------------------------------------- |
| value     | `num`                 | Number used for the plural form.                                                                     |
| args      | `List<String>`        | Replaces `{}` placeholders from left to right.                                                       |
| namedArgs | `Map<String, String>` | Replaces the named placeholders `{key_name}` by name.                                                |
| name      | `String`              | Name of the number value. Replaces `{$name}` with the value.                                         |
| format    | `NumberFormat`        | Formats the number with a [NumberFormat](https://pub.dev/documentation/intl/latest/intl/NumberFormat-class.html). |

Example translation file:

```json
{
  "day": {
    "zero": "{} дней",
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

The key `other` is required.

```dart
// Text widget with a number format
Text('money'.plural(1000000, format: NumberFormat.compact(locale: localization.presentationLocale.toString()))); // You have 1M dollars

// String
print('day'.plural(21)); // 21 день

// Global function
var money = plural('money', 10.23); // You have 10.23 dollars

// Force a supported, preloaded locale without changing the UI language
Text(plural('money', 10.23, locale: const Locale('de')))

// Global function with arguments
var money = plural('money_args', 10.23, args: ['John', '10.23']); // John has 10.23 dollars

// Global function with named arguments
var money = plural('money_named_args', 10.23, namedArgs: {'name': 'Jane', 'money': '10.23'}); // Jane has 10.23 dollars
var money = plural('money_named_args', 10.23, namedArgs: {'name': 'Jane'}, name: 'money'); // Jane has 10.23 dollars
```

Plural rules:

1. The package uses `Intl.pluralLogic` with the full locale.
2. If the forms `zero`, `one`, and `two` are present, they are selected for exactly 0, 1, and 2. These explicit cases extend CLDR.
3. Otherwise the locale's CLDR category is used, and then `other`.
4. For the TWO category, a missing `two` falls back to `few`, then `other`.
5. English uses `other` for 3, 4, and 5, even when `few` or `many` is present.
6. Russian uses `one`, `few`, and `many` for 21, 22, and 5.
7. Each language's own forms are tried before the base and fallback translations, and each source locale uses its own rules.

### Linked translations

A key can link to another key with the `@:` prefix followed by the full key name, including its namespace. Link keys support Unicode letters, combining marks and numbers, and the ASCII characters `_`, `-` and `|`.

```json
{
  "example": {
    "hello": "Hello",
    "world": "World!",
    "helloWorld": "@:example.hello @:example.world"
  }
}
```

```dart
print('example.helloWorld'.tr()); // Hello World!
```

Linked keys are looked up first in the dictionary that supplied the containing phrase, then in the usual primary, base-language and fallback order. Each nested link uses the dictionary that supplied its containing text. Empty translations follow the fallback-for-empty setting. Linked messages can contain named and anonymous arguments:

```json
{
  "date": "{currentDate}.",
  "dateLogging": "INFO: the date today is @:date"
}
```

```dart
print('dateLogging'.tr(namedArgs: {'currentDate': DateTime.now().toIso8601String()}));
```

Format a linked message with `@.modifier:key`. The modifiers are:

- `upper`: uppercases all characters of the linked message;
- `lower`: lowercases all characters of the linked message;
- `capitalize`: capitalizes the first character of the linked message.

```json
{
  "example": {
    "fullName": "Full Name",
    "emptyNameError": "Please fill in your @.lower:example.fullName"
  }
}
```

```dart
print('example.emptyNameError'.tr()); // Please fill in your full name
```

Linked text expansion is limited to 4,096 link transitions and 256 Ki UTF-16 code units per result. When a limit is exceeded, the original template is returned without argument substitution and a warning is emitted. The audit command reports excessive link traversal as an input error.

### Linked files

A large locale can be split into several JSON files. Set a key's value to a path that starts with `:/` and is relative to the translations folder. For example, with the default path `assets/translations` and the locale `en-US`:

```json
{
  "errors": ":/errors.json",
  "validation": ":/validation.json",
  "notifications": ":/notifications.json"
}
```

At runtime the package loads:

```
assets
└── translations
    └── en-US
        ├── errors.json
        ├── validation.json
        └── notifications.json
```

Declare the translations folder and each nested folder that contains linked files in `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/translations/
    - assets/translations/en-US/
```

The built-in JSON resolver uses `language[-Script][-COUNTRY]/file.json`. For example: `en/errors.json`, `en-US/errors.json`, `zh-Hans/errors.json`, `zh-Hant/errors.json`, and `zh-Hans-CN/errors.json`. A missing script-specific file is an error; another script is never used as a fallback. The same file may be linked from separate branches. Cycles and chains deeper than 32 links are errors. Each root linked JSON file is limited to 4,096 file transitions; exceeding the limit fails resolution before the next file is read.

Each linked file must contain a valid object of translation keys in the file type you use.

Custom `LinkedFileResolver` subclasses must add the optional `String? scriptCode` parameter to their `resolveLinkedFiles` override and forward it to `super.resolveLinkedFiles` where applicable. Overrides of `getLinkedLocalePath` must also accept `scriptCode`. Replace `resolveLinkedFilesForLocale` overrides and calls with `resolveLinkedFiles`.

The `generate` and `audit` commands read linked JSON files from the project. Use them only with trusted translation folders and trusted JSON files throughout the link chain. See [Tooling (CLI)](#tooling-cli).

### Change or reload the locale

Use the owner to change the locale:

```dart
await localization.setLocale(const Locale('en', 'US'));
final outcome = await localization.waitForPresentation();
if (outcome == LocalizationApplyOutcome.applied) {
  // The new language is visible.
}
```

Await the returned future and handle its errors. Calling a change without awaiting it can produce an unhandled asynchronous error. A newer command supersedes an outstanding load. A storage failure can leave the new data active; selecting the same locale again retries the storage write.

After you update the data of your `AssetLoader` and its cache, call `await localization.reloadTranslations()`. It reloads the requested language and its fallback, and supersedes any outstanding locale change or reload. The superseded command completes with `LocalizationOperationSupersededException`. A later command can supersede the reload in turn. A failed reload leaves the previous translations available. To make the updated widgets visible, await `localization.waitForPresentation()` and check for `LocalizationApplyOutcome.applied`. If commands compete, also check that `localization.presentationLocale` is the expected locale.

### Reset the locale

`resetLocale` returns to following the system language, including later system changes, and removes the saved selection. `startLocale` takes precedence over a saved selection. Either one prevents system changes from overriding the selection until the reset. If translations fail to load, the current language and selection mode remain active. A storage failure completes the reset future with an error after the language has changed.

```dart
await localization.resetLocale();
final outcome = await localization.waitForPresentation();
// Treat only LocalizationApplyOutcome.applied as a visible success.
```

### Device locale and saved locale

```dart
print(localization.deviceLocale); // en_US
```

`deleteSaveLocale()` clears the saved locale without changing the current selection mode:

```dart
await localization.deleteSaveLocale();
```

### Translating a document in another language

An independent translator keeps its own language and resources while the interface changes:

```dart
final document = await EasyLocalization.instance.translators.once(const Locale('ru'));
final title = document.tr('invoice.title');
final items = document.plural('invoice.items', 3);

// Load again when the document should use the latest resources.
final refreshedDocument = await EasyLocalization.instance.translators.once(document.locale);
```

The requested locale must be in `supportedLocales`. A translator remains usable after the owner is disposed.

To read locale data for the cache without a translator, use `translators`:

```dart
await localization.translators.load([const Locale('de')]);
final title = tr('title', locale: const Locale('de'));
final snapshot = localization.translators[const Locale('de')];
localization.translators.unload(const Locale('de'));
```

`translators.load()` shares unfinished reads for each locale and publishes each batch atomically. When overlapping batches compete, a newer batch can publish first, and the older batch completes with `LocalizationOperationSupersededException`. A completed asset read alone does not mean that its batch was published. Load a locale before forcing it in global calls. Held snapshots survive reload, cache eviction and owner disposal. `unload` removes only the cache reference, not a snapshot the caller already holds.

### Locale helpers

```dart
'en_US'.toLocale(); // Locale('en', 'US')

// with a custom separator
'en|US'.toLocale(separator: '|'); // Locale('en', 'US')

Locale('en', 'US').toStringWithSeparator(separator: '|'); // en|US
```

## Configuration

`EasyLocalizationConfig` is an immutable object. Create it once and pass it to `EasyLocalization.initialize`. The fields are:

| Field | Required | Default | Description |
| --- | --- | --- | --- |
| `supportedLocales` | yes | none | Locales the app can show. Must not be empty; the list is copied. |
| `path` | yes | none | Folder with the translation files. Must not be empty. |
| `fallbackLocale` | yes | none | Startup locale when no start, saved, or system choice applies. Must be in `supportedLocales`. It does not enable key fallback. |
| `startLocale` | no | none | Explicit start locale. Must be in `supportedLocales`. See [Startup locale](#startup-locale). |
| `preloadLocales` | no | `[]` | Locales loaded during initialization. Each must be in `supportedLocales`. |
| `assetLoader` | no | `RootBundleAssetLoader(fileLoader: RootBundleFileLoader(), linkedFileResolver: JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()))` | Loader for the translation files. Implement `AssetLoader` for other sources. `RootBundleAssetLoader.fromRootBundle()` gives an equivalent default. |
| `extraAssetLoaders` | no | `[]` | Loaders for translations from other modules or packages. |
| `additionalDelegates` | no | `[]` | Custom Flutter `LocalizationsDelegate`s, prepared atomically with the presentation. |
| `useOnlyLangCode` | no | `false` | When `true`, files are named by language code only (`en.json`); when `false`, by full locale (`en-US.json`). |
| `useFallbackTranslations` | no | `false` | When a key is missing in the locale's translations, read it from the fallback locale. |
| `useBaseLanguageFallback` | no | `false` | When fallback translations are enabled, load the base language before the fallback. See [Fallback behavior](#fallback-behavior). |
| `useFallbackTranslationsForEmptyResources` | no | `false` | Treat empty strings as missing, even when no fallback resource is loaded. Try any loaded base and fallback resources. |
| `saveLocale` | no | `true` | Save the selected locale in device storage. |

The legacy widget accepts the same properties, with two differences: `fallbackLocale` is optional there, and `preloadLocales` is not available. See [Legacy widget root](#legacy-widget-root).

### Fallback behavior

Three separate settings control fallback. `fallbackLocale` selects the startup locale. It does not enable key fallback. Enable `useFallbackTranslations` separately.

- `useFallbackTranslations` reads a missing key from the fallback locale.
- `useBaseLanguageFallback` loads the language-and-script base, such as `zh-Hans` for `zh-Hans-CN`, before the fallback. Both startup paths disable it by default.
- `useFallbackTranslationsForEmptyResources` treats empty strings as missing.

With `useBaseLanguageFallback` enabled for a region, the owner loads the primary locale, then the base, then the configured fallback. A missing optional base is skipped. A missing primary or fallback resource throws before anything is committed. The RootBundle loader throws for missing assets, so enable base fallback only when the base asset exists or when a custom loader reports confirmed absence. Duplicate normalized resources are loaded once per operation.

### Startup locale

`initialize` completes after all selected resources and the required startup write. It chooses the locale in this order:

1. `startLocale`, when it is set.
2. The saved choice, when `saveLocale: true`.
3. A supported system locale, or the required `fallbackLocale`.

The owner reads the engine's ordered list of preferred locales at startup, on locale events, and on resume. For each preferred locale, the owner:

1. selects an exact supported match;
2. if the region is not supported, checks the later preferred locales for an exact supported region of the same language;
3. applies the existing script, country, or first-supported match.

When the first preference specifies a script, later exact matches must specify the same script. Otherwise the preferred script is searched first. If it is unavailable, the usual country or first-supported fallback applies. The engine may supply a default `en_US`; the library adds no English default.

Resume reads the engine's list. It does not force a browser language refresh, and it does not guarantee iOS per-app locale events.

### Saved and explicit choices

- A valid `startLocale` overrides old saved data. It is applied and saved after loading on every launch.
- To keep the user's choice, omit `startLocale` on later launches.
- A system or fallback choice is never saved as an explicit choice.
- Invalid, unsupported, or unreadable saved data is ignored with a warning, and it is not deleted.
- A resource failure throws. A failed startup write leaves the translations available and reports a persistence error in `state`. Selecting the language again retries the write.
- With `saveLocale: false`, initialize, set, reset, and delete never access preferences.
- The stored `locale` key and the language, script and country forms stay compatible. No storage migration is needed.

### Lifecycle

Commands return `Future<void>`. A persistence error may leave the committed data available, and repeating the selection retries the storage. Read `dataTranslator` for a snapshot and `state` for progress and errors. Dispose the owner when it is no longer needed. Global access before readiness or after disposal throws `StateError`. Reusing the same config object reuses the initialization. Another config requires disposing the current owner first.

`await EasyLocalization.ensureInitialized(config)` is a facade for `initialize`. Obtain the owner with `EasyLocalization.instance`. The call without arguments only prepares Flutter and does not load translations.

Reading the configuration:

```dart
print(localization.supportedLocales); // [en_US, ar_DZ, de_DE, ru_RU]
print(localization.fallbackLocale); // en_US
```

## Custom loaders and multiple modules

An `AssetLoader` returns the translations of one resource:

- return `null` only when the resource is confirmed to be missing;
- return `{}` when the resource exists and is empty;
- throw when loading fails.

Example of an in-memory loader:

```dart
class MemoryLoader extends AssetLoader {
  MemoryLoader(this.translations);

  final Map<String, dynamic> translations;

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) => Future.value(translations);
}
```

The `AssetLoader` constructor takes no arguments. It has no `fileLoader` or `linkedFileResolver` getters. Keep file dependencies inside your own loader. `RootBundleAssetLoader` keeps both fields and its named constructor.

Generate a loader from JSON files:

1. Open a terminal in your project folder.
2. Run `dart run easy_localization_continued:generate`.
3. Use the generated loader:

```dart
import 'generated/codegen_loader.g.dart';

void main() async {
  final owner = await EasyLocalization.initialize(EasyLocalizationConfig(
    supportedLocales: const [Locale('en', 'US'), Locale('ar', 'DZ')],
    fallbackLocale: const Locale('en', 'US'),
    path: 'assets/translations',
    assetLoader: CodegenLoader(),
  ));
  runApp(EasyLocalization.withInstance(instance: owner, child: const MyApp()));
}
```

### Multiple modules and packages

Add translations from other modules and packages with `extraAssetLoaders`:

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

The upstream `easy_localization_loader` package depends on `easy_localization` 3.x. Changing its dependency key or an override does not make its `AssetLoader` a type of this package. Port each such loader to the new import and to the contract above. See [Migrating from 3.x](#migrating-from-3x).

## Tooling (CLI)

### generate

`dart run easy_localization_continued:generate` creates a loader from the JSON files, or a keys class from one JSON file.

| Argument                     | Short | Default               | Description                                                                 |
| ---------------------------- | ----- | --------------------- | --------------------------------------------------------------------------- |
| `--help`                     | `-h`  |                       | Shows help.                                                                 |
| `--source-dir`               | `-S`  | `assets/translations` | Folder with the localization files.                                         |
| `--source-file`              | `-s`  | first JSON by name    | File used to generate the keys.                                             |
| `--output-dir`               | `-O`  | `lib/generated`       | Folder for the generated file.                                              |
| `--output-file`              | `-o`  | `codegen_loader.g.dart` | Name of the generated file.                                               |
| `--format`                   | `-f`  | `json`                | `json` for a loader, `keys` for key constants.                              |
| `--[no-]skip-unnecessary-keys` | `-u` | `false`               | Skips constants for keys that define only nested objects, except `plural()` and `gender` keys. |

For JSON loaders and the audit, file names use a 2–3 letter language code, an optional 4-letter script, and an optional 2-letter or 3-digit region, separated by `-` or `_`. Names are normalized: `zh_hans_cn.json` becomes `zh_Hans_CN`, and linked files are read from `zh-Hans-CN/`. Invalid names, and names that normalize to the same locale, are rejected. Key generation also accepts arbitrary source file names.

JSON loader filenames must have a non-empty locale name made of ASCII letters, digits, underscores and hyphens. Hyphens become underscores, so `en-US.json` and `en_US.json` cannot be used together. JSON loader generation uses all regular `.json` files in filename order, unless a source file is given. Linked JSON files are resolved during generation for both formats, so the generated loaders do not read them at runtime. A missing or invalid source, or a broken link, exits with code 1 and leaves the existing output unchanged.

### Generated keys

Generate keys from one JSON file. Keys are never combined across languages. By default the first regular `.json` file in filename order is used. Pass `--source-file` to choose a complete fallback file when another file lacks some keys:

1. Open a terminal in your project folder.
2. Run `dart run easy_localization_continued:generate -f keys -o locale_keys.g.dart`.
3. Import the generated file:

```dart
import 'generated/locale_keys.g.dart';
```

Use the keys:

```dart
Text(LocaleKeys.title.tr());
// Optionally, use the Text extension:
Text(LocaleKeys.title).tr();
```

String leaves, including plural and gender forms, have generated constants. `-u` controls only the constants of parent keys. Generated identifiers must be public Dart identifiers, so they cannot start with `_`. They must not be reserved words, and they must not collide after nested paths are joined with underscores. For example, `auth.login`, `bad-key`, `class`, and the combination of `a_b` with nested `a.b` cannot be generated. The command reports an error and keeps the existing output. Runtime translation keys can still contain dots.

Since 4.0.0, the generated keys re-export the translation extensions. The keys file is a Flutter-facing artifact and is not a standalone Dart library.

### audit

The audit finds keys that appear in your code but are missing from the translation files:

```
dart run easy_localization_continued:audit
```

| Argument           | Short | Default               | Description                                                                                       |
| ------------------ | ----- | --------------------- | ------------------------------------------------------------------------------------------------- |
| `--translations-dir` | `-t` | `assets/translations` | Folder with the localization files.                                                               |
| `--source-dir`     | `-s`  | `lib`                 | Folder with the app code.                                                                         |
| `--strict`         |       | `false`               | Exits with code 2 when a static key is missing or a plural has no `other` form.                   |

For CI, run `dart run easy_localization_continued:audit --strict`. Exit codes:

- `0`: the audit completed without confirmed missing keys, or strict mode is off.
- `2`: strict mode found a missing static key, or a plural without `other`.
- `1`: the audit could not complete, for example because of an invalid option, unreadable input, invalid JSON, or no JSON locales.

The report and warnings go to stdout. Errors go to stderr.

The scanner finds literal keys in `tr` and `plural` calls. This includes literal or `LocaleKeys` String receivers, `Text` with named arguments, and bare or prefixed calls such as `loc.tr` and `EasyLocalization.instance.dataTranslator.tr`. It scans executable expressions inside string interpolation and ignores ordinary string examples and comments. It reads literal `static const` values of `LocaleKeys` from the Dart files in the source folder. Conflicting values, interpolated keys, dynamic expressions and unresolved constants are unverified. Receiver types are not resolved, and complex Dart syntax can exceed the scanner's limits. The scanner is not a full Dart parser.

Each JSON locale is checked on its own, without app configuration or fallback:

- a translation must be a string;
- a plural call needs at least one string plural form, and a missing `other` is reported as a warning and fails strict mode;
- a literal gender in a top-level call checks that form, while a dynamic gender remains unverified;
- named arguments inside nested helpers do not affect the outer call;
- for static calls, the audit follows the links reachable from the selected string, the literal gender form, and the available string plural forms, and reports missing or non-string targets with their paths.

The audit does not determine which plural form a given locale and value select. Cycles and dynamic calls remain unverified. The audit does not verify the entire application.

The audit also warns when corresponding resolved strings in different locales use different named parameters, such as `{name}` and `{naem}`. It includes reachable linked strings and compares only matching plural or gender forms that resolve in both locales. Parameter mismatches are warnings and do not change either exit code.

**Trusted input.** Run `generate` and `audit` only on trusted translation folders and trusted JSON files throughout the link chain. A linked path can read files outside the translations folder with the permissions of the process that runs the command, and the contents can appear in the generated output. These commands are not an operating-system sandbox. When you handle untrusted input, restrict the process's access to resources.

## Diagnostics and errors

### Diagnostic callbacks

Diagnostics are silent by default. Set any of the three independent callbacks before initialization to receive messages, including initialization messages:

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

Each callback runs synchronously in the current zone. Resource errors include their original stack trace. Set a callback to `null` to disable its category. The application controls filtering, formatting and output. Exceptions thrown by a callback are passed to `FlutterError.reportError`; they do not affect localization work. The application remains responsible for handling those reported errors.

The removed `EasyLocalization.logger` API is migrated in [Migrating from 3.x](#migrating-from-3x).

### Startup retry

An initial loading failure should be handled outside the localization root. Keep the configuration in a startup widget, retry the initialization there, and create the root only after it succeeds:

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

Run `runApp(Startup(config: config))`. Keep the startup widget mounted until the initialization completes. Dispose a successfully initialized owner when it is no longer needed.

### Command state

`localization.state` is a `ValueListenable<LocalizationState>`. Its fields are:

- `locale`: the committed locale;
- `appliedLocale`: the locale of the last applied resources;
- `isSystemMode`: whether the system choice is in effect;
- `isLoading`: whether a command is running;
- `error` and `errorStage`: the last error and the stage where it occurred. The stages are `resources`, `persistence` and `flutterDelegates`.

Committed data remains usable after an error.

`waitForPresentation()` returns a `LocalizationApplyOutcome`: `applied`, `superseded`, `detached`, `failed`, or `disposed`. Treat only `applied` as a visible success.

### Exceptions

- `LocalizationNotFoundException` is thrown by context-based calls when no localization root is found.
- `StateError` is thrown by global calls before the owner is ready and after it is disposed.
- `LocalizationOperationSupersededException` completes a command that a newer command superseded.

## Testing

Initialize a fresh owner before pumping the widget, and unmount the root before disposing the owner. This in-memory loader returns a completed future. The example needs neither `runAsync` nor the asset bundle:

```dart
import 'package:easy_localization_continued/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class MemoryLoader extends AssetLoader {
  MemoryLoader(this.translations);

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

The [runnable recipe](test/easy_localization_testing_recipe_test.dart) has a second independent test with another locale and dictionary. Real bundle or plugin operations can require `tester.runAsync`; this memory loader does not. If you use `saveLocale: true`, set up mock preferences before initializing the owner.

For [Alchemist](https://pub.dev/packages/alchemist), use its [custom pumping](https://github.com/Betterment/alchemist#custom-pumping-behavior) to initialize a fresh owner before the golden subtree:

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

Register this inside `main()`. The [complete Windows example](example/test/localization_golden_test.dart) loads Roboto, checks English and Russian plurals, and compares readable platform goldens. From `example`, run `flutter pub get`, then `flutter test --no-pub test/localization_golden_test.dart`. Add `--update-goldens` to regenerate the baselines.

## Platform support and limitations

Verified with the 4.0.0 evidence:

- Android, iOS Simulator, macOS, and the Web (JavaScript and WASM browser journeys);
- Windows: only the golden test of the example app;
- Flutter 3.44.9, with a downgrade check. Flutter 3.44.0 was not checked.

Not verified:

- physical iOS devices;
- Firefox and Safari;
- native Settings events and per-app locale events.

Known limitations:

- A single loader or delegate that hangs without reporting an error has no timeout.
- A `path` that ends with `/` does not find assets. This was also the case in 3.x. Omit the trailing slash.
- Resume does not force a browser language refresh, and iOS per-app locale events are not guaranteed. See [Startup locale](#startup-locale).
- `generate` and `audit` read linked files with the permissions of the process. See [Tooling (CLI)](#tooling-cli).

## FAQ

**Why does `tr()` not update outside `build`?**
Values computed outside `build` are snapshots. Under the localization root, `tr()` and `plural()` called in `build` are recalculated when the root publishes a new presentation.

**How do I keep the user's choice when I use `startLocale`?**
Omit `startLocale` on later launches. A `startLocale` that is set is applied and saved on every launch.

**Why do I need `fallbackLocale` if keys do not fall back?**
`fallbackLocale` selects the startup locale. Enable `useFallbackTranslations` to read missing keys from the fallback locale.

**How do I switch the language and know that it is visible?**
Await `setLocale(...)`, then await `waitForPresentation()`. The change is visible when the outcome is `applied`.

**How do I load the language of a document without changing the UI?**
Use `translators.once(locale)` for an independent snapshot. See [Translating a document in another language](#translating-a-document-in-another-language).

**What about upstream loaders from `easy_localization_loader`?**
They depend on `easy_localization` 3.x and must be ported to `AssetLoader`. See [Migrating from 3.x](#migrating-from-3x).

**How do I run the translations in tests?**
Use an in-memory `AssetLoader`, initialize a fresh owner, and follow [Testing](#testing).

**What does `useOnlyLangCode` change?**
With `true`, files are named by language code only (`en.json`). With `false`, they use the full locale (`en-US.json`).

**Why does `generate` fail on `bad-key` or `class`?**
Generated identifiers must be public Dart identifiers that are not reserved words, and they must not collide. The command reports an error and keeps the existing output. See [Generated keys](#generated-keys).

## Migrating from 3.x

<a id="compatibility-and-migration-to-400"></a>

Checklist for an app that uses `easy_localization` 3.x:

1. Replace the dependency `easy_localization: ^3.x` with `easy_localization_continued: ^4.0.0`. A constraint such as `^3.0.8` does not select 4.0.0.
2. Change the import from `package:easy_localization/easy_localization.dart` to `package:easy_localization_continued/easy_localization.dart`, or to `easy_localization_continued.dart`.
3. Replace the `easy_localization:generate` and `easy_localization:audit` commands in scripts with `easy_localization_continued:generate` and `easy_localization_continued:audit`, and regenerate the loaders and keys.
4. Use Dart 3.12 and Flutter 3.44. Remove the `ignorePluralRules` argument; all constructors use the plural rules described in [Plurals with plural()](#plurals-with-plural).
5. Port upstream loaders to `AssetLoader`. Its constructor takes no arguments. Its `null`, `{}`, and `throw` contract is described in [Custom loaders and multiple modules](#custom-loaders-and-multiple-modules).
6. In 3.x, a saved locale took precedence over `startLocale`. In 4.0, `startLocale` is applied and saved on every launch. Omit it to keep the user's saved choice.
7. Replace the deprecated `context.locale = locale` setter with `await context.setLocale(locale)`, and handle its errors.
8. Replace the `EasyLocalization.logger` configuration with the diagnostic callbacks in [Diagnostic callbacks](#diagnostic-callbacks).
9. Replace the scoped `context` forms of `tr`, `plural` and `trExists` with the forms without `context`. The scoped forms are deprecated until 5.0.

## Legacy widget root

The `EasyLocalization` widget is supported and is not deprecated. It is the shortest migration path from 3.x. It takes the same properties as `EasyLocalizationConfig`, except that `fallbackLocale` is optional and `preloadLocales` is not available:

| Properties                | Required | Default                   | Description                                                                                                  |
| ------------------------- | -------- | ------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `key`                     | no       |                           | Widget key.                                                                                                  |
| `child`                   | yes      |                           | The main page widget.                                                                                        |
| `supportedLocales`        | yes      |                           | Locales the app can show.                                                                                    |
| `path`                    | yes      |                           | Folder with the localization files.                                                                          |
| `assetLoader`             | no       | `RootBundleAssetLoader(fileLoader: RootBundleFileLoader(), linkedFileResolver: JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()))` | Loader for the localization files. `RootBundleAssetLoader.fromRootBundle()` is equivalent. |
| `extraAssetLoaders`       | no       | `null`                    | Loaders for additional modules or packages.                                                                  |
| `additionalDelegates`     | no       | `[]`                      | Custom Flutter `LocalizationsDelegate`s.                                                                     |
| `fallbackLocale`          | no       | first of `supportedLocales` | Startup locale when no start, saved, or system choice applies. Does not enable key fallback.              |
| `startLocale`             | no       |                           | Overrides the device locale.                                                                                 |
| `saveLocale`              | no       | `true`                    | Saves the locale in device storage.                                                                          |
| `useFallbackTranslations` | no       | `false`                   | Reads a missing key from the fallback locale.                                                                |
| `useBaseLanguageFallback` | no       | `false`                   | Loads the base language before the fallback when fallback translations are enabled.                          |
| `useFallbackTranslationsForEmptyResources` | no | `false`          | Treats empty strings as missing.                                                                             |
| `useOnlyLangCode`         | no       | `false`                   | Reads files by language code only. See [Configuration](#configuration).                                      |
| `errorWidget`             | no       | `ErrorWidget`             | Shows a custom widget when an error occurs. Receives the `FlutterError?` message.                            |

The legacy widget uses the same startup priority as the configuration. Its fallback defaults to the first supported locale, and base-language fallback is disabled by default.

Its configuration must stay unchanged while the root is mounted, including during startup. To change it:

1. Completely unmount the old root and finish that frame.
2. Mount a new root with a new key in a later frame.

Supported locale lists are compared by value, loaders by identity, and delegates by `==`. Create loaders and delegates once outside `build`, or use `const`.

A ready root can be replaced in one frame with a new key when the configuration is the same, or when the owner is borrowed. A legacy-owned root passes its ownership to the replacement. A waiter for presentation receives `detached` during the replacement. To use a different legacy configuration, render a placeholder for one frame before mounting the new root with a new key.

An initial loading error of the legacy root is shown before any owner or provider is ready. Keep the root key in its parent, and create a new key to retry. Do not call context or global localization APIs from the error widget. `reloadTranslations()` applies only to an owner that has already initialized.

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

### BuildContext API

Under the legacy root, `BuildContext` exposes the following members. Each one throws `LocalizationNotFoundException` when there is no root above the context:

| Member | Purpose |
| --- | --- |
| `context.locale` | The current locale. |
| `await context.setLocale(locale)` | Changes the locale. Await it to see errors. |
| `context.supportedLocales` | The supported locales. |
| `context.fallbackLocale` | The fallback locale. |
| `context.localizationDelegates` | The delegates for `MaterialApp`. |
| `context.deviceLocale` | The device locale. |
| `context.savedLocale` | The saved locale, or `null`. |
| `await context.resetLocale()` | Follows the system language again and removes the saved selection. |
| `await context.deleteSaveLocale()` | Removes the saved locale without changing the selection mode. |
| `await context.reloadTranslations()` | Reloads the translations after loader changes. |

The deprecated `context.locale = locale` setter is replaced by `setLocale`. The scoped `context` forms of `tr`, `plural` and `trExists` are deprecated until 5.0.

```dart
ElevatedButton(
  onPressed: () async => context.setLocale(const Locale('de')),
  child: Text('title'.tr()),
);
```

## About this fork

Easy Localization Continued is developed in [Anfet/easy_localization](https://github.com/Anfet/easy_localization). It is based on [aissat/easy_localization](https://github.com/aissat/easy_localization) 3.0.9. The upstream project is distributed under the MIT license, and its copyright notice is kept in [LICENSE](LICENSE) together with the copyright of the contributors to this fork.

Contributions are welcome. See [CONTRIBUTING](CONTRIBUTING.md). The contributors are listed on the [GitHub contributors graph](https://github.com/Anfet/easy_localization/graphs/contributors).

### Screenshots

| Arabic RTL | English LTR | Error widget |
| --- | --- | --- |
| ![Arabic RTL](https://raw.githubusercontent.com/Anfet/easy_localization/develop/screenshots/Screenshot_ar.png "Arabic RTL") | ![English LTR](https://raw.githubusercontent.com/Anfet/easy_localization/develop/screenshots/Screenshot_en.png "English LTR") | ![Error widget](https://raw.githubusercontent.com/Anfet/easy_localization/develop/screenshots/Screenshot_err.png "Error widget") |
