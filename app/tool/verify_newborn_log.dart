/// Pure-Dart verification of the newborn daily log.
/// `dart run tool/verify_newborn_log.dart`
library;

import 'dart:io';
import '../lib/domain/newborn_log.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

NewbornEvent feed(DateTime at, [String? side]) =>
    NewbornEvent(at: at, kind: NewbornEventKind.feed, detail: side);
NewbornEvent diaper(DateTime at, String kind) =>
    NewbornEvent(at: at, kind: NewbornEventKind.diaper, detail: kind);
NewbornEvent sleep(DateTime at, [int? min]) =>
    NewbornEvent(at: at, kind: NewbornEventKind.sleep, durationMin: min);

void main() {
  final t8 = DateTime(2026, 7, 22, 8);
  final t9 = DateTime(2026, 7, 22, 9);
  final t10 = DateTime(2026, 7, 22, 10);
  final yesterday = DateTime(2026, 7, 21, 23);

  // ---- Ordering ----
  {
    var log = <NewbornEvent>[];
    log = addNewbornEvent(log, feed(t8));
    log = addNewbornEvent(log, feed(t10));
    log = addNewbornEvent(log, feed(t9));
    _chk('events are newest first', log.first.at == t10 && log.last.at == t8);

    // No per-day dedup: ten feeds a day is normal, each is a real event.
    log = addNewbornEvent(log, feed(t8));
    _chk('a second event at the same time is kept, not merged', log.length == 4);
  }

  // ---- Removal ----
  {
    var log = [feed(t8), diaper(t9, 'wet')];
    log = removeNewbornEventFrom(log, feed(t8));
    _chk('an event can be removed by time and kind', log.length == 1);
    // A value reconstructed from storage (not the same instance) still removes.
    log = removeNewbornEventFrom(log, NewbornEvent(at: t9, kind: NewbornEventKind.diaper, detail: 'wet'));
    _chk('removal works on a reconstructed value, not just identity', log.isEmpty);
    // Removing a feed must not take a diaper at the same instant.
    var mixed = [feed(t8), diaper(t8, 'wet')];
    mixed = removeNewbornEventFrom(mixed, feed(t8));
    _chk('removal is specific to the kind', mixed.length == 1 && mixed.single.kind == NewbornEventKind.diaper);
  }

  // ---- Today vs other days ----
  {
    final log = [feed(t8), feed(t9), diaper(t10, 'both'), sleep(t9, 90), feed(yesterday)];
    final today = summaryFor(log, t8);
    _chk("today counts today's feeds only", today.feeds == 2); // yesterday's excluded
    _chk('today counts diapers', today.diapers == 1);
    _chk('and the wet ones (both is wet)', today.wetDiapers == 1);
    _chk('and sleep stretches', today.sleepStretches == 1);
    _chk('and recorded sleep minutes', today.sleepMinutes == 90);

    final ystd = summaryFor(log, yesterday);
    _chk('yesterday has its own tally', ystd.feeds == 1 && ystd.diapers == 0);
  }
  {
    // Wet counting: 'wet' and 'both' count, 'dirty' does not.
    final log = [diaper(t8, 'wet'), diaper(t9, 'dirty'), diaper(t10, 'both')];
    final s = summaryFor(log, t8);
    _chk('three nappies, two of them wet', s.diapers == 3 && s.wetDiapers == 2);
  }
  {
    // An untimed nap counts as a stretch but adds no minutes.
    final log = [sleep(t8), sleep(t9, 60)];
    final s = summaryFor(log, t8);
    _chk('an untimed nap still counts as a stretch', s.sleepStretches == 2);
    _chk('but adds no minutes', s.sleepMinutes == 60);
  }
  {
    final empty = summaryFor(const [], t8);
    _chk('a day with nothing is empty', empty.isEmpty);
    _chk('and reports zeros, not nulls', empty.feeds == 0 && empty.sleepMinutes == 0);
  }

  // ---- Last of a kind ----
  {
    final log = [feed(t10), diaper(t9, 'wet'), feed(t8)];
    _chk('the last feed is the most recent one', lastOfKind(log, NewbornEventKind.feed)!.at == t10);
    _chk('the last diaper is found across feeds', lastOfKind(log, NewbornEventKind.diaper)!.at == t9);
    _chk('no sleep logged yields null', lastOfKind(log, NewbornEventKind.sleep) == null);
    _chk('an empty log yields null', lastOfKind(const [], NewbornEventKind.feed) == null);
  }

  // ---- Recent-days history ----
  {
    // Feeds today and two days back; nothing yesterday.
    final twoBack = DateTime(2026, 7, 20, 9);
    final log = [feed(t8), feed(t9), diaper(t10, 'wet'), feed(twoBack), diaper(twoBack, 'both')];
    final week = recentDays(log, t8);
    _chk('a week is seven days', week.length == 7);
    _chk('most recent first', week.first.day.day == 22 && week.last.day.day == 16);
    _chk("today's row rolls up today", week.first.summary.feeds == 2);
    _chk('an empty day is kept, not skipped', week[1].summary.isEmpty); // yesterday
    _chk('a day two back keeps its own tally', week[2].summary.feeds == 1 && week[2].summary.wetDiapers == 1);
  }
  {
    // Averages divide by ACTIVE days, not a flat 7.
    final twoBack = DateTime(2026, 7, 20, 9);
    // Today: 2 feeds, 1 wet. Two days back: 1 feed, 1 wet. Yesterday: nothing.
    final log = [feed(t8), feed(t9), diaper(t10, 'wet'), feed(twoBack), diaper(twoBack, 'both')];
    final avg = weekAverages(log, t8);
    _chk('two active days, not seven', avg.activeDays == 2);
    _chk('feeds per active day is (2+1)/2', avg.feedsPerDay == 1.5);
    _chk('wet nappies per active day is (1+1)/2', avg.wetDiapersPerDay == 1.0);
    _chk('a two-day-old log does not read as one-a-day', avg.feedsPerDay > 1.0);
  }
  {
    final avg = weekAverages(const [], t8);
    _chk('no activity: averages are zero, not NaN', avg.isEmpty && avg.feedsPerDay == 0);
  }
  {
    // Sleep minutes average over active days too.
    final log = [sleep(t8, 120), sleep(t9, 60)]; // one active day, 180 min
    final avg = weekAverages(log, t8);
    _chk('sleep minutes per active day', avg.activeDays == 1 && avg.sleepMinutesPerDay == 180);
  }

  // ---- JSON round-trip ----
  {
    final events = [
      feed(t8, 'left'),
      diaper(t9, 'both'),
      sleep(t10, 75),
    ];
    for (final e in events) {
      final back = NewbornEvent.fromJson(e.toJson());
      _chk('${e.kind.name} survives a round-trip',
          back.at == e.at && back.kind == e.kind && back.detail == e.detail && back.durationMin == e.durationMin);
    }
  }
  {
    // A corrupt row throws, so the tolerant list parser drops that event, not
    // the child.
    var threw = false;
    try {
      NewbornEvent.fromJson({'at': '2026-07-22T08:00:00.000', 'kind': 'telepathy'});
    } catch (_) {
      threw = true;
    }
    _chk('an unknown kind is rejected', threw);

    threw = false;
    try {
      NewbornEvent.fromJson({'at': '2026-07-22T08:00:00.000', 'kind': 'sleep', 'durationMin': 5000});
    } catch (_) {
      threw = true;
    }
    _chk('an impossible sleep length is rejected', threw);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
