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

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
