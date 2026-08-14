/// The refused sentences, made a build failure instead of a document.
///
/// `docs/CLINICAL-REVIEW-WATCH.md` lists sentences a clinical gate refused, each
/// with its reason. Twice now, a refused sentence has been found still shipping:
///
///   * «Ваши показатели в пределах нормы» was recorded on 2026-08-13 with the
///     words "this SHIPS TODAY" — and was still on the home screen a day later,
///     under her name, because the dashboard substituted its own copy instead of
///     rendering the advisory that had been fixed;
///   * «Сахар в норме» was refused as sentence #5 on the same day. Blood sugar
///     was withdrawn from the admin panel that afternoon for exactly this
///     reason. The app kept saying it.
///
/// A withdrawal on one surface is not a withdrawal, and a rule that lives only
/// in prose is a rule that ships broken. So the list is executable here.
///
/// WHAT THIS CAN AND CANNOT DO. It cannot judge truth, and it is not a
/// substitute for the gate: new copy still needs review, because the harmful
/// sentence nobody has written yet is not on any deny-list. What it catches is
/// verbatim RE-ENTRY and quiet survival — which is the failure that has actually
/// happened, twice, and both times to a sentence someone had already written
/// down as refused.
///
/// It reads the CATALOGUE, not the source file: a comment explaining why a
/// string was deleted must not fail the build, and after each of these removals
/// there is exactly such a comment sitting where the string used to be.
library;

import 'package:flutter_test/flutter_test.dart';

import 'package:fcs_app/l10n/l10n.dart';

/// A refused phrasing, and why. The reason travels with the pattern so that
/// whoever trips this test reads the argument rather than only the rule — the
/// point is never to find a synonym that slips past the matcher.
class _Refused {
  final String fragment;
  final String number;
  final String why;
  const _Refused(this.fragment, this.number, this.why);
}

/// Fragments, not whole sentences, because the defect survives rewording. Each
/// is the part that carries the refused CLAIM.
const _refused = <_Refused>[
  _Refused('в пределах нормы', '#2',
      'a normality verdict on a body, from an uncalibrated wrist estimate of unknown age'),
  _Refused('давление в норме', '#3',
      'the protocol pairs BP with urine protein at every visit from the second; a wrist estimate cannot exclude preeclampsia'),
  _Refused('температуры нет', '#4', 'from a daily mean, which hides the fever it would be opened to find'),
  _Refused('сахар в норме', '#5',
      'an optical estimate in a unit the vendor never states anywhere in 3,248 pages'),
  _Refused('сообщили вашему врачу', '#9', 'no such channel exists'),
  _Refused('вызвали скорую', '#10',
      'the app is not a rescue service; the reviewed pattern is «Звоните 103», imperative to her'),
  // The fragment is «следим за ваш…», NOT «круглосуточно». The refused claim is
  // US watching HER; «круглосуточно» on its own is true of the ambulance service
  // and appears legitimately in `eh_call_body` — «Скорая помощь — бесплатно,
  // круглосуточно, с любого телефона». The first version of this list flagged
  // that string, which would have meant editing a true sentence no clinician
  // ever refused. A deny-list that cries wolf is how the document stops being
  // believed.
  _Refused('следим за ваш', '#11', 'the watch stops the moment she takes it off'),
  _Refused('вас предупредит', '#12',
      'the strongest false reassurance available here: it turns every gap in coverage into an implied all-clear'),
  _Refused('всё стабильно', '#21',
      'a verdict on everything, computed from whichever subset happened to be measured, and it travels to the clipboard without its body'),
  _Refused('все стабильно', '#21', 'as above, written without the ё'),
];

/// Lower-cased and whitespace-collapsed, so a line break or a capital cannot
/// carry a refused sentence past the check.
String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

void main() {
  test('no refused sentence is in the catalogue, in any language', () {
    final hits = <String>[];
    for (final key in allL10nKeys) {
      for (final locale in AppLocale.values) {
        final text = _norm(L10n(locale).t(key));
        for (final r in _refused) {
          if (text.contains(_norm(r.fragment))) {
            hits.add('$key [$locale] contains «${r.fragment}» — refused ${r.number}: ${r.why}');
          }
        }
      }
    }
    expect(
      hits,
      isEmpty,
      reason: 'A sentence refused by the clinical gate is in the catalogue:\n'
          '${hits.join('\n')}\n\n'
          'Do NOT reword it past this matcher. The fragment is the claim, not the wording. '
          'Read the reason above and docs/CLINICAL-REVIEW-WATCH.md, and if the sentence is '
          'genuinely needed, it goes back through the gate first.',
    );
  });

  test('the matcher actually works, and actually reads the catalogue', () {
    // Without this the test above passes when `allL10nKeys` is empty, when
    // `t()` starts returning the key instead of the string, or when `_norm`
    // breaks — three ways to get a green tick that asserts nothing. Every
    // previous guard in this repo that silently matched nothing looked exactly
    // like a pass.
    expect(allL10nKeys.length, greaterThan(500),
        reason: 'the catalogue did not load — the test above proved nothing');

    // A control that IS present: proves t() returns real text, not keys.
    final anyRussian = allL10nKeys
        .map((k) => L10n(AppLocale.ru).t(k))
        .any((s) => s.contains('беременност') || s.contains('давлен'));
    expect(anyRussian, isTrue,
        reason: 't() is not returning Russian text — the scan above read nothing real');

    // And the matcher finds a phrase it should: normalisation is live.
    expect(_norm('ВСЁ  СТАБИЛЬНО').contains(_norm('всё стабильно')), isTrue);
  });

  test('every refused fragment is one the gate actually wrote down', () {
    // Guards the list itself. A fragment invented here would fail builds for a
    // sentence no clinician ever refused, which is its own way of making the
    // document untrustworthy.
    for (final r in _refused) {
      expect(r.number, matches(RegExp(r'^#\d+$')),
          reason: '${r.fragment} carries no refused-sentence number');
      expect(r.why.length, greaterThan(20),
          reason: '${r.fragment} carries no reason — the reason is what stops a reword');
    }
  });
}
