/// Pure-Dart verification of the sleep domain (nightly summaries + quality).
/// `dart run tool/verify_sleep.dart`
library;

import 'dart:io';
import '../lib/domain/manual_sleep.dart';
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

  // ---- Sleep consistency ----
  SleepSummary night(int asleep) => SleepSummary(night: DateTime(2026, 7, 15), lightMin: asleep);
  _chk('consistency insufficient with <3', sleepConsistency([night(400), night(410)]).level == SleepConsistency.insufficient);
  final consistent = sleepConsistency([night(420), night(440), night(400)]); // spread 40
  _chk('consistent when spread ≤60', consistent.level == SleepConsistency.consistent && consistent.spreadMin == 40);
  _chk('variable when spread 61..120', sleepConsistency([night(360), night(450), night(420)]).level == SleepConsistency.variable); // spread 90
  _chk('irregular when spread >120', sleepConsistency([night(300), night(480), night(400)]).level == SleepConsistency.irregular); // spread 180

  // ---- Recent-window helper ----
  final wNow = DateTime(2026, 7, 20, 8);
  final window = [
    SleepSummary(night: DateTime(2026, 7, 20), deepMin: 90, remMin: 90, lightMin: 240), // today, 420
    SleepSummary(night: DateTime(2026, 7, 18), deepMin: 60, remMin: 60, lightMin: 180), // 300
    SleepSummary(night: DateTime(2026, 7, 14), deepMin: 60, remMin: 60, lightMin: 240), // edge of a 7-day window
    SleepSummary(night: DateTime(2026, 7, 13), deepMin: 60, remMin: 60, lightMin: 60), // outside
    SleepSummary(night: DateTime(2026, 7, 25), deepMin: 60, remMin: 60, lightMin: 60), // future, outside
  ];
  final last7 = nightsWithin(window, wNow, 7);
  _chk('window keeps in-range nights', last7.length == 3);
  _chk('window includes the 7th-day edge', last7.any((n) => n.night == DateTime(2026, 7, 14)));
  _chk('window excludes older nights', !last7.any((n) => n.night == DateTime(2026, 7, 13)));
  _chk('window excludes future nights', !last7.any((n) => n.night == DateTime(2026, 7, 25)));
  _chk('window average', sleepStats(last7)!.avgAsleepMin == 360); // (420+300+360)/3
  _chk('empty window → no stats', sleepStats(nightsWithin(const [], wNow, 7)) == null);

  // ---- Hand-entered nights ----
  DateTime at(int h, int m, {int day = 14}) => DateTime(2026, 7, day, h, m);

  // The ordinary case crosses midnight, which is what the sheet resolves before
  // handing an entry over: bed 23:00, up 07:00 the next morning.
  final typedNight = SleepEntry(bedAt: at(23, 0), wokeAt: at(7, 0, day: 15), awakeMin: 30);
  _chk('a normal night is valid', sleepEntryIsValid(typedNight));
  _chk('time in bed is the elapsed time', typedNight.inBedMin == 8 * 60);
  _chk('awake time comes off the total', typedNight.asleepMin == 7 * 60 + 30);
  _chk('an entry is filed under the wake date', sleepEntryNight(typedNight) == DateTime(2026, 7, 15));

  // Which day each clock time belongs to. The sheet anchored both to TODAY,
  // so the commonest case in the app — she wakes at seven and logs the night
  // over breakfast — put "bed 23:00" tonight, hours in the future, and filed
  // the night under TOMORROW. It disappeared from "last night" and sat in the
  // history as a future-dated night dragging the averages around.
  {
    final morning = DateTime(2026, 7, 15, 8, 0); // logging at breakfast
    final e = sleepEntryFromClockTimes(
        now: morning, bedHour: 23, bedMinute: 0, wokeHour: 7, wokeMinute: 0, awakeMin: 30);
    _chk('the night just finished is filed under this morning',
        sleepEntryNight(e) == DateTime(2026, 7, 15));
    _chk('bedtime lands on the evening before', e.bedAt == DateTime(2026, 7, 14, 23, 0));
    _chk('and it is never in the future', !e.bedAt.isAfter(morning) && !e.wokeAt.isAfter(morning));
    _chk('an ordinary night still measures eight hours', e.inBedMin == 8 * 60);
    _chk('and is valid', sleepEntryIsValid(e));

    // Logging late the same evening still means the night that ended today.
    final evening = DateTime(2026, 7, 15, 23, 30);
    final e2 = sleepEntryFromClockTimes(
        now: evening, bedHour: 23, bedMinute: 0, wokeHour: 7, wokeMinute: 0);
    _chk('logging at night still files the morning that passed',
        sleepEntryNight(e2) == DateTime(2026, 7, 15) && e2.inBedMin == 8 * 60);

    // A short night that ended after midnight, logged at 01:00.
    final small = DateTime(2026, 7, 15, 1, 0);
    final e3 = sleepEntryFromClockTimes(
        now: small, bedHour: 23, bedMinute: 0, wokeHour: 0, wokeMinute: 30);
    _chk('a night ending after midnight is filed under that day',
        sleepEntryNight(e3) == DateTime(2026, 7, 15) && e3.inBedMin == 90);
  }

  _chk('a zero-length night is rejected',
      validateSleepEntry(SleepEntry(bedAt: at(23, 0), wokeAt: at(23, 0))) == SleepEntryError.empty);
  _chk('a backwards night is rejected',
      validateSleepEntry(SleepEntry(bedAt: at(7, 0), wokeAt: at(1, 0))) == SleepEntryError.empty);
  _chk('an implausibly long night is rejected',
      validateSleepEntry(SleepEntry(bedAt: at(1, 0), wokeAt: at(21, 0))) == SleepEntryError.tooLong);
  _chk('18 hours exactly is still accepted',
      sleepEntryIsValid(SleepEntry(bedAt: at(1, 0), wokeAt: at(19, 0))));
  _chk('more awake than in bed is rejected',
      validateSleepEntry(SleepEntry(bedAt: at(23, 0), wokeAt: at(7, 0, day: 15), awakeMin: 600)) ==
          SleepEntryError.awakeExceedsInBed);
  _chk('negative awake time is rejected',
      validateSleepEntry(SleepEntry(bedAt: at(23, 0), wokeAt: at(7, 0, day: 15), awakeMin: -5)) ==
          SleepEntryError.awakeExceedsInBed);
  _chk('a night spent entirely awake is rejected',
      validateSleepEntry(SleepEntry(bedAt: at(23, 0), wokeAt: at(7, 0, day: 15), awakeMin: 8 * 60)) ==
          SleepEntryError.noSleep);

  // ---- A manual night is judged only on what a person can report ----
  // Nobody can measure their own deep sleep, so holding a hand-entered night to
  // the deep-sleep threshold would score a perfect 8 hours as merely "fair".
  final goodManual = SleepSummary.manual(night: DateTime(2026, 7, 15), asleepMin: 8 * 60, awakeMin: 20);
  _chk('a full manual night reads as good', goodManual.quality == SleepQuality.good);
  _chk('a manual night reports its own total', goodManual.asleepMin == 8 * 60);
  _chk('a manual night has no stage breakdown', !goodManual.hasStages);
  _chk('a short manual night is still only fair',
      SleepSummary.manual(night: DateTime(2026, 7, 15), asleepMin: 6 * 60 + 30).quality ==
          SleepQuality.fair);
  _chk('a broken manual night is poor',
      SleepSummary.manual(night: DateTime(2026, 7, 15), asleepMin: 4 * 60).quality ==
          SleepQuality.poor);
  // Efficiency IS knowable by hand, so it still counts against the total.
  _chk('a manual night spent largely awake is not good',
      SleepSummary.manual(night: DateTime(2026, 7, 15), asleepMin: 7 * 60, awakeMin: 3 * 60).quality !=
          SleepQuality.good);

  // A band night must be judged exactly as before — stages still required.
  final bandNoDeep = SleepSummary(night: DateTime(2026, 7, 15), lightMin: 8 * 60);
  _chk('a band night with no deep sleep is still not good', bandNoDeep.quality != SleepQuality.good);
  _chk('a band night still reports stages', bandNoDeep.hasStages);

  // ---- Round-trip, including older backups with no source recorded ----
  final manualBack = SleepSummary.fromJson(goodManual.toJson());
  _chk('a manual night round-trips',
      manualBack.source == SleepSource.manual &&
          manualBack.asleepMin == goodManual.asleepMin &&
          manualBack.awakeMin == goodManual.awakeMin);
  final bandJson = SleepSummary(night: DateTime(2026, 7, 15), deepMin: 60, remMin: 90, lightMin: 300).toJson();
  _chk('a band night writes no manual fields',
      !bandJson.containsKey('source') && !bandJson.containsKey('manualAsleepMin'));
  _chk('a night saved before manual entry existed reads as a band night',
      SleepSummary.fromJson({'night': '2026-07-15T00:00:00.000', 'deepMin': 60, 'remMin': 90, 'lightMin': 300})
              .source ==
          SleepSource.band);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
