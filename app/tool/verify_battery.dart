/// Pure-Dart verification of tracker battery classification.
/// `dart run tool/verify_battery.dart`
library;

import 'dart:io';
import '../lib/domain/battery.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  _chk('0 → critical', batteryLevel(0) == BatteryLevel.critical);
  _chk('10 → critical (boundary)', batteryLevel(10) == BatteryLevel.critical);
  _chk('11 → low', batteryLevel(11) == BatteryLevel.low);
  _chk('25 → low (boundary)', batteryLevel(25) == BatteryLevel.low);
  _chk('26 → ok', batteryLevel(26) == BatteryLevel.ok);
  _chk('80 → ok (boundary)', batteryLevel(80) == BatteryLevel.ok);
  _chk('81 → full', batteryLevel(81) == BatteryLevel.full);
  _chk('100 → full', batteryLevel(100) == BatteryLevel.full);

  _chk('over 100 clamps to full', batteryLevel(150) == BatteryLevel.full);
  _chk('negative clamps to critical', batteryLevel(-5) == BatteryLevel.critical);

  _chk('low battery at 8', isLowBattery(8));
  _chk('low battery at 20', isLowBattery(20));
  _chk('not low at 50', !isLowBattery(50));
  _chk('not low at 100', !isLowBattery(100));

  _chk('clampPct low', clampPct(-3) == 0);
  _chk('clampPct high', clampPct(140) == 100);
  _chk('clampPct mid', clampPct(63) == 63);

  // ---- Reading history ----
  final t = DateTime(2026, 7, 15, 9);
  var h = <BatteryReading>[];
  h = appendBatteryReading(h, 80, t);
  h = appendBatteryReading(h, 80, t.add(const Duration(hours: 1))); // duplicate collapses
  h = appendBatteryReading(h, 74, t.add(const Duration(hours: 2)));
  h = appendBatteryReading(h, 60, t.add(const Duration(hours: 3)));
  _chk('duplicate reading collapsed', h.length == 3);
  _chk('history is oldest-first', h.first.pct == 80 && h.last.pct == 60);
  _chk('net change is negative', batteryChange(h) == -20 && batteryDraining(h));
  _chk('single reading → no change', batteryChange([BatteryReading(t, 50)]) == 0);
  _chk('reading round-trips', BatteryReading.fromJson(h.last.toJson()).pct == 60);

  // Cap keeps only the most recent N.
  var capped = <BatteryReading>[];
  for (var i = 0; i < 40; i++) {
    capped = appendBatteryReading(capped, 100 - i, t.add(Duration(minutes: i)), cap: 10);
  }
  _chk('history capped at 10', capped.length == 10 && capped.last.pct == 61);

  // ---- The tracker dying is the alert that matters most ----
  //
  // The check was `isLowBattery(next) && !isLowBattery(prev)`, and isLowBattery
  // treats low AND critical as one bucket. So 30% → 20% alerted and 20% → 5%
  // did not: the tracker going from "low" to "about to die" was the one
  // transition that said nothing — the last chance to charge it before the
  // child is carrying something that has stopped reporting.
  _chk('dropping into low warns', batteryWarningWorsened(30, 20));
  _chk('dropping from low into critical warns too', batteryWarningWorsened(20, 5));
  _chk('falling straight from full to critical warns',
      batteryWarningWorsened(90, 4));

  // Suppression within a level: a tracker sitting at 20% reporting every few
  // minutes is announced once, not forever.
  _chk('staying low does not repeat', !batteryWarningWorsened(20, 18));
  _chk('staying critical does not repeat', !batteryWarningWorsened(8, 5));
  _chk('an ordinary level says nothing', !batteryWarningWorsened(90, 60));
  _chk('dropping within ok says nothing', !batteryWarningWorsened(80, 30));

  // Charging back up is silent in every direction.
  _chk('critical → low does not warn', !batteryWarningWorsened(5, 20));
  _chk('low → ok does not warn', !batteryWarningWorsened(20, 60));
  _chk('critical → full does not warn', !batteryWarningWorsened(3, 100));

  // A first reading that is already in a warning state should say so.
  _chk('a first reading already low warns', batteryWarningWorsened(null, 20));
  _chk('a first reading already critical warns', batteryWarningWorsened(null, 5));
  _chk('a first reading that is fine says nothing', !batteryWarningWorsened(null, 75));

  // The boundaries themselves.
  _chk('26 is not yet low', !batteryWarningWorsened(80, 26));
  _chk('25 is low', batteryWarningWorsened(80, 25));
  _chk('11 is still only low', !batteryWarningWorsened(20, 11));
  _chk('10 is critical', batteryWarningWorsened(20, 10));

  // A drain from full to empty announces exactly twice — once entering low,
  // once entering critical — however many readings arrive in between.
  {
    var warnings = 0;
    int? prev;
    for (final pct in [100, 90, 74, 60, 45, 30, 26, 25, 22, 18, 14, 11, 10, 7, 4, 1, 0]) {
      if (batteryWarningWorsened(prev, pct)) warnings++;
      prev = pct;
    }
    _chk('a full drain warns exactly twice', warnings == 2);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
