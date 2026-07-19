/// Runs every `tool/verify_*.dart` runner and reports a combined total.
/// `dart run tool/verify_all.dart`
///
/// Each runner is a standalone pure-Dart process that prints "N passed, M
/// failed" and exits non-zero on failure. This aggregates them so the whole
/// domain layer can be checked in one command (and so the README's numbers can
/// be regenerated rather than guessed).
library;

import 'dart:io';

final _summary = RegExp(r'(\d+) passed, (\d+) failed');

Future<void> main(List<String> args) async {
  final files = Directory('tool')
      .listSync()
      .whereType<File>()
      .map((f) => f.path.replaceAll(r'\', '/'))
      .where((p) {
        final name = p.split('/').last;
        return name.startsWith('verify_') && name.endsWith('.dart') && name != 'verify_all.dart';
      })
      .toList()
    ..sort();

  if (files.isEmpty) {
    stderr.writeln('No verify_*.dart runners found — run this from the app/ directory.');
    exit(2);
  }

  var totalPass = 0, totalFail = 0;
  final broken = <String>[];
  final nameWidth = files.map((f) => f.split('/').last.length).reduce((a, b) => a > b ? a : b);

  for (final path in files) {
    final name = path.split('/').last;
    final r = await Process.run('dart', ['run', path]);
    final out = '${r.stdout}${r.stderr}';
    final m = _summary.firstMatch(out);

    if (m == null) {
      // Runner crashed or changed its output format — surface it, don't skip it.
      broken.add(name);
      print('${name.padRight(nameWidth)}  ERROR (no summary line, exit ${r.exitCode})');
      continue;
    }
    final pass = int.parse(m.group(1)!);
    final fail = int.parse(m.group(2)!);
    totalPass += pass;
    totalFail += fail;
    if (fail > 0 || r.exitCode != 0) broken.add(name);
    final status = fail == 0 && r.exitCode == 0 ? 'ok  ' : 'FAIL';
    print('${name.padRight(nameWidth)}  $status  $pass passed, $fail failed');
  }

  print('\n${'-' * (nameWidth + 28)}');
  print('${files.length} runners · $totalPass assertions passed · $totalFail failed');
  if (broken.isNotEmpty) {
    print('Problem runners: ${broken.join(', ')}');
    exit(1);
  }
  exit(0);
}
