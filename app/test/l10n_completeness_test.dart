/// Every string exists, in every language.
///
/// Two failures this guards, both of which reach a user as broken text rather
/// than as a crash, and neither of which any other test would notice:
///
///   1. A key defined for Russian but not Kazakh. The app does not fall back to
///      another language — a missing entry yields the key itself, so a Kazakh
///      mother sees `set_notifications` where a sentence should be. The whole
///      product is sold on being usable in Kazakh.
///   2. A key the UI asks for that was never defined — a typo in `l.t('...')`,
///      or a string renamed on one side only. Same result: raw identifiers on
///      screen.
///
/// Read from source rather than through the L10n API because the point is to
/// catch the entry that is absent; asking the API for it just returns the
/// fallback and tells you nothing.
///
/// NOT checked: unused keys. 64 call sites build their key by interpolation —
/// `l.t('bag_$id')`, `l.t('cry_reason_${r.name}')` — so a static scan cannot
/// tell a dead string from one reached dynamically. Deleting on that count
/// would put a raw key on a real screen.
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `'key': {AppLocale.ru: '…', AppLocale.kk: '…', AppLocale.en: '…'}`
///
/// Ends at `AppLocale.en: '…'` rather than at the first `}`, because a great
/// many strings interpolate — `'через {n} дн.'`, `'Вход в «{zone}»'` — and a
/// body matched with `[^{}]` silently drops every one of them. That first
/// version reported 30-odd perfectly good keys as undefined.
final _entry = RegExp(
  // The placeholder class allows digits: `{t1low}` in the weight-gain copy is
  // a real placeholder, and `[a-zA-Z]+` reported that whole entry missing.
  r"'([a-z0-9_]+)':\s*\{((?:[^{}]|\{[a-zA-Z0-9_]+\})*?)\}(?=\s*,?\s*(?://[^\n]*\n\s*)*(?:'|\}))",
  dotAll: true,
);
final _locale = RegExp(r'AppLocale\.(ru|kk|en)\s*:');

/// A literal key in the UI: `l.t('some_key')`. Interpolated keys are excluded
/// by the character class — `'bag_$id'` has no closing quote before the `$`.
final _usage = RegExp(r"\.t\(\s*'([a-z0-9_]+)'\s*[,)]");

void main() {
  // Normalised: the file is CRLF on this machine, and a regex anchored to \n
  // silently matches nothing. That is not hypothetical — the first version of
  // this check parsed zero keys and cheerfully reported zero problems.
  final source = File('lib/l10n/l10n.dart').readAsStringSync().replaceAll('\r\n', '\n');

  final translations = <String, Set<String>>{};
  for (final m in _entry.allMatches(source)) {
    final langs = _locale.allMatches(m.group(2)!).map((x) => x.group(1)!).toSet();
    if (langs.isNotEmpty) translations[m.group(1)!] = langs;
  }

  test('the parser actually found the string table', () {
    // Guards every assertion below. A parser that matches nothing passes a
    // completeness check trivially, which is the most comfortable way to ship
    // a missing translation.
    expect(translations.length, greaterThan(1000),
        reason: 'parsed ${translations.length} keys — the table has over a thousand, '
            'so the regex has stopped matching and the checks below mean nothing');
  });

  test('every string is translated into all three languages', () {
    final gaps = <String>[];
    for (final entry in translations.entries) {
      for (final lang in const ['ru', 'kk', 'en']) {
        if (!entry.value.contains(lang)) gaps.add('${entry.key} ($lang)');
      }
    }
    expect(gaps, isEmpty,
        reason: 'these render as the raw key, not as another language:\n'
            '${gaps.take(20).join('\n')}');
  });

  test('every key the UI asks for by name exists', () {
    final used = <String, String>{};
    for (final file in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('l10n.dart')) continue;
      for (final m in _usage.allMatches(file.readAsStringSync())) {
        used.putIfAbsent(m.group(1)!, () => file.path);
      }
    }

    expect(used.length, greaterThan(500),
        reason: 'found ${used.length} call sites — the usage regex has stopped matching');

    final undefined = [
      for (final e in used.entries)
        if (!translations.containsKey(e.key)) '${e.key}  (${e.value})',
    ];
    expect(undefined, isEmpty,
        reason: 'asked for but never defined — these print as the key itself:\n'
            '${undefined.take(20).join('\n')}');
  });
}
