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

  const CryResult({required this.reason, required this.confidence, required this.at});

  /// Save the primary outcome of an [analysis], stamped at [at].
  factory CryResult.from(CryAnalysis a, DateTime at) =>
      CryResult(reason: a.primaryReason, confidence: a.confidence, at: at);

  /// The reason as an enum, or null when it is a code the app doesn't know.
  CryReason? get reasonEnum => CryReason.fromCode(reason);
  int get confidencePct => (confidence * 100).round().clamp(0, 100);

  Map<String, dynamic> toJson() => {
        'reason': reason,
        'confidence': confidence,
        'at': at.toIso8601String(),
      };

  factory CryResult.fromJson(Map<String, dynamic> j) {
    final conf = j['confidence'];
    final at = j['at'];
    return CryResult(
      reason: (j['reason'] as String?) ?? '',
      confidence: conf is num ? conf.toDouble() : 0.0, // tolerate a non-numeric value
      at: at is String ? (DateTime.tryParse(at) ?? DateTime.fromMillisecondsSinceEpoch(0)) : DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
