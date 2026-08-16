import '../../lib/l10n/l10n.dart';
const ruWords = {'и','не','на','что','если','для','при','это','вы','ваш','ваша','ваше','ваши','вам','с','в','к','по','из','до','от','за','или','но','как','так','же','бы','он','она','они','мы','я','его','её','их','был','была','было','быть','есть','нет','да','уже','ещё','еще','очень','можно','нужно','надо','будет','может','все','всё','этот','эта','эти','том','о','об','а','то','ли','у','раз','день','дня','дней','час','часа','мин','неделя','недели'};
void main() {
  final hits = <String>[];
  for (final k in allL10nKeys) {
    final kk = L10n(AppLocale.kk).t(k);
    final ru = L10n(AppLocale.ru).t(k);
    if (kk == ru) continue;
    final toks = kk.toLowerCase().split(RegExp(r'[^\p{L}]+', unicode: true)).where((w) => w.isNotEmpty).toList();
    final bad = toks.where(ruWords.contains).toList();
    if (bad.isNotEmpty) hits.add('$k  [${bad.join(",")}]\n   KK: $kk\n   RU: $ru');
  }
  print(hits.join('\n'));
  print('${hits.length} suspicious');
}
