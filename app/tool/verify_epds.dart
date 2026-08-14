/// Pure-Dart verification of the EPDS screening domain.
/// `dart run tool/verify_epds.dart`
///
/// The reverse-scored items are the whole reason this file exists. Score all
/// ten in printed order and every total still lands in 0–30, still looks
/// plausible, and is wrong for every woman who answered calmly — the calmest
/// possible sheet scores 21 instead of 0. Nothing on screen could reveal that,
/// so it is pinned here, item by item.
library;

import 'dart:io';
import '../lib/domain/cycle_log.dart';
import '../lib/domain/epds.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

/// A sheet where every item was answered with printed option [o].
List<int> _all(int o) => List<int>.filled(epdsItemCount, o);

void main() {
  // ---- The shape of the instrument ----
  {
    _chk('ten items', epdsItemCount == 10);
    _chk('four options each', epdsOptionCount == 4);
    _chk('the maximum is 30', epdsMaxScore == 30);
    _chk('seven items are reverse-scored', reverseScoredItems.length == 7);
    // Named one by one: this is the list, not a count.
    for (final i in [3, 5, 6, 7, 8, 9, 10]) {
      _chk('item $i is reverse-scored', isReverseScored(i));
    }
    for (final i in [1, 2, 4]) {
      _chk('item $i is scored in printed order', !isReverseScored(i));
    }
  }

  // ---- Scoring, per item ----
  {
    // Forward items: first line = 0, last line = 3.
    _chk('item 1, first option, is 0', optionScore(1, 0) == 0);
    _chk('item 1, last option, is 3', optionScore(1, 3) == 3);
    _chk('item 4 middle options rise', optionScore(4, 1) == 1 && optionScore(4, 2) == 2);
    // Reverse items: first line = 3, last line = 0.
    _chk('item 3, first option, is 3', optionScore(3, 0) == 3);
    _chk('item 3, last option, is 0', optionScore(3, 3) == 0);
    _chk('item 10, first option, is 3', optionScore(10, 0) == 3);
    _chk('item 10, last option, is 0', optionScore(10, 3) == 0);
    // Out of range never throws and never invents points.
    _chk('an unknown item scores nothing', optionScore(0, 2) == 0 && optionScore(11, 2) == 0);
    _chk('an unknown option scores nothing', optionScore(1, 9) == 0 && optionScore(1, -1) == 0);
  }

  // ---- Totals ----
  {
    // The calmest possible sheet: forward items answered first-line, reverse
    // items answered last-line.
    final calm = [
      for (var i = 1; i <= epdsItemCount; i++) isReverseScored(i) ? 3 : 0,
    ];
    _chk('the calmest sheet scores 0', epdsTotal(calm) == 0);

    final worst = [
      for (var i = 1; i <= epdsItemCount; i++) isReverseScored(i) ? 0 : 3,
    ];
    _chk('the worst sheet scores 30', epdsTotal(worst) == epdsMaxScore);

    // The bug this file exists for: all-first-line is NOT zero, because seven
    // items read worst-first. 7 items × 3 = 21.
    _chk('all-first-line scores 21, not 0', epdsTotal(_all(0)) == 21);
    _chk('all-last-line scores 9, not 30', epdsTotal(_all(3)) == 9);

    // A partial sheet totals what it has rather than throwing.
    _chk('a short sheet totals what it has', epdsTotal([3, 3]) == 6);
    _chk('an over-long sheet stops at ten', epdsTotal(List<int>.filled(20, 0)) == 21);

    // A worked example — item by item, so a future edit that "simplifies" the
    // scoring has one concrete sheet to fail on.
    //   1:1  2:2  3:o1→2  4:0  5:o0→3  6:o2→1  7:o3→0  8:o1→2  9:o2→1  10:o3→0
    final worked = [1, 2, 1, 0, 0, 2, 3, 1, 2, 3];
    _chk('the worked example totals 12', epdsTotal(worked) == 12);
  }

  // ---- Completeness ----
  {
    _chk('a full sheet is complete', isComplete(List<int?>.filled(10, 0)));
    final gap = List<int?>.filled(10, 0)..[4] = null;
    _chk('a blank answer is not a zero', !isComplete(gap));
    _chk('a short sheet is not complete', !isComplete(List<int?>.filled(9, 0)));
  }

  // ---- Bands, at the published thresholds ----
  {
    _chk('0 is the low band', epdsBandFor(0) == EpdsBand.low);
    _chk('9 is still the low band', epdsBandFor(9) == EpdsBand.low);
    _chk('10 enters the possible band', epdsBandFor(10) == EpdsBand.possible);
    _chk('12 is the top of the possible band', epdsBandFor(12) == EpdsBand.possible);
    _chk('13 is the published threshold', epdsBandFor(13) == EpdsBand.high);
    _chk('30 is the high band', epdsBandFor(30) == EpdsBand.high);
    _chk('the thresholds are the published ones',
        epdsPossibleFrom == 10 && epdsHighFrom == 13);
    // No band may be named after a diagnosis.
    _chk('no band is called depression',
        !EpdsBand.values.map((b) => b.name.toLowerCase()).any(
            (n) => n.contains('depress') || n.contains('diagnos')));
  }

  // ---- Item 10 outranks the total ----
  {
    // A calm sheet except item 10 answered "hardly ever" (printed option 2 → 1
    // point). The total is nowhere near 13.
    final calmButHarm = [
      for (var i = 1; i <= epdsItemCount; i++) isReverseScored(i) ? 3 : 0,
    ]..[9] = 2;
    final total = epdsTotal(calmButHarm);
    _chk('the sheet totals 1', total == 1);
    _chk('and its band is low', epdsBandFor(total) == EpdsBand.low);
    _chk('item 10 is flagged', flaggedSelfHarm(calmButHarm));
    _chk('and it routes outward anyway',
        routesOutward(score: total, selfHarm: flaggedSelfHarm(calmButHarm)));

    // "Never" on item 10 does not flag.
    final calm = [
      for (var i = 1; i <= epdsItemCount; i++) isReverseScored(i) ? 3 : 0,
    ];
    _chk('"never" on item 10 does not flag', !flaggedSelfHarm(calm));
    _chk('and a calm sheet does not route outward',
        !routesOutward(score: epdsTotal(calm), selfHarm: flaggedSelfHarm(calm)));

    // The other route: a high total with item 10 answered "never".
    final highNoHarm = [3, 3, 0, 3, 0, 0, 0, 0, 0, 3];
    _chk('a high total routes outward on its own',
        routesOutward(score: epdsTotal(highNoHarm), selfHarm: flaggedSelfHarm(highNoHarm))
            && !flaggedSelfHarm(highNoHarm));

    // A short sheet cannot flag something it does not contain.
    _chk('a sheet without item 10 does not flag', !flaggedSelfHarm([0, 0, 0]));
  }

  // ---- What is stored: score, band and date. Never the answers ----
  {
    final r = EpdsResult(id: 'a1', takenAt: DateTime.utc(2026, 8, 12, 9), score: 15);
    final json = r.toJson();
    _chk('the row carries score, band and date',
        json['score'] == 15 && json['band'] == 'high' && (json['takenAt'] as String).startsWith('2026-08-12'));
    _chk('the row carries NO answers',
        !json.keys.any((k) => k.toLowerCase().contains('answer') || k.toLowerCase().contains('item')));
    _chk('exactly four fields travel', json.length == 4);

    final back = EpdsResult.fromJson(json);
    _chk('a row round-trips', back != null && back.score == 15 && back.id == 'a1');
    _chk('and the band survives', back!.band == EpdsBand.high);

    // Tolerant reads.
    _chk('a band that disagrees with its score is re-derived',
        EpdsResult.fromJson({...json, 'band': 'low'})!.band == EpdsBand.high);
    _chk('a score out of range is refused',
        EpdsResult.fromJson({...json, 'score': 31}) == null &&
            EpdsResult.fromJson({...json, 'score': -1}) == null);
    _chk('a row with no id is refused', EpdsResult.fromJson({...json, 'id': ''}) == null);
    _chk('a row with an unparseable date is refused',
        EpdsResult.fromJson({...json, 'takenAt': 'yesterday'}) == null);
  }

  // ---- Noticing four low weeks in her own diary ----
  {
    final today = DateTime(2026, 8, 12);
    Map<String, DayLog> diary(int weeks, {Mood mood = Mood.sad, int perWeek = 3}) {
      final out = <String, DayLog>{};
      for (var w = 0; w < weeks; w++) {
        for (var d = 0; d < perWeek; d++) {
          final day = addDays(today, -(w * 7 + d));
          out[dateKey(day)] = DayLog(date: dateKey(day), mood: mood);
        }
      }
      return out;
    }

    _chk('four low weeks raise the offer', shouldOfferScreening(diary(4), today));
    _chk('three low weeks do NOT', !shouldOfferScreening(diary(3), today));
    _chk('and the run counts them', lowMoodWeekRun(diary(3), today) == 3);
    _chk('five low weeks still raise it', shouldOfferScreening(diary(5), today));

    // A good week in the middle breaks the run: weeks 0,1 low, week 2 happy,
    // week 3 low again is not "four weeks in a row".
    final broken = <String, DayLog>{...diary(2)};
    for (var d = 0; d < 3; d++) {
      final day = addDays(today, -(2 * 7 + d));
      broken[dateKey(day)] = DayLog(date: dateKey(day), mood: Mood.happy);
    }
    for (var d = 0; d < 3; d++) {
      final day = addDays(today, -(3 * 7 + d));
      broken[dateKey(day)] = DayLog(date: dateKey(day), mood: Mood.sad);
    }
    _chk('a good week breaks the run', lowMoodWeekRun(broken, today) == 2);
    _chk('and the offer is not raised', !shouldOfferScreening(broken, today));

    // Silence is not evidence: one entry a month apart is not four weeks.
    final sparse = <String, DayLog>{};
    for (final w in [0, 1, 2, 3]) {
      final day = addDays(today, -(w * 7));
      sparse[dateKey(day)] = DayLog(date: dateKey(day), mood: Mood.sad);
    }
    _chk('one low day a week still counts (it is her only entry)',
        lowMoodWeekRun(sparse, today) == 4);
    final gap = <String, DayLog>{...sparse}..remove(dateKey(addDays(today, -14)));
    _chk('an EMPTY week breaks the run', lowMoodWeekRun(gap, today) == 2);

    // A tie does not count as low — "мне по-разному" is not four bad weeks.
    final tied = <String, DayLog>{};
    for (var w = 0; w < 4; w++) {
      final a = addDays(today, -(w * 7));
      final b = addDays(today, -(w * 7 + 1));
      tied[dateKey(a)] = DayLog(date: dateKey(a), mood: Mood.sad);
      tied[dateKey(b)] = DayLog(date: dateKey(b), mood: Mood.happy);
    }
    _chk('an even split is not a low week', lowMoodWeekRun(tied, today) == 0);

    _chk('an empty diary raises nothing', !shouldOfferScreening({}, today));
    _chk('the threshold is four', lowMoodRunThreshold == 4);

    // Which moods count.
    _chk('sad, anxious and tired are low',
        isLowMood(Mood.sad) && isLowMood(Mood.anxious) && isLowMood(Mood.tired));
    _chk('happy and calm are not', !isLowMood(Mood.happy) && !isLowMood(Mood.calm));
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
