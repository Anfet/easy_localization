import 'dart:convert';
import 'dart:io';

import 'package:easy_localization_continued/src/linked_file_resolver.dart';
import 'package:easy_localization_continued/src/linked_key_parser.dart';
import 'package:path/path.dart';

import '../io_file_loader.dart';
import '../locale_name.dart';

class AuditCommand {
  /// Returns whether any locale has confirmed missing translations.
  Future<bool> run({required String transDir, required String srcDir, bool strict = false}) async {
    final translations = await _loadTranslations(Directory(transDir));
    if (translations.isEmpty) throw StateError('No JSON locales found in "$transDir".');
    return _report(translations, _scanSourceForKeys(Directory(srcDir)), strict: strict);
  }

  Future<Map<String, Map<String, dynamic>>> _loadTranslations(Directory directory) async {
    final result = <String, Map<String, dynamic>>{};
    const resolver = JsonLinkedFileResolver(fileLoader: IOFileLoader());
    final localeFiles = <String, String>{};
    for (final file in directory.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;
      final locale = basenameWithoutExtension(file.path);
      final parsed = LocaleName.parse(locale);
      if (parsed == null) throw FormatException('Unsupported JSON locale filename: ${basename(file.path)}');
      final filename = basename(file.path);
      final previous = localeFiles[parsed.key];
      if (previous != null) throw FormatException('Duplicate JSON locale filenames: $previous and $filename');
      localeFiles[parsed.key] = filename;
      result[parsed.key] = await resolver.resolveLinkedFiles(
        basePath: directory.path,
        languageCode: parsed.language,
        baseJson: json.decode(file.readAsStringSync()) as Map<String, dynamic>,
        scriptCode: parsed.script,
        countryCode: parsed.region,
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
    final textReceiver = RegExp(r'\bText\s*\(((?:r?Q+)|[^,()]+)(?:[^()]|\([^()]*\))*\)\s*\.\s*(tr|plural)\s*\(');
    final receiver = RegExp(r'(?<![\w.])((?:r?Q+)|\w+(?:\s*\.\s*\w+)*)\s*\.\s*(tr|plural)\s*\(');
    final function = RegExp(r'(?<![\w.])(?:context\s*\.\s*)?\b(tr|plural)\s*\(');
    final usages = <_Usage>[];

    void add(String expression, String method, String arguments, String maskedArguments) {
      final value = expression.trim();
      String? key;
      final literal = RegExp(r'''^(r)?(['"])(.*?)\2$''').firstMatch(value);
      final reference = RegExp(r'^LocaleKeys\s*\.\s*(\w+)$').firstMatch(value);
      if (literal != null && (literal[1] != null || (!(literal[3] ?? '').contains(r'$') && !(literal[3] ?? '').contains(r'\')))) {
        key = literal[3];
      } else if (reference != null) {
        final values = constants[reference[1]];
        if (values != null && values.length == 1) key = values.first;
      }
      final topLevel = maskedArguments.split('');
      var nesting = 0;
      for (var i = 0; i < topLevel.length; i++) {
        final char = topLevel[i];
        if ('([{'.contains(char)) {
          nesting++;
          topLevel[i] = ' ';
        } else if (')]}'.contains(char)) {
          nesting--;
          topLevel[i] = ' ';
        } else if (nesting > 0) {
          topLevel[i] = ' ';
        }
      }
      final topLevelArguments = topLevel.join();
      final gender = RegExp(r'\bgender\s*:\s*(r?Q+|null)\s*(?:,|$)').firstMatch(topLevelArguments);
      var hasGender = RegExp(r'\bgender\s*:').hasMatch(topLevelArguments);
      String? genderValue;
      if (gender != null && gender[1] != 'null') {
        final start = gender.start + (gender[0]?.indexOf(gender[1] ?? '') ?? 0);
        final literal = arguments.substring(start, start + (gender[1]?.length ?? 0));
        final match = RegExp(r'''^(r)?(['"])(.*?)\2$''').firstMatch(literal);
        if (match != null && (match[1] != null || (!(match[3] ?? '').contains(r'$') && !(match[3] ?? '').contains(r'\')))) {
          genderValue = match[3];
        }
      } else if (gender != null) {
        hasGender = false;
      }
      usages.add(_Usage(key, method == 'plural', hasGender, genderValue));
    }

    for (final content in contents) {
      var masked = _maskSource(content);
      for (final pattern in [textReceiver, receiver, function]) {
        final matches = pattern.allMatches(masked).toList();
        for (final match in matches) {
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
          final receiverExpression = match[1] ?? '';
          final isKeyReceiver =
              pattern == receiver &&
              (RegExp(r'^r?Q+$').hasMatch(receiverExpression) || RegExp(r'^LocaleKeys\s*\.\s*\w+$').hasMatch(receiverExpression));
          if (pattern == function || (pattern == receiver && !isKeyReceiver)) {
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
            var previous = start - 1;
            while (previous >= 0 && RegExp(r'\s').hasMatch(masked[previous])) {
              previous--;
            }
            expression = previous >= 0 && masked[previous] == 'Q' ? '' : content.substring(start, start + group.length);
          }
          add(expression, match[pattern == function ? 1 : 2] ?? '', arguments, argumentMask);
          masked = masked.replaceRange(match.start, match.end, ' ' * (match.end - match.start));
        }
      }
      for (final match in RegExp(r'\.\s*(tr|plural)\s*\(').allMatches(masked)) {
        usages.add(_Usage(null, match[1] == 'plural', false, null));
      }
    }
    return usages;
  }

  String _maskSource(String source) {
    final chars = source.split('');
    var i = 0;

    void scanCode({bool interpolation = false}) {
      var braces = 0;
      while (i < source.length) {
        if (interpolation && source[i] == '}' && braces == 0) {
          chars[i++] = ' ';
          return;
        }
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
          final delimiter = source.startsWith(quote * 3, i) ? quote * 3 : quote;
          final raw = i > 0 && source[i - 1] == 'r' && (i < 2 || !RegExp(r'[\w$]').hasMatch(source[i - 2]));
          for (var n = 0; n < delimiter.length; n++) {
            chars[i++] = 'Q';
          }
          while (i < source.length && !source.startsWith(delimiter, i)) {
            if (!raw && source[i] == r'\' && i + 1 < source.length) {
              chars[i++] = 'Q';
              chars[i++] = 'Q';
            } else if (!raw && source.startsWith(r'${', i)) {
              chars[i++] = ' ';
              chars[i++] = ' ';
              scanCode(interpolation: true);
            } else {
              chars[i++] = 'Q';
            }
          }
          for (var n = 0; n < delimiter.length && i < source.length; n++) {
            chars[i++] = 'Q';
          }
        } else {
          if (interpolation && source[i] == '{') braces++;
          if (interpolation && source[i] == '}') braces--;
          i++;
        }
      }
    }

    scanCode();
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

  bool _report(Map<String, Map<String, dynamic>> translations, List<_Usage> usages, {required bool strict}) {
    var hasMissing = false;
    stdout.writeln('=== Keys Audit ===');
    const forms = ['zero', 'one', 'two', 'few', 'many', 'other'];
    final parameterSetsByLocale = <String, Map<String, Map<String, Set<String>>>>{};
    final incompleteVariantsByLocale = <String, Set<String>>{};
    for (final entry in translations.entries) {
      final missing = <String>{};
      final unverified = <String>{};
      final incomplete = <String>{};

      var remainingLinks = 4096;
      void checkLinks(String key, List<String> path, String variant) {
        if (path.length == 1) remainingLinks = 4096;
        final value = _lookup(entry.value, key);
        if (value is! String) {
          if (path.length > 1) incompleteVariantsByLocale.putIfAbsent(entry.key, () => <String>{}).add(variant);
          missing.add(path.length == 1 ? key : '$key (${path.join(' -> ')})');
          return;
        }
        final parameters = RegExp(
          r'\{([^{}]+)\}',
        ).allMatches(value).map((match) => match[1] ?? (throw StateError('Parameter capture group 1 was missing.'))).toSet();
        parameterSetsByLocale
            .putIfAbsent(entry.key, () => <String, Map<String, Set<String>>>{})
            .putIfAbsent(variant, () => <String, Set<String>>{})
            .putIfAbsent(key, () => <String>{})
            .addAll(parameters);
        for (final match in linkedKeyMatcher.allMatches(value)) {
          if (--remainingLinks < 0) throw StateError('Maximum linked translation transitions (4096) exceeded for [${path.first}] in ${entry.key}.');
          final target = (match[0] ?? '').replaceFirst(linkedKeyPrefixMatcher, '').replaceAll(RegExp(r'[()]'), '');
          final next = [...path, target];
          if (path.contains(target)) {
            unverified.add('cycle: ${next.join(' -> ')}');
            incompleteVariantsByLocale.putIfAbsent(entry.key, () => <String>{}).add(variant);
          } else {
            checkLinks(target, next, variant);
          }
        }
      }

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
            for (final name in candidates) {
              final formKey = '$key.$name';
              if (_lookup(entry.value, formKey) is String) checkLinks(formKey, [formKey], formKey);
            }
          } else {
            final formKey = '$key.${usage.genderValue}';
            checkLinks(formKey, [formKey], formKey);
          }
        } else if (usage.plural) {
          if (!forms.any((form) => _lookup(entry.value, '$key.$form') is String)) {
            missing.add(key);
          } else {
            if (_lookup(entry.value, '$key.other') is! String) incomplete.add(key);
            for (final form in forms) {
              final formKey = '$key.$form';
              if (_lookup(entry.value, formKey) is String) checkLinks(formKey, [formKey], formKey);
            }
          }
        } else {
          checkLinks(key, [key], key);
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
      if (incomplete.isNotEmpty) {
        stdout.writeln('  🟡 Plural groups without other: ${incomplete.join(', ')}');
        if (strict) hasMissing = true;
      }
    }

    final variants = parameterSetsByLocale.values.expand((sets) => sets.keys).toSet().toList()..sort();
    final mismatches = <String>[];
    for (final variant in variants) {
      final locales = parameterSetsByLocale.entries.where((entry) => entry.value.containsKey(variant)).toList();
      for (var first = 0; first < locales.length; first++) {
        for (var second = first + 1; second < locales.length; second++) {
          final firstStrings =
              locales[first].value[variant] ?? (throw StateError('Parameter map missing for ${locales[first].key} variant $variant.'));
          final secondStrings =
              locales[second].value[variant] ?? (throw StateError('Parameter map missing for ${locales[second].key} variant $variant.'));
          final firstComplete = !(incompleteVariantsByLocale[locales[first].key]?.contains(variant) ?? false);
          final secondComplete = !(incompleteVariantsByLocale[locales[second].key]?.contains(variant) ?? false);
          final firstParameters = firstComplete && secondComplete
              ? firstStrings.values.expand((parameters) => parameters).toSet()
              : firstStrings[variant] ?? (throw StateError('Parameter set missing for ${locales[first].key} variant $variant.'));
          final secondParameters = firstComplete && secondComplete
              ? secondStrings.values.expand((parameters) => parameters).toSet()
              : secondStrings[variant] ?? (throw StateError('Parameter set missing for ${locales[second].key} variant $variant.'));
          if (firstParameters.length == secondParameters.length && firstParameters.containsAll(secondParameters)) continue;
          mismatches.add(
            '  ⚠️ $variant: ${locales[first].key} {${(firstParameters.toList()..sort()).join(', ')}}; '
            '${locales[second].key} {${(secondParameters.toList()..sort()).join(', ')}}',
          );
        }
      }
    }
    if (mismatches.isNotEmpty) {
      stdout.writeln('\n⚠️ Named parameter mismatches (${mismatches.length}):');
      for (final mismatch in mismatches) {
        stdout.writeln(mismatch);
      }
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
