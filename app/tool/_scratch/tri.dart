import '../../lib/l10n/l10n.dart';
void main() {
  for (final c in triageCodesWithMessages) {
    print('--- $c');
    print('RU: ${const L10n(AppLocale.ru).triageMessage(c)}');
    print('KK: ${const L10n(AppLocale.kk).triageMessage(c)}');
    print('EN: ${const L10n(AppLocale.en).triageMessage(c)}');
  }
}
