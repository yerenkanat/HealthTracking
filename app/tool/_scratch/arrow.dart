import '../../lib/l10n/l10n.dart';
void main() {
  for (final k in allL10nKeys) {
    for (final l in AppLocale.values) {
      final v = L10n(l).t(k);
      if (v.contains('\u2192')) print('${l.name}  $k: $v');
    }
  }
}
