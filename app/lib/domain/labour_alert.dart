/// The «пора ехать в роддом» card — BUILT, WIRED, AND DELIBERATELY SILENT
/// until the clinical gate rules on it.
///
/// PURE Dart. No copy lives here, and no threshold does either. That is the
/// whole design, and it is the `advisory_layout.dart` pattern applied to a
/// sentence that is much more dangerous than a card layout.
///
/// WHAT THIS SENTENCE IS
///
/// `docs/CLAUDE-app-design.md`, frame 10, asks for a night plate reading
/// «по минуте каждые 5 минут в течение часа — пора в роддом». That is the
/// 5-1-1 rule, and it is not a label: it is an instruction telling a woman in
/// labour when to leave her house, at the moment she is least able to
/// second-guess it. Getting it wrong in either direction is a harm — too eager
/// sends her to be turned away in early labour, too slow is a birth in a car.
///
/// WHY IT IS NOT IN THE CATALOGUE
///
/// `docs/CLINICAL-REVIEW-WATCH.md` has NO ruling on contractions. Grep it: the
/// document covers heart rate, SpO2, blood pressure, temperature and glucose,
/// and says nothing about labour. So this sentence has never been reviewed, in
/// any language, and a designer or an engineer is not the person who gets to
/// decide it ships. An unreviewed sentence that exists only as a task
/// description is exactly the thing this repo has shipped twice and had to
/// withdraw.
///
/// The l10n catalogue is the surface `reviewed_medical_copy_test` guards, so
/// the sentence is kept OUT of the catalogue entirely rather than added and
/// hidden behind a flag. A string in `l10n.dart` is one `if` away from a
/// screen; a string that does not exist is not.
///
/// WHAT SHIPS TODAY INSTEAD
///
/// The 5-1-1 CHECKLIST that is already on the screen: three criteria, each
/// ticked as the timed pattern meets it, under «не медицинский совет. Всегда
/// следуйте рекомендациям своего врача». It describes her own data back to her
/// and gives no instruction. That is the honest default — less useful than the
/// directive, and true.
///
/// HOW THE GATE TURNS THIS ON
///
/// One verdict produces three things, and all three are needed:
///
///   1. the wording, in ru + kk + en, added to `l10n.dart` and pinned in
///      `reviewed_medical_copy_test.dart`'s manifest with the verdict recorded;
///   2. the key name, put in [labourAlertBodyKey] below;
///   3. the threshold — which is NOT necessarily 5-1-1 as taught abroad. The
///      RK protocol is the source this product cites, and whether it says the
///      same thing is a question for the gate, not an assumption for us.
///
/// No widget code changes. The card is built and calls [labourAlertBodyKey]
/// every rebuild; it renders nothing while that is null.
library;

import 'contraction.dart';

/// The l10n key of the REVIEWED directive body, or null while unreviewed.
///
/// NULL UNTIL THE CLINICAL GATE RULES. See the library note above.
///
/// The shape a verdict takes, deliberately commented out rather than guessed:
///
///   const String? labourAlertBodyKey = 'contr_go_in_b';
///
/// …which would also require that key to exist in all three languages and to
/// carry a fingerprint in the reviewed manifest. Setting this to a key that is
/// not in the manifest fails `labour_alert_gate_test.dart`, on purpose: the two
/// halves cannot be landed separately.
const String? labourAlertBodyKey = null;

/// Whether the directive card should be shown for [progress].
///
/// Two conditions, and BOTH are gates:
///
///   * the copy has been reviewed ([labourAlertBodyKey] is set), and
///   * the pattern the gate named is met.
///
/// [FivOneOneProgress.allMet] is used as the pattern for now because it is the
/// only measured pattern this screen has. If the gate names a different
/// threshold — a different interval, a different window, a minimum count — it
/// replaces this expression, and that is a one-line change here rather than a
/// hunt through the widget tree.
bool showLabourAlert(FivOneOneProgress progress) =>
    labourAlertBodyKey != null && progress.allMet;
