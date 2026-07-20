/// Scans the UI tree for user-facing text that bypasses l10n.
/// `dart run tool/verify_ui_strings.dart`
///
/// The app ships in ru/kk/en with Russian as the default, so an untranslated
/// literal isn't a cosmetic slip — it's Latin text sitting in an otherwise
/// Cyrillic screen. This caught the weight card rendering "63.4 kg" directly
/// above "+1.4 кг с начала", where every other mention of the unit was already
/// translated.
///
/// Source-scanning rather than widget-testing on purpose: a widget test only
/// covers the screens someone remembered to write one for, while this sees
/// every file in lib/ui the moment it's added.
library;

import 'dart:io';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

/// Literals that are deliberately not translated, with the reason. Anything not
/// listed here has to go through `l.t(...)`.
const _allowed = <String, String>{
  'Русский': 'a language name is written in its own language, never translated',
  'Қазақша': 'a language name is written in its own language, never translated',
  'English': 'a language name is written in its own language, never translated',
  '0.1.0': 'a version number is not language-dependent',
};

final _letter = RegExp(r'[A-Za-zА-Яа-яЁёӘәҒғҚқҢңӨөҰұҮүҺһІі]');

/// Where a literal would reach the user: as the text of a Text widget, or as a
/// property that a screen reader or field label surfaces.
final _sites = RegExp(r'''(?:\bText\(|\b(?:tooltip|labelText|hintText|helperText|semanticsLabel|errorText)\s*:\s*)''');

/// Read the Dart string literal starting at [i] (which must be its quote),
/// returning its raw source and the index just past it. Understands escapes and
/// `${...}` interpolation — including quotes nested inside an interpolation,
/// which is what defeats a plain regex (`Text('${l.t('x')} ...')`).
({String value, int end})? _readLiteral(String s, int i) {
  final quote = s[i];
  if (quote != "'" && quote != '"') return null;
  final buf = StringBuffer();
  var j = i + 1;
  while (j < s.length) {
    final c = s[j];
    if (c == r'\') {
      buf.write(s.substring(j, (j + 2).clamp(0, s.length)));
      j += 2;
      continue;
    }
    if (c == quote) return (value: buf.toString(), end: j + 1);
    if (c == r'$') {
      // Skip the interpolated expression: its VALUE is computed at runtime and
      // is normally already localized, so only the surrounding text counts.
      j++;
      if (j < s.length && s[j] == '{') {
        var depth = 0;
        while (j < s.length) {
          if (s[j] == '{') depth++;
          if (s[j] == '}') {
            depth--;
            j++;
            if (depth == 0) break;
            continue;
          }
          j++;
        }
      } else {
        while (j < s.length && RegExp(r'[A-Za-z0-9_.]').hasMatch(s[j])) {
          j++;
        }
      }
      continue;
    }
    buf.write(c);
    j++;
  }
  return null; // unterminated on this line (a multi-line string) — not our concern
}

bool _isUserFacing(String literal) {
  final t = literal.trim();
  if (t.isEmpty) return false;
  if (_allowed.containsKey(t)) return false;
  return _letter.hasMatch(t);
}

void main() {
  final uiDir = Directory.fromUri(Platform.script.resolve('../lib/ui'));
  final offenders = <String>[];
  var scanned = 0;

  for (final f in uiDir.listSync(recursive: true).whereType<File>()) {
    if (!f.path.endsWith('.dart')) continue;
    scanned++;
    final lines = f.readAsLinesSync();
    final rel = f.path.replaceAll(r'\', '/').split('/lib/ui/').last;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.trimLeft().startsWith('//')) continue; // a comment isn't shipped
      for (final site in _sites.allMatches(line)) {
        var k = site.end;
        while (k < line.length && line[k] == ' ') {
          k++;
        }
        if (k >= line.length) continue;
        final lit = _readLiteral(line, k);
        if (lit == null) continue;
        if (_isUserFacing(lit.value)) {
          offenders.add('lib/ui/$rel:${i + 1}  "${lit.value}"');
        }
      }
    }
  }

  _chk('the UI tree was actually scanned', scanned > 20);
  if (offenders.isNotEmpty) {
    print('\n  Untranslated user-facing text (route it through l.t(...), or add');
    print('  it to _allowed here with the reason it stays untranslated):');
    for (final o in offenders) {
      print('    $o');
    }
    print('');
  }
  _chk('no user-facing text bypasses l10n (${offenders.length} found in $scanned files)',
      offenders.isEmpty);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
