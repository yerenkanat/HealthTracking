/// The in-app legal text and the public pages must say the same thing.
///
/// /privacy and /terms on ana-bala.kz are rendered by the backend from
/// legal/legal.json. The app renders the same documents from its l10n table.
/// Two policies that disagree is worse than one that is late: whichever a
/// customer read, the other one is what we would be held to — and a store
/// reviewer compares the listing's URL against the screen inside the app.
///
/// So this reads the shared file and asserts the app agrees with it, string
/// for string. If somebody edits one side, this fails and names the key.
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/l10n/l10n.dart';

/// Every key the two documents are built from, plus their titles and the
/// draft banner. Mirrors PRIVACY_SECTIONS/TERMS_SECTIONS on the server.
const _keys = <String>[
  'legal_privacy_title',
  'legal_terms_title',
  'legal_draft_note',
  'legal_updated',
  'legal_terms_title',
  'legal_priv_collect_h',
  'legal_priv_collect_b',
  'legal_priv_storage_h',
  'legal_priv_storage_b',
  'legal_priv_medical_h',
  'legal_priv_medical_b',
  'legal_priv_contact_h',
  'legal_priv_contact_b',
  'legal_terms_medical_h',
  'legal_terms_medical_b',
  'legal_terms_emergency_h',
  'legal_terms_emergency_b',
  'legal_terms_responsib_h',
  'legal_terms_responsib_b',
  'legal_terms_warranty_h',
  'legal_terms_warranty_b',
  'legal_terms_law_h',
  'legal_terms_law_b',
  'legal_priv_who_h',
  'legal_priv_who_b',
  'legal_priv_short_h',
  'legal_priv_short_b',
  'legal_priv_child_h',
  'legal_priv_child_b',
  'legal_priv_cry_h',
  'legal_priv_cry_b',
  'legal_priv_ai_h',
  'legal_priv_ai_b',
  'legal_priv_share_h',
  'legal_priv_share_b',
  'legal_priv_transfer_h',
  'legal_priv_transfer_b',
  'legal_priv_retention_h',
  'legal_priv_retention_b',
  'legal_priv_rights_h',
  'legal_priv_rights_b',
  'legal_priv_staff_h',
  'legal_priv_staff_b',
  'legal_priv_age_h',
  'legal_priv_age_b',
  'legal_priv_security_h',
  'legal_priv_security_b',
  'legal_priv_changes_h',
  'legal_priv_changes_b',
  'legal_terms_about_h',
  'legal_terms_about_b',
  'legal_terms_who_h',
  'legal_terms_who_b',
  'legal_terms_account_h',
  'legal_terms_account_b',
  'legal_terms_device_h',
  'legal_terms_device_b',
  'legal_terms_paid_h',
  'legal_terms_paid_b',
  'legal_terms_orders_h',
  'legal_terms_orders_b',
  'legal_terms_content_h',
  'legal_terms_content_b',
  'legal_terms_prohibited_h',
  'legal_terms_prohibited_b',
  'legal_terms_availability_h',
  'legal_terms_availability_b',
  'legal_terms_termination_h',
  'legal_terms_termination_b',
  'legal_terms_changes_h',
  'legal_terms_changes_b',
  'legal_terms_contact_h',
  'legal_terms_contact_b',
];

void main() {
  test('the app and ana-bala.kz publish identical legal text', () {
    final file = File('../legal/legal.json');
    expect(file.existsSync(), isTrue,
        reason: 'legal/legal.json is the source both sides read; '
            'regenerate it with `node tools/extract-legal.mjs`');

    final strings = (jsonDecode(file.readAsStringSync())
        as Map<String, dynamic>)['strings'] as Map<String, dynamic>;

    final drift = <String>[];
    for (final key in _keys) {
      final shared = strings[key] as Map<String, dynamic>?;
      if (shared == null) {
        drift.add('$key: missing from legal/legal.json');
        continue;
      }
      for (final locale in AppLocale.values) {
        final inApp = L10n(locale).t(key);
        final published = shared[locale.name] as String?;
        if (inApp != published) {
          drift.add('$key.${locale.name}');
        }
      }
    }

    expect(
      drift,
      isEmpty,
      reason: 'the app and the public page disagree on: ${drift.join(', ')}. '
          'Edit the app strings, then re-run `node tools/extract-legal.mjs`.',
    );
  });
}
