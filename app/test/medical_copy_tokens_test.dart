/// The words a reviewed medical claim cannot lose, in every language it ships in.
///
/// Asked for by the clinical gate on 2026-08-17, after this was found in
/// production:
///
///   RU  «Это оценка датчика на запястье, А НЕ ИЗМЕРЕНИЕ»
///   KK  «...нақты өлшем емес»          =  "not an ACCURATE measurement"
///
/// The Russian denies the number is a measurement. The Kazakh conceded that it
/// IS one and disputed only its precision — and that denial is the whole card:
/// both device rulings rest on the sensor value not BEING the quantity. A
/// clinical claim was reviewed in Russian and shipped in two languages.
///
/// WHY THE OTHER GUARDS DID NOT CATCH IT, and why this file is a different
/// shape from both of them:
///
///   * `verify_l10n`'s kk≠ru check catches a COPY-PASTE. These strings were not
///     copy-pasted; they were translated, and the translation conceded
///     something. The gate's instruction was explicit: do not grow that check
///     toward semantics. `vac_hib` is the proof it cannot go there — a Russian
///     «(ревакцинация)» inside an otherwise-Kazakh string was invisible to it
///     because the rest of the string differed.
///   * `refused_sentences_test` is a deny-list over the WHOLE catalogue. It
///     answers "has a refused sentence re-entered anywhere". It cannot express
///     "this particular key must still contain this particular word".
///
/// So this is the third shape: per key, per language, the load-bearing tokens —
/// the ones whose removal changes the claim. The gate names them when it
/// approves; they are transcribed here with the reason.
///
/// WHAT IT CANNOT DO. It cannot read Kazakh. A reviewer who replaces a whole
/// sentence with a different one that happens to contain these words still
/// passes. It pins the load-bearing WORDS of copy a clinician has already read;
/// it does not review copy. New medical copy still goes to the gate.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/l10n/l10n.dart';

/// What one language of one reviewed key must, and must not, contain.
class _Pin {
  final List<String> must;
  final List<String> mustNot;
  final String why;
  const _Pin({this.must = const [], this.mustNot = const [], required this.why});
}

/// key → locale → pin. Transcribed from the gate's verdicts in
/// `docs/CLINICAL-REVIEW-WATCH.md`; every entry cites the ruling it comes from.
const _pins = <String, Map<AppLocale, _Pin>>{
  // ---- The two device cards. "Device temperature — closed 2026-08-13",
  //      "Device blood pressure — closed 2026-08-14", and the Kazakh
  //      correction of 2026-08-17. -------------------------------------------
  'ADV_TEMP_DEVICE_HIGH_b': {
    AppLocale.ru: _Pin(
      must: ['а не измерение', 'на запястье', 'термометром'],
      why: 'the card denies that the number is a measurement at all; the '
          'instrument and its site are named deliberately, and the whole '
          'instruction is to reach the one instrument this product may act on',
    ),
    AppLocale.kk: _Pin(
      must: ['өлшем емес', 'білезік', 'термометр'],
      // The defect, verbatim. `нақты өлшем емес` = "not an ACCURATE
      // measurement" — it concedes the category. `қолыңыздағы` = hand/arm,
      // which loses the wrist. `білек` is the forearm and would repeat it.
      mustNot: ['нақты өлшем', 'қолыңыздағы', 'білек '],
      why: 'the 2026-08-17 correction. Re-adding нақты, дәл or толық here is '
          'the defect returning and the gate has refused it in advance',
    ),
  },
  'ADV_BP_DEVICE_HIGH_b': {
    AppLocale.ru: _Pin(
      must: ['а не измерение', 'на запястье', 'тонометром', '103'],
      // 140/90 is cited to ACOG and may appear beside a CUFF reading. Beside a
      // wrist estimate it invites the comparison the estimate cannot support —
      // refused sentence #20. 135/85 fire the card and are cited nowhere.
      mustNot: ['140', '90', '135', '85'],
      why: 'refused #20: numeric permission follows the SOURCE, not the metric. '
          'The device card carries no threshold in any language',
    ),
    AppLocale.kk: _Pin(
      must: ['өлшем емес', 'білезік', 'тонометр', '103'],
      mustNot: ['нақты өлшем', 'қолыңыздағы', '140', '90', '135', '85'],
      why: 'as above, plus the 2026-08-17 correction',
    ),
  },
  // Titles ship ALONE through the clipboard export, so tense is the only
  // temporal information they carry. «көрсетті» (showed) reads as a closed
  // episode — a warning that reads as concluded is a warning weakened, and
  // weakened only for Kazakh readers. Bare `көрсетеді` is refused too: the
  // aorist reads habitual, a claim about what sensors do in general.
  'ADV_TEMP_DEVICE_HIGH': {
    AppLocale.kk: _Pin(
      must: ['көрсетіп тұр'],
      mustNot: ['көрсетті'],
      why: 'the title tense, ruled a defect rather than a nit on 2026-08-17',
    ),
  },
  'ADV_BP_DEVICE_HIGH': {
    AppLocale.kk: _Pin(
      must: ['көрсетіп тұр'],
      mustNot: ['көрсетті'],
      why: 'the same title-tense ruling as the temperature card: a past tense '
          'reads as a closed episode on a warning that is about a reading '
          'standing now, and the title travels without its body',
    ),
  },

  // ---- The note that deliberately KEEPS the word deleted two keys away. ----
  // Stated as a pin precisely so nobody "harmonises" it after seeing `нақты`
  // removed from the device cards. This sentence is a claim about the
  // THERMOMETER — the opposite construction to the defect.
  'temp_device_estimate_note': {
    AppLocale.kk: _Pin(
      must: ['Нақты дене қызуын тек термометр'],
      why: 'the opposite construction to the 2026-08-17 defect, and the gate '
          'ordered it kept',
    ),
  },

  // ---- The reassurance whose third sentence is the clinically load-bearing
  //      one. "The absorber rule — 2026-08-14". ------------------------------
  'ADV_NOTHING_UNUSUAL_b': {
    AppLocale.ru: _Pin(
      must: ['врачу'],
      why: 'the third sentence — tell your doctor if you feel unwell, whatever '
          'the numbers show — is what stops the reassurance outranking her own '
          'symptoms. It is the reason the card was approvable',
    ),
    AppLocale.kk: _Pin(
      must: ['дәрігерге'],
      why: 'as above; the Kazakh read back clean on 2026-08-17 and is pinned '
          'so it stays that way',
    ),
  },

  // ---- The two "nothing to report" cards. Approved 2026-08-17 (ru, kk, en).
  //      Their closing sentence is the SAME sentence as the one above, word for
  //      word, in all three languages: it is the counterweight that stops a
  //      card about MISSING data from reading as an all-clear. --------------
  'ADV_GATHERING_b': {
    AppLocale.ru: _Pin(
      must: ['врачу'],
      // The refused version: «Наденьте браслет — советы появятся после
      // нескольких измерений.» A band upsell shown to a woman who types her
      // readings by hand, plus a promise that advice arrives once she owns the
      // hardware. The dashboard's empty state had this exact sentence family
      // removed for the same reason — «Апселла браслета здесь нет».
      mustNot: ['браслет', 'появятся'],
      why: 'the 2026-08-17 replacement: no band upsell, no promise of future '
          'advice, and the closing sentence that keeps the card from being read '
          'as an all-clear',
    ),
    AppLocale.kk: _Pin(
      must: ['дәрігерге'],
      mustNot: ['білезік', 'пайда болады'],
      why: 'as above; білезік is the word the Kazakh app uses for the band, so '
          'its absence is what proves the upsell is gone',
    ),
    AppLocale.en: _Pin(
      must: ['doctor'],
      mustNot: ['band', 'will appear'],
      why: 'as the Russian: the upsell and the promise of future advice are '
          'both gone, and the closing sentence stays',
    ),
  },
  'ADV_NO_CURRENT_READINGS_b': {
    AppLocale.ru: _Pin(
      must: ['врачу'],
      why: 'the card says her readings are out of date; without the closing '
          'sentence an absence of data reads as an absence of trouble',
    ),
    AppLocale.kk: _Pin(
      must: ['дәрігерге'],
      why: 'the Kazakh carries the same closing sentence as the Russian, and '
          'it is the one part of this card that is a clinical instruction',
    ),
    AppLocale.en: _Pin(
      must: ['doctor'],
      why: 'the English carries the same closing sentence, which is what stops '
          'the card being read as an all-clear by a stranger it is forwarded to',
    ),
  },
};

void main() {
  test('every reviewed medical string still carries its load-bearing words', () {
    final broken = <String>[];
    for (final entry in _pins.entries) {
      for (final loc in entry.value.entries) {
        final text = L10n(loc.key).t(entry.key);
        for (final m in loc.value.must) {
          if (!text.contains(m)) {
            broken.add('${entry.key} [${loc.key.name}] LOST «$m» — ${loc.value.why}');
          }
        }
        for (final m in loc.value.mustNot) {
          if (text.contains(m)) {
            broken.add('${entry.key} [${loc.key.name}] REGAINED «$m» — ${loc.value.why}');
          }
        }
      }
    }
    expect(
      broken,
      isEmpty,
      reason: 'Reviewed medical copy changed in a way that alters the claim:\n'
          '${broken.join('\n')}\n\n'
          'These words were named by the clinical gate when it approved the '
          'string. Do not adjust the pin to match new copy — take the new copy '
          'back to the gate. See docs/CLINICAL-REVIEW-WATCH.md.',
    );
  });

  test('the pins actually resolve to real strings', () {
    // The failure mode every guard in this repo has had: matching nothing and
    // looking exactly like a pass. If a key is renamed, `t()` returns the key
    // itself, and every `must` would fail loudly — but a `mustNot`-only entry
    // would silently pass forever.
    for (final entry in _pins.entries) {
      for (final loc in entry.value.entries) {
        final text = L10n(loc.key).t(entry.key);
        expect(text, isNot(equals(entry.key)),
            reason: '${entry.key} [${loc.key.name}] is not in the catalogue — '
                'the pin below it is asserting nothing');
        expect(text.length, greaterThan(10),
            reason: '${entry.key} [${loc.key.name}] resolved to something too '
                'short to be the reviewed sentence');
      }
    }
  });

  test('every pin carries a reason', () {
    // A pin without a reason is a rule nobody can evaluate: whoever trips it
    // cannot tell whether the copy is wrong or the pin is stale.
    for (final entry in _pins.entries) {
      for (final loc in entry.value.entries) {
        expect(loc.value.why.length, greaterThan(20),
            reason: '${entry.key} [${loc.key.name}] has no reason recorded');
        expect(loc.value.must.isNotEmpty || loc.value.mustNot.isNotEmpty, isTrue,
            reason: '${entry.key} [${loc.key.name}] pins nothing');
      }
    }
  });
}
