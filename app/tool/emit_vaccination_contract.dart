/// Emits packages/contract/vaccination_schedule.json from the app's vaccination
/// domain + ru l10n, so the shared contract cannot drift from the app. Run:
///   dart run tool/emit_vaccination_contract.dart > ../packages/contract/vaccination_schedule.json
/// Asserted back by tool/verify_vaccination_contract.dart.
library;

import 'dart:convert';
import '../lib/domain/vaccination.dart';
import '../lib/l10n/l10n.dart';

void main() {
  const ru = L10n(AppLocale.ru);
  final map = {
    '_comment':
        'CANONICAL Kazakhstan childhood immunisation schedule, the single source of truth shared '
            'by the Dart app, the Node backend (GET /vaccination/schedule) and the admin panel. '
            'Structure is asserted against the app domain by app/tool/verify_vaccination_contract.dart. '
            'Russian labels mirror the app l10n.',
    'version': 1,
    'dueWindowMonths': dueWindowMonths,
    'vaccines': [
      for (final v in kzSchedule)
        {
          'id': v.id,
          'atMonth': v.atMonth,
          if (v.dose != null) 'dose': v.dose,
          'ru': ru.t('vac_${v.id}'),
        },
    ],
  };
  print(const JsonEncoder.withIndent('  ').convert(map));
}
