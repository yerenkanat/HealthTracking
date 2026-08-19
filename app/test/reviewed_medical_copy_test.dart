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

/// WIDENED 2026-08-18 (TODO §8.8). The predicate used to be four prefixes off
/// the watch-vitals review — `ADV_`, `em_`, `repeat_` and the triage codes —
/// because that review is what created it. It therefore matched by ORIGIN, not
/// by what a sentence does to a reader, and everything clinical the app says
/// that did not come out of the wearable pipeline was outside it.
///
/// The string that showed it: `lab_go_five_one_one`, «Схватки примерно каждые
/// 5 минут по ~1 минуте в течение часа», live in ru and kk on the labour-signs
/// screen, reachable from the contraction timer and from «Экстренная помощь».
/// It tells a woman in labour when to leave her house, and it carried no
/// fingerprint. It was found by accident.
///
/// THE TEST APPLIED HERE, and it is not the key prefix: does the sentence make
/// a clinical claim, give a clinical instruction, name a threshold, or tell the
/// reader to seek or delay care? Fetal-development copy («лёгкие почти готовы
/// к первому вдоху») and the baby-size fruit list fail that test and are
/// deliberately NOT here — they describe, they do not triage.
///
/// TWO MECHANISMS, on purpose:
///   · a PREFIX where the whole screen is clinical — a red-flag list, a
///     validated instrument, a protocol transcribed from a contract;
///   · an EXPLICIT KEY where one clinical sentence sits among UI chrome.
///
/// The second exists so this guard does not cry wolf. `bag_` is 26 keys and
/// two of them are clinical, so `bag_intro` is named and «Ночная рубашка» is
/// not — the same calibration a «роддом» token rule failed earlier today when
/// it fired on «Сумка в роддом». A guard that fails on a packing list stops
/// being believed, and then someone loosens it.
///
/// PINNED IS NOT APPROVED. Everything added on 2026-08-18 is frozen at the
/// wording it already shipped with, so it cannot drift silently while it waits
/// for a verdict. See docs/CLINICAL-REVIEW-WATCH.md, «The labour hole».

/// Whole screens whose every string is a clinical claim, instruction,
/// threshold or triage verdict.
const _medicalPrefixes = <String>[
  'ADV_', // advisory cards off the vitals pipeline
  'CS_', // child-safety advisory cards: back-sleeping, car seat, choking, water
  'an_', // the RK MOH 8-visit antenatal protocol, verbatim from the contract
  'contr_511_', // the 5-1-1 scheme on the contraction timer
  'eh_', // «Экстренная помощь»: the 103 card, the severity verdicts, the address
  'em_', // the emergency confirmation gate
  'epds_', // the Edinburgh scale — every word of it IS the instrument
  'hs_', // home safety: 50 °C tap water, safe sleep, choking, medicines locked
  'ill_', // «Если малыш заболел»: 38 °C under three months, red flags, aspirin
  'lab_', // signs of labour and when to go in
  'pp_note_', // postpartum: what is normal now
  'pp_warn_', // postpartum red flags
  'preg_note_', // pregnancy: what is normal now
  'preg_warn_', // pregnancy red flags
  'pwg_', // pregnancy weight-gain ranges, by pre-pregnancy BMI band
  'repeat_', // the repeat-reading prompts
  'sol_', // solids: 6 months, honey and botulism, choking, allergens
  'ss_', // safe sleep — the SIDS risk-reduction rules
  'teeth_not_', // what teething does NOT cause, i.e. go and be seen
  'vac_', // the national immunisation schedule, catch-up wording, vaccine notes
];

/// Single clinical sentences living on screens that are otherwise chrome.
/// Named one by one so the rest of their screen stays out of the guard.
const _medicalKeys = <String>{
  'art_red_flag', // the label over an authored red flag
  'bag_intro', // «В роддоме могут дать свой список» — the caveat, not the list
  'chat_disclaimer', 'chat_emergency_note', 'chat_empty_body', 'chat_error',
  'cry_disclaimer', 'cry_intro', // «подсказка, а не диагноз»
  'cyc_pp_paused_body', 'cyc_share_disclaimer', // «не средство контрацепции»
  'db_not_measuring', 'db_outside_range', 'db_ring_partial', 'db_ring_ungraded',
  'detail_safe_range', // the app names a range «безопасный»
  'dev_ask_note', 'dev_first_solids_note', 'dev_spread',
  'ei_disclaimer', // the emergency card is unverified and says so
  'gd_call_body', 'gd_call_title', // «Когда сразу звонить 103»
  'gest_estimate_note', 'grw_no_percentiles',
  'help_emergency_note', 'help_q2_a',
  'kick_goal_hits', // the same verdict, aggregated, in the history strip
  'kick_goal_reached', // was «Цель достигнута» on a fetal-movement count
  'kick_goal_reached_slow', 'kick_low_action', 'kick_low_body', 'kick_low_title',
  'kick_method_note', // «считай до десяти» — ten movements in about two hours
  'legal_priv_medical_b', 'legal_priv_medical_h',
  'legal_terms_emergency_b', 'legal_terms_emergency_h',
  'legal_terms_medical_b', 'legal_terms_medical_h',
  'med_disclaimer', 'phase_fertile_note',
  'pp_card_sub', 'pp_check_body', 'pp_disclaimer', 'pp_low_run_body',
  'set_about_body', // «Не является медицинским прибором»
  'share_bp_cuff_only', 'sup_chat_disclaimer', 'teeth_disclaimer',
  'temp_device_estimate_note',
  'visit_bp_cuff', 'visit_disclaimer', 'visit_temp_thermometer',
  'wm_off_wrist',
};

bool isMedicalKey(String k) =>
    _medicalPrefixes.any(k.startsWith) ||
    _medicalKeys.contains(k) ||
    _triageCodes.contains(k);

/// FNV-1a over «ru kk en». Pure Dart on purpose: this repo carries no crypto
/// dependency, and adding one so a test can hash 508 strings would be a cost
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
///
/// TWO KINDS OF ENTRY LIVE IN THIS MAP, and conflating them would undo the
/// point of it.
///
///   · The 72 entries carried over from the watch-vitals review have a VERDICT
///     behind them. Each was read in ru + kk + en and approved, and the
///     reasoning is in docs/CLINICAL-REVIEW-WATCH.md.
///   · The four marked `REVIEWED 2026-08-19` are the reduced-fetal-movement
///     set, read as one item by the clinical gate against the RK MOH protocol
///     «Антенатальный уход» (2025) — docs/CLINICAL-REVIEW-WATCH.md, «Reduced
///     fetal movement — CLOSED, 2026-08-19». Three were approved unchanged;
///     `kick_low_action` was rewritten, and its Kazakh has since been
///     gate-reviewed too (docs/TODO.md §9.12).
///   · FOUR MORE carry a verdict from 2026-08-19, the sitting of the same day
///     that closed the movement item — `kick_goal_reached` and `kick_goal_hits`
///     (the reassurance verdict on a fetal-movement count, REFUSED as written
///     and rewritten in all three languages) and `lab_intro` and
///     `db_ring_partial` (Kazakh that did not say what the Russian said,
///     CHANGES in kk only, ru + en approved unchanged). Their lines say so.
///     `kick_goal_hits` is NEW to this manifest: it was never matched, and it
///     printed the same two Russian words one screen away from a string that
///     was.
///   · The remainder marked `// pinned 2026-08-18, UNREVIEWED` do NOT. They are the
///     strings the old predicate never matched — labour, antenatal, postpartum,
///     EPDS, vaccination, solids, safe sleep, child illness, home safety,
///     emergency help. They are frozen at the wording that was ALREADY LIVE on
///     that date so it cannot drift while it waits for one.
///
/// PINNING IS NOT APPROVING. A fingerprint here means "this text has not
/// changed since we noticed it", not "a reviewer says it is safe". Do not cite
/// membership of this map as clearance for anything. The verdicts, when they
/// come, go in docs/CLINICAL-REVIEW-WATCH.md and the marker comes off the line.
const reviewed = <String, String>{
 'ADV_BP_DEVICE_HIGH': 'ae2d5f237b75bfd7',
 'ADV_BP_DEVICE_HIGH_b': '51a822daf784f8ef',
 'ADV_BP_ELEVATED': 'b3454be5d00cae45',
 'ADV_BP_ELEVATED_b': '39b41fc89495d1eb',
 // 'ADV_BP_STEADY' and 'ADV_BP_STEADY_b' were pinned here. Both keys were
 // DELETED from the catalogue on 2026-08-19 with a verdict behind them — the
 // card gated «Давление ровное» on `sys < 130 && dia < 85`, and 130/85 is
 // uncited in every source this product names, exactly as 135/85 was. A
 // reassurance is the worse direction for an uncited number, so the assertion
 // stopped rather than moving to another band. See docs/CLINICAL-REVIEW-WATCH.md,
 // «ADV_BP_STEADY — REFUSED, and the card with it». Removed from the manifest
 // so the "manifest does not name keys that no longer exist" test passes for
 // the right reason; their absence from the catalogue is pinned by
 // bp_advisory_provenance_test.dart instead. This is a deletion with a verdict
 // behind it, not a fingerprint updated to make a build green.
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
 'CS_AT_ZONE': 'fa762e15aab73424', // pinned 2026-08-18, UNREVIEWED
 'CS_AT_ZONE_b': '62cfe1948e05df03', // pinned 2026-08-18, UNREVIEWED
 'CS_DELAYED': '1b0d99c3782f4028', // pinned 2026-08-18, UNREVIEWED
 'CS_DELAYED_b': '10a61e8bd0ec7dc2', // pinned 2026-08-18, UNREVIEWED
 'CS_INFANT_CARSEAT': 'bdadc598f8d548d9', // pinned 2026-08-18, UNREVIEWED
 'CS_INFANT_CARSEAT_b': '381e80b3ebdd8c17', // pinned 2026-08-18, UNREVIEWED
 'CS_INFANT_SLEEP': '4dbd3a319ee28f4d', // pinned 2026-08-18, UNREVIEWED
 'CS_INFANT_SLEEP_b': '526c2380a7604fe2', // pinned 2026-08-18, UNREVIEWED
 'CS_NO_DOB': 'dd1f04e452a8fa22', // pinned 2026-08-18, UNREVIEWED
 'CS_NO_DOB_b': '33cbdc26c052c3c6', // pinned 2026-08-18, UNREVIEWED
 'CS_ON_MOVE': 'cc0ac1a60b8331a1', // pinned 2026-08-18, UNREVIEWED
 'CS_ON_MOVE_b': '5e5173975d125731', // pinned 2026-08-18, UNREVIEWED
 'CS_PRESCHOOL_IDENTITY': 'd9756af6927de101', // pinned 2026-08-18, UNREVIEWED
 'CS_PRESCHOOL_IDENTITY_b': 'b6ecd26e0169dde9', // pinned 2026-08-18, UNREVIEWED
 'CS_PRESCHOOL_ROAD': '25c5477144eeaf92', // pinned 2026-08-18, UNREVIEWED
 'CS_PRESCHOOL_ROAD_b': '404a5ec40636fd6d', // pinned 2026-08-18, UNREVIEWED
 'CS_PRETEEN_LOCATION': '68c25cf81b762a77', // pinned 2026-08-18, UNREVIEWED
 'CS_PRETEEN_LOCATION_b': '27d1c2c0947bee1d', // pinned 2026-08-18, UNREVIEWED
 'CS_PRETEEN_ONLINE': '5f64944525acbb26', // pinned 2026-08-18, UNREVIEWED
 'CS_PRETEEN_ONLINE_b': 'b4e054ba2be16f62', // pinned 2026-08-18, UNREVIEWED
 'CS_SCHOOL_CHECKIN': '302a97bac2b3a35f', // pinned 2026-08-18, UNREVIEWED
 'CS_SCHOOL_CHECKIN_b': '64e9c6210917f8ac', // pinned 2026-08-18, UNREVIEWED
 'CS_SCHOOL_ROUTE': '1a3b7a3446c071d7', // pinned 2026-08-18, UNREVIEWED
 'CS_SCHOOL_ROUTE_b': '7b945da705672f6a', // pinned 2026-08-18, UNREVIEWED
 'CS_TODDLER_CHOKING': '07b4a6f0c889c868', // pinned 2026-08-18, UNREVIEWED
 'CS_TODDLER_CHOKING_b': '4919d802c1fe3871', // pinned 2026-08-18, UNREVIEWED
 'CS_TODDLER_WATER': 'b7f840513db304f2', // pinned 2026-08-18, UNREVIEWED
 'CS_TODDLER_WATER_b': 'a095dbe296e8a0e8', // pinned 2026-08-18, UNREVIEWED
 'EMERGENCY_GENERIC': '2101449da2c95cf6',
 'HIGH_FEVER': '94b0c15405f55553',
 'HYPOXIA_SEVERE': 'bb6ec30c0db2cd5b',
 'PREECLAMPSIA_BP': 'e106137b854b512b',
 'PREECLAMPSIA_BP_SEVERE': 'aea28f6f2f9d0ef3',
 'TACHYCARDIA_SEVERE': 'a784a2a7ea543866',
 'an_book_cta': '89a0b58e27f87c70', // pinned 2026-08-18, UNREVIEWED
 'an_book_title': '2c70e517e37645c2', // pinned 2026-08-18, UNREVIEWED
 'an_booked': '7b20b1f94856c214', // pinned 2026-08-18, UNREVIEWED
 'an_card_due': '891805636552b318', // pinned 2026-08-18, UNREVIEWED
 'an_card_next': '2bb42bedb4b36a88', // pinned 2026-08-18, UNREVIEWED
 'an_card_title': '781ab25944bca8b1', // pinned 2026-08-18, UNREVIEWED
 'an_cat_counsel': '899f6d7715982985', // pinned 2026-08-18, UNREVIEWED
 'an_cat_exam': '7297e3fe3d96ce12', // pinned 2026-08-18, UNREVIEWED
 'an_cat_imaging': 'cf324b6e8f7ff33f', // pinned 2026-08-18, UNREVIEWED
 'an_cat_lab': '8617eff3dd648970', // pinned 2026-08-18, UNREVIEWED
 'an_cat_prophylaxis': '34297ccd6f365ec2', // pinned 2026-08-18, UNREVIEWED
 'an_disclaimer': '1d624f74ed23d481', // pinned 2026-08-18, UNREVIEWED
 'an_due_now': 'a619e52b08afe4c5', // pinned 2026-08-18, UNREVIEWED
 'an_full_plan': 'fe1a3b03d4b1ae19', // pinned 2026-08-18, UNREVIEWED
 'an_intro': 'eafea12441485727', // pinned 2026-08-18, UNREVIEWED
 'an_item_anti_d': '19f3af426856f947', // pinned 2026-08-18, UNREVIEWED
 'an_item_aspirin': 'f84dd472ca3a2785', // pinned 2026-08-18, UNREVIEWED
 'an_item_birth_school': '919f9ff96cfb9279', // pinned 2026-08-18, UNREVIEWED
 'an_item_blood_glucose': '0b5ab9c77d03bf81', // pinned 2026-08-18, UNREVIEWED
 'an_item_blood_type_rh': '477cff27eba8c8be', // pinned 2026-08-18, UNREVIEWED
 'an_item_bmi': '0654b0b5e2a2d639', // pinned 2026-08-18, UNREVIEWED
 'an_item_bp_pulse': '33666f745403e437', // pinned 2026-08-18, UNREVIEWED
 'an_item_breast_exam': '04819cfb2a9fa11e', // pinned 2026-08-18, UNREVIEWED
 'an_item_breastfeeding_contraception': '73e85474e399b1da', // pinned 2026-08-18, UNREVIEWED
 'an_item_calcium': '28faa92c616091b9', // pinned 2026-08-18, UNREVIEWED
 'an_item_cbc': '15d1b1aeba6acc11', // pinned 2026-08-18, UNREVIEWED
 'an_item_cervical_cytology': '2010d6ebbf4d70ae', // pinned 2026-08-18, UNREVIEWED
 'an_item_danger_signs': '496e6806a5dee130', // pinned 2026-08-18, UNREVIEWED
 'an_item_ecg': '101d821c00d532ac', // pinned 2026-08-18, UNREVIEWED
 'an_item_fetal_heartbeat': 'b72c4519f039a691', // pinned 2026-08-18, UNREVIEWED
 'an_item_fetal_position': '91db228d484d8457', // pinned 2026-08-18, UNREVIEWED
 'an_item_folic_acid': 'c726645c3c05d1f6', // pinned 2026-08-18, UNREVIEWED
 'an_item_fundal_height': 'b1dbb107fe50c779', // pinned 2026-08-18, UNREVIEWED
 'an_item_gyn_exam': '4c6ad1bcb00878c4', // pinned 2026-08-18, UNREVIEWED
 'an_item_hep_b': '28cbac7ed9ff21f8', // pinned 2026-08-18, UNREVIEWED
 'an_item_history_risk': '8043626392ee9425', // pinned 2026-08-18, UNREVIEWED
 'an_item_hiv': '42c3052837969d05', // pinned 2026-08-18, UNREVIEWED
 'an_item_hospital_41w': '2ede8fadb7e96877', // pinned 2026-08-18, UNREVIEWED
 'an_item_legs_varicose': '161731d65fab5631', // pinned 2026-08-18, UNREVIEWED
 'an_item_maternity_leave': '37ed430a49ffef99', // pinned 2026-08-18, UNREVIEWED
 'an_item_ogtt': '0c67834cbfd625db', // pinned 2026-08-18, UNREVIEWED
 'an_item_postterm_talk': 'e2d206675336216d', // pinned 2026-08-18, UNREVIEWED
 'an_item_risk_review': 'e45f9f5439e11db6', // pinned 2026-08-18, UNREVIEWED
 'an_item_schedule_plan': '0c2d2992db4e9fa2', // pinned 2026-08-18, UNREVIEWED
 'an_item_screening_review': '3f4dc680c199bbac', // pinned 2026-08-18, UNREVIEWED
 'an_item_serum_markers': '73dff629509afdb7', // pinned 2026-08-18, UNREVIEWED
 'an_item_syphilis': 'f9a182e7fb938fe2', // pinned 2026-08-18, UNREVIEWED
 'an_item_therapist': '8bb0db8e07f4bedc', // pinned 2026-08-18, UNREVIEWED
 'an_item_urinalysis': 'ee3c6faffe75bd3c', // pinned 2026-08-18, UNREVIEWED
 'an_item_urine_culture': '6391c4bf5853d257', // pinned 2026-08-18, UNREVIEWED
 'an_item_urine_protein': '350ef3b54397c097', // pinned 2026-08-18, UNREVIEWED
 'an_item_us_anomaly': '3006cbedd3bae7e0', // pinned 2026-08-18, UNREVIEWED
 'an_item_us_dating': 'a79de23e34270855', // pinned 2026-08-18, UNREVIEWED
 'an_item_us_growth': 'a44d5cc3c16567d5', // pinned 2026-08-18, UNREVIEWED
 'an_item_weight_recheck': '07e3a0dc07877e76', // pinned 2026-08-18, UNREVIEWED
 'an_of_eight': 'b31138cf61249972', // pinned 2026-08-18, UNREVIEWED
 'an_risk_note': '14803423d62e1cc0', // pinned 2026-08-18, UNREVIEWED
 'an_risk_tag': 'b907626e799e68ee', // pinned 2026-08-18, UNREVIEWED
 'an_source': '4ba5a48218c6aa9d', // pinned 2026-08-18, UNREVIEWED
 'an_term_note': '44b9f9ee379060a2', // pinned 2026-08-18, UNREVIEWED
 'an_term_title': '9465bc5ecd158386', // pinned 2026-08-18, UNREVIEWED
 'an_title': '362c62504d3d2cdc', // pinned 2026-08-18, UNREVIEWED
 'an_upcoming': '45bcf61d5d69cf6a', // pinned 2026-08-18, UNREVIEWED
 'an_visit_label': 'de7cd08bbe17414e', // pinned 2026-08-18, UNREVIEWED
 'an_week_single': 'c2997e9f8023df69', // pinned 2026-08-18, UNREVIEWED
 'an_weeks_range': 'bdd75325ee024a85', // pinned 2026-08-18, UNREVIEWED
 'an_win_open': 'f5c5e033003b6e9e', // pinned 2026-08-18, UNREVIEWED
 'an_win_range': '19ea5c71e4ef3c3c', // pinned 2026-08-18, UNREVIEWED
 'an_windows_intro': 'b0ee65d4703a030e', // pinned 2026-08-18, UNREVIEWED
 'an_windows_title': '8f30b0c46f2ab411', // pinned 2026-08-18, UNREVIEWED
 'art_red_flag': 'a5e5e33a14c635a6', // pinned 2026-08-18, UNREVIEWED
 'bag_intro': 'e25b110d5ab79b53', // pinned 2026-08-18, UNREVIEWED
 'chat_disclaimer': 'a980f329a0df0202', // pinned 2026-08-18, UNREVIEWED
 'chat_emergency_note': 'f4047f2e5a685265', // pinned 2026-08-18, UNREVIEWED
 'chat_empty_body': 'fc44903733e0e4c8', // pinned 2026-08-18, UNREVIEWED
 'chat_error': '773d077f268e824a', // pinned 2026-08-18, UNREVIEWED
 'contr_511_duration': 'fcaba98931d7e943', // pinned 2026-08-18, UNREVIEWED
 'contr_511_interval': 'ad3646b5e9a3f0ec', // pinned 2026-08-18, UNREVIEWED
 'contr_511_note': 'd2dc668eccbe67c4', // pinned 2026-08-18, UNREVIEWED
 'contr_511_ready': '70b67874b35e25a9', // pinned 2026-08-18, UNREVIEWED
 'contr_511_sustained': 'e447f988df88f633', // pinned 2026-08-18, UNREVIEWED
 'contr_511_title': '03d34e8297cc12ef', // pinned 2026-08-18, UNREVIEWED
 'cry_disclaimer': '487cc7fc2046b91d', // pinned 2026-08-18, UNREVIEWED
 'cry_intro': 'df75014c2eccc09d', // pinned 2026-08-18, UNREVIEWED
 'cyc_pp_paused_body': '69b1ec96845f5ecc', // pinned 2026-08-18, UNREVIEWED
 'cyc_share_disclaimer': '222b440cf2251d11', // pinned 2026-08-18, UNREVIEWED
 'db_not_measuring': '9a27d7c8fa250298', // pinned 2026-08-18, UNREVIEWED
 'db_outside_range': '6a5abe517d132320', // pinned 2026-08-18, UNREVIEWED
 'db_ring_partial': '4826097ffa3b6a87', // REVIEWED 2026-08-19; kk CHANGED, ru/en unchanged
 'db_ring_ungraded': '3d2d6a1fd60527ef', // pinned 2026-08-18, UNREVIEWED
 'detail_safe_range': '2900744a7b475ded', // pinned 2026-08-18, UNREVIEWED
 'dev_ask_note': '3e122f72cb2f6ef7', // pinned 2026-08-18, UNREVIEWED
 'dev_first_solids_note': 'e0294561d8e0021a', // pinned 2026-08-18, UNREVIEWED
 'dev_spread': '169a16526c041352', // pinned 2026-08-18, UNREVIEWED
 'eh_address_copied': '0de1d6644087bba2', // pinned 2026-08-18, UNREVIEWED
 'eh_address_copy': '65b274314dc86b2e', // pinned 2026-08-18, UNREVIEWED
 'eh_address_hint': '06527cbfe57a8f18', // pinned 2026-08-18, UNREVIEWED
 'eh_address_missing': 'c8c9e9c0a068857b', // pinned 2026-08-18, UNREVIEWED
 'eh_address_missing_body': '3d435fce30ecd648', // pinned 2026-08-18, UNREVIEWED
 'eh_address_title': '2b4634f7cc79687e', // pinned 2026-08-18, UNREVIEWED
 'eh_call_103': 'fd414d3770515b00', // pinned 2026-08-18, UNREVIEWED
 'eh_call_body': 'e731f056e0028a92', // pinned 2026-08-18, UNREVIEWED
 'eh_call_doctor': '37c78b69c210da48', // pinned 2026-08-18, UNREVIEWED
 'eh_do': 'fcdb309a3018ee45', // pinned 2026-08-18, UNREVIEWED
 'eh_labour_signs': '9c815ff3746f053d', // pinned 2026-08-18, UNREVIEWED
 'eh_no_doctor': '940158f5ee23bcd7', // pinned 2026-08-18, UNREVIEWED
 'eh_no_scenarios': '0b8ac15fa9a27667', // pinned 2026-08-18, UNREVIEWED
 'eh_sev_amber': 'a3a148dec3181e29', // pinned 2026-08-18, UNREVIEWED
 'eh_sev_red': '4e5ae34ac833babd', // pinned 2026-08-18, UNREVIEWED
 'eh_title': '0a049f8a0cb43225', // pinned 2026-08-18, UNREVIEWED
 'eh_whats_happening': 'bd00e57424d7d701', // pinned 2026-08-18, UNREVIEWED
 'ei_disclaimer': '13c4557c1d6c985d', // pinned 2026-08-18, UNREVIEWED
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
 'epds_band_high': 'd57eaf18a5b974ff', // pinned 2026-08-18, UNREVIEWED
 'epds_band_low': '58e4f98bc555915c', // pinned 2026-08-18, UNREVIEWED
 'epds_band_possible': '6ab53d64c76217fe', // pinned 2026-08-18, UNREVIEWED
 'epds_close': 'c483c6aeecde2dd3', // pinned 2026-08-18, UNREVIEWED
 'epds_disclaimer': '39ef8294fa8e9be1', // pinned 2026-08-18, UNREVIEWED
 'epds_entry': '899548f4793fb799', // pinned 2026-08-18, UNREVIEWED
 'epds_harm_flag': 'bb9dcdb3c19837a0', // pinned 2026-08-18, UNREVIEWED
 'epds_incomplete': '2c68932b0f7d806b', // pinned 2026-08-18, UNREVIEWED
 'epds_instrument': 'f53d4678398d6100', // pinned 2026-08-18, UNREVIEWED
 'epds_not_validated': '89058ff714d65e14', // pinned 2026-08-18, UNREVIEWED
 'epds_period': '5cc581893c84779a', // pinned 2026-08-18, UNREVIEWED
 'epds_progress': 'a82667de85c3dd5f', // pinned 2026-08-18, UNREVIEWED
 'epds_q1': '9bd6c9cde8d1aaa8', // pinned 2026-08-18, UNREVIEWED
 'epds_q10': '37bb065616a0b2ac', // pinned 2026-08-18, UNREVIEWED
 'epds_q10_a0': '3004056a29bad3de', // pinned 2026-08-18, UNREVIEWED
 'epds_q10_a1': '381d24a4b7fa5cb4', // pinned 2026-08-18, UNREVIEWED
 'epds_q10_a2': '03a722f5da4bb20a', // pinned 2026-08-18, UNREVIEWED
 'epds_q10_a3': '02c955d4ce3c7e9e', // pinned 2026-08-18, UNREVIEWED
 'epds_q1_a0': '33bedbbc55240da6', // pinned 2026-08-18, UNREVIEWED
 'epds_q1_a1': 'd90b37df67b1b0a6', // pinned 2026-08-18, UNREVIEWED
 'epds_q1_a2': 'fdc0d3a6dd394beb', // pinned 2026-08-18, UNREVIEWED
 'epds_q1_a3': '964d1934508d5461', // pinned 2026-08-18, UNREVIEWED
 'epds_q2': '575f70d05d9dc769', // pinned 2026-08-18, UNREVIEWED
 'epds_q2_a0': '00f87df0bcca0c6c', // pinned 2026-08-18, UNREVIEWED
 'epds_q2_a1': 'a0a5dcd405e10d2c', // pinned 2026-08-18, UNREVIEWED
 'epds_q2_a2': '779bd5eb8f03bdc0', // pinned 2026-08-18, UNREVIEWED
 'epds_q2_a3': '3a00e1267614c8e8', // pinned 2026-08-18, UNREVIEWED
 'epds_q3': '70f8c3c862be31bf', // pinned 2026-08-18, UNREVIEWED
 'epds_q3_a0': 'fcfc3f16156092b9', // pinned 2026-08-18, UNREVIEWED
 'epds_q3_a1': '2e87dd5beb1fd403', // pinned 2026-08-18, UNREVIEWED
 'epds_q3_a2': '0f784c9ade484b99', // pinned 2026-08-18, UNREVIEWED
 'epds_q3_a3': '049da71467bcebd4', // pinned 2026-08-18, UNREVIEWED
 'epds_q4': 'd3a0a21c1198cb74', // pinned 2026-08-18, UNREVIEWED
 'epds_q4_a0': '34f5de5d989531f8', // pinned 2026-08-18, UNREVIEWED
 'epds_q4_a1': '03a722f5da4bb20a', // pinned 2026-08-18, UNREVIEWED
 'epds_q4_a2': 'c6024cc3cde27d3e', // pinned 2026-08-18, UNREVIEWED
 'epds_q4_a3': '8d5e7a02dff40eaa', // pinned 2026-08-18, UNREVIEWED
 'epds_q5': '4eaf9bd03022053f', // pinned 2026-08-18, UNREVIEWED
 'epds_q5_a0': '5e2084db660077c2', // pinned 2026-08-18, UNREVIEWED
 'epds_q5_a1': 'c6024cc3cde27d3e', // pinned 2026-08-18, UNREVIEWED
 'epds_q5_a2': '717d696d8c78e6b6', // pinned 2026-08-18, UNREVIEWED
 'epds_q5_a3': '34f5de5d989531f8', // pinned 2026-08-18, UNREVIEWED
 'epds_q6': 'f04b98c09d9a0cac', // pinned 2026-08-18, UNREVIEWED
 'epds_q6_a0': 'cc54ccb2e68546e1', // pinned 2026-08-18, UNREVIEWED
 'epds_q6_a1': 'c30fccc0d498e803', // pinned 2026-08-18, UNREVIEWED
 'epds_q6_a2': 'c7ed747988672991', // pinned 2026-08-18, UNREVIEWED
 'epds_q6_a3': '45015583c8f4f3c9', // pinned 2026-08-18, UNREVIEWED
 'epds_q7': '8aca9426b2d6ab93', // pinned 2026-08-18, UNREVIEWED
 'epds_q7_a0': 'fcfc3f16156092b9', // pinned 2026-08-18, UNREVIEWED
 'epds_q7_a1': 'c6024cc3cde27d3e', // pinned 2026-08-18, UNREVIEWED
 'epds_q7_a2': '0f784c9ade484b99', // pinned 2026-08-18, UNREVIEWED
 'epds_q7_a3': '34f5de5d989531f8', // pinned 2026-08-18, UNREVIEWED
 'epds_q8': '8dccd322454d4dfa', // pinned 2026-08-18, UNREVIEWED
 'epds_q8_a0': 'fcfc3f16156092b9', // pinned 2026-08-18, UNREVIEWED
 'epds_q8_a1': '3004056a29bad3de', // pinned 2026-08-18, UNREVIEWED
 'epds_q8_a2': '0f784c9ade484b99', // pinned 2026-08-18, UNREVIEWED
 'epds_q8_a3': '34f5de5d989531f8', // pinned 2026-08-18, UNREVIEWED
 'epds_q9': 'af2431c0033a67a0', // pinned 2026-08-18, UNREVIEWED
 'epds_q9_a0': 'fcfc3f16156092b9', // pinned 2026-08-18, UNREVIEWED
 'epds_q9_a1': '3004056a29bad3de', // pinned 2026-08-18, UNREVIEWED
 'epds_q9_a2': '42bd819e5eee8398', // pinned 2026-08-18, UNREVIEWED
 'epds_q9_a3': '049da71467bcebd4', // pinned 2026-08-18, UNREVIEWED
 'epds_result_title': 'a6a3d90be7ad443b', // pinned 2026-08-18, UNREVIEWED
 'epds_retake': '279213818234ee40', // pinned 2026-08-18, UNREVIEWED
 'epds_saved': 'ef5d5edec302758b', // pinned 2026-08-18, UNREVIEWED
 'epds_score': '78648d355f8b4d88', // pinned 2026-08-18, UNREVIEWED
 'epds_submit': '812098e34f582a4c', // pinned 2026-08-18, UNREVIEWED
 'epds_title': '382124aedc74e1d4', // pinned 2026-08-18, UNREVIEWED
 'gd_call_body': 'e4b4113b5cce6cd1', // pinned 2026-08-18, UNREVIEWED
 'gd_call_title': 'ebf29df2ad6be85a', // pinned 2026-08-18, UNREVIEWED
 'gest_estimate_note': '00feee4450608443', // pinned 2026-08-18, UNREVIEWED
 'grw_no_percentiles': 'b98046e6ccc4e8b5', // pinned 2026-08-18, UNREVIEWED
 'help_emergency_note': 'fd854692b01730c7', // pinned 2026-08-18, UNREVIEWED
 'help_q2_a': '3b19a4c8dd308f3a', // pinned 2026-08-18, UNREVIEWED
 'hs_all_done': 'cfe20e90f98f8321', // pinned 2026-08-18, UNREVIEWED
 'hs_blind_cords': '8cc1b78784e89cf6', // pinned 2026-08-18, UNREVIEWED
 'hs_card_title': 'bb8202954701e821', // pinned 2026-08-18, UNREVIEWED
 'hs_chemicals_high': '05176a93700e6b66', // pinned 2026-08-18, UNREVIEWED
 'hs_cupboard_locks': '3523ff53a91db198', // pinned 2026-08-18, UNREVIEWED
 'hs_furniture_anchored': '27aef6fc0c48ee2e', // pinned 2026-08-18, UNREVIEWED
 'hs_hot_drinks': '930a7f96472fd329', // pinned 2026-08-18, UNREVIEWED
 'hs_intro': 'bcd45d421f422ac5', // pinned 2026-08-18, UNREVIEWED
 'hs_medicines_locked': '00ca1cfbc98998d9', // pinned 2026-08-18, UNREVIEWED
 'hs_never_alone_high': 'a6d8fca32479a082', // pinned 2026-08-18, UNREVIEWED
 'hs_outlet_covers': '44393b692cc649c0', // pinned 2026-08-18, UNREVIEWED
 'hs_progress': 'a5a3093ccfb6fc68', // pinned 2026-08-18, UNREVIEWED
 'hs_safe_sleep_space': 'f854f2e44c753b56', // pinned 2026-08-18, UNREVIEWED
 'hs_sharp_corners': 'd35111c39eb3bb7f', // pinned 2026-08-18, UNREVIEWED
 'hs_small_objects': 'deefe8daf5bb1315', // pinned 2026-08-18, UNREVIEWED
 'hs_smoke_alarm': 'bec0b9f76e2f20de', // pinned 2026-08-18, UNREVIEWED
 'hs_stage_birth': '46899303a28e81d4', // pinned 2026-08-18, UNREVIEWED
 'hs_stage_crawling': 'c40880d400afea1e', // pinned 2026-08-18, UNREVIEWED
 'hs_stage_rolling': '0a3f230a003bafe3', // pinned 2026-08-18, UNREVIEWED
 'hs_stage_standing': '45398334ba9ce007', // pinned 2026-08-18, UNREVIEWED
 'hs_stair_gates': 'c3359fec6be97e21', // pinned 2026-08-18, UNREVIEWED
 'hs_title': 'bb8202954701e821', // pinned 2026-08-18, UNREVIEWED
 'hs_water_supervision': '6551a687ac0c906f', // pinned 2026-08-18, UNREVIEWED
 'hs_water_temp': 'f09440982ab1e938', // pinned 2026-08-18, UNREVIEWED
 'hs_window_locks': 'dfe7f05e34e3593c', // pinned 2026-08-18, UNREVIEWED
 'ill_care_fluids': '4b6480eabde145ce', // pinned 2026-08-18, UNREVIEWED
 'ill_care_light_clothing': 'fb2a4a6e27a3183e', // pinned 2026-08-18, UNREVIEWED
 'ill_care_medicine': 'bfe4876ab32e677d', // pinned 2026-08-18, UNREVIEWED
 'ill_care_rest': 'e33ccbbd64141f5d', // pinned 2026-08-18, UNREVIEWED
 'ill_care_title': '0f2eccabb82ccaa6', // pinned 2026-08-18, UNREVIEWED
 'ill_care_watch': '75da8911bca5dd9a', // pinned 2026-08-18, UNREVIEWED
 'ill_disclaimer': '107f3508a37c1d97', // pinned 2026-08-18, UNREVIEWED
 'ill_intro': '3eca65f7d4f3658d', // pinned 2026-08-18, UNREVIEWED
 'ill_title': '36da0751d9faf586', // pinned 2026-08-18, UNREVIEWED
 'ill_warn_breathing': 'c1ad319fa24effd3', // pinned 2026-08-18, UNREVIEWED
 'ill_warn_colour': '3e850378acdf1f9e', // pinned 2026-08-18, UNREVIEWED
 'ill_warn_dehydration': 'a1bf515669780053', // pinned 2026-08-18, UNREVIEWED
 'ill_warn_intro': '22addc596d625f16', // pinned 2026-08-18, UNREVIEWED
 'ill_warn_persistent': 'fd78b12deed234b2', // pinned 2026-08-18, UNREVIEWED
 'ill_warn_rash': '5d25fe28d1d7aa38', // pinned 2026-08-18, UNREVIEWED
 'ill_warn_seizure': '6927e2ece5e7ea66', // pinned 2026-08-18, UNREVIEWED
 'ill_warn_stiff_neck': '5da7133afcffbfd4', // pinned 2026-08-18, UNREVIEWED
 'ill_warn_title': 'dbb15d43065cc946', // pinned 2026-08-18, UNREVIEWED
 'ill_warn_unrousable': '936c0e1c327dade2', // pinned 2026-08-18, UNREVIEWED
 'ill_young_body': 'f2ecb5dc03ccd2b9', // pinned 2026-08-18, UNREVIEWED
 'ill_young_title': '229f5bdd2cbbd24e', // pinned 2026-08-18, UNREVIEWED
 'kick_goal_hits': '894aa4be4d4149c2', // REVIEWED + REWRITTEN 2026-08-19 (all three)
 'kick_goal_reached': '942b0082b689e064', // REVIEWED + REWRITTEN 2026-08-19 (all three)
 'kick_goal_reached_slow': '7331c5c534b66a1e', // pinned 2026-08-18, UNREVIEWED
 'kick_low_action': '00677ac9fd6a374c', // REVIEWED + REWRITTEN 2026-08-19 (ru/en); kk §9.12
 'kick_low_body': 'f9b753c88cc9fcdb', // pinned 2026-08-18, UNREVIEWED
 'kick_low_title': '53205632acef4748', // pinned 2026-08-18, UNREVIEWED
 'kick_method_note': 'd155042e2e0176d4', // pinned 2026-08-18, UNREVIEWED
 'lab_disclaimer': '54c64da980c9d072', // pinned 2026-08-18, UNREVIEWED
 'lab_go_bleeding': 'ad1b12c44c850771', // pinned 2026-08-18, UNREVIEWED
 'lab_go_five_one_one': 'cd3966cb6a5688e7', // pinned 2026-08-18, UNREVIEWED
 'lab_go_intro': '6e6d39e0d0d5f9a6', // pinned 2026-08-18, UNREVIEWED
 'lab_go_preterm': 'ccef88cc36018ea3', // pinned 2026-08-18, UNREVIEWED
 'lab_go_reduced_movements': '6fe6751cb16adf1c', // REVIEWED 2026-08-19, unchanged
 'lab_go_title': '9b2e311656851dea', // pinned 2026-08-18, UNREVIEWED
 'lab_go_unsure': '3c93e3451065ab15', // pinned 2026-08-18, UNREVIEWED
 'lab_go_waters_broke': '84678c997e2ab2e9', // pinned 2026-08-18, UNREVIEWED
 'lab_intro': '1853663aac4db948', // REVIEWED 2026-08-19; kk CHANGED, ru/en unchanged
 'lab_sign_backache': '5b414b65cdc7c1a2', // pinned 2026-08-18, UNREVIEWED
 'lab_sign_contractions': 'c23e35ce5f8b190d', // pinned 2026-08-18, UNREVIEWED
 'lab_sign_show': 'ecbb1aaae1d02845', // pinned 2026-08-18, UNREVIEWED
 'lab_sign_waters': '702bc38592e8684f', // pinned 2026-08-18, UNREVIEWED
 'lab_signs_title': 'c30d5ab9c989a925', // pinned 2026-08-18, UNREVIEWED
 'lab_title': '022f2ca03f991126', // pinned 2026-08-18, UNREVIEWED
 'legal_priv_medical_b': '2505787d13d65b87', // pinned 2026-08-18, UNREVIEWED
 'legal_priv_medical_h': '52f4d5134522e2ce', // pinned 2026-08-18, UNREVIEWED
 'legal_terms_emergency_b': 'a3ece82b152ce373', // pinned 2026-08-18, UNREVIEWED
 'legal_terms_emergency_h': '38f7a138ce3d3363', // pinned 2026-08-18, UNREVIEWED
 'legal_terms_medical_b': '3bab70a3633cfc70', // pinned 2026-08-18, UNREVIEWED
 'legal_terms_medical_h': '6e5fecd33114cadf', // pinned 2026-08-18, UNREVIEWED
 'med_disclaimer': '194d9c4bcebe875f', // pinned 2026-08-18, UNREVIEWED
 'phase_fertile_note': '245432b127095564', // pinned 2026-08-18, UNREVIEWED
 'pp_card_sub': '233e8c7afdb6db70', // pinned 2026-08-18, UNREVIEWED
 'pp_check_body': '3254acc73e6695c3', // pinned 2026-08-18, UNREVIEWED
 'pp_disclaimer': '8344b6fc13205d33', // pinned 2026-08-18, UNREVIEWED
 'pp_low_run_body': 'a8167812ae51d461', // pinned 2026-08-18, UNREVIEWED
 'pp_note_blues': '089d6a675b017148', // pinned 2026-08-18, UNREVIEWED
 'pp_note_clearance': '38707a6154bfabd0', // pinned 2026-08-18, UNREVIEWED
 'pp_note_contraception': '6c6d284d6e591992', // pinned 2026-08-18, UNREVIEWED
 'pp_note_gentle_moving': '6f96a0daca8dbdac', // pinned 2026-08-18, UNREVIEWED
 'pp_note_hydrate': '9984f68f757e1014', // pinned 2026-08-18, UNREVIEWED
 'pp_note_lochia_early': '29a1490d4fb5accd', // pinned 2026-08-18, UNREVIEWED
 'pp_note_lochia_fading': '9da5ede73e71404c', // pinned 2026-08-18, UNREVIEWED
 'pp_note_mood_check': '2d510542e58d219b', // pinned 2026-08-18, UNREVIEWED
 'pp_note_pelvic_floor': '2775e8e6f5310cfc', // pinned 2026-08-18, UNREVIEWED
 'pp_note_rest': '70fd3e1ca177d70a', // pinned 2026-08-18, UNREVIEWED
 'pp_note_soreness': '6008e49c3726de38', // pinned 2026-08-18, UNREVIEWED
 'pp_warn_bleeding': 'aa4ebc02825fe425', // pinned 2026-08-18, UNREVIEWED
 'pp_warn_calf': '380067490a0c0878', // pinned 2026-08-18, UNREVIEWED
 'pp_warn_discharge': '40eb6ada75005049', // pinned 2026-08-18, UNREVIEWED
 'pp_warn_fever': 'd3ba3ef742c28cfe', // pinned 2026-08-18, UNREVIEWED
 'pp_warn_harm': '4f5b5c3c6e342c9b', // pinned 2026-08-18, UNREVIEWED
 'pp_warn_headache': '5f5792e9f22cfae1', // pinned 2026-08-18, UNREVIEWED
 'pp_warn_intro': '7ecdf9b46ac51066', // pinned 2026-08-18, UNREVIEWED
 'pp_warn_title': '6914eeb032097df9', // pinned 2026-08-18, UNREVIEWED
 'pp_warn_wound': 'd63a342c90ad75fe', // pinned 2026-08-18, UNREVIEWED
 'preg_note_braxton': '46103387e05ac871', // pinned 2026-08-18, UNREVIEWED
 'preg_note_bump': '13e747a91f41d222', // pinned 2026-08-18, UNREVIEWED
 'preg_note_eating': '704ad27592429d7f', // pinned 2026-08-18, UNREVIEWED
 'preg_note_emotions': 'b581f92ffdd75be8', // pinned 2026-08-18, UNREVIEWED
 'preg_note_energy': 'd8c3458fe44c51bc', // pinned 2026-08-18, UNREVIEWED
 'preg_note_first_movements': 'd58600f93b538a5e', // pinned 2026-08-18, UNREVIEWED
 'preg_note_hospital_bag': '91daa4495f0a0753', // pinned 2026-08-18, UNREVIEWED
 'preg_note_ligament': 'e246b513fa1e6c6d', // pinned 2026-08-18, UNREVIEWED
 'preg_note_movement_pattern': 'ee9b59a8e6698efe', // REVIEWED 2026-08-19, unchanged
 'preg_note_nausea': '11cf281ad9eaa2d5', // pinned 2026-08-18, UNREVIEWED
 'preg_note_sleep_side': '0b08c836b73d1026', // pinned 2026-08-18, UNREVIEWED
 'preg_note_swelling': '9bd96a25d1697239', // pinned 2026-08-18, UNREVIEWED
 'preg_note_tired': '127f111cb6f49aa8', // pinned 2026-08-18, UNREVIEWED
 'preg_warn_bleeding': 'd3b057d202fbcbc4', // pinned 2026-08-18, UNREVIEWED
 'preg_warn_fever': 'bc0d53313eaa1e4f', // pinned 2026-08-18, UNREVIEWED
 'preg_warn_fluid': '34d3414265c6502a', // pinned 2026-08-18, UNREVIEWED
 'preg_warn_headache': '53e3de8ec43d6de0', // pinned 2026-08-18, UNREVIEWED
 'preg_warn_intro': 'cfd01f896b93e33f', // pinned 2026-08-18, UNREVIEWED
 'preg_warn_movement': 'fd623c43695b62de', // REVIEWED 2026-08-19, unchanged
 'preg_warn_pain': 'd0f5cf538886d7a8', // pinned 2026-08-18, UNREVIEWED
 'preg_warn_title': '594a6de5e2d23e2a', // pinned 2026-08-18, UNREVIEWED
 'pwg_band_normal': '39723b87b963dd24', // pinned 2026-08-18, UNREVIEWED
 'pwg_band_obese': '2ec3ec2b470b1e67', // pinned 2026-08-18, UNREVIEWED
 'pwg_band_overweight': '6be81a486338071b', // pinned 2026-08-18, UNREVIEWED
 'pwg_band_underweight': '85cf17006d37f1df', // pinned 2026-08-18, UNREVIEWED
 'pwg_disclaimer': 'c44635b752859b8f', // pinned 2026-08-18, UNREVIEWED
 'pwg_intro': '7ce265c6f189b083', // pinned 2026-08-18, UNREVIEWED
 'pwg_link': '7345b89ab76373e7', // pinned 2026-08-18, UNREVIEWED
 'pwg_no_data': '5d49e1f44c0b18e2', // pinned 2026-08-18, UNREVIEWED
 'pwg_pace_fast': 'f03a582632ebca12', // pinned 2026-08-18, UNREVIEWED
 'pwg_pace_onTrack': 'cc62a2097b0456de', // pinned 2026-08-18, UNREVIEWED
 'pwg_pace_slow': '4faa6156d887819b', // pinned 2026-08-18, UNREVIEWED
 'pwg_range_value': 'de02cbe001d34be2', // pinned 2026-08-18, UNREVIEWED
 'pwg_ranges_title': '94c08ac4aa3bc232', // pinned 2026-08-18, UNREVIEWED
 'pwg_title': 'fcfeb0c9e977d5b9', // pinned 2026-08-18, UNREVIEWED
 'pwg_weekly_body': '121eb22d5e94bfd4', // pinned 2026-08-18, UNREVIEWED
 'pwg_weekly_title': '2178831b9578d4f6', // pinned 2026-08-18, UNREVIEWED
 'pwg_your_avg': 'c0fab90e90fbfe00', // pinned 2026-08-18, UNREVIEWED
 'pwg_your_pace_title': '11c70698b2486cde', // pinned 2026-08-18, UNREVIEWED
 'repeat_body': '426b098885186992',
 // 'repeat_cta' was pinned here. The key was DELETED from the catalogue on the
 // gate’s instruction (2026-08-17) when hand entry went and its button had
 // nowhere to open; see the note at its old home in l10n.dart. Removed from the
 // manifest so the "manifest does not name keys that no longer exist" test
 // passes for the right reason. This is a deletion with a verdict behind it,
 // not a fingerprint updated to make a build green.
 'repeat_title_bp': 'f35ce10bc590bff2',
 'repeat_title_fever': '9d8dc7a70e85e6c2',
 'repeat_title_hr': '036817c5db1316f6',
 'repeat_title_spo2': '4c90c755871ae7b7',
 'set_about_body': '38acf6ec2f055442', // pinned 2026-08-18, UNREVIEWED
 'share_bp_cuff_only': '71fa80f31c5c67e0', // pinned 2026-08-18, UNREVIEWED
 'sol_avoid_choking': '2d3023760ea740dd', // pinned 2026-08-18, UNREVIEWED
 'sol_avoid_honey': '2d813c7ad7b6a7da', // pinned 2026-08-18, UNREVIEWED
 'sol_avoid_salt': 'cb6ed1b2a6bafb87', // pinned 2026-08-18, UNREVIEWED
 'sol_avoid_sugar': '740f43e4b1ad34d6', // pinned 2026-08-18, UNREVIEWED
 'sol_avoid_title': '7f0226dc9d4da830', // pinned 2026-08-18, UNREVIEWED
 'sol_card_sub': '33199ceadfe41ba1', // pinned 2026-08-18, UNREVIEWED
 'sol_card_title': '5b9bdb7918daa785', // pinned 2026-08-18, UNREVIEWED
 'sol_disclaimer': '1d887abcca5ce213', // pinned 2026-08-18, UNREVIEWED
 'sol_ready_interest': 'efbafafebaf6a737', // pinned 2026-08-18, UNREVIEWED
 'sol_ready_mouth': '9fb7025d4ff29327', // pinned 2026-08-18, UNREVIEWED
 'sol_ready_reflex': '8bc4f33dbef60bb7', // pinned 2026-08-18, UNREVIEWED
 'sol_ready_sits': 'c55691df2abdebb1', // pinned 2026-08-18, UNREVIEWED
 'sol_ready_title': '5f078c99aa0c7f9d', // pinned 2026-08-18, UNREVIEWED
 'sol_stage_allergens': '8f36680a575078ff', // pinned 2026-08-18, UNREVIEWED
 'sol_stage_family': '7670cf017b849e5e', // pinned 2026-08-18, UNREVIEWED
 'sol_stage_first_foods': '52995028fbee6524', // pinned 2026-08-18, UNREVIEWED
 'sol_stage_textures': '13925529a8fdebce', // pinned 2026-08-18, UNREVIEWED
 'sol_stage_title': '1f9d95e9882ac3b9', // pinned 2026-08-18, UNREVIEWED
 'sol_title': '5b9bdb7918daa785', // pinned 2026-08-18, UNREVIEWED
 'sol_until': '1bae3a8913f66448', // pinned 2026-08-18, UNREVIEWED
 'sol_when_body': 'e267a64a720fdd8e', // pinned 2026-08-18, UNREVIEWED
 'sol_when_title': 'd23ee168af6f6b65', // pinned 2026-08-18, UNREVIEWED
 'ss_avoid_title': 'fea24c8d89986880', // pinned 2026-08-18, UNREVIEWED
 'ss_back': '09339ba4d2e559fb', // pinned 2026-08-18, UNREVIEWED
 'ss_bedshare': 'dc60620898e91756', // pinned 2026-08-18, UNREVIEWED
 'ss_clear': '2e06c586bc02d8ab', // pinned 2026-08-18, UNREVIEWED
 'ss_disclaimer': '27e521e1e17d912f', // pinned 2026-08-18, UNREVIEWED
 'ss_do_title': '1cd287d4a8e3fdbe', // pinned 2026-08-18, UNREVIEWED
 'ss_firm': '261e39098213fc41', // pinned 2026-08-18, UNREVIEWED
 'ss_intro': '1dbe40a188a529e6', // pinned 2026-08-18, UNREVIEWED
 'ss_overheat': 'b5fa4bac279659f5', // pinned 2026-08-18, UNREVIEWED
 'ss_own_bed': '385bdd975e45050c', // pinned 2026-08-18, UNREVIEWED
 'ss_pacifier': 'a20db4d5c4b48d78', // pinned 2026-08-18, UNREVIEWED
 'ss_smoke': 'e39b647e5d09d107', // pinned 2026-08-18, UNREVIEWED
 'ss_soft': 'a62b5f960f99a35a', // pinned 2026-08-18, UNREVIEWED
 'ss_title': '4dbd3a319ee28f4d', // pinned 2026-08-18, UNREVIEWED
 'sup_chat_disclaimer': '7d919ed7bfab5c81', // pinned 2026-08-18, UNREVIEWED
 'teeth_disclaimer': 'f3a4b8649031f23a', // pinned 2026-08-18, UNREVIEWED
 'teeth_not_diarrhoea': 'a81b012512393e0f', // pinned 2026-08-18, UNREVIEWED
 'teeth_not_high_fever': '919290bd809e0a72', // pinned 2026-08-18, UNREVIEWED
 'teeth_not_intro': '1ec11e35a38b55bd', // pinned 2026-08-18, UNREVIEWED
 'teeth_not_title': '771dcdb16340435d', // pinned 2026-08-18, UNREVIEWED
 'temp_device_estimate_note': '74ffd269d07bdba2',
 'vac_adt': '0d64d911e53ad129', // pinned 2026-08-18, UNREVIEWED
 'vac_adt_note': 'a2ee1de3c9e0ad16', // pinned 2026-08-18, UNREVIEWED
 'vac_at_birth': '86243cd01c21d280', // pinned 2026-08-18, UNREVIEWED
 'vac_at_month': '7789c0b82edebc72', // pinned 2026-08-18, UNREVIEWED
 'vac_bcg': '8989452428713843', // pinned 2026-08-18, UNREVIEWED
 'vac_bcg_note': 'ee9f3215a2a69205', // pinned 2026-08-18, UNREVIEWED
 'vac_catchup': 'd55d6b057efb829f', // pinned 2026-08-18, UNREVIEWED
 'vac_complete': 'b77b128a96ec5305', // pinned 2026-08-18, UNREVIEWED
 'vac_disclaimer': '753996bb9732b4ea', // pinned 2026-08-18, UNREVIEWED
 'vac_dose': '78340876ab7c0a53', // pinned 2026-08-18, UNREVIEWED
 'vac_dtp': '799950c7d56e6815', // pinned 2026-08-18, UNREVIEWED
 'vac_dtp_note': '70c4f3afd66f036f', // pinned 2026-08-18, UNREVIEWED
 'vac_due': '94a1f2687be37034', // pinned 2026-08-18, UNREVIEWED
 'vac_hepb': 'f48decf2d33108b4', // pinned 2026-08-18, UNREVIEWED
 'vac_hepb_note': '043c67f33d7879fd', // pinned 2026-08-18, UNREVIEWED
 'vac_hib': 'ab0465a9ca14343e', // pinned 2026-08-18, UNREVIEWED
 'vac_hib_note': 'b5ba7ae1df042c10', // pinned 2026-08-18, UNREVIEWED
 'vac_in_months': '1c91b64e93e0ceec', // pinned 2026-08-18, UNREVIEWED
 'vac_mmr': '7d531a0c0fe8dad6', // pinned 2026-08-18, UNREVIEWED
 'vac_mmr_note': '409c6cb80a556d21', // pinned 2026-08-18, UNREVIEWED
 'vac_next': '45bcf61d5d69cf6a', // pinned 2026-08-18, UNREVIEWED
 'vac_opv': '8676144cfdd75a2c', // pinned 2026-08-18, UNREVIEWED
 'vac_opv_note': 'e4708a4d4b4c4539', // pinned 2026-08-18, UNREVIEWED
 'vac_passed': '456429f5f02b8522', // pinned 2026-08-18, UNREVIEWED
 'vac_pcv': 'f06014748001d59f', // pinned 2026-08-18, UNREVIEWED
 'vac_pcv_note': '8d4d9682316618ef', // pinned 2026-08-18, UNREVIEWED
 'vac_pentavalent': '1826d316883ce85f', // pinned 2026-08-18, UNREVIEWED
 'vac_pentavalent_note': '7dddd42538c1b29c', // pinned 2026-08-18, UNREVIEWED
 'vac_reminder_body': 'b4a4d33e284f8541', // pinned 2026-08-18, UNREVIEWED
 'vac_reminder_on': '8daa919477147b6d', // pinned 2026-08-18, UNREVIEWED
 'vac_reminder_title': 'b86e2874a90e11df', // pinned 2026-08-18, UNREVIEWED
 'vac_revision': '73164ab00b2d9660', // pinned 2026-08-18, UNREVIEWED
 'vac_source_server': 'a75e63b8a650eadc', // pinned 2026-08-18, UNREVIEWED
 'vac_sub': 'b9137e4bf557d718', // pinned 2026-08-18, UNREVIEWED
 'vac_title': '054868b429a134db', // pinned 2026-08-18, UNREVIEWED
 'visit_bp_cuff': 'edcbba5b3d82951d', // pinned 2026-08-18, UNREVIEWED
 'visit_disclaimer': '95f51a82f73b6274', // pinned 2026-08-18, UNREVIEWED
 'visit_temp_thermometer': '8c4659d4b6935417', // pinned 2026-08-18, UNREVIEWED
 'wm_off_wrist': '4a4957f194ef926b', // pinned 2026-08-18, UNREVIEWED
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
