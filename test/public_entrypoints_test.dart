import 'package:easy_localization_continued/easy_localization.dart' as legacy;
import 'package:easy_localization_continued/easy_localization_continued.dart' as continued;
import 'package:flutter_test/flutter_test.dart';

class _FileLoader implements legacy.FileLoader {
  @override
  Future<String> loadString(String path) async => '';
}

void main() {
  test('both public entrypoints expose the same declarations', () {
    expect(continued.AssetLoader, same(legacy.AssetLoader));
    expect(continued.EasyLocalization, same(legacy.EasyLocalization));
    expect(continued.EasyLocalizationConfig, same(legacy.EasyLocalizationConfig));
    expect(continued.tr, same(legacy.tr));
  });

  test('main entrypoint exposes loader and snapshot types', () {
    final legacy.FileLoader loader = _FileLoader();
    final translations = legacy.Translations({'hello': 'world'});

    expect(loader, isA<legacy.FileLoader>());
    expect(translations.get('hello'), 'world');
  });
}
