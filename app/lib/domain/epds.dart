/// The Edinburgh Postnatal Depression Scale (EPDS) — the screening half of the
/// postpartum screen.
///
/// PURE Dart → verified by tool/verify_epds.dart.
///
/// WHY THIS EXISTS
///
/// `postpartum.dart` already carries the calm half: what is ordinary around
/// now, and a warning list that points outward. What it cannot do is notice.
/// Postnatal depression is the most under-recognised postpartum complication,
/// and the woman living inside it is the last person able to see the slope she
/// is on — «мне просто тяжело» is what four low weeks in a row feel like from
/// the inside. The app already holds her own mood entries; not reading them is
/// the difference between a diary and a companion.
///
/// WHAT THIS IS, AND IS NOT
///
/// The EPDS is a SCREENING questionnaire, not a diagnostic test. Nothing here —
/// not the total, not the band, not a single string this file names — is a
/// diagnosis, and nothing in the UI built on it may print one. The one thing a
/// score is allowed to do is send her to a real clinician, which is exactly
/// what `postpartum.dart`'s warning list already does.
///
/// TWO HONESTIES THAT ARE NOT NEGOTIABLE
///
///   1. **Item 10 outranks the total.** Question 10 asks about thoughts of
///      self-harm. Any answer above "never" routes outward on its own, whatever
///      the total says — a woman can score 6 and still be the one this whole
///      screen exists for. See [flaggedSelfHarm].
///   2. **Only the score, the band and the date are ever stored.** The ten
///      answers are never persisted, never pushed, never shown to staff. An
///      answer to item 10 sitting in a database is a disclosure she did not
///      consent to and cannot take back, and the back office has no use for it
///      that outweighs that. [EpdsResult] has no field to put it in, so nothing
///      downstream can leak what it never received.
///
/// THE KAZAKH RENDERING IS A SCREENING AID, NOT A VALIDATED INSTRUMENT
///
/// The EPDS is validated per language: its thresholds come from studies of a
/// specific translation in a specific population. This app ships a Kazakh
/// rendering that has not been through that, so the Kazakh (and Russian) UI must
/// present it as a self-check that helps her decide whether to raise it with a
/// doctor — never as a scored, validated test. The wording lives in l10n
/// (`epds_disclaimer`); the rule lives here so nobody has to guess.
library;

import 'cycle_log.dart' show DayLog, Mood, addDays, dateKey;

/// How many items the scale has. Fixed by the instrument, not a preference.
const epdsItemCount = 10;

/// Options per item. Every item offers exactly four, scored 0–3.
const epdsOptionCount = 4;

/// The highest possible total: 10 items × 3.
const epdsMaxScore = epdsItemCount * (epdsOptionCount - 1);

/// The items whose options are printed WORST-FIRST, and so score 3→0 rather
/// than 0→3.
///
/// This is the single detail that makes an EPDS implementation right or wrong,
/// and getting it wrong is silent: every score still lands in 0–30 and still
/// looks plausible. Items 1, 2 and 4 read "as much as I always could → not at
/// all"; the other seven read "yes, most of the time → no, never". Scoring all
/// ten in printed order turns "no, never" into 3 points and hands the calmest
/// possible answer sheet a score of 21.
const reverseScoredItems = <int>{3, 5, 6, 7, 8, 9, 10};

/// Whether item [item] (1-based) is printed worst-first.
bool isReverseScored(int item) => reverseScoredItems.contains(item);

/// The points an answer is worth: [item] is 1-based, [option] is the index of
/// the chosen option AS PRINTED (0 = the first line on screen).
///
/// Returns 0 for anything out of range rather than throwing — a stored answer
/// sheet from a future build with an extra option must not crash the screen a
/// mother is standing in front of.
int optionScore(int item, int option) {
  if (item < 1 || item > epdsItemCount) return 0;
  if (option < 0 || option >= epdsOptionCount) return 0;
  return isReverseScored(item) ? (epdsOptionCount - 1 - option) : option;
}

/// The total for a full answer sheet, given as printed-option indices in item
/// order (index 0 = item 1). Missing items score 0.
int epdsTotal(List<int> answers) {
  var sum = 0;
  for (var i = 0; i < answers.length && i < epdsItemCount; i++) {
    sum += optionScore(i + 1, answers[i]);
  }
  return sum;
}

/// True once every item has an answer — the questionnaire cannot be totalled
/// from a partly filled sheet, because a blank is not a zero.
bool isComplete(List<int?> answers) =>
    answers.length == epdsItemCount && answers.every((a) => a != null);

/// Item 10 — thoughts of self-harm — answered as anything other than "never".
///
/// Deliberately its own function, and deliberately independent of the total.
/// Every caller that decides whether to point her outward must consult this as
/// well as [epdsBandFor]; a low total does not overrule it.
bool flaggedSelfHarm(List<int> answers) =>
    answers.length >= epdsItemCount && optionScore(10, answers[9]) > 0;

/// Where a total sits against the instrument's PUBLISHED thresholds.
///
/// Named for what the score is, not for what she is. There is no `depressed`
/// value here and there must never be one: a band is a reason to talk to
/// somebody, not a label to wear.
enum EpdsBand {
  /// Below the lower published threshold.
  low,

  /// 10–12: the "possible depression" range of the original community sample.
  possible,

  /// 13 and above: the threshold the instrument publishes for "further
  /// assessment by a clinician".
  high,
}

/// The lower published threshold (9/10 in the original paper).
const epdsPossibleFrom = 10;

/// The upper published threshold (12/13 in the original paper).
///
/// This number is NOT tuned, rounded, or localised. It is the cut-off the
/// instrument publishes; inventing a different one — "13 feels high for our
/// users" — would be inventing a clinical claim, and a screening tool with a
/// house threshold is not the screening tool it says it is.
const epdsHighFrom = 13;

EpdsBand epdsBandFor(int score) => score >= epdsHighFrom
    ? EpdsBand.high
    : (score >= epdsPossibleFrom ? EpdsBand.possible : EpdsBand.low);

/// Whether a completed questionnaire should send her to a clinician.
///
/// The OR is the point: either the total reached the published threshold, or
/// item 10 was answered at all. Two independent routes outward, because they
/// catch different women.
bool routesOutward({required int score, required bool selfHarm}) =>
    selfHarm || epdsBandFor(score) == EpdsBand.high;

/// One completed screening, as it is kept and synced: the date, the total, the
/// band. No answers — see the file header.
class EpdsResult {
  /// Client-supplied id (a UUID), so a re-push updates rather than duplicates.
  final String id;

  /// When she finished it.
  final DateTime takenAt;

  /// 0–[epdsMaxScore].
  final int score;

  const EpdsResult({
    required this.id,
    required this.takenAt,
    required this.score,
  });

  EpdsBand get band => epdsBandFor(score);

  Map<String, dynamic> toJson() => {
        'id': id,
        'takenAt': takenAt.toUtc().toIso8601String(),
        'score': score,
        'band': band.name,
      };

  /// Tolerant on the way in: a row whose band disagrees with its score is
  /// re-derived rather than trusted, so one bad write cannot make the app
  /// contradict its own arithmetic. Returns null when the row is unusable.
  static EpdsResult? fromJson(Map<String, dynamic> j) {
    final id = j['id'];
    final at = j['takenAt'];
    final score = (j['score'] as num?)?.toInt();
    if (id is! String || id.isEmpty || at is! String || score == null) return null;
    final taken = DateTime.tryParse(at);
    if (taken == null) return null;
    if (score < 0 || score > epdsMaxScore) return null;
    return EpdsResult(id: id, takenAt: taken, score: score);
  }
}

// ---------------------------------------------------------------------------
// Noticing, from the diary she already keeps
// ---------------------------------------------------------------------------

/// The moods that count as a low week.
///
/// `tired` is in the list and that is a judgement call worth stating: exhaustion
/// after a birth is ordinary, and on its own it means nothing. It earns its
/// place because this is not a verdict — it is the threshold for OFFERING a
/// ten-question self-check, and four weeks in which "усталость" was the truest
/// word she had is a fair moment to offer it.
bool isLowMood(Mood m) =>
    m == Mood.anxious || m == Mood.tired || m == Mood.sad;

/// How many 7-day weeks in a row, counting back from [today], were mostly low.
///
/// A week counts as low when she logged at least one mood in it and STRICTLY
/// more of those moods were low than were good. A week with no mood at all
/// breaks the run — silence is not evidence, and «четвёртую неделю подряд» said
/// on the strength of two entries a month apart is a sentence the app cannot
/// support.
///
/// Capped at [maxWeeks] so the count stays cheap and bounded; callers only ever
/// ask "is it at least four".
int lowMoodWeekRun(Map<String, DayLog> logs, DateTime today, {int maxWeeks = 12}) {
  var run = 0;
  for (var week = 0; week < maxWeeks; week++) {
    var low = 0, good = 0;
    // Days [today-7w-6 .. today-7w], stepped by the calendar (see addDays).
    for (var d = 0; d < 7; d++) {
      final day = addDays(today, -(week * 7 + d));
      final mood = logs[dateKey(day)]?.mood;
      if (mood == null) continue;
      isLowMood(mood) ? low++ : good++;
    }
    if (low == 0 || low <= good) return run;
    run++;
  }
  return run;
}

/// How many low weeks in a row are worth raising the offer over.
///
/// Four, from the frame («Четвёртую неделю подряд так себе») and from the
/// instrument's own logic: the baby blues are expected and self-limiting in the
/// first two weeks, so a threshold shorter than that would flag what every
/// midwife would call ordinary.
const lowMoodRunThreshold = 4;

/// Whether the screen should raise the amber card.
bool shouldOfferScreening(Map<String, DayLog> logs, DateTime today) =>
    lowMoodWeekRun(logs, today) >= lowMoodRunThreshold;
