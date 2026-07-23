/// Pure-Dart verification of the v4 UUID generator. A child id must be a real
/// UUID or the backend rejects it, so the format and version/variant bits matter.
/// `dart run tool/verify_uuid.dart`
library;

import 'dart:io';
import 'dart:math';
import '../lib/core/uuid.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

final _re = RegExp(r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');

void main() {
  final u = uuidV4(Random(1));
  _chk('matches the canonical v4 shape (8-4-4-4-12, version 4, variant 1)', _re.hasMatch(u));

  // 1000 generated ids are all well-formed and unique.
  final seen = <String>{};
  var wellFormed = true;
  final rng = Random(42);
  for (var i = 0; i < 1000; i++) {
    final id = uuidV4(rng);
    if (!_re.hasMatch(id)) wellFormed = false;
    seen.add(id);
  }
  _chk('1000 ids are all well-formed', wellFormed);
  _chk('1000 ids are unique', seen.length == 1000);

  // A seeded RNG is deterministic (needed for reproducible tests).
  _chk('a seeded RNG is deterministic', uuidV4(Random(7)) == uuidV4(Random(7)));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
