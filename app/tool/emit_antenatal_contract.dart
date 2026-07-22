/// Emits packages/contract/antenatal_protocol.json from the Dart domain + ru
/// l10n, so the shared contract cannot drift from the app. Run:
///   dart run tool/emit_antenatal_contract.dart > ../packages/contract/antenatal_protocol.json
/// The structure is asserted back against the domain by verify_antenatal_contract.dart.
library;

import 'dart:convert';
import '../lib/domain/antenatal_protocol.dart';
import '../lib/l10n/l10n.dart';

void main() {
  const ru = L10n(AppLocale.ru);
  final map = {
    '_comment':
        'CANONICAL Kazakhstan antenatal-care schedule (MOH Clinical Protocol No.248, 2025), '
            'the single source of truth shared by the Dart app, the Node backend (GET /antenatal/protocol) '
            'and the admin panel. Structure is asserted against the app domain by '
            'app/tool/verify_antenatal_contract.dart. Russian labels mirror the app l10n.',
    'version': 1,
    'categories': {
      for (final c in AntenatalCategory.values) c.name: ru.t('an_cat_${c.name}'),
    },
    'visits': [
      for (final v in antenatalVisits)
        {
          'number': v.number,
          'fromWeek': v.fromWeek,
          'toWeek': v.toWeek,
          'items': [
            for (final it in v.items)
              {
                'id': it.id,
                'category': it.category.name,
                'risk': it.risk,
                'ru': ru.t('an_item_${it.id}'),
              },
          ],
        },
    ],
    'windows': [
      for (final w in antenatalWindows)
        {
          'id': w.id,
          'fromWeek': w.fromWeek,
          'toWeek': w.toWeek,
          'risk': w.risk,
          'ru': ru.t('an_item_${w.id}'),
        },
    ],
  };
  print(const JsonEncoder.withIndent('  ').convert(map));
}
