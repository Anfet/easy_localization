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
    final contents = files.map((file) => file.readAsStringSync()).toList();
    final constants = <String, Set<String>>{};
    final constant = RegExp(r'''static\s+const\s+(?:String\s+)?(\w+)\s*=\s*(['"])([^'"$\\]*)\2\s*;''');
    final localeKeysClass = RegExp(r'\bclass\s+LocaleKeys\s*\{([^{}]*)\}');
    for (final content in contents) {
      final masked = _maskSource(content);
      for (final declaration in localeKeysClass.allMatches(masked)) {
        final bodyStart = declaration.start + (declaration[0]?.indexOf('{') ?? 0) + 1;
        final body = content.substring(bodyStart, declaration.end - 1);
        for (final match in constant.allMatches(body)) {
          if (!masked.substring(bodyStart + match.start).startsWith('static')) continue;
          final name = match[1];
          final value = match[3];
          if (name != null && value != null) constants.putIfAbsent(name, () => {}).add(value);
        }
      }
    }
    final textReceiver = RegExp(r'\bText\s*\(([^()]*)\)\s*\.\s*(tr|plural)\s*\(');
    final receiver = RegExp(r'\b(\w+(?:\s*\.\s*\w+)?)\s*\.\s*(tr|plural)\s*\(');
    final function = RegExp(r'(?<![\w.])(?:context\s*\.\s*)?\b(tr|plural)\s*\(');
    final usages = <_Usage>[];

    void add(String expression, String method, String arguments, String maskedArguments) {
      final value = expression.trim();
      String? key;
      final literal = RegExp(r'''^(['"])([^'"\\]*)\1$''').firstMatch(value);
      final reference = RegExp(r'^LocaleKeys\s*\.\s*(\w+)$').firstMatch(value);
      if (literal != null && !(literal[2] ?? '').contains(r'$')) {
        key = literal[2];
      } else if (reference != null) {
        final values = constants[reference[1]];
        if (values != null && values.length == 1) key = values.first;
      }
      final gender = RegExp(r'\bgender\s*:\s*(Q+)\s*(?:,|$)').firstMatch(maskedArguments);
      final hasGender = RegExp(r'\bgender\s*:').hasMatch(maskedArguments);
      String? genderValue;
      if (gender != null) {
        final start = gender.start + (gender[0]?.indexOf(gender[1] ?? '') ?? 0);
        final literal = arguments.substring(start, start + (gender[1]?.length ?? 0));
        final match = RegExp(r'''^(['"])([^'"$\\]*)\1$''').firstMatch(literal);
        genderValue = match?[2];
      }
      usages.add(_Usage(key, method == 'plural', hasGender, genderValue));
    }

    for (final content in contents) {
      var masked = _maskSource(content);
      for (final pattern in [textReceiver, receiver, function]) {
        final matches = pattern.allMatches(masked).toList();
        for (final match in matches) {
          if (pattern == receiver && match[1] == 'context') continue;
          var depth = 1;
          var end = match.end;
          while (end < masked.length && depth > 0) {
            if (masked[end] == '(') depth++;
            if (masked[end] == ')') depth--;
            end++;
          }
          if (depth != 0) continue;
          final argsStart = match.end;
          final argsEnd = end - 1;
          final maskedArgs = masked.substring(argsStart, argsEnd);
          var expression = '';
          var arguments = content.substring(argsStart, argsEnd);
          var argumentMask = maskedArgs;
          if (pattern == function) {
            var nesting = 0;
            var separator = maskedArgs.length;
            for (var i = 0; i < maskedArgs.length; i++) {
              if ('([{'.contains(maskedArgs[i])) nesting++;
              if (')]}'.contains(maskedArgs[i])) nesting--;
              if (maskedArgs[i] == ',' && nesting == 0) {
                separator = i;
                break;
              }
            }
            expression = content.substring(argsStart, argsStart + separator);
            arguments = arguments.substring(separator);
            argumentMask = maskedArgs.substring(separator);
          } else {
            final group = match[1] ?? '';
            final start = match.start + (match[0]?.indexOf(group) ?? 0);
            expression = content.substring(start, start + group.length);
          }
          add(expression, match[pattern == function ? 1 : 2] ?? '', arguments, argumentMask);
          masked = masked.replaceRange(match.start, match.end, ' ' * (match.end - match.start));
        }
      }
    }
    return usages;
  }

  String _maskSource(String source) {
    final chars = source.split('');
    var i = 0;
    while (i < source.length) {
      if (source.startsWith('//', i)) {
        while (i < source.length && source[i] != '\n') {
          chars[i++] = ' ';
        }
      } else if (source.startsWith('/*', i)) {
        var depth = 0;
        do {
          if (source.startsWith('/*', i)) {
            depth++;
            chars[i++] = ' ';
            chars[i++] = ' ';
          } else if (source.startsWith('*/', i)) {
            depth--;
            chars[i++] = ' ';
            chars[i++] = ' ';
          } else {
            chars[i++] = ' ';
          }
        } while (i < source.length && depth > 0);
      } else if (source[i] == "'" || source[i] == '"') {
        final quote = source[i];
        final triple = source.startsWith(quote * 3, i);
        final delimiter = triple ? quote * 3 : quote;
        final raw = i > 0 && source[i - 1] == 'r';
        for (var n = 0; n < delimiter.length; n++) {
          chars[i++] = 'Q';
        }
        while (i < source.length && !source.startsWith(delimiter, i)) {
          if (!raw && source[i] == r'\' && i + 1 < source.length) chars[i++] = 'Q';
          chars[i++] = 'Q';
        }
        for (var n = 0; n < delimiter.length && i < source.length; n++) {
          chars[i++] = 'Q';
        }
      } else {
        i++;
      }
    }
    return chars.join();
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
            final candidates = <String>{
              if (group is Map) ...group.keys.whereType<String>(),
              ...entry.value.keys.where((name) => name.startsWith('$key.')).map((name) => name.substring(key.length + 1)),
            };
            if (!candidates.any((name) => _lookup(entry.value, '$key.$name') is String)) missing.add(key);
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
