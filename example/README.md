# easy_localization example

This app demonstrates translated text, plurals, currency formatting, and switching or resetting the language.

```sh
cd example
flutter pub get
flutter run
flutter run -d windows
```

For an Android debug APK, install the Android SDK and JDK 17, then run `flutter build apk --debug` from this directory.

The app initializes its shared configuration before mounting the localization root:

```dart
final localizationConfig = EasyLocalizationConfig(
  supportedLocales: [Locale('en', 'US'), Locale('ar', 'DZ'), Locale('de', 'DE'), Locale('ru', 'RU')],
  fallbackLocale: Locale('en', 'US'),
  path: 'resources/langs',
);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final localization = await EasyLocalization.initialize(localizationConfig);
  runApp(EasyLocalization.withInstance(instance: localization, child: MyApp()));
}
```

The selector and reset action await the owner command and `waitForPresentation()` before treating a change as visible. They show busy state and report errors or non-applied outcomes. Currency formatting uses the published presentation locale.

See the [package README](../README.md) for the full API.

The [Alchemist golden test](test/localization_golden_test.dart) initializes a fresh owner for each locale, loads Roboto, and checks translated text before capturing readable Windows goldens. From this directory:

```sh
flutter pub get
flutter test --no-pub test/localization_golden_test.dart
```

To regenerate its Windows baselines, append `--update-goldens` to the test command and review the images. See the [testing recipe](../README.md#testing) for the wrapper.
