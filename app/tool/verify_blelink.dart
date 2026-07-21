/// Verifies the band link policy: backoff bounds, retry classification, and the
/// state each failure shows the user.
///
/// The manager itself needs a radio, so what is checked here is every decision
/// that does not.
library;

import '../lib/ble/link_policy.dart';

int _passed = 0, _failed = 0;

void _chk(String name, bool ok) {
  if (ok) {
    _passed++;
  } else {
    _failed++;
    print('  FAIL: $name');
  }
}

void main() {
  // ---- backoff ----
  _chk('first retry waits 1s', reconnectDelay(0).inMilliseconds == 1000);
  _chk('backoff doubles', reconnectDelay(1).inMilliseconds == 2000);
  _chk('backoff doubles again', reconnectDelay(2).inMilliseconds == 4000);
  _chk('backoff caps at 30s', reconnectDelay(5).inMilliseconds == 30000);
  _chk('backoff stays capped', reconnectDelay(9).inMilliseconds == 30000);

  // The bug this guards: `1 << 64` is 0 in Dart, so an unclamped shift turned
  // the backoff into a 1s hot loop after a few hours out of range — the
  // opposite of what a backoff is for. Attempt counts this high are reached by
  // a band left off the wrist overnight, not by anything exotic.
  _chk('overnight attempt count still waits the cap',
      reconnectDelay(64).inMilliseconds == 30000);
  _chk('absurd attempt count still waits the cap',
      reconnectDelay(1 << 20).inMilliseconds == 30000);
  _chk('never busy-loops', () {
    for (var i = 0; i < 200; i++) {
      if (reconnectDelay(i).inMilliseconds < 1000) return false;
    }
    return true;
  }());
  _chk('never waits longer than the cap', () {
    for (var i = 0; i < 200; i++) {
      if (reconnectDelay(i).inMilliseconds > 30000) return false;
    }
    return true;
  }());

  // ---- what is worth retrying ----
  _chk('out of range retries', LinkFailure.outOfRange.isWorthRetrying);
  _chk('unknown retries (a misread must cost retries, not tracking)',
      LinkFailure.unknown.isWorthRetrying);
  _chk('denied permission does not retry', !LinkFailure.permissionDenied.isWorthRetrying);
  _chk('wrong device does not retry', !LinkFailure.wrongDevice.isWorthRetrying);
  _chk('bluetooth off does not spin a timer', !LinkFailure.bluetoothOff.isWorthRetrying);

  // ---- every failure says something to the user ----
  for (final f in LinkFailure.values) {
    _chk('$f maps to a reportable state', f.state != BandLinkState.connected);
    _chk('$f is never silently idle', f.state != BandLinkState.idle);
  }

  // ---- classification ----
  _chk('platform permission error is permission',
      classifyLinkError(Exception('PlatformException: BLUETOOTH_CONNECT permission denied')) ==
          LinkFailure.permissionDenied);
  _chk('adapter off is bluetoothOff',
      classifyLinkError(Exception('bluetooth adapter is off')) == LinkFailure.bluetoothOff);
  _chk('connect timeout is out of range',
      classifyLinkError(Exception('Timed out after 15s')) == LinkFailure.outOfRange);
  _chk('device disconnected is out of range',
      classifyLinkError(Exception('device is disconnected')) == LinkFailure.outOfRange);
  _chk('an unrecognised error is unknown, and so retries',
      classifyLinkError(Exception('gatt error 133')) == LinkFailure.unknown);
  _chk('classification is case-insensitive',
      classifyLinkError(Exception('PERMISSION DENIED')) == LinkFailure.permissionDenied);

  print('$_passed passed, $_failed failed');
  if (_failed > 0) throw Exception('blelink verification failed');
}
