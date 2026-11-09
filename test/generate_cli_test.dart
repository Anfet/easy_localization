import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory scratch;
  final generator = path.absolute('bin/generate.dart');

  setUp(() async {
    scratch = await Directory.systemTemp.createTemp('loc8 cli ');
  });

  tearDown(() async => scratch.delete(recursive: true));

  Future<String> generate(Directory source, String format, {String? sourceFile, bool skip = false}) async {
    final output = Directory(path.join(scratch.path, 'output'));
    final result = await Process.run(
      'dart',
      [
        generator,
        '-S',
        path.basename(source.path),
        '-O',
        'output',
        '-o',
        '$format.dart',
        '-f',
        format,
        if (sourceFile != null) ...['-s', sourceFile],
        if (skip) '-u',
      ],
      workingDirectory: scratch.path,
      runInShell: true,
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return File(path.join(output.path, '$format.dart')).readAsString();
  }

  Future<void> createFixtures(Directory dir, List<String> order) async {
    await dir.create(recursive: true);
    final fixtures = {
      'en.json': {
        'englishOnly': 'English',
        'abstract': 'valid',
        'nested': {'child': 'value'},
        'count': {'one': 'one', 'other': 'other'},
      },
      'fr.json': {
        'frenchOnly': 'Français',
        'nested': {'child': 'valeur'},
      },
    };
    for (final name in order) {
      await File(path.join(dir.path, name)).writeAsString(jsonEncode(fixtures[name]));
    }
    await File(path.join(dir.path, 'ignored.json.bak')).writeAsString('{}');
    await Directory(path.join(dir.path, 'folder.json')).create();
  }

  test('sorts regular JSON files and selects one key source', () async {
    final first = Directory(path.join(scratch.path, 'first'));
    final second = Directory(path.join(scratch.path, 'second'));
    await createFixtures(first, ['en.json', 'fr.json']);
    await createFixtures(second, ['fr.json', 'en.json']);

    expect(await generate(first, 'json'), await generate(second, 'json'));
    final keys = await generate(first, 'keys');
    expect(keys, contains('show StringTranslateExtension, TextTranslateExtension, BuildContextEasyLocalizationExtension;'));
    expect(keys, await generate(second, 'keys'));
    expect(keys, contains('englishOnly'));
    expect(keys, contains("abstract = 'abstract'"));
    expect(keys, isNot(contains('frenchOnly')));
    final french = await generate(first, 'keys', sourceFile: 'fr.json');
    expect(french, contains('frenchOnly'));
    expect(french, isNot(contains('englishOnly')));
    final skipped = await generate(first, 'keys', skip: true);
    expect(skipped, contains('nested_child'));
    expect(skipped, isNot(contains('static const nested =')));
    expect(skipped, contains('static const count ='));
    expect(skipped, contains("static const count_one = 'count.one'"));
  });

  test('accepts relative and absolute filesystem paths with spaces', () async {
    final source = Directory(path.join(scratch.path, 'source files'));
    await source.create();
    await File(path.join(source.path, 'en.json')).writeAsString('{"hello":"Hello"}');
    for (final absolute in [false, true]) {
      final result = await Process.run(
        'dart',
        [
          generator,
          '-S',
          absolute ? source.path : 'source files',
          '-O',
          absolute ? path.join(scratch.path, 'output files') : 'output files',
          '-o',
          'keys.dart',
          '-f',
          'keys',
        ],
        workingDirectory: scratch.path,
        runInShell: true,
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect(await File(path.join(scratch.path, 'output files', 'keys.dart')).readAsString(), contains("hello = 'hello'"));
    }
  });

  test('defaults to assets/translations when source-dir is omitted', () async {
    final source = Directory(path.join(scratch.path, 'assets', 'translations'));
    await source.create(recursive: true);
    await File(path.join(source.path, 'en.json')).writeAsString('{"hello":"Hello"}');
    final output = Directory(path.join(scratch.path, 'output'));
    final result = await Process.run(
      'dart',
      [generator, '-O', 'output', '-o', 'loader.dart', '-f', 'json'],
      workingDirectory: scratch.path,
      runInShell: true,
    );
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    expect(await File(path.join(output.path, 'loader.dart')).readAsString(), contains('Hello'));
  });

  test('resolves linked files for loaders and keys, including script locales', () async {
    final source = Directory(path.join(scratch.path, 'langs'));
    await source.create();
    for (final locale in ['en', 'zh-Hans-CN']) {
      await File(path.join(source.path, '$locale.json')).writeAsString('{"section":":/section.json"}');
      final fragments = Directory(path.join(source.path, locale));
      await fragments.create();
      await File(path.join(fragments.path, 'section.json')).writeAsString('{"title":"$locale"}');
    }
    final loader = await generate(source, 'json');
    expect(loader, isNot(contains('StringTranslateExtension')));
    expect(loader, contains('"title": "en"'));
    expect(loader, contains('"title": "zh-Hans-CN"'));
    expect(loader, isNot(contains(':/')));
    final keys = await generate(source, 'keys');
    expect(keys, contains("section_title = 'section.title'"));
  });

  test('invalid generated identifiers preserve the previous keys file', () async {
    final source = Directory(path.join(scratch.path, 'langs'));
    await source.create();
    final input = File(path.join(source.path, 'en.json'));
    final output = File(path.join(scratch.path, 'output', 'keys.dart'));
    await output.create(recursive: true);
    for (final translations in [
      {'auth.login': 'value'},
      {'bad-key': 'value'},
      {'_private': 'value'},
      {'class': 'value'},
      {'hashCode': 'value'},
      {
        'a_b': 'value',
        'a': {'b': 'value'},
      },
    ]) {
      await input.writeAsString(jsonEncode(translations));
      await output.writeAsString('previous');
      final result = await Process.run(
        'dart',
        [generator, '-S', 'langs', '-O', 'output', '-o', 'keys.dart', '-f', 'keys'],
        workingDirectory: scratch.path,
        runInShell: true,
      );
      expect(result.exitCode, 1, reason: '$translations: ${result.stdout} ${result.stderr}');
      expect(result.stderr.toString(), isNotEmpty);
      expect(await output.readAsString(), 'previous');
    }
  });

  test('rejects invalid or duplicate JSON locale filenames without replacing output', () async {
    final source = Directory(path.join(scratch.path, 'langs'));
    await source.create();
    final output = File(path.join(scratch.path, 'output', 'loader.dart'));
    await output.create(recursive: true);
    for (final names in [
      ['En.US.json'],
      [r'en$.json'],
      ['en-US.json', 'en_US.json'],
    ]) {
      for (final name in names) {
        await File(path.join(source.path, name)).writeAsString('{"hello":"Hello"}');
      }
      await output.writeAsString('previous');
      final result = await Process.run(
        'dart',
        [generator, '-S', 'langs', '-O', 'output', '-o', 'loader.dart', '-f', 'json'],
        workingDirectory: scratch.path,
        runInShell: true,
      );
      expect(result.exitCode, 1, reason: '${result.stdout} ${result.stderr}');
      for (final name in names) {
        expect(result.stderr.toString(), contains(name));
        await File(path.join(source.path, name)).delete();
      }
      expect(await output.readAsString(), 'previous');
    }
    await File(path.join(source.path, 'en.US.json')).writeAsString('{"hello":"Hello"}');
    expect(await generate(source, 'keys', sourceFile: 'en.US.json'), contains("hello = 'hello'"));
  });

  test('generates the compiled loader fixture with relative and absolute paths', () async {
    final fixture = Directory(path.absolute('test/fixtures/generated_loader'));
    final expected = await File(path.join(fixture.path, 'codegen_loader.g.dart')).readAsString();
    final source = Directory(path.join(scratch.path, 'source files'));
    await source.create();
    for (final locale in ['en', 'zh-Hans-CN']) {
      await File(path.join(source.path, '$locale.json')).writeAsString('{"section":":/section.json"}');
      final fragments = Directory(path.join(source.path, locale));
      await fragments.create();
      await File(path.join(fragments.path, 'section.json')).writeAsString('{"title":"$locale"}');
    }
    for (final absolute in [false, true]) {
      final result = await Process.run(
        'dart',
        [
          generator,
          '-S',
          absolute ? source.path : 'source files',
          '-O',
          absolute ? path.join(scratch.path, 'output files') : 'output files',
          '-o',
          'loader.dart',
        ],
        workingDirectory: scratch.path,
        runInShell: true,
      );
      expect(result.exitCode, 0, reason: '${result.stdout} ${result.stderr}');
      final actual = await File(path.join(scratch.path, 'output files', 'loader.dart')).readAsString();
      expect(actual.replaceAll('\r\n', '\n'), expected.replaceAll('\r\n', '\n'));
    }
  });

  test('input errors return failure and preserve the output', () async {
    final source = Directory(path.join(scratch.path, 'langs'));
    final output = File(path.join(scratch.path, 'output', 'loader.dart'));
    await output.create(recursive: true);
    Future<void> fails(List<String> extra) async {
      await output.writeAsString('previous');
      final result = await Process.run(
        'dart',
        [generator, '-S', 'langs', '-O', 'output', '-o', 'loader.dart', ...extra],
        workingDirectory: scratch.path,
        runInShell: true,
      );
      expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
      expect(result.stderr.toString(), isNotEmpty);
      expect(await output.readAsString(), 'previous');
    }

    await fails([]);
    await source.create();
    await fails([]);
    await fails(['-s', 'missing.json']);
    final root = File(path.join(source.path, 'en.json'));
    await root.writeAsString('{broken');
    await fails([]);
    await root.writeAsString('{"section":":/section.json"}');
    await fails([]);
    final fragments = Directory(path.join(source.path, 'en'));
    await fragments.create();
    await File(path.join(fragments.path, 'section.json')).writeAsString('{"section":":/section.json"}');
    await fails([]);
  });
}
