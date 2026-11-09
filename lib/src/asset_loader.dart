import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:easy_localization_continued/easy_localization.dart';
import 'package:easy_localization_continued/src/diagnostics.dart';

/// Loads translation resources from a custom source.
///
/// Subclasses must pass a [FileLoader] and [LinkedFileResolver] to the
/// superclass constructor. Upstream easy_localization_loader implementations
/// target a different package and must be ported before use.
abstract class AssetLoader {
  // Place inside class RootBundleAssetLoader
  final FileLoader fileLoader;
  final LinkedFileResolver linkedFileResolver;

  const AssetLoader({required this.linkedFileResolver, required this.fileLoader});

  /// Return null only for a confirmed missing resource. An empty map is a
  /// successful empty resource; loading and parsing failures must throw.
  /// Strict owners require primary and configured fallback resources.
  Future<Map<String, dynamic>?> load(String path, Locale locale);
}

///
/// default used is RootBundleAssetLoader which uses flutter's assetloader
///
class RootBundleAssetLoader extends AssetLoader {
  const RootBundleAssetLoader({required LinkedFileResolver linkedFileResolver, required FileLoader fileLoader})
    : super(linkedFileResolver: linkedFileResolver, fileLoader: fileLoader);

  factory RootBundleAssetLoader.fromRootBundle() {
    return const RootBundleAssetLoader(
      linkedFileResolver: JsonLinkedFileResolver(fileLoader: RootBundleFileLoader()),
      fileLoader: RootBundleFileLoader(),
    );
  }

  String getLocalePath(String basePath, Locale locale) {
    return '$basePath/${locale.toStringWithSeparator(separator: "-")}.json';
  }

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    var localePath = getLocalePath(path, locale);
    reportLocalizationDiagnostic(EasyLocalization.onVerbose, 'Load asset from $path');

    Map<String, dynamic> baseJson = json.decode(await fileLoader.loadString(localePath));
    return await linkedFileResolver.resolveLinkedFiles(
      basePath: path,
      languageCode: locale.languageCode,
      scriptCode: locale.scriptCode,
      countryCode: locale.countryCode,
      baseJson: baseJson,
    );
  }
}
