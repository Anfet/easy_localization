import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'io_file_loader.dart';
import 'package:easy_localization_continued/src/linked_file_resolver.dart';
import 'package:path/path.dart' as path;

const _invalidIdentifiers = {
  'assert',
  'break',
  'case',
  'catch',
  'class',
  'const',
  'continue',
  'default',
  'do',
  'else',
  'enum',
  'extends',
  'false',
  'final',
  'finally',
  'for',
  'if',
  'in',
  'is',
  'new',
  'null',
  'rethrow',
  'return',
  'super',
  'switch',
  'this',
  'throw',
  'true',
  'try',
  'var',
  'void',
  'while',
  'with',
  'typedef',
  'LocaleKeys',
  'hashCode',
  'runtimeType',
  'noSuchMethod',
  'toString',
};

const _preservedKeywords = ['few', 'many', 'one', 'other', 'two', 'zero', 'male', 'female'];

Future<void> main(List<String> args) async {
  try {
    if (_isHelpCommand(args)) {
      _printHelperDisplay();
    } else {
      await handleLangFiles(_generateOption(args));
    }
  } catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  }
}

bool _isHelpCommand(List<String> args) {
  return args.length == 1 && (args[0] == '--help' || args[0] == '-h');
}

void _printHelperDisplay() {
  var parser = _generateArgParser(null);
  stdout.writeln(parser.usage);
}

GenerateOptions _generateOption(List<String> args) {
  var generateOptions = GenerateOptions();
  var parser = _generateArgParser(generateOptions);
  parser.parse(args);
  return generateOptions;
}

ArgParser _generateArgParser(GenerateOptions? generateOptions) {
  var parser = ArgParser();

  parser.addOption(
    'source-dir',
    abbr: 'S',
    defaultsTo: 'assets/translations',
    callback: (String? x) => generateOptions!.sourceDir = x,
    help: 'Folder containing localization files',
  );

  parser.addOption('source-file', abbr: 's', callback: (String? x) => generateOptions!.sourceFile = x, help: 'File to use for localization');

  parser.addOption(
    'output-dir',
    abbr: 'O',
    defaultsTo: 'lib/generated',
    callback: (String? x) => generateOptions!.outputDir = x,
    help: 'Output folder stores for the generated file',
  );

  parser.addOption(
    'output-file',
    abbr: 'o',
    defaultsTo: 'codegen_loader.g.dart',
    callback: (String? x) => generateOptions!.outputFile = x,
    help: 'Output file name',
  );

  parser.addOption(
    'format',
    abbr: 'f',
    defaultsTo: 'json',
    callback: (String? x) => generateOptions!.format = x,
    help: 'Support json or keys formats',
    allowed: ['json', 'keys'],
  );

  parser.addFlag(
    'skip-unnecessary-keys',
    abbr: 'u',
    defaultsTo: false,
    callback: (bool? x) => generateOptions!.skipUnnecessaryKeys = x,
    help: 'If true - Skip unnecessary keys of nested objects.',
  );

  return parser;
}

class GenerateOptions {
  String? sourceDir;
  String? sourceFile;
  String? outputDir;
  String? outputFile;
  String? format;
  bool? skipUnnecessaryKeys;

  @override
  String toString() {
    return 'format: $format sourceDir: $sourceDir sourceFile: $sourceFile outputDir: $outputDir outputFile: $outputFile skipUnnecessaryKeys: $skipUnnecessaryKeys';
  }
}

Future<void> handleLangFiles(GenerateOptions options) async {
  final sourcePath = Directory(path.absolute(options.sourceDir!));
  final outputPath = Directory(path.join(path.absolute(options.outputDir!), options.outputFile));

  if (!await sourcePath.exists()) {
    throw StateError('Source path does not exist: ${sourcePath.path}');
  }

  var files = await dirContents(sourcePath);
  if (options.sourceFile != null) {
    final sourceFile = File(path.join(sourcePath.path, options.sourceFile));
    if (!await sourceFile.exists()) {
      throw StateError('Source file does not exist: ${sourceFile.path}');
    }
    files = [sourceFile];
  } else {
    files = files.where((f) => f is File && path.extension(f.path) == '.json').toList()
      ..sort((a, b) => path.basename(a.path).compareTo(path.basename(b.path)));
  }

  if (files.isNotEmpty) {
    await generateFile(files, outputPath, options);
  } else {
    throw StateError('Source path empty: ${sourcePath.path}');
  }
}

Future<List<FileSystemEntity>> dirContents(Directory dir) => dir.list(recursive: false).toList();

Future<void> generateFile(List<FileSystemEntity> files, Directory outputPath, GenerateOptions options) async {
  const loader = IOFileLoader();
  const resolver = JsonLinkedFileResolver(fileLoader: loader);
  final translations = <String, Map<String, dynamic>>{};
  final localeFiles = <String, String>{};
  for (final file in options.format == 'keys' ? files.take(1) : files) {
    final locale = path.basenameWithoutExtension(file.path);
    final normalized = locale.replaceAll('-', '_');
    if (options.format == 'json') {
      final filename = path.basename(file.path);
      if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(normalized)) {
        throw FormatException('Unsupported JSON locale filename: $filename');
      }
      final previous = localeFiles[normalized];
      if (previous != null) {
        throw FormatException('Duplicate JSON locale filenames: $previous and $filename');
      }
      localeFiles[normalized] = filename;
    }
    final parts = locale.split('-');
    final hasScript = parts.length > 1 && parts[1].length == 4;
    translations[normalized] = await resolver.resolveLinkedFiles(
      basePath: path.dirname(file.path),
      languageCode: parts.first,
      scriptCode: hasScript ? parts[1] : null,
      countryCode: parts.length > (hasScript ? 2 : 1) ? parts.last : null,
      baseJson: json.decode(await loader.loadString(file.path)) as Map<String, dynamic>,
    );
  }

  final classBuilder = StringBuffer();
  switch (options.format) {
    case 'json':
      _writeJson(classBuilder, translations);
      break;
    case 'keys':
      _writeKeys(classBuilder, translations.values.first, options.skipUnnecessaryKeys);
      break;
    default:
      throw StateError('Format not supported: ${options.format}');
  }
  classBuilder.writeln('}');
  final generatedFile = File(outputPath.path);
  await generatedFile.create(recursive: true);
  await generatedFile.writeAsString(classBuilder.toString());
  stdout.writeln('All done! File generated in ${outputPath.path}');
}

void _writeKeys(StringBuffer classBuilder, Map<String, dynamic> translations, bool? skipUnnecessaryKeys) {
  var file = '''
// DO NOT EDIT. This is code generated via package:easy_localization_continued/generate.dart

// ignore_for_file: constant_identifier_names

export 'package:easy_localization_continued/easy_localization.dart'
    show StringTranslateExtension, TextTranslateExtension, BuildContextEasyLocalizationExtension;

abstract class LocaleKeys {
''';

  file += _resolve(translations, skipUnnecessaryKeys, <String>{});

  classBuilder.writeln(file);
}

String _resolve(Map<String, dynamic> translations, bool? skipUnnecessaryKeys, Set<String> names, [String? accKey]) {
  var fileContent = '';

  final sortedKeys = translations.keys.toList();

  final canIgnoreKeys = skipUnnecessaryKeys == true;

  bool containsPreservedKeywords(Map<String, dynamic> map) => map.keys.any((element) => _preservedKeywords.contains(element));

  for (var key in sortedKeys) {
    var ignoreKey = false;
    if (translations[key] is Map) {
      // If key does not contain keys for plural(), gender() etc. and option is enabled -> ignore it
      ignoreKey = !containsPreservedKeywords(translations[key] as Map<String, dynamic>) && canIgnoreKeys;

      var nextAccKey = key;
      if (accKey != null) {
        nextAccKey = '$accKey.$key';
      }

      fileContent += _resolve(translations[key], skipUnnecessaryKeys, names, nextAccKey);
    }

    if (!ignoreKey) {
      final name = accKey == null ? key : '${accKey.replaceAll('.', '_')}_$key';
      final value = accKey == null ? key : '$accKey.$key';
      if (!RegExp(r'^[a-zA-Z$][a-zA-Z0-9_$]*$').hasMatch(name) || _invalidIdentifiers.contains(name)) {
        throw FormatException('Unsupported generated identifier "$name" for key "$value"');
      }
      if (!names.add(name)) {
        throw FormatException('Duplicate generated identifier "$name" for key "$value"');
      }
      final escapedValue = value.replaceAll(r'$', r'\$');
      fileContent += "  static const $name = '$escapedValue';\n";
    }
  }

  return fileContent;
}

void _writeJson(StringBuffer classBuilder, Map<String, Map<String, dynamic>> translations) {
  var gFile = '''
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

  ''';

  final listLocales = [];

  for (final entry in translations.entries) {
    final localeName = entry.key;
    listLocales.add('"$localeName": _$localeName');
    final data = entry.value;

    final mapString = const JsonEncoder.withIndent('  ').convert(data).replaceAll(r'$', r'\$');
    gFile += 'static const Map<String,dynamic> _$localeName = $mapString;\n';
  }

  gFile += 'static const Map<String, Map<String,dynamic>> mapLocales = {${listLocales.join(', ')}};';
  classBuilder.writeln(gFile);
}
