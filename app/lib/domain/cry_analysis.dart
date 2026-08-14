/// Result of the baby-cry analysis service — the reason a cry most likely
/// signals, with a confidence and the full spread across reasons.
///
/// PURE Dart (parse + helpers) → verified by tool/verify_cry_analysis.dart.
///
/// Mirrors the JSON returned by the cry-classifier API
/// (packages/cry-classifier, POST /api/v1/predict-cry). The recommendation text
/// comes from the server already localized to Russian; the reason CODE is
/// localized in the app so the label matches the user's chosen language.
library;

/// How sure the classifier has to be before this app NAMES a reason.
///
/// Below it the screen says «не уверены», keeps the probability bars and asks
/// for another recording. Naming «голод» at 31 % reads to a mother exactly like
/// naming it at 91 %, and this is a screen somebody opens at 3am while deciding
/// whether to feed a baby who is actually in pain.
///
/// This is the SHIPPED DEFAULT, mirrored from the backend's
/// `CRY_MIN_CONFIDENCE_DEFAULT` (packages/backend/src/cry/settings.ts). The
/// number in force comes from `GET /protocols/cry` — see
/// data/cry_settings_repository.dart — so the back office can move it without a
/// release. This constant is what a phone with no signal applies, which is a
/// threshold rather than none.
const kCryMinConfidenceDefault = 0.45;

/// The two answers to «Это было верно?». Wire values — the backend stores these
/// exact strings in `cry_results.verdict`.
class CryVerdict {
  static const correct = 'correct';
  static const wrong = 'wrong';
  const CryVerdict._();
}

/// The five reasons the classifier distinguishes. Kept as an enum so the UI can
/// switch on them exhaustively and localize each; [code] is the wire value.
enum CryReason {
  hungry('hungry'),
  tired('tired'),
  bellyPain('belly_pain'),
  discomfort('discomfort'),
  burping('burping');

  const CryReason(this.code);
  final String code;

  /// The reason for a wire code, or null if unknown (a server that added a
  /// class the app doesn't know yet — shown generically rather than crashing).
  static CryReason? fromCode(String code) {
    for (final r in CryReason.values) {
      if (r.code == code) return r;
    }
    return null;
  }
}

class CryAnalysis {
  /// The wire code of the most likely reason (e.g. 'hungry').
  final String primaryReason;

  /// 0..1 confidence in the primary reason.
  final double confidence;

  /// Percentage (0..100) for every reason code the server returned.
  final Map<String, int> probabilities;

  /// Ready-to-show recommendation, already in Russian (from the server).
  final String recommendationRu;

  const CryAnalysis({
    required this.primaryReason,
    required this.confidence,
    required this.probabilities,
    required this.recommendationRu,
  });

  /// The primary reason as an enum, or null when the server sent an unknown code.
  CryReason? get reason => CryReason.fromCode(primaryReason);

  /// Confidence as a whole percentage (0..100), for display.
  int get confidencePct => (confidence * 100).round().clamp(0, 100);

  /// Reasons sorted by probability, highest first — for a ranked bar list.
  List<MapEntry<String, int>> get ranked {
    final entries = probabilities.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  factory CryAnalysis.fromJson(Map<String, dynamic> j) {
    final probsRaw = (j['probabilities'] as Map?)?.cast<String, dynamic>() ?? const {};
    final probs = <String, int>{};
    probsRaw.forEach((k, v) {
      if (v is num) probs[k] = v.round();
    });
    return CryAnalysis(
      primaryReason: (j['primary_reason'] as String?) ?? '',
      confidence: (j['confidence'] as num?)?.toDouble() ?? 0.0,
      probabilities: probs,
      recommendationRu: (j['recommendation_ru'] as String?) ?? '',
    );
  }
}

/// One saved cry-analysis result, for the "recent analyses" history. Compact on
/// purpose — the reason + confidence + when — so persisting a run of them is
/// cheap; the full probability spread and recommendation are re-derivable and
/// not worth storing.
class CryResult {
  final String reason; // the wire code, e.g. 'hungry'
  final double confidence; // 0..1
  final DateTime at;

  /// Her own answer to «Это было верно?» — [CryVerdict.correct] / `.wrong`, or
  /// null while she has not said.
  ///
  /// Null is a THIRD state, never «неверно»: it is the only honest reading of
  /// an unanswered question, and the back office counts it as unknown.
  final String? verdict;

  /// What it actually was, when she said «нет» and picked one. A wire reason
  /// code, or null — «не знаю» is a legitimate answer and must not be forced
  /// into one of the five.
  final String? actualReason;

  const CryResult({
    required this.reason,
    required this.confidence,
    required this.at,
    this.verdict,
    this.actualReason,
  });

  /// Save the primary outcome of an [analysis], stamped at [at].
  factory CryResult.from(CryAnalysis a, DateTime at) =>
      CryResult(reason: a.primaryReason, confidence: a.confidence, at: at);

  /// The same analysis with her verdict on it. `actualReason` is dropped for a
  /// «верно», where the stored reason already IS the answer.
  CryResult rated(String verdict, {String? actualReason}) => CryResult(
        reason: reason,
        confidence: confidence,
        at: at,
        verdict: verdict,
        actualReason: verdict == CryVerdict.wrong ? actualReason : null,
      );

  /// The reason as an enum, or null when it is a code the app doesn't know.
  CryReason? get reasonEnum => CryReason.fromCode(reason);
  int get confidencePct => (confidence * 100).round().clamp(0, 100);

  /// Whether the app may NAME this result's reason, or must say «не уверены».
  bool namesReasonAt(double minConfidence) => confidence >= minConfidence;

  Map<String, dynamic> toJson() => {
        'reason': reason,
        'confidence': confidence,
        'at': at.toIso8601String(),
        // Omitted when absent, so a history written by an older build and one
        // written by this one decode to the same thing.
        if (verdict != null) 'verdict': verdict,
        if (actualReason != null) 'actualReason': actualReason,
      };

  factory CryResult.fromJson(Map<String, dynamic> j) {
    final conf = j['confidence'];
    final at = j['at'];
    final v = j['verdict'];
    final actual = j['actualReason'] ?? j['actual_reason']; // server spells it with an underscore
    return CryResult(
      reason: (j['reason'] as String?) ?? '',
      confidence: conf is num ? conf.toDouble() : 0.0, // tolerate a non-numeric value
      at: at is String ? (DateTime.tryParse(at) ?? DateTime.fromMillisecondsSinceEpoch(0)) : DateTime.fromMillisecondsSinceEpoch(0),
      // Only the two words this app understands. A third value from a future
      // server reads as "not rated" rather than being shown as a tick.
      verdict: v == CryVerdict.correct || v == CryVerdict.wrong ? v as String : null,
      actualReason: actual is String && actual.isNotEmpty ? actual : null,
    );
  }
}
