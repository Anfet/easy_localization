import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/src/file_loaders/io_file_loader.dart';
import 'package:easy_localization/src/linked_file_resolver.dart';
import 'package:path/path.dart';

class AuditCommand {
  /// Returns whether any locale has confirmed missing translations.
  Future<bool> run({required String transDir, required String srcDir}) async {
    final translations = await _loadTranslations(Directory(transDir));
    if (translations.isEmpty) throw StateError('No JSON locales found in "$transDir".');
    return _report(translations, _scanSourceForKeys(Directory(srcDir)));
  }

  Future<Map<String, Map<String, dynamic>>> _loadTranslations(Directory directory) async {
    final result = <String, Map<String, dynamic>>{};
    const resolver = JsonLinkedFileResolver(fileLoader: IOFileLoader());
    for (final file in directory.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final locale = basenameWithoutExtension(file.path);
      final parts = locale.split('-');
      final hasScript = parts.length > 1 && parts[1].length == 4;
      result[locale] = await resolver.resolveLinkedFiles(
        basePath: directory.path,
        languageCode: parts.first,
        baseJson: json.decode(file.readAsStringSync()) as Map<String, dynamic>,
        scriptCode: hasScript ? parts[1] : null,
        countryCode: parts.length > (hasScript ? 2 : 1) ? parts.last : null,
      );
    }
    return result;
  }

  List<_Usage> _scanSourceForKeys(Directory directory) {
    final files = directory.listSync(recursive: true).whereType<File>().where((file) => file.path.endsWith('.dart'));
    // Keep strings intact while masking comments, including comment markers inside strings.
    final tokens = RegExp(r'''("(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')|//[^\n]*|/\*[\s\S]*?\*/''');
    final contents = files.map((file) => file.readAsStringSync().replaceAllMapped(tokens, (m) => m[1] ?? ' ')).toList();
    final constants = <String, String>{};
    final constant = RegExp(r'''static\s+const\s+(?:String\s+)?(\w+)\s*=\s*(['"])([^'"$\\]*)\2\s*;''');
    final localeKeysClass = RegExp(r'\bclass\s+LocaleKeys\s*\{([^{}]*)\}');
    for (final content in contents) {
      for (final declaration in localeKeysClass.allMatches(content)) {
        for (final match in constant.allMatches(declaration[1] ?? '')) {
          final name = match[1];
          final value = match[3];
          if (name != null && value != null) constants[name] = value;
        }
      }
    }
    const expression = r'''(?:['"](?:\\.|[^'"\\])*['"](?=\s*[,)])|LocaleKeys\s*\.\s*\w+(?=\s*[,)])|[^,)]*)''';
    const receiverExpression = r'''(?:['"](?:\\.|[^'"\\])*['"]|LocaleKeys\s*\.\s*\w+|\b\w+)''';
    final receiver = RegExp('($receiverExpression)\\s*\\.\\s*(tr|plural)\\s*\\(([^)]*)\\)');
    final textReceiver = RegExp('Text\\s*\\(\\s*($expression)\\s*\\)\\s*\\.\\s*(tr|plural)\\s*\\(([^)]*)\\)');
    final function = RegExp('(?:\\bcontext\\s*\\.\\s*)?\\b(tr|plural)\\s*\\(\\s*($expression)([^)]*)\\)');
    final usages = <_Usage>[];

    void add(String expression, String method, String arguments) {
      final value = expression.trim();
      String? key;
      final literal = RegExp(r'''^(['"])([^'"\\]*)\1$''').firstMatch(value);
      final reference = RegExp(r'^LocaleKeys\s*\.\s*(\w+)$').firstMatch(value);
      if (literal != null && !(literal[2] ?? '').contains(r'$')) {
        key = literal[2];
      } else if (reference != null) {
        key = constants[reference[1]];
      }
      final gender = RegExp(r'''\bgender\s*:\s*(['"])([^'"$\\]*)\1\s*(?:,|$)''').firstMatch(arguments);
      final hasGender = RegExp(r'\bgender\s*:').hasMatch(arguments);
      usages.add(_Usage(key, method == 'plural', hasGender, gender?[2]));
    }

    for (final content in contents) {
      // Mask complete Text calls before scanning receivers and function forms.
      var rest = content.replaceAllMapped(textReceiver, (match) {
        add(match[1] ?? '', match[2] ?? '', match[3] ?? '');
        return ' ';
      });
      rest = rest.replaceAllMapped(receiver, (match) {
        if (match[1] == 'context') return match[0] ?? '';
        add(match[1] ?? '', match[2] ?? '', match[3] ?? '');
        return ' ';
      });
      for (final match in function.allMatches(rest)) {
        add(match[2] ?? '', match[1] ?? '', match[3] ?? '');
      }
    }
    return usages;
  }

  dynamic _lookup(Map<String, dynamic> translations, String key) {
    if (translations.containsKey(key)) return translations[key];
    dynamic value = translations;
    for (final part in key.split('.')) {
      if (value is! Map) return null;
      value = value[part];
    }
    return value;
  }

  bool _report(Map<String, Map<String, dynamic>> translations, List<_Usage> usages) {
    var hasMissing = false;
    stdout.writeln('=== Keys Audit ===');
    const forms = ['zero', 'one', 'two', 'few', 'many', 'other'];
    for (final entry in translations.entries) {
      final missing = <String>{};
      final unverified = <String>{};
      final incomplete = <String>{};
      for (final usage in usages) {
        final key = usage.key;
        if (key == null) {
          unverified.add('dynamic key');
          continue;
        }
        if (usage.gender) {
          if (usage.genderValue == null) {
            final group = _lookup(entry.value, key);
            if (group is! Map || !group.values.any((value) => value is String)) missing.add(key);
            unverified.add('$key gender');
          } else if (_lookup(entry.value, '$key.${usage.genderValue}') is! String) {
            missing.add('$key.${usage.genderValue}');
          }
        } else if (usage.plural) {
          if (!forms.any((form) => _lookup(entry.value, '$key.$form') is String)) {
            missing.add(key);
          } else if (_lookup(entry.value, '$key.other') is! String) {
            incomplete.add(key);
          }
        } else if (_lookup(entry.value, key) is! String) {
          missing.add(key);
        }
      }
      stdout.writeln('\nLanguage: ${entry.key}');
      if (missing.isEmpty) stdout.writeln('  ✅ No missing static keys found (dynamic calls may not be checked).');
      if (missing.isNotEmpty) {
        hasMissing = true;
        stdout.writeln('  🔴 Missing (${missing.length}):');
        for (final key in missing) {
          stdout.writeln('    – $key');
        }
      }
      if (unverified.isNotEmpty) {
        stdout.writeln('  🟡 Unverified keys: These keys contain variables or expressions and cannot be verified.');
        for (final key in unverified) {
          stdout.writeln('    – $key');
        }
      }
      if (incomplete.isNotEmpty) stdout.writeln('  🟡 Plural groups without other: ${incomplete.join(', ')}');
    }
    return hasMissing;
  }
}

class _Usage {
  _Usage(this.key, this.plural, this.gender, this.genderValue);

  final String? key;
  final bool plural;
  final bool gender;
  final String? genderValue;
}
