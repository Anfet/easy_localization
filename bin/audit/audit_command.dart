import 'dart:convert';
import 'dart:io';
import 'package:easy_localization/src/linked_file_resolver.dart';
import 'package:path/path.dart';
import 'package:easy_localization/src/file_loaders/io_file_loader.dart';

class AuditCommand {
  /// Audits the source and returns whether any locale has confirmed missing keys.
  /// File system, JSON and linked-file errors propagate to the CLI caller.
  Future<bool> run({required String transDir, required String srcDir}) async {
    final translationDir = Directory(transDir);
    final sourceDir = Directory(srcDir);
    final allTranslations = await _loadTranslations(translationDir);
    if (allTranslations.isEmpty) {
      throw StateError('No JSON locales found in "$transDir".');
    }
    final usedKeys = _scanSourceForKeys(sourceDir);
    return _report(allTranslations, usedKeys);
  }

  /// Walks [translationsDir], reads every `.json`, flattens nested maps
  /// into dot‑separated keys, and returns a map:
  ///   { 'en': {'home.title', 'home.subtitle', …}, 'fr': { … } }
  /// Also handles linked translation files (those containing ':/file.json' references)
  Future<Map<String, Set<String>>> _loadTranslations(Directory translationsDir) async {
    final result = <String, Set<String>>{};
    const IOFileLoader fileLoader = IOFileLoader();
    const LinkedFileResolver linkedFileResolver = JsonLinkedFileResolver(fileLoader: fileLoader);

    for (var file in translationsDir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;

      final local = basenameWithoutExtension(file.path);
      final parts = local.split('-');
      final langCode = parts.first;
      final hasScript = parts.length > 1 && parts[1].length == 4;
      final scriptCode = hasScript ? parts[1] : null;
      final countryCode = parts.length > (hasScript ? 2 : 1) ? parts.last : null;
      final jsonMap = json.decode(file.readAsStringSync()) as Map<String, dynamic>;

      // Process linked files if present using the shared resolver
      final resolvedJson = await linkedFileResolver.resolveLinkedFiles(
        basePath: translationsDir.path,
        languageCode: langCode,
        baseJson: jsonMap,
        scriptCode: scriptCode,
        countryCode: countryCode,
      );
      result[local] = _flatten(resolvedJson);
    }
    return result;
  }

  Set<String> _flatten(Map<String, dynamic> json, [String parentKey = '']) {
    final keys = <String>{};
    for (var entry in json.entries) {
      final key = entry.key;
      final value = entry.value;

      final newKey = parentKey.isEmpty ? key : '$parentKey.$key';
      if (value is String) {
        keys.add(newKey);
        continue;
      }

      if (value is Map<String, dynamic>) {
        keys.addAll(_flatten(value, newKey));
        continue;
      }

      if (value is List || value is num || value is bool) {
        keys.add(newKey);
      }
    }
    return keys;
  }

  Set<String> _scanSourceForKeys(Directory srcDir) {
    List<RegExp> keyPatterns = [
      // 1) tr('foo.bar') or tr("foo.bar"), with optional args/comma before the )
      RegExp(r"""\btr\s*\(\s*['"]([^'"]+)['"](?:\s*,[^)]*)?\)"""),

      // 2) context.tr('foo.bar') same as above but with the context qualifier
      RegExp(r"""context\s*\.\s*tr\s*\(\s*['"]([^'"]+)['"](?:\s*,[^)]*)?\)"""),

      // 3) 'foo.bar'.tr() or "foo.bar".tr(), allowing whitespace/newlines
      RegExp(r"""['"]([^'"]+)['"]\s*\.\s*tr\s*\(\s*[^)]*\)"""),

      // 4) generated keys: LocaleKeys.foo_bar (whitespace around the dot ok)
      RegExp(r"""LocaleKeys\s*\.\s*([A-Za-z0-9_]+)"""),

      // 5) plural() calls
      RegExp(r"""\bplural\s*\(\s*['"]([^'"]+)['"](?:\s*,[^)]*)?\)"""),

      // 6) context.plural() calls
      RegExp(r"""context\s*\.\s*plural\s*\(\s*['"]([^'"]+)['"](?:\s*,[^)]*)?\)"""),
    ];

    final used = <String>{};

    for (var file in srcDir.listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final content = file.readAsStringSync();
      for (var pattern in keyPatterns) {
        final matches = pattern.allMatches(content);
        for (var match in matches) {
          if (match.groupCount > 0) {
            String key = match.group(1)!;
            if (pattern.pattern.contains('LocaleKeys')) {
              key = key.replaceAll('_', '.');
            }
            used.add(key);
          }
        }
      }
    }
    return used;
  }

  bool _report(Map<String, Set<String>> allTranslations, Set<String> usedKeys) {
    var hasMissing = false;
    stdout.writeln('=== Keys Audit ===');

    for (var lang in allTranslations.keys) {
      final keysInFile = allTranslations[lang]!;
      final missing = usedKeys.difference(keysInFile);
      final missingWithVariables = usedKeys.where((key) => key.contains('\$')).toList();
      final missingWithoutVariables = missing.where((key) => !key.contains('\$')).toList();

      stdout.writeln('\nLanguage: $lang');
      if (missingWithVariables.isEmpty && missingWithoutVariables.isEmpty) {
        stdout.writeln('  ✅ No missing static keys found (dynamic calls may not be checked).');
      }

      if (missingWithoutVariables.isNotEmpty) {
        hasMissing = true;
        stdout.writeln('  🔴 Missing (${missingWithoutVariables.length}):');
        for (var key in missingWithoutVariables) {
          stdout.writeln('    – $key');
        }

        stdout.writeln('\n');
      }

      if (missingWithVariables.isNotEmpty) {
        stdout.writeln('  🟡 Unverified keys with variables (${missingWithVariables.length}):');
        stdout.writeln('    These keys contain variables and cannot be verified.');
        for (var key in missingWithVariables) {
          stdout.writeln('    – $key');
        }
      }
    }
    return hasMissing;
  }
}
