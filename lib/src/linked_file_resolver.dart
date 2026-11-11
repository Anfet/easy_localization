import 'dart:async';
import 'dart:convert';

import 'package:easy_localization_continued/src/file_loaders/file_loader.dart';

/// Resolves linked translation files using the `:/filename.json` syntax.
abstract class LinkedFileResolver {
  final int maxLinkedDepth = 32;
  final FileLoader fileLoader;

  const LinkedFileResolver({required this.fileLoader});

  /// Resolves links in [baseJson] for the locale and tracks cycles in [visited].
  Future<Map<String, dynamic>> resolveLinkedFiles({
    required String basePath,
    required String languageCode,
    required Map<String, dynamic> baseJson,
    String? scriptCode,
    String? countryCode,
    Set<String>? visited,
    int depth = 0,
  });

  /// Builds the linked file path for the locale under [basePath].
  String getLinkedLocalePath(String basePath, String filePath, String languageCode, {String? scriptCode, String? countryCode}) {
    final locale = [languageCode, if (scriptCode != null && scriptCode.isNotEmpty) scriptCode, ?countryCode].join('-');
    return '$basePath/$locale/$filePath';
  }
}

class JsonLinkedFileResolver extends LinkedFileResolver {
  const JsonLinkedFileResolver({required super.fileLoader});

  @override
  Future<Map<String, dynamic>> resolveLinkedFiles({
    required String basePath,
    required String languageCode,
    required Map<String, dynamic> baseJson,
    String? scriptCode,
    String? countryCode,
    Set<String>? visited,
    int depth = 0,
  }) async {
    Future<Map<String, dynamic>> resolve() => _resolveLinkedFiles(
      basePath: basePath,
      languageCode: languageCode,
      baseJson: baseJson,
      scriptCode: scriptCode,
      countryCode: countryCode,
      visited: visited,
      depth: depth,
    );
    return Zone.current[_linkedBudgetKey] == null
        ? runZoned(
            resolve,
            zoneValues: {
              _linkedBudgetKey: [4096],
            },
          )
        : resolve();
  }

  Future<Map<String, dynamic>> _resolveLinkedFiles({
    required String basePath,
    required String languageCode,
    required Map<String, dynamic> baseJson,
    String? scriptCode,
    String? countryCode,
    Set<String>? visited,
    required int depth,
  }) async {
    final budget = Zone.current[_linkedBudgetKey] as List<int>;
    visited ??= <String>{};
    if (depth > maxLinkedDepth) {
      throw StateError('Maximum linked files depth ($maxLinkedDepth) exceeded for $languageCode at $basePath.');
    }
    final fullJson = Map<String, dynamic>.from(baseJson);
    for (final entry in baseJson.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is String && value.startsWith(':/')) {
        if (--budget[0] < 0) throw StateError('Maximum linked files transitions (4096) exceeded for key "$key" in $basePath ($languageCode).');
        final linkedAssetPath = getLinkedLocalePath(
          basePath,
          value.substring(2).trim(),
          languageCode,
          scriptCode: scriptCode,
          countryCode: countryCode,
        );
        if (visited.contains(linkedAssetPath)) {
          throw StateError('Cyclic linked files detected at "$linkedAssetPath" (key: "$key").');
        }
        visited.add(linkedAssetPath);
        try {
          late Map<String, dynamic> linkedJson;
          try {
            final content = await fileLoader.loadString(linkedAssetPath);
            linkedJson = json.decode(content) as Map<String, dynamic>;
          } catch (error, stack) {
            Error.throwWithStackTrace(StateError('Error resolving linked file "$linkedAssetPath" for key "$key": $error'), stack);
          }
          fullJson[key] = await resolveLinkedFiles(
            basePath: basePath,
            languageCode: languageCode,
            baseJson: linkedJson,
            scriptCode: scriptCode,
            countryCode: countryCode,
            visited: visited,
            depth: depth + 1,
          );
        } finally {
          visited.remove(linkedAssetPath);
        }
      } else if (value is Map<String, dynamic>) {
        fullJson[key] = await resolveLinkedFiles(
          basePath: basePath,
          languageCode: languageCode,
          baseJson: value,
          scriptCode: scriptCode,
          countryCode: countryCode,
          visited: visited,
          depth: depth,
        );
      }
    }
    return fullJson;
  }
}

final Object _linkedBudgetKey = Object();
