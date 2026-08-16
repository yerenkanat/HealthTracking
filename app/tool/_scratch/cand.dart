import 'dart:io';
import 'dart:typed_data';
Set<int> cmapOf(String path) {
  final b = File(path).readAsBytesSync();
  final d = ByteData.sublistView(Uint8List.fromList(b));
  final numTables = d.getUint16(4);
  int? cmapOff;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    if (String.fromCharCodes(b.sublist(rec, rec + 4)) == 'cmap') cmapOff = d.getUint32(rec + 8);
  }
  final n = d.getUint16(cmapOff! + 2);
  final out = <int>{};
  for (var i = 0; i < n; i++) {
    final rec = cmapOff + 4 + i * 8;
    final off = cmapOff + d.getUint32(rec + 4);
    if (d.getUint16(off) != 4) continue;
    final segX2 = d.getUint16(off + 6), seg = segX2 ~/ 2;
    final endO = off + 14, startO = endO + segX2 + 2, deltaO = startO + segX2, rangeO = deltaO + segX2;
    for (var s = 0; s < seg; s++) {
      final end = d.getUint16(endO + s * 2), start = d.getUint16(startO + s * 2);
      final delta = d.getInt16(deltaO + s * 2), ro = d.getUint16(rangeO + s * 2);
      if (start == 0xFFFF) continue;
      for (var c = start; c <= end; c++) {
        int g;
        if (ro == 0) { g = (c + delta) & 0xFFFF; }
        else { final gi = rangeO + s * 2 + ro + (c - start) * 2; if (gi + 1 >= b.length) continue; g = d.getUint16(gi); if (g != 0) g = (g + delta) & 0xFFFF; }
        if (g != 0) out.add(c);
      }
    }
  }
  return out;
}
void main() {
  final r = cmapOf('assets/fonts/Rubik.ttf');
  for (final c in ['·','›','>','→','—','–','«','»','°','№','×','…','’','ә','Ұ','һ','I','і']) {
    print('${c} U+${c.runes.first.toRadixString(16).toUpperCase().padLeft(4,"0")}: ${r.contains(c.runes.first) ? "present" : "MISSING"}');
  }
}
