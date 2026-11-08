# easy_localization example

This app demonstrates translated text, plurals, currency formatting, and switching or resetting the language.

```sh
cd example
flutter pub get
flutter run
flutter run -d windows
```

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

See the [package README](../README.md) for the full API.
