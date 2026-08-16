import 'dart:io';
import 'dart:typed_data';
import '../../lib/l10n/l10n.dart';

Set<int> cmapOf(String path) {
  final b = File(path).readAsBytesSync();
  final d = ByteData.sublistView(Uint8List.fromList(b));
  final numTables = d.getUint16(4);
  int? cmapOff;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    final tag = String.fromCharCodes(b.sublist(rec, rec + 4));
    if (tag == 'cmap') cmapOff = d.getUint32(rec + 8);
  }
  if (cmapOff == null) throw 'no cmap';
  final n = d.getUint16(cmapOff + 2);
  final out = <int>{};
  var subtables = 0;
  for (var i = 0; i < n; i++) {
    final rec = cmapOff + 4 + i * 8;
    final pid = d.getUint16(rec), eid = d.getUint16(rec + 2);
    final off = cmapOff + d.getUint32(rec + 4);
    final fmt = d.getUint16(off);
    if (fmt == 4) {
      subtables++;
      final segX2 = d.getUint16(off + 6);
      final seg = segX2 ~/ 2;
      final endO = off + 14, startO = endO + segX2 + 2, deltaO = startO + segX2, rangeO = deltaO + segX2;
      for (var s = 0; s < seg; s++) {
        final end = d.getUint16(endO + s * 2);
        final start = d.getUint16(startO + s * 2);
        final delta = d.getInt16(deltaO + s * 2);
        final ro = d.getUint16(rangeO + s * 2);
        if (start == 0xFFFF) continue;
        for (var c = start; c <= end && c != 0x10000; c++) {
          int g;
          if (ro == 0) {
            g = (c + delta) & 0xFFFF;
          } else {
            final gi = rangeO + s * 2 + ro + (c - start) * 2;
            if (gi + 1 >= b.length) continue;
            g = d.getUint16(gi);
            if (g != 0) g = (g + delta) & 0xFFFF;
          }
          if (g != 0) out.add(c);
        }
      }
    } else if (fmt == 12) {
      subtables++;
      final ng = d.getUint32(off + 12);
      for (var gi = 0; gi < ng; gi++) {
        final go = off + 16 + gi * 12;
        final sc = d.getUint32(go), ec = d.getUint32(go + 4);
        for (var c = sc; c <= ec && c - sc < 0x11000; c++) out.add(c);
      }
    }
    if (pid == 3 && (eid == 1 || eid == 10)) {} // noted
  }
  if (subtables == 0) throw 'no usable subtable in $path';
  return out;
}

void main() {
  final dir = 'assets/fonts';
  final fonts = Directory(dir).listSync().whereType<File>().where((f) => f.path.endsWith('.ttf')).toList();
  final maps = {for (final f in fonts) f.path.split(RegExp(r'[\/]')).last: cmapOf(f.path)};
  maps.forEach((k, v) => print('$k: ${v.length} codepoints'));

  // Kazakh-specific letters, and the punctuation the copy actually uses.
  const kkLetters = 'әғқңөұүһіӘҒҚҢӨҰҮҺІ';
  print('\n--- Kazakh letters per font ---');
  maps.forEach((name, cps) {
    final missing = kkLetters.runes.where((r) => !cps.contains(r)).map((r) => String.fromCharCode(r)).join();
    print('$name: ${missing.isEmpty ? "ALL PRESENT" : "MISSING $missing"}');
  });

  // Every codepoint the catalogue actually renders, per locale.
  final perLocale = <AppLocale, Set<int>>{for (final l in AppLocale.values) l: {}};
  for (final k in allL10nKeys) {
    for (final l in AppLocale.values) {
      perLocale[l]!.addAll(L10n(l).t(k).runes);
    }
  }
  print('\n--- catalogue codepoints not in each font ---');
  maps.forEach((name, cps) {
    for (final l in AppLocale.values) {
      final miss = perLocale[l]!.where((c) => !cps.contains(c) && c != 0x0A).toList()..sort();
      if (miss.isNotEmpty) {
        print('$name / ${l.name}: ${miss.map((c) => 'U+${c.toRadixString(16).toUpperCase().padLeft(4, "0")}(${String.fromCharCode(c)})').join(' ')}');
      }
    }
  });
}
