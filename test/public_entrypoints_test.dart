import 'package:easy_localization_continued/easy_localization.dart' as legacy;
import 'package:easy_localization_continued/easy_localization_continued.dart' as continued;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('both public entrypoints expose the same declarations', () {
    expect(continued.AssetLoader, same(legacy.AssetLoader));
    expect(continued.EasyLocalization, same(legacy.EasyLocalization));
    expect(continued.EasyLocalizationConfig, same(legacy.EasyLocalizationConfig));
    expect(continued.tr, same(legacy.tr));
  });
}
