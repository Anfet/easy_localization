import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory scratch;
  final generator = path.absolute('bin/generate.dart');

  setUp(() async {
    final root = Directory(r'Z:\.ai\claude-work\easy_localization');
    await root.create(recursive: true);
    scratch = await root.createTemp('loc8_cli_');
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
        runInShell: true);
    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    return File(path.join(output.path, '$format.dart')).readAsString();
  }

  Future<void> createFixtures(Directory dir, List<String> order) async {
    await dir.create(recursive: true);
    final fixtures = {
      'en.json': {
        'englishOnly': 'English',
        'nested': {'child': 'value'},
        'count': {'one': 'one', 'other': 'other'}
      },
      'fr.json': {
        'frenchOnly': 'Français',
        'nested': {'child': 'valeur'}
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
    expect(keys, await generate(second, 'keys'));
    expect(keys, contains('englishOnly'));
    expect(keys, isNot(contains('frenchOnly')));
    final french = await generate(first, 'keys', sourceFile: 'fr.json');
    expect(french, contains('frenchOnly'));
    expect(french, isNot(contains('englishOnly')));
    final skipped = await generate(first, 'keys', skip: true);
    expect(skipped, contains('nested_child'));
    expect(skipped, isNot(contains('static const nested =')));
    expect(skipped, contains('static const count ='));
    expect(skipped, isNot(contains('static const one =')));
  });
}
