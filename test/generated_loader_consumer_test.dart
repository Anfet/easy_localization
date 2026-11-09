import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'fixtures/generated_loader/codegen_loader.g.dart';

void main() {
  test('generated loader returns linked resources for language and script locales', () async {
    const loader = CodegenLoader();
    expect(await loader.load('', const Locale('en')), {
      'section': {'title': 'en'},
    });
    expect(await loader.load('', const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans', countryCode: 'CN')), {
      'section': {'title': 'zh-Hans-CN'},
    });
  });
}
