import 'dart:io';

import 'package:args/args.dart';
import 'audit/audit_command.dart';

Future<void> main(List<String> args) async {
  final actual = args.isEmpty ? ['audit'] : args;
  var parser = ArgParser();

  parser.addOption('translations-dir', abbr: 't', defaultsTo: 'assets/translations');
  parser.addOption('source-dir', abbr: 's', defaultsTo: 'lib');
  parser.addFlag('strict', defaultsTo: false);

  try {
    var argResults = parser.parse(actual);
    final transDir = argResults['translations-dir'] as String;
    final srcDir = argResults['source-dir'] as String;

    if (!Directory(transDir).existsSync()) {
      stderr.writeln('Error: Translation directory "$transDir" does not exist.');
      exitCode = 1;
      return;
    }

    if (!Directory(srcDir).existsSync()) {
      stderr.writeln('Error: Source directory "$srcDir" does not exist.');
      exitCode = 1;
      return;
    }

    final hasMissing = await AuditCommand().run(transDir: transDir, srcDir: srcDir, strict: argResults['strict'] as bool);
    if (argResults['strict'] as bool && hasMissing) exitCode = 2;
  } catch (e) {
    stderr.writeln('Error: $e');
    exitCode = 1;
  }
}
