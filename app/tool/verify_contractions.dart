/// Pure-Dart verification of the contraction-timing domain.
/// `dart run tool/verify_contractions.dart`
library;

import 'dart:io';
import '../lib/domain/contraction.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  final t = DateTime(2026, 12, 1, 3, 0, 0);
  // Three contractions: 50s long, starts 5 min apart.
  final list = [
    Contraction(start: t, end: t.add(const Duration(seconds: 50))),
    Contraction(start: t.add(const Duration(minutes: 5)), end: t.add(const Duration(minutes: 5, seconds: 55))),
    Contraction(start: t.add(const Duration(minutes: 10)), end: t.add(const Duration(minutes: 11))),
  ];

  _chk('duration of first', list[0].duration == const Duration(seconds: 50));
  _chk('duration clamps negative to zero',
      Contraction(start: t, end: t.subtract(const Duration(seconds: 5))).duration == Duration.zero);

  _chk('no interval before first', intervalBefore(list, 0) == null);
  _chk('interval before second is 5 min', intervalBefore(list, 1) == const Duration(minutes: 5));
  _chk('interval before third is 5 min', intervalBefore(list, 2) == const Duration(minutes: 5));
  _chk('out-of-range interval null', intervalBefore(list, 9) == null);

  final s = contractionStats(list);
  _chk('count', s.count == 3);
  _chk('avg duration (50+55+60)/3 = 55s', s.avgDuration == const Duration(seconds: 55));
  _chk('avg interval 5 min', s.avgInterval == const Duration(minutes: 5));

  final one = contractionStats([list.first]);
  _chk('single → interval zero', one.avgInterval == Duration.zero && one.count == 1);

  final none = contractionStats(const []);
  _chk('empty stats zeroed', none.count == 0 && none.avgDuration == Duration.zero);

  // ---- 5-1-1 progress ----
  // The 3-contraction fixture: ~5 min apart, ~55s long, spans only 10 min.
  final early = fiveOneOneProgress(list);
  _chk('5-1-1 interval met (~5 min apart)', early.intervalMet);
  _chk('5-1-1 duration not yet met (<60s avg)', !early.durationMet);
  _chk('5-1-1 not sustained (10 min span)', !early.sustainedMet);
  _chk('5-1-1 metCount = 1', early.metCount == 1 && !early.allMet);

  // A full hour of minute-long contractions 5 min apart → all three met.
  final active = [
    for (var i = 0; i <= 12; i++)
      Contraction(start: t.add(Duration(minutes: 5 * i)), end: t.add(Duration(minutes: 5 * i, seconds: 65))),
  ];
  final p = fiveOneOneProgress(active);
  _chk('5-1-1 all met over a sustained hour', p.allMet && p.metCount == 3);

  _chk('5-1-1 empty → nothing met', fiveOneOneProgress(const []).metCount == 0);
  _chk('5-1-1 single contraction → interval/sustained false',
      !fiveOneOneProgress([list.first]).intervalMet && !fiveOneOneProgress([list.first]).sustainedMet);

  // ---- 5-1-1 describes the CURRENT pattern, not the whole session ----
  //
  // The card this feeds says "the 5-1-1 pattern is met — many providers suggest
  // contacting them around now". So both directions of error matter: telling
  // her it is met when it is not, and staying quiet when it is.
  {
    Contraction at(DateTime start, int seconds) =>
        Contraction(start: start, end: start.add(Duration(seconds: seconds)));

    // Real labour: three hours of early contractions 15 minutes apart, then an
    // hour of active labour four minutes apart. She IS 5-1-1 right now.
    final t0 = DateTime(2026, 7, 21, 6);
    final labour = <Contraction>[
      for (var i = 0; i < 12; i++) at(t0.add(Duration(minutes: 15 * i)), 45),
      for (var i = 1; i <= 15; i++)
        at(t0.add(Duration(minutes: 180 + 4 * i)), 70),
    ];
    final now = labour.last.end;
    final p = fiveOneOneProgress(labour, now: now);
    _chk('active labour after a long early phase is recognised', p.allMet);
    _chk('  intervals in the last hour are what count', p.intervalMet);
    _chk('  and so are durations', p.durationMet);
    _chk('  and the pattern has held for an hour', p.sustainedMet);

    // Two contractions an hour apart are not labour — they are two
    // contractions. Spanning an hour must not read as "sustained".
    final sparse = [
      at(DateTime(2026, 7, 21, 8), 60),
      at(DateTime(2026, 7, 21, 9, 5), 60),
    ];
    final sp = fiveOneOneProgress(sparse, now: DateTime(2026, 7, 21, 9, 6));
    _chk('two contractions an hour apart are not "sustained"', !sp.sustainedMet);
    _chk('and are nowhere near the pattern', sp.metCount <= 1);

    // Early labour must NOT read as met.
    final early = [
      for (var i = 0; i < 8; i++) at(t0.add(Duration(minutes: 15 * i)), 40),
    ];
    _chk('early labour is not 5-1-1',
        !fiveOneOneProgress(early, now: early.last.end).allMet);

    // A pattern that qualified an hour ago but has since stopped must not keep
    // claiming it: contractions that faded are exactly when she should NOT be
    // told to set off.
    final faded = [
      for (var i = 0; i < 13; i++) at(t0.add(Duration(minutes: 5 * i)), 65),
    ];
    final twoHoursLater = faded.last.end.add(const Duration(hours: 2));
    _chk('a pattern that stopped two hours ago no longer counts',
        !fiveOneOneProgress(faded, now: twoHoursLater).allMet);
    _chk('but it did count while it was happening',
        fiveOneOneProgress(faded, now: faded.last.end).allMet);

    // Contractions long enough but too far apart, and vice versa.
    final longButSparse = [
      for (var i = 0; i < 13; i++) at(t0.add(Duration(minutes: 8 * i)), 90),
    ];
    _chk('long contractions eight minutes apart are not 5-1-1',
        !fiveOneOneProgress(longButSparse, now: longButSparse.last.end).intervalMet);

    final closeButShort = [
      for (var i = 0; i < 13; i++) at(t0.add(Duration(minutes: 4 * i)), 30),
    ];
    _chk('short contractions four minutes apart are not 5-1-1',
        !fiveOneOneProgress(closeButShort, now: closeButShort.last.end).durationMet);

    // Without a clock, the last contraction anchors the window, so a stored
    // session renders the same way it did when it was timed.
    _chk('with no clock the last contraction anchors the window',
        fiveOneOneProgress(faded).allMet);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
