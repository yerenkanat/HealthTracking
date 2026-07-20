/// Write `assets/content/catalog.json` from the seeded catalogue.
/// `dart run tool/export_catalog_template.dart`
///
/// Authoring starts from a complete file rather than a blank page: every
/// pregnancy week and every child month is already present with the right
/// shape, so publishing real content is editing text and pasting URLs — not
/// working out a schema.
///
/// It REFUSES to overwrite an existing file. Regenerating over hand-authored
/// content would destroy the work this exists to support; delete the file
/// deliberately, or pass --force, if that is really what you want.
library;

import 'dart:convert';
import 'dart:io';

import '../lib/data/demo_content.dart';

void main(List<String> args) {
  final force = args.contains('--force');
  final file = File.fromUri(Platform.script.resolve('../assets/content/catalog.json'));

  if (file.existsSync() && !force) {
    stderr.writeln('Refusing to overwrite ${file.path}');
    stderr.writeln('It already exists, and regenerating would discard whatever is in it.');
    stderr.writeln('Pass --force if you are sure.');
    exit(1);
  }

  file.parent.createSync(recursive: true);
  const encoder = JsonEncoder.withIndent('  ');
  file.writeAsStringSync('${encoder.convert(demoContentCatalog().toJson())}\n');

  final stages = demoContentCatalog().byStage.length;
  var items = 0;
  for (final v in demoContentCatalog().byStage.values) {
    items += v.length;
  }
  stdout.writeln('Wrote ${file.path}');
  stdout.writeln('$stages stages, $items items — placeholder text, no URLs yet.');
  stdout.writeln('Edit it, then run: dart run tool/verify_content_catalog.dart');
}
