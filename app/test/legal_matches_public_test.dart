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
  'legal_priv_collect_h', 'legal_priv_collect_b',
  'legal_priv_storage_h', 'legal_priv_storage_b',
  'legal_priv_cloud_h', 'legal_priv_cloud_b',
  'legal_priv_medical_h', 'legal_priv_medical_b',
  'legal_priv_controls_h', 'legal_priv_controls_b',
  'legal_priv_contact_h', 'legal_priv_contact_b',
  'legal_terms_use_h', 'legal_terms_use_b',
  'legal_terms_medical_h', 'legal_terms_medical_b',
  'legal_terms_emergency_h', 'legal_terms_emergency_b',
  'legal_terms_responsib_h', 'legal_terms_responsib_b',
  'legal_terms_warranty_h', 'legal_terms_warranty_b',
  'legal_terms_law_h', 'legal_terms_law_b',
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
