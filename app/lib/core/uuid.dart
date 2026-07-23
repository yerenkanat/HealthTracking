/// A tiny dependency-free RFC-4122 v4 UUID generator.
///
/// PURE Dart → verified by tool/verify_uuid.dart.
///
/// Children need a real UUID, not a `child-<millis>` id: the backend's child
/// upsert and the /ingest/batch schema both require one, so a non-UUID child
/// could never sync or have a location recorded. Small enough to inline rather
/// than pull in the `uuid` package for one call site.
library;

import 'dart:math';

/// Generate a v4 UUID (8-4-4-4-12 hex). Pass a seeded [rng] in tests for
/// determinism; production uses a fresh [Random].
String uuidV4([Random? rng]) {
  final r = rng ?? Random();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40; // version 4
  b[8] = (b[8] & 0x3f) | 0x80; // variant 1 (10xxxxxx)
  String hex(int lo, int hi) {
    final sb = StringBuffer();
    for (var i = lo; i < hi; i++) {
      sb.write(b[i].toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  return '${hex(0, 4)}-${hex(4, 6)}-${hex(6, 8)}-${hex(8, 10)}-${hex(10, 16)}';
}
