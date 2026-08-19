/// What a bundled font can actually DRAW, read out of the file itself.
///
/// Extracted from `verify_l10n.dart` so that the l10n runner and
/// `test/localised_text_font_test.dart` read one parser rather than two that
/// can drift. Nothing here imports Flutter, so both a `dart run` tool and a
/// `flutter test` can use it.
///
/// The whole reason this exists: a family that lacks a glyph does not fail, and
/// usually does not even show a box — `ThemeData.fontFamilyFallback` is
/// `[Rubik]`, so the missing letter is quietly drawn from another typeface. The
/// only way to know is to read the cmap.
library;

import 'dart:io';
import 'dart:typed_data';

/// The nine Kazakh-specific letters (and their capitals) that the coverage
/// table in `lib/ui/design_system.dart` is about.
const kazakhOnlyLetters = 'ӘҒҚҢӨҰҮҺІәғқңөұүһі';

/// Every Unicode codepoint a TrueType file can actually draw, read out of its
/// `cmap` table. Formats 4 (BMP) and 12 (full range) only — those are the two
/// the bundled families use, and an unrecognised subtable is skipped rather
/// than guessed at. Throws if no subtable was usable, so a font this cannot
/// parse fails loudly instead of reporting "no missing glyphs".
Set<int> cmapOf(File f) {
  final bytes = f.readAsBytesSync();
  final d = ByteData.sublistView(Uint8List.fromList(bytes));
  final numTables = d.getUint16(4);
  int? cmap;
  for (var i = 0; i < numTables; i++) {
    final rec = 12 + i * 16;
    if (String.fromCharCodes(bytes.sublist(rec, rec + 4)) == 'cmap') {
      cmap = d.getUint32(rec + 8);
    }
  }
  if (cmap == null) throw StateError('no cmap table in ${f.path}');

  final out = <int>{};
  var usable = 0;
  final n = d.getUint16(cmap + 2);
  for (var i = 0; i < n; i++) {
    final off = cmap + d.getUint32(cmap + 4 + i * 8 + 4);
    switch (d.getUint16(off)) {
      case 4:
        usable++;
        final segX2 = d.getUint16(off + 6);
        final endO = off + 14;
        final startO = endO + segX2 + 2;
        final deltaO = startO + segX2;
        final rangeO = deltaO + segX2;
        for (var s = 0; s < segX2 ~/ 2; s++) {
          final start = d.getUint16(startO + s * 2);
          if (start == 0xFFFF) continue;
          final end = d.getUint16(endO + s * 2);
          final delta = d.getInt16(deltaO + s * 2);
          final ro = d.getUint16(rangeO + s * 2);
          for (var c = start; c <= end; c++) {
            int g;
            if (ro == 0) {
              g = (c + delta) & 0xFFFF;
            } else {
              final gi = rangeO + s * 2 + ro + (c - start) * 2;
              if (gi + 1 >= bytes.length) continue;
              g = d.getUint16(gi);
              if (g != 0) g = (g + delta) & 0xFFFF;
            }
            if (g != 0) out.add(c);
          }
        }
      case 12:
        usable++;
        final groups = d.getUint32(off + 12);
        for (var g = 0; g < groups; g++) {
          final go = off + 16 + g * 12;
          final sc = d.getUint32(go), ec = d.getUint32(go + 4);
          for (var c = sc; c <= ec; c++) {
            out.add(c);
          }
        }
    }
  }
  if (usable == 0) throw StateError('no format 4 or 12 subtable in ${f.path}');
  return out;
}

/// family name → every asset declared for it in pubspec.yaml.
///
/// Read from the manifest rather than from a list in Dart, so a family added
/// later is covered without anyone remembering to register it.
Map<String, List<String>> declaredFontAssets(File pubspec) {
  final out = <String, List<String>>{};
  final lines = pubspec.readAsLinesSync();
  var inFonts = false;
  String? family;
  for (final raw in lines) {
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) continue;
    final indent = raw.length - raw.trimLeft().length;
    if (!inFonts) {
      // The `fonts:` key of the `flutter:` section — two spaces in. The nested
      // `fonts:` under a family is six spaces in and must not start this.
      if (indent == 2 && raw.trim() == 'fonts:') inFonts = true;
      continue;
    }
    if (indent <= 2) break; // out of the fonts block
    final t = raw.trim();
    if (t.startsWith('- family:')) {
      family = t.substring('- family:'.length).trim();
      out.putIfAbsent(family, () => <String>[]);
    } else if (t.startsWith('- asset:') && family != null) {
      out[family]!.add(t.substring('- asset:'.length).trim());
    }
  }
  return out;
}

/// family name → the codepoints EVERY asset of that family can draw.
///
/// The intersection, not the union: JetBrainsMono ships Regular and Bold, and a
/// glyph only one of them has is still a hole the moment the text is bold.
Map<String, Set<int>> bundledFontCoverage(Directory appRoot) {
  final assets = declaredFontAssets(File('${appRoot.path}/pubspec.yaml'));
  final out = <String, Set<int>>{};
  for (final e in assets.entries) {
    Set<int>? acc;
    for (final a in e.value) {
      final cps = cmapOf(File('${appRoot.path}/$a'));
      acc = acc == null ? cps : acc.intersection(cps);
    }
    if (acc != null) out[e.key] = acc;
  }
  return out;
}
