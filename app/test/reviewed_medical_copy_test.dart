/// Reviewed medical copy is pinned, in ALL THREE languages, by fingerprint.
///
/// Asked for by the clinical gate on 2026-08-14, and again on 2026-08-17 after
/// the reason for it shipped: the Kazakh of two approved cards conceded that a
/// sensor value IS a measurement while the Russian denied it. The gate's note
/// on the second ask is the design of this file:
///
///   «Hashing Russian only would have let today's Kazakh title through.»
///
/// So the fingerprint spans ru + kk + en. Any edit to any language of a
/// reviewed key changes it, and this test fails, and the change routes back to
/// the gate. That is the whole mechanism — `carryReview` for hard-coded
/// strings, which content cards have had all along and the catalogue never did.
///
/// HOW THIS DIFFERS FROM THE OTHER THREE GUARDS, none of which subsumes it:
///
///   · `verify_l10n` kk≠ru       — is this Kazakh a copy-paste of the Russian?
///   · `refused_sentences_test`  — has a refused sentence re-entered anywhere?
///   · `medical_copy_tokens`     — does THIS key still contain THIS word?
///   · here                      — has ANY reviewed string changed at all?
///
/// The token guard pins the words a claim cannot lose. This one notices every
/// other edit — a softened verb, a dropped clause, a new sentence — that no
/// token list anticipated. Neither is redundant: the tokens say what must not
/// change, this says that nothing changed unnoticed.
///
/// WHEN THIS FAILS, THE FIX IS NOT TO UPDATE THE FINGERPRINT. It is to take the
/// new text to the gate, get a verdict that names all three languages, and then
/// update the fingerprint with that verdict recorded. Updating the number to
/// make the build pass is the exact act this file exists to prevent.
///
/// Regenerate with `dart run tool/_scratch/genmanifest.dart` AFTER a verdict.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/l10n/l10n.dart';

/// The medical surface: every advisory card, every emergency-screen string,
/// the confirmation-gate copy, the triage messages, and the vitals qualifier.
/// Membership is a PREDICATE, not a list, so a newly added `ADV_*` key is
/// caught by the completeness test below rather than slipping in unreviewed.
const _triageCodes = {
  'PREECLAMPSIA_BP', 'PREECLAMPSIA_BP_SEVERE', 'HIGH_FEVER', 'LOW_FEVER',
  'HYPOXIA_SEVERE', 'HYPOXIA_SLEEP', 'TACHYCARDIA_SEVERE',
  'BRADYCARDIA_SEVERE', 'DEVICE_TEMP_HIGH', 'EMERGENCY_GENERIC',
};

bool isMedicalKey(String k) =>
    k.startsWith('ADV_') ||
    k.startsWith('em_') ||
    k.startsWith('repeat_') ||
    _triageCodes.contains(k) ||
    k == 'temp_device_estimate_note';

/// FNV-1a over «ru kk en». Pure Dart on purpose: this repo carries no crypto
/// dependency, and adding one so a test can hash 71 strings would be a cost
/// with no matching benefit. Collision resistance is irrelevant here — nobody
/// is attacking the manifest, the job is to notice an edit.
String fingerprint(String key) {
  final joined = [
    const L10n(AppLocale.ru).t(key),
    const L10n(AppLocale.kk).t(key),
    const L10n(AppLocale.en).t(key),
  ].join(' ');
  var h = BigInt.parse('14695981039346656037');
  final mask = (BigInt.one << 64) - BigInt.one;
  final prime = BigInt.parse('1099511628211');
  for (final c in joined.runes) {
    h = (h ^ BigInt.from(c)) & mask;
    h = (h * prime) & mask;
  }
  return h.toRadixString(16).padLeft(16, '0');
}

/// REGENERATE WITH `flutter test`, NEVER with a standalone `dart run` script.
///
/// The two environments produce DIFFERENT fingerprints from byte-identical
/// strings and byte-identical code. That was checked rather than assumed: the
/// three strings were dumped from both and compared character by character
/// (`RU[37] KK[38] EN[45]`, the same in each), and each environment is
/// self-consistent across repeated runs — so it is a stable difference, not
/// randomness.
///
/// The cause is not understood, and does not need to be: a manifest only has to
/// agree with the environment that CHECKS it, so it is generated there. Written
/// down because otherwise someone regenerates this with a helper script one
/// afternoon and is handed 73 spurious failures on copy nobody touched.
const reviewed = <String, String>{
 'ADV_BP_DEVICE_HIGH': 'ae2d5f237b75bfd7',
 'ADV_BP_DEVICE_HIGH_b': '51a822daf784f8ef',
 'ADV_BP_ELEVATED': 'b3454be5d00cae45',
 'ADV_BP_ELEVATED_b': '39b41fc89495d1eb',
 'ADV_BP_STEADY': '145364321f0f022c',
 'ADV_BP_STEADY_b': '4e73890134198469',
 'ADV_GATHERING': '8d58a49c0de65853',
 'ADV_GATHERING_b': '8bf8e75ceef1df9f',
 'ADV_GLUCOSE_HIGH': '7589240640d46392',
 'ADV_GLUCOSE_HIGH_b': '6d3d9b3795597567',
 'ADV_GLUCOSE_LOW': '2652e9342574c196',
 'ADV_GLUCOSE_LOW_b': 'f63ec1ecbba4f556',
 'ADV_HR_RISING': '91ff65ba0c01f89b',
 'ADV_HR_RISING_b': 'f64e2606def30015',
 'ADV_HR_STEADY': 'e9d15f22b526c0fd',
 'ADV_HR_STEADY_b': 'f670c47a714e4857',
 'ADV_HYDRATED': '6541683e96dc3ecb',
 'ADV_HYDRATED_b': 'f3637cfbc9b018cb',
 'ADV_HYDRATE_LOW': '17c057df92bc64e0',
 'ADV_HYDRATE_LOW_b': '6c0f785130d24beb',
 'ADV_NOTHING_UNUSUAL': '5a9f54f43f27d8e9',
 'ADV_NOTHING_UNUSUAL_b': '4a558edcb30e0d02',
 'ADV_NO_CURRENT_READINGS': '3168f55276b68fb0',
 'ADV_NO_CURRENT_READINGS_b': 'ba55d4e212f4a7d4',
 'ADV_SLEEP_DEBT': '343b6e8ecac7802d',
 'ADV_SLEEP_DEBT_b': '18503119c4059432',
 'ADV_SLEEP_GOOD': 'd9cccb605dcffd90',
 'ADV_SLEEP_GOOD_b': 'bd4e168dbb26714a',
 'ADV_SLEEP_OK': 'b45adc79631d8d26',
 'ADV_SLEEP_OK_b': '95bbb1f9d360e2f6',
 'ADV_SLEEP_SHORT': 'ef4fbe90068ea54f',
 'ADV_SLEEP_SHORT_b': '13eda786cc65cd99',
 'ADV_SPO2_SLEEP_DIP': '5d9cb5eb16abb487',
 'ADV_SPO2_SLEEP_DIP_b': '3b999a15c701e887',
 'ADV_SPO2_STEADY': '277c476c93601079',
 'ADV_SPO2_STEADY_b': '4c0174c20cc70ded',
 'ADV_TEMP_DEVICE_HIGH': 'efafa1b6cbacac9a',
 'ADV_TEMP_DEVICE_HIGH_b': '0d9904df66acf5bc',
 'ADV_TEMP_ELEVATED': '61b6d4b2c7d7ec8f',
 'ADV_TEMP_ELEVATED_b': '809e4690155c11ab',
 'ADV_TEMP_STEADY': '35347f583c1a3e96',
 'ADV_TEMP_STEADY_b': 'dfa6e015cf4ba955',
 'BRADYCARDIA_SEVERE': 'a784a2a7ea543866',
 'EMERGENCY_GENERIC': '2101449da2c95cf6',
 'HIGH_FEVER': '94b0c15405f55553',
 'HYPOXIA_SEVERE': 'bb6ec30c0db2cd5b',
 'PREECLAMPSIA_BP': 'e106137b854b512b',
 'PREECLAMPSIA_BP_SEVERE': 'aea28f6f2f9d0ef3',
 'TACHYCARDIA_SEVERE': 'a784a2a7ea543866',
 'em_ambulance_hint': '201a751da51113c9',
 'em_call_ambulance': '944411907fac1ff9',
 'em_call_doctor': '226958588913ba85',
 'em_call_failed_body': '2352d9c60e50b663',
 'em_call_failed_title': 'b50bbf978dbf04e5',
 'em_call_semantics': 'f3b3f1b70a74ec65',
 'em_copy_number': '48aa21755bcb5f74',
 'em_dismiss': 'a2f8580616d4d003',
 'em_dismiss_body': '30a05c748779fdb7',
 'em_dismiss_title': 'de7c1a2f9cde2dce',
 'em_keep': 'f4cac42a5539d58f',
 'em_not_emergency': 'd0ce595fdaeb8d64',
 'em_reading_bp': '365f98d05195428a',
 'em_reading_hr': '753755bb421717fc',
 'em_reading_spo2': 'e8d32429d59b715f',
 'em_reading_temp': 'dbae256c0dd1cfc6',
 'em_title': '5e11be70ec3f0149',
 'repeat_body': '426b098885186992',
 // 'repeat_cta' was pinned here. The key was DELETED from the catalogue on the
 // gate's instruction (2026-08-17) when hand entry went and its button had
 // nowhere to open; see the note at its old home in l10n.dart. Removed from the
 // manifest so the "manifest does not name keys that no longer exist" test
 // passes for the right reason. This is a deletion with a verdict behind it,
 // not a fingerprint updated to make a build green.
 'repeat_title_bp': 'f35ce10bc590bff2',
 'repeat_title_fever': '9d8dc7a70e85e6c2',
 'repeat_title_hr': '036817c5db1316f6',
 'repeat_title_spo2': '4c90c755871ae7b7',
 'temp_device_estimate_note': '74ffd269d07bdba2',
};

void main() {
  test('no reviewed medical string changed without a new verdict', () {
    final changed = <String>[];
    for (final e in reviewed.entries) {
      final now = fingerprint(e.key);
      if (now != e.value) changed.add('${e.key}: ${e.value} -> $now');
    }
    expect(
      changed,
      isEmpty,
      reason: 'Reviewed medical copy changed:\n${changed.join('\n')}\n\n'
          'The fingerprint spans ru + kk + en, so this fires for an edit to ANY '
          'language — which is the point: the Kazakh of two approved cards once '
          'shipped saying something weaker than the Russian, and a Russian-only '
          'hash would not have noticed.\n'
          'DO NOT update the fingerprint to make this pass. Take the new text to '
          'the clinical gate, get a verdict naming all three languages, then '
          'regenerate. See docs/CLINICAL-REVIEW-WATCH.md.',
    );
  });

  test('every medical key in the catalogue is in the manifest', () {
    // The half that stops the manifest rotting. Without it, a new ADV_* card
    // ships unreviewed simply by not being listed — the guard would pass by
    // saying nothing about it, which is how «verify_l10n reports 82/0» happened.
    final unpinned = allL10nKeys.where(isMedicalKey).where((k) => !reviewed.containsKey(k)).toList()..sort();
    expect(
      unpinned,
      isEmpty,
      reason: 'Medical keys with no reviewed fingerprint: $unpinned\n'
          'A new advisory, emergency or triage string must be reviewed in all '
          'three languages before it ships. Add it to the manifest only with a '
          'verdict behind it.',
    );
  });

  test('the manifest does not name keys that no longer exist', () {
    // The other direction: a stale entry is a pin guarding nothing, and it
    // makes the manifest look larger than the surface it covers.
    final all = allL10nKeys.toSet();
    final ghosts = reviewed.keys.where((k) => !all.contains(k)).toList()..sort();
    expect(ghosts, isEmpty, reason: 'Manifest names keys not in the catalogue: $ghosts');
  });

  test('the fingerprint actually reads the strings', () {
    // Non-vacuity, the failure mode every guard in this repo has had. If `t()`
    // started returning the key, or the catalogue failed to load, every
    // fingerprint would still be *a* value and the first test would pass on a
    // manifest of nonsense.
    expect(reviewed.length, greaterThan(50),
        reason: 'the manifest is too small to be the medical surface');
    final a = fingerprint('ADV_BP_DEVICE_HIGH_b');
    final b = fingerprint('ADV_TEMP_DEVICE_HIGH_b');
    expect(a, isNot(equals(b)), reason: 'two different strings hashed the same');
    expect(const L10n(AppLocale.kk).t('ADV_BP_DEVICE_HIGH_b'), contains('өлшем емес'),
        reason: 't() is not returning the reviewed Kazakh — the scan read nothing real');
  });
}
