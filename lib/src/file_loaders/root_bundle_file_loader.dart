import 'package:easy_localization_continued/src/file_loaders/file_loader.dart';
import 'package:flutter/services.dart';

/// File loader implementation for Flutter applications using rootBundle
class RootBundleFileLoader implements FileLoader {
  const RootBundleFileLoader();

  @override
  Future<String> loadString(String path) async {
    try {
      return await rootBundle.loadString(path);
    } catch (error, stackTrace) {
      rootBundle.evict(path);
      Error.throwWithStackTrace(error, stackTrace);
    }
  }
}
