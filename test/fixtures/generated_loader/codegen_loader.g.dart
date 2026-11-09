// DO NOT EDIT. This is code generated via package:easy_localization_continued/generate.dart

// ignore_for_file: prefer_single_quotes, avoid_renaming_method_parameters, constant_identifier_names

import 'dart:ui';

import 'package:easy_localization_continued/easy_localization.dart'
    show AssetLoader, JsonLinkedFileResolver, RootBundleFileLoader;

class CodegenLoader extends AssetLoader{
  const CodegenLoader() : super(
    fileLoader: const RootBundleFileLoader(),
    linkedFileResolver: const JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
  );

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) {
    return Future.value(mapLocales[locale.toString()]);
  }

  static const Map<String,dynamic> _en = {
  "section": {
    "title": "en"
  }
};
static const Map<String,dynamic> _zh_Hans_CN = {
  "section": {
    "title": "zh-Hans-CN"
  }
};
static const Map<String, Map<String,dynamic>> mapLocales = {"en": _en, "zh_Hans_CN": _zh_Hans_CN};
}
