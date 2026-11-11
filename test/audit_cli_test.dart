import 'dart:io';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;

void main() {
  late Directory scratch;
  late Directory translations;
  late Directory source;

  setUp(() {
    scratch = Directory.systemTemp.createTempSync('localization_audit_');
    translations = Directory(path.join(scratch.path, 'translations'))..createSync();
    source = Directory(path.join(scratch.path, 'source'))..createSync();
    File(path.join(translations.path, 'en.json')).writeAsStringSync('{"present":"Hello"}');
    File(path.join(translations.path, 'fr.json')).writeAsStringSync('{"present":"Bonjour"}');
  });

  tearDown(() => scratch.deleteSync(recursive: true));

  Future<ProcessResult> audit({bool strict = false, List<String> extra = const []}) => Process.run('dart', [
    'run',
    'bin/audit.dart',
    '-t',
    translations.absolute.path,
    '-s',
    source.absolute.path,
    if (strict) '--strict',
    ...extra,
  ], runInShell: Platform.isWindows);

  void writeSource(String content) => File(path.join(source.path, 'sample.dart')).writeAsStringSync(content);

  void expectSuccess(ProcessResult result, int code) {
    expect(result.exitCode, code, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stdout, contains('Keys Audit'));
    expect(result.stderr, isEmpty);
  }

  void expectError(ProcessResult result) {
    expect(result.exitCode, 1, reason: '${result.stdout}\n${result.stderr}');
    expect(result.stderr, contains('Error'));
    expect(result.stdout, isNot(contains('all good')));
  }

  test('rejects excessive acyclic linked traversal as an input error', () async {
    final values = <String, String>{'k0': 'x'};
    for (var i = 1; i <= 13; i++) {
      values['k$i'] = '@:k${i - 1}@:k${i - 1}';
    }
    File(path.join(translations.path, 'en.json')).writeAsStringSync(jsonEncode(values));
    writeSource("void f() { 'k13'.tr(); }");
    expectError(await audit());
  });

  test('complete translations succeed with and without strict', () async {
    writeSource("tr('present');");
    expectSuccess(await audit(), 0);
    expectSuccess(await audit(strict: true), 0);
  });

  test('named parameter mismatches warn without failing and compare reachable strings', () async {
    File(path.join(translations.path, 'en.json')).writeAsStringSync(
      '{"greet":"Hello {name}","ordered":"{name}, {city}","linked":"@:linked_text","linked_text":"{name}",'
      '"count":{"one":"{name}","other":"{city}"},"person":{"male":"{name}","female":"{given}"}}',
    );
    File(path.join(translations.path, 'fr.json')).writeAsStringSync(
      '{"greet":"Bonjour {naem}","ordered":"{city}, {name}","linked":"@:linked_text","linked_text":"{appel}",'
      '"count":{"one":"{name}","other":"{city}"},"person":{"male":"{name}","female":"{given}"}}',
    );
    writeSource("tr('greet'); tr('ordered'); tr('linked'); plural('count', 2); tr('person', gender: 'male');");

    for (final strict in [false, true]) {
      final result = await audit(strict: strict);
      expectSuccess(result, 0);
      expect(result.stdout, contains('Named parameter mismatches'));
      expect(result.stdout, contains('greet'));
      expect(result.stdout, contains('{name}'));
      expect(result.stdout, contains('{naem}'));
      expect(result.stdout, contains('linked'));
      expect(result.stdout, isNot(contains('ordered:')));
      expect(result.stdout, isNot(contains('count.one:')));
      expect(result.stdout, isNot(contains('person.male:')));
    }
  });

  test('named parameter mismatches compare linked strings with different target keys', () async {
    File(path.join(translations.path, 'en.json')).writeAsStringSync('{"screen":{"title":"@:strings.enTitle"},"strings":{"enTitle":"Hello {name}"}}');
    File(
      path.join(translations.path, 'fr.json'),
    ).writeAsStringSync('{"screen":{"title":"@:strings.frTitle"},"strings":{"frTitle":"Bonjour {naem}"}}');
    writeSource("tr('screen.title');");

    for (final strict in [false, true]) {
      final result = await audit(strict: strict);
      expectSuccess(result, 0);
      expect(result.stdout, contains('Named parameter mismatches'));
      expect(result.stdout, contains('screen.title'));
      expect(result.stdout, contains('{name}'));
      expect(result.stdout, contains('{naem}'));
      expect(result.stdout, isNot(contains('Missing')));
    }
  });

  test('audit resolves links in script and region locale directories', () async {
    File(path.join(translations.path, 'en.json')).deleteSync();
    File(path.join(translations.path, 'fr.json')).deleteSync();
    File(path.join(translations.path, 'zh-Hans-CN.json')).writeAsStringSync('{"section":":/section.json"}');
    final linked = Directory(path.join(translations.path, 'zh-Hans-CN'))..createSync();
    File(path.join(linked.path, 'section.json')).writeAsStringSync('{"title":"Title"}');
    writeSource("tr('section.title');");
    expectSuccess(await audit(strict: true), 0);
  });

  test('normalizes locale paths and rejects invalid or duplicate filenames', () async {
    File(path.join(translations.path, 'en.json')).deleteSync();
    File(path.join(translations.path, 'fr.json')).deleteSync();
    writeSource("tr('section.title');");
    for (final pair in {'en-us': 'en-US', 'en_US': 'en-US', 'zh_hans_cn': 'zh-Hans-CN', 'es_419': 'es-419'}.entries) {
      final input = File(path.join(translations.path, '${pair.key}.json'))..writeAsStringSync('{"section":":/section.json"}');
      final linked = Directory(path.join(translations.path, pair.value))..createSync(recursive: true);
      File(path.join(linked.path, 'section.json')).writeAsStringSync('{"title":"Title"}');
      expectSuccess(await audit(strict: true), 0);
      input.deleteSync();
    }
    File(path.join(translations.path, 'en-us.json')).writeAsStringSync('{}');
    File(path.join(translations.path, 'en_US.json')).writeAsStringSync('{}');
    expectError(await audit());
    File(path.join(translations.path, 'en-us.json')).deleteSync();
    File(path.join(translations.path, 'en_US.json')).deleteSync();
    File(path.join(translations.path, 'invalid.name.json')).writeAsStringSync('{}');
    expectError(await audit());
  });

  test('static missing key only fails in strict mode', () async {
    File(path.join(translations.path, 'en.json')).writeAsStringSync('{"absent":"Present"}');
    writeSource("tr('absent');");
    final ordinary = await audit();
    final strict = await audit(strict: true);
    expectSuccess(ordinary, 0);
    expectSuccess(strict, 2);
    expect(strict.stdout, contains('absent'));
  });
  test('raw literal keys and receivers report missing keys in strict mode', () async {
    for (final expression in ["tr(r'missing');", "r'missing'.tr();"]) {
      writeSource(expression);
      final result = await audit(strict: true);
      expectSuccess(result, 2);
      expect(result.stdout, contains('missing'));
    }
  });

  test('interpolated and dynamic keys are not confirmed missing', () async {
    writeSource(r"tr('item.$name'); tr(variable);");
    final result = await audit(strict: true);
    expectSuccess(result, 0);
    expect(result.stdout, contains('cannot be verified'));
    expect(result.stdout, isNot(contains('all good')));
    writeSource('tr(variable);');
    final dynamicOnly = await audit(strict: true);
    expectSuccess(dynamicOnly, 0);
    expect(dynamicOnly.stdout, contains('dynamic calls may not be checked'));
  });

  test('static missing key still fails alongside dynamic keys', () async {
    writeSource(r"tr('absent'); tr('item.$name'); tr(variable);");
    expectSuccess(await audit(strict: true), 2);
  });

  test('plural, gender and generated constants use their actual values', () async {
    const data = '{"count":{"one":"one","other":"many"},"person":{"male":"man","female":"woman"},"reset_locale":"reset"}';
    for (final file in translations.listSync().whereType<File>()) {
      file.writeAsStringSync(data);
    }
    writeSource("""
      class LocaleKeys { static const String reset_locale = 'reset_locale'; }
      tr(LocaleKeys.reset_locale); plural('count', 2);
      Text('person').tr(gender: 'male'); 'count'.plural(2);
      // tr('commented');
    """);
    expectSuccess(await audit(strict: true), 0);
  });

  test('plural without other warns normally and fails strict mode', () async {
    for (final file in translations.listSync().whereType<File>()) {
      file.writeAsStringSync('{"count":{"one":"one"}}');
    }
    writeSource("plural('count', 2);");

    final normal = await audit();
    expectSuccess(normal, 0);
    expect(normal.stdout, contains('Plural groups without other: count'));

    final strict = await audit(strict: true);
    expectSuccess(strict, 2);
    expect(strict.stdout, contains('Plural groups without other: count'));
  });

  test('missing extensions and invalid resource types fail strict', () async {
    for (final file in translations.listSync().whereType<File>()) {
      file.writeAsStringSync('{"number":42,"count":{"one":4}}');
    }
    writeSource("Text('absent').tr(); 'absent'.plural(2); tr('number'); plural('count', 2); context.tr('context_absent');");
    final result = await audit(strict: true);
    expectSuccess(result, 2);
    for (final key in ['absent', 'number', 'count', 'context_absent']) {
      expect(result.stdout, contains(key));
    }
  });

  test('unknown constants and interpolated keys remain unverified', () async {
    writeSource(r"tr(LocaleKeys.unknown); Text('item.$name').tr(); Text(variable, style: style).tr();");
    final result = await audit(strict: true);
    expectSuccess(result, 0);
    expect(result.stdout, contains('cannot be verified'));
  });

  test('unparsed translation calls and adjacent string receivers are unverified', () async {
    writeSource("Text('a', style: X(y: Z(w: 1))).tr(); ('b').tr(); 'a' 'b'.tr();");
    final result = await audit(strict: true);
    expectSuccess(result, 0);
    expect(result.stdout, contains('Unverified keys'));
    expect(result.stdout, contains('dynamic key'));
    expect(result.stdout, isNot(contains('🔴 Missing (')));
    expect(result.stdout, isNot(contains('all good')));
  });

  test('nested arguments retain literal gender for all call forms', () async {
    for (final file in translations.listSync().whereType<File>()) {
      file.writeAsStringSync('{"person":{"male":"man"}}');
    }
    writeSource(
      "tr('person', args: makeArgs(), gender: 'male'); "
      "context.tr('person', args: makeArgs(), gender: 'male'); "
      "Text('person').tr(args: makeArgs(), gender: 'male'); "
      "'person'.tr(args: makeArgs(), gender: 'male');",
    );
    expectSuccess(await audit(strict: true), 0);
    writeSource("tr('person', args: makeArgs(), gender: 'female');");
    final missing = await audit(strict: true);
    expectSuccess(missing, 2);
    expect(missing.stdout, contains('person.female'));
  });
  test('null gender uses the ordinary translation key', () async {
    for (final file in translations.listSync().whereType<File>()) {
      file.writeAsStringSync('{"greet":"Hello"}');
    }
    writeSource("tr('greet', gender: null);");
    expectSuccess(await audit(strict: true), 0);
  });

  test('generated receivers and translator chains resolve static keys', () async {
    for (final key in ['present', 'absent']) {
      writeSource("""
        import 'package:easy_localization_continued/easy_localization.dart';
        import 'package:flutter/widgets.dart';
        class LocaleKeys { static const String key = '$key'; }
        void example() {
          LocaleKeys.key.tr();
          Text(LocaleKeys.key).tr();
          tr(LocaleKeys.key);
          EasyLocalization.instance.dataTranslator.tr('$key');
        }
      """);
      final result = await audit(strict: true);
      expectSuccess(result, key == 'present' ? 0 : 2);
      if (key == 'absent') expect(result.stdout, contains('absent'));
    }
  });

  test('only translation call arguments determine gender', () async {
    writeSource("""
      import 'package:easy_localization_continued/easy_localization.dart';
      List<String> helper({required String gender}) => [gender];
      void example() { tr('present', args: helper(gender: 'female')); }
    """);
    expectSuccess(await audit(strict: true), 0);
    writeSource("""
      import 'package:easy_localization_continued/easy_localization.dart';
      List<String> helper({required String gender}) => [gender];
      void example() { tr('present', args: helper(gender: tr('absent'))); }
    """);
    final nested = await audit(strict: true);
    expectSuccess(nested, 2);
    expect(nested.stdout, contains('absent'));
  });

  test('dynamic gender accepts direct string keys and rejects non-string groups', () async {
    for (final file in translations.listSync().whereType<File>()) {
      file.writeAsStringSync('{"person.male":"man","empty.male":42}');
    }
    writeSource("tr('person', gender: choice);");
    final result = await audit(strict: true);
    expectSuccess(result, 0);
    expect(result.stdout, contains('cannot be verified'));
    writeSource("tr('empty', gender: choice);");
    expectSuccess(await audit(strict: true), 2);
  });

  test('source strings and nested comments are not calls', () async {
    writeSource('''
      final example = "tr('absent')";
      /* outer /* inner */ tr('also_absent'); */
      tr('present');
    ''');
    expectSuccess(await audit(strict: true), 0);
    writeSource('''final example = "tr('present')"; tr('absent');''');
    expectSuccess(await audit(strict: true), 2);
  });

  test('static API forms and interpolation report missing keys', () async {
    for (final expression in [r'''"value ${tr('KEY')}"''', "loc.tr('KEY')", "snapshot.tr('KEY')", "Text('KEY', style: style).tr()"]) {
      writeSource(expression.replaceAll('KEY', 'present'));
      expectSuccess(await audit(strict: true), 0);
      writeSource(expression.replaceAll('KEY', 'absent'));
      final missing = await audit(strict: true);
      expectSuccess(missing, 2);
      expect(missing.stdout, contains('absent'));
    }
  });

  test('nested interpolation scans expressions but ignores examples and comments', () async {
    writeSource(r'''
      final example = "tr('ignored')";
      /* outer /* tr('ignored') */ tr('ignored') */
      final value = "${call("text ${tr('absent')}", /* tr('ignored') */ 'quoted')}";
    ''');
    final result = await audit(strict: true);
    expectSuccess(result, 2);
    expect(result.stdout, contains('absent'));
    expect(result.stdout, isNot(contains('ignored')));
  });

  test('conflicting LocaleKeys values remain unverified', () async {
    writeSource("class LocaleKeys { static const String key = 'present'; } void example() { LocaleKeys.key.tr(); tr(LocaleKeys.key); }");
    File(path.join(source.path, 'other.dart')).writeAsStringSync("class LocaleKeys { static const String key = 'absent'; }");
    final result = await audit(strict: true);
    expectSuccess(result, 0);
    expect(result.stdout, contains('cannot be verified'));
  });

  test('reachable links report missing and non-string targets in both modes', () async {
    File(path.join(translations.path, 'en.json')).writeAsStringSync('{"title":"@:middle","middle":"@.upper:(absent)","absent":42}');
    File(path.join(translations.path, 'fr.json')).writeAsStringSync('{"title":"@:missing"}');
    writeSource("tr('title');");
    for (final strict in [false, true]) {
      final result = await audit(strict: strict);
      expectSuccess(result, strict ? 2 : 0);
      expect(result.stdout, contains('title -> middle -> absent'));
      expect(result.stdout, contains('title -> missing'));
    }
  });

  test('strict audit follows Unicode linked keys and reports missing Unicode targets', () async {
    File(path.join(translations.path, 'en.json')).writeAsStringSync('{"заголовок":"@:привет","привет":"OK"}');
    File(path.join(translations.path, 'fr.json')).writeAsStringSync('{"заголовок":"@:(раздел.ключ)"}');
    writeSource("tr('заголовок');");

    final result = await audit(strict: true);

    expectSuccess(result, 2);
    expect(result.stdout, contains('Missing (1)'));
  });

  test('gender and plural links are checked, diamond succeeds and cycle is unverified', () async {
    for (final file in translations.listSync().whereType<File>()) {
      file.writeAsStringSync(
        '{"person":{"male":"@:(shared)"},"count":{"one":"@.upper:shared","other":"@:shared"},'
        '"shared":"ok","title":"@:left @:right","left":"@:shared","right":"@:shared","cycle":"@:loop","loop":"@:cycle"}',
      );
    }
    writeSource("tr('person', gender: 'male'); plural('count', 2); tr('title'); tr('cycle'); tr(variable);");
    final result = await audit(strict: true);
    expectSuccess(result, 0);
    expect(result.stdout, contains('cycle -> loop -> cycle'));
    expect(result.stdout, contains('dynamic key'));
    expect(result.stdout, isNot(contains('🔴 Missing')));
    for (final file in translations.listSync().whereType<File>()) {
      file.writeAsStringSync('{"person":{"male":"@:absent"},"count":{"other":"@.upper:(missing)"}}');
    }
    final missing = await audit(strict: true);
    expectSuccess(missing, 2);
    expect(missing.stdout, contains('person.male -> absent'));
    expect(missing.stdout, contains('count.other -> missing'));
  });

  test('invalid option, missing directory and empty locales fail', () async {
    expectError(await audit(extra: ['--unknown']));
    source.deleteSync(recursive: true);
    expectError(await audit());
    source.createSync();
    translations.deleteSync(recursive: true);
    translations.createSync();
    expectError(await audit());
  });

  test('malformed locale JSON reaches the CLI catch', () async {
    File(path.join(translations.path, 'fr.json')).writeAsStringSync('{bad');
    expectError(await audit(strict: true));
  });

  test('source decoding failure reaches the CLI catch', () async {
    File(path.join(source.path, 'bad.dart')).writeAsBytesSync([0xff]);
    expectError(await audit(strict: true));
  });

  test('asynchronous linked file failure reaches the CLI catch', () async {
    File(path.join(translations.path, 'fr.json')).writeAsStringSync('{"link":":/missing.json"}');
    expectError(await audit(strict: true));
  });
}
