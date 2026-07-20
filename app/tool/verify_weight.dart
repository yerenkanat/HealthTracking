/// Pure-Dart verification of the weight-tracking domain.
/// `dart run tool/verify_weight.dart`
library;

import 'dart:io';
import '../lib/domain/weight.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  var e = <WeightEntry>[];
  e = upsertWeight(e, DateTime(2026, 7, 1), 62.0);
  e = upsertWeight(e, DateTime(2026, 7, 8), 62.6);
  e = upsertWeight(e, DateTime(2026, 7, 15), 63.4);
  _chk('three entries', e.length == 3);
  _chk('sorted chronological', e.first.date == '2026-07-01' && e.last.date == '2026-07-15');

  // Same-day upsert replaces, doesn't duplicate.
  e = upsertWeight(e, DateTime(2026, 7, 15), 63.9);
  _chk('same-day upsert replaces', e.length == 3 && e.last.kg == 63.9);

  final s = computeWeightStats(e)!;
  _chk('latest', s.latest == 63.9);
  _chk('first', s.first == 62.0);
  _chk('delta since start', (s.delta - 1.9).abs() < 1e-9);
  _chk('min/max', s.min == 62.0 && s.max == 63.9);
  _chk('count', s.count == 3);

  // Clamping.
  final low = upsertWeight(const [], DateTime(2026, 7, 1), 5).first;
  final high = upsertWeight(const [], DateTime(2026, 7, 1), 999).first;
  _chk('clamps below min', low.kg == minWeightKg);
  _chk('clamps above max', high.kg == maxWeightKg);

  // Remove.
  final r = removeWeight(e, '2026-07-08');
  _chk('remove drops one', r.length == 2 && r.every((x) => x.date != '2026-07-08'));

  _chk('empty stats null', computeWeightStats(const []) == null);

  // Weekly gain rate: +1.9 kg over Jul 1 → Jul 15 (14 days = 2 weeks) = 0.95/wk.
  _chk('weekly gain rate', (weeklyGainRate(e)! - 0.95).abs() < 1e-9);
  _chk('weeks spanned', weeksSpanned(e) == 2);
  _chk('rate null with one entry', weeklyGainRate([e.first]) == null);
  _chk('weeks null with one entry', weeksSpanned([e.first]) == 0);
  final sameDay = [const WeightEntry(date: '2026-07-01', kg: 60), const WeightEntry(date: '2026-07-01', kg: 61)];
  _chk('rate null within a day', weeklyGainRate(sameDay) == null);

  // JSON round-trip.
  final rt = WeightEntry.fromJson(e.last.toJson());
  _chk('round-trip', rt.date == '2026-07-15' && rt.kg == 63.9);

  // Target progress.
  _chk('remaining to target', weightRemaining(63.9, 70) == (70 - 63.9));
  _chk('remaining negative when above', weightRemaining(72, 70) == -2);
  _chk('target not reached below', !weightTargetReached(63.9, 70));
  _chk('target reached at goal', weightTargetReached(70, 70));
  _chk('target reached when above', weightTargetReached(71, 70));

  // ---- Invariants under messy input ----
  // The cycle-length bug came from a derived number being wrecked by dirty
  // data, so the same question is asked here: what survives typos, duplicate
  // weigh-ins and extreme values? Unlike cycle length, these hold up — the
  // entry point clamps and sorts — and these assertions keep it that way.
  final base = DateTime(2026, 1, 1);
  var entries = <WeightEntry>[];
  var threw = 0, unsorted = 0, badStats = 0, nanRate = 0, outOfBand = 0;
  for (var i = 0; i < 400; i++) {
    final day = base.add(Duration(days: (i * 37) % 500));
    // Includes nonsense a fat-fingered entry could produce.
    final kg = [45.0, 60.0, 72.5, 0.0, -20.0, 5000.0, 300.0][i % 7];
    try {
      entries = upsertWeight(entries, day, kg);
      final stats = computeWeightStats(entries);
      final rate = weeklyGainRate(entries);
      if (stats != null && stats.min > stats.max) badStats++;
      if (rate != null && rate.isNaN) nanRate++;
      if (weeksSpanned(entries) < 0) badStats++;
      for (final e in entries) {
        if (e.kg < minWeightKg || e.kg > maxWeightKg) outOfBand++;
      }
      for (var j = 1; j < entries.length; j++) {
        if (entries[j - 1].date.compareTo(entries[j].date) > 0) unsorted++;
      }
    } catch (_) {
      threw++;
    }
  }
  _chk('messy weight input never throws', threw == 0);
  _chk('entries stay sorted by date', unsorted == 0);
  _chk('stats stay coherent (min <= max, weeks >= 0)', badStats == 0);
  _chk('the gain rate is never NaN', nanRate == 0);
  _chk('every stored weight is clamped to a plausible range', outOfBand == 0);

  // Weighing yourself twice in a day replaces the entry rather than stacking
  // two readings for the same date, which would double-count in every average.
  var repeatedWeighIn = <WeightEntry>[];
  for (var i = 0; i < 5; i++) {
    repeatedWeighIn = upsertWeight(repeatedWeighIn, base, 60.0 + i);
  }
  _chk('a second weigh-in on the same day replaces the first',
      repeatedWeighIn.length == 1 && repeatedWeighIn.single.kg == 64.0);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
