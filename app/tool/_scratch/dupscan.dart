import '../../lib/l10n/l10n.dart';

void main() {
  var kkDup = 0, enDup = 0;
  final keys = allL10nKeys.toList()..sort();
  print('TOTAL KEYS: ${keys.length}');
  print('=== kk == ru ===');
  for (final k in keys) {
    final ru = const L10n(AppLocale.ru).t(k);
    final kk = const L10n(AppLocale.kk).t(k);
    if (ru == kk) { kkDup++; print('KK  $k  ||  $ru'); }
  }
  print('=== en == ru ===');
  for (final k in keys) {
    final ru = const L10n(AppLocale.ru).t(k);
    final en = const L10n(AppLocale.en).t(k);
    if (ru == en) { enDup++; print('EN  $k  ||  $ru'); }
  }
  print('=== kk == en ===');
  for (final k in keys) {
    final en = const L10n(AppLocale.en).t(k);
    final kk = const L10n(AppLocale.kk).t(k);
    if (en == kk) { print('KKEN  $k  ||  $en'); }
  }
  print('kkDup=$kkDup enDup=$enDup');
}
