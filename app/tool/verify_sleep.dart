/// Pure-Dart verification of the sleep domain (nightly summaries + quality).
/// `dart run tool/verify_sleep.dart`
library;

import 'dart:io';
import '../lib/domain/sleep.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

bool _near(double a, double b) => (a - b).abs() < 1e-6;

void main() {
  // A solid night: 7h40m asleep (deep 90, rem 100, light 270), 30 awake.
  final good = SleepSummary(night: DateTime(2026, 7, 15), deepMin: 90, remMin: 100, lightMin: 270, awakeMin: 30);
  _chk('asleepMin sums stages', good.asleepMin == 460);
  _chk('inBedMin includes awake', good.inBedMin == 490);
  _chk('hours/minutes split', good.hours == 7 && good.minutes == 40);
  _chk('efficiency', _near(good.efficiency, 460 / 490));
  _chk('deepFraction', _near(good.deepFraction, 90 / 460));
  _chk('good quality', good.quality == SleepQuality.good);

  // Fair: 6h20m asleep, low deep.
  final fair = SleepSummary(night: DateTime(2026, 7, 14), deepMin: 25, remMin: 70, lightMin: 285, awakeMin: 20);
  _chk('fair asleep 380', fair.asleepMin == 380);
  _chk('fair quality (enough total, low deep)', fair.quality == SleepQuality.fair);

  // Poor: only 4h.
  final poor = SleepSummary(night: DateTime(2026, 7, 13), deepMin: 30, remMin: 40, lightMin: 170, awakeMin: 60);
  _chk('poor asleep 240', poor.asleepMin == 240);
  _chk('poor quality', poor.quality == SleepQuality.poor);

  // Empty summary → safe zeros, poor.
  final empty = SleepSummary(night: DateTime(2026, 1, 1));
  _chk('empty asleep 0 + efficiency 0', empty.asleepMin == 0 && empty.efficiency == 0 && empty.deepFraction == 0);
  _chk('empty is poor', empty.quality == SleepQuality.poor);

  // Round-trip.
  final rt = SleepSummary.fromJson(good.toJson());
  _chk('round-trip stages', rt.deepMin == 90 && rt.remMin == 100 && rt.lightMin == 270 && rt.awakeMin == 30);
  _chk('round-trip night', rt.night == DateTime(2026, 7, 15));

  // Latest + stats + sorting over a list (unordered).
  final nights = [fair, poor, good];
  _chk('latestNight = most recent date', latestNight(nights)?.night == DateTime(2026, 7, 15));
  _chk('latestNight null on empty', latestNight(const []) == null);
  final st = sleepStats(nights)!;
  _chk('stats nights count', st.nights == 3);
  _chk('stats avg asleep', st.avgAsleepMin == ((460 + 380 + 240) / 3).round());
  _chk('stats best asleep', st.bestAsleepMin == 460);
  _chk('sorted oldest->newest', () {
    final s = sortedByNight(nights);
    return s.first.night == DateTime(2026, 7, 13) && s.last.night == DateTime(2026, 7, 15);
  }());
  _chk('stats null on empty', sleepStats(const []) == null);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
