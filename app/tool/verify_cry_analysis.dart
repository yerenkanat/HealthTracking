/// Pure-Dart verification of the cry-analysis model (parsing + helpers).
/// `dart run tool/verify_cry_analysis.dart`
///
/// The model is the boundary with a separate service, so parsing must be
/// tolerant: unknown reason codes, missing fields and non-numeric probabilities
/// must degrade rather than throw, since a crash here would take down the whole
/// screen over one odd field.
library;

import 'dart:io';
import '../lib/domain/cry_analysis.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  final a = CryAnalysis.fromJson({
    'status': 'success',
    'primary_reason': 'hungry',
    'confidence': 0.84,
    'probabilities': {'hungry': 84, 'tired': 10, 'belly_pain': 4, 'discomfort': 2, 'burping': 0},
    'recommendation_ru': 'Покормите малыша.',
  });
  _chk('parses primary reason', a.primaryReason == 'hungry');
  _chk('primary maps to enum', a.reason == CryReason.hungry);
  _chk('confidence percent rounds', a.confidencePct == 84);
  _chk('recommendation carried through', a.recommendationRu == 'Покормите малыша.');
  _chk('all five probabilities parsed', a.probabilities.length == 5);
  _chk('ranked is sorted high→low', a.ranked.first.key == 'hungry' && a.ranked.last.value == 0);

  // Tolerance: missing fields, unknown code, non-numeric probability.
  final b = CryAnalysis.fromJson({
    'primary_reason': 'sleepy_unknown',
    'probabilities': {'hungry': 50, 'weird': 'x'},
  });
  _chk('unknown reason code → null enum', b.reason == null);
  _chk('missing confidence defaults to 0', b.confidencePct == 0);
  _chk('non-numeric probability dropped', !b.probabilities.containsKey('weird'));
  _chk('numeric probability kept', b.probabilities['hungry'] == 50);
  _chk('missing recommendation → empty', b.recommendationRu.isEmpty);

  // Confidence clamps into 0..100.
  final c = CryAnalysis.fromJson({'confidence': 1.5});
  _chk('confidence over 1 clamps to 100', c.confidencePct == 100);

  // fromCode round-trips every known reason.
  var allCodes = true;
  for (final r in CryReason.values) {
    if (CryReason.fromCode(r.code) != r) allCodes = false;
  }
  _chk('fromCode round-trips every reason', allCodes);

  // ---- Кадр 17c: the threshold and the verdict ------------------------------
  //
  // The threshold rule is a pure predicate, and it decides whether a mother is
  // told a reason at all — so it is verified here rather than only through the
  // widget that reads it.
  final low = CryResult(reason: 'hungry', confidence: 0.31, at: DateTime.utc(2026, 8, 10));
  final high = CryResult(reason: 'hungry', confidence: 0.82, at: DateTime.utc(2026, 8, 10));
  _chk('below the threshold names no reason', !low.namesReasonAt(kCryMinConfidenceDefault));
  _chk('above it does', high.namesReasonAt(kCryMinConfidenceDefault));
  // Exactly AT the threshold counts as sure: the panel's field says «порог», and
  // a boundary that excluded its own value would make 45 % mean 46 %.
  _chk('the boundary itself is sure',
      CryResult(reason: 'x', confidence: 0.45, at: DateTime.utc(2026)).namesReasonAt(0.45));
  _chk('the shipped default matches the backend constant', kCryMinConfidenceDefault == 0.45);

  final wrong = high.rated(CryVerdict.wrong, actualReason: 'belly_pain');
  _chk('a wrong verdict keeps what it actually was', wrong.actualReason == 'belly_pain');
  _chk('rating does not rewrite the analysis', wrong.reason == 'hungry' && wrong.at == high.at);
  // «Верно» means "the stored reason was right", so a second reason beside it
  // would be a row saying two different things about one cry.
  _chk('a correct verdict carries no actual reason',
      high.rated(CryVerdict.correct, actualReason: 'tired').actualReason == null);
  final back = CryResult.fromJson(wrong.toJson());
  _chk('the verdict survives a JSON round trip',
      back.verdict == CryVerdict.wrong && back.actualReason == 'belly_pain');
  _chk('a history written before verdicts existed reads as unrated',
      CryResult.fromJson({'reason': 'hungry', 'confidence': 0.8, 'at': '2026-08-10T00:00:00.000Z'})
              .verdict ==
          null);
  _chk('a verdict word this build does not know is not shown as an answer',
      CryResult.fromJson({'reason': 'hungry', 'confidence': 0.8, 'at': '2026-08-10T00:00:00.000Z', 'verdict': 'partly'})
              .verdict ==
          null);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
