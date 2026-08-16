import '../../lib/l10n/l10n.dart';
void main(List<String> a) {
  final keys = allL10nKeys.where((k) => a.any((p) => k.startsWith(p))).toList()..sort();
  for (final k in keys) {
    print('--- $k');
    print('RU: ${const L10n(AppLocale.ru).t(k)}');
    print('KK: ${const L10n(AppLocale.kk).t(k)}');
    print('EN: ${const L10n(AppLocale.en).t(k)}');
  }
  print('(${keys.length} keys)');
}
