/// Pure-Dart verification of notification preferences + quiet hours.
/// `dart run tool/verify_notification_prefs.dart`
///
/// The assertion that matters most: an SOS is delivered no matter what — every
/// toggle off, deep in quiet hours. Suppressing an emergency is the one failure
/// this whole feature exists to prevent.
library;

import 'dart:io';
import '../lib/domain/notification_prefs.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

int hm(int h, int m) => h * 60 + m;

void main() {
  // ---- SOS is never suppressible ----
  {
    const off = NotificationPrefs(zoneEvents: false, checkIn: false, lowBattery: false, updates: false, quietStart: 0, quietEnd: 1439);
    _chk('SOS delivers with every category off', off.shouldDeliver(NotifyCategory.sos, hm(3, 0)));
    _chk('SOS delivers deep in quiet hours', off.shouldDeliver(NotifyCategory.sos, hm(3, 0)));
    _chk('SOS.allows is always true', off.allows(NotifyCategory.sos));
  }

  // ---- Per-category toggles ----
  {
    const p = NotificationPrefs(zoneEvents: false, checkIn: true, lowBattery: false);
    _chk('a disabled category does not deliver', !p.shouldDeliver(NotifyCategory.zoneEvents, hm(12, 0)));
    _chk('an enabled category delivers', p.shouldDeliver(NotifyCategory.checkIn, hm(12, 0)));
    _chk('low-battery off does not deliver', !p.shouldDeliver(NotifyCategory.lowBattery, hm(12, 0)));
    const on = NotificationPrefs();
    _chk('defaults: all categories on', on.zoneEvents && on.checkIn && on.lowBattery && on.updates);
    _chk('defaults: no quiet hours', !on.hasQuietHours);
  }

  // ---- `updates` is its own category, not a reuse of checkIn ----
  //
  // The shortcut this enum invites: рассылки and support answers already have
  // two neighbouring switches, so hanging them off `checkIn` is one line. It
  // would mean a mother who silenced advertisements also silenced «ребёнок на
  // месте», with nothing on the screen to tell her which switch did it.
  {
    const mutedAds = NotificationPrefs(updates: false);
    _chk('muting updates does not mute check-ins',
        mutedAds.shouldDeliver(NotifyCategory.checkIn, hm(12, 0)));
    _chk('muting updates does not mute zone events',
        mutedAds.shouldDeliver(NotifyCategory.zoneEvents, hm(12, 0)));
    _chk('a рассылка is held when updates is off',
        !mutedAds.shouldDeliver(NotifyCategory.updates, hm(12, 0)));
    const mutedCheckIn = NotificationPrefs(checkIn: false);
    _chk('muting check-ins does not mute updates',
        mutedCheckIn.shouldDeliver(NotifyCategory.updates, hm(12, 0)));
    _chk('updates is held in quiet hours like any other category',
        !const NotificationPrefs(quietStart: 1320, quietEnd: 420)
            .shouldDeliver(NotifyCategory.updates, hm(3, 0)));
  }

  // ---- A pre-existing install has no `updates` key ----
  //
  // Every phone that stored prefs before this switch existed has a blob without
  // it. Reading "absent" as "off" would silently stop the support answers she
  // is waiting for, on the day it shipped.
  {
    final old = NotificationPrefs.fromJson(
        {'zoneEvents': false, 'checkIn': true, 'lowBattery': true});
    _chk('a stored blob with no `updates` key defaults it to ON', old.updates);
    _chk('…without disturbing the switches it does carry',
        !old.zoneEvents && old.checkIn && old.lowBattery);
  }

  // ---- What travels to the server ----
  {
    const cleared = NotificationPrefs(zoneEvents: false);
    final api = cleared.toApiJson();
    // The window must travel as an explicit null. PUT is a full replace, so a
    // missing key would leave the server holding quiet hours she just cleared.
    _chk('toApiJson sends a cleared window as an explicit null',
        api.containsKey('quietStart') && api['quietStart'] == null &&
        api.containsKey('quietEnd') && api['quietEnd'] == null);
    _chk('toApiJson carries every switch', api['zoneEvents'] == false &&
        api['checkIn'] == true && api['lowBattery'] == true && api['updates'] == true);
    // No SOS field, in either direction. A key the server would accept is a key
    // somebody eventually sets to false.
    _chk('toApiJson has no SOS switch', !api.containsKey('sos') && !api.containsKey('emergency'));
  }

  // ---- Value equality, which the sync hook and the restore both rely on ----
  {
    const a = NotificationPrefs(zoneEvents: false, quietStart: 1320, quietEnd: 420);
    const b = NotificationPrefs(zoneEvents: false, quietStart: 1320, quietEnd: 420);
    _chk('equal preferences compare equal (no needless push)', a == b);
    _chk('a changed switch compares unequal', a != a.copyWith(updates: false));
    _chk('the defaults compare equal to a fresh instance',
        const NotificationPrefs() == NotificationPrefs.fromJson({}));
  }

  // ---- Quiet hours (daytime window) ----
  {
    const day = NotificationPrefs(quietStart: 600, quietEnd: 720); // 10:00–12:00
    _chk('inside the window is quiet', day.inQuietHours(hm(11, 0)));
    _chk('the start edge is quiet (inclusive)', day.inQuietHours(600));
    _chk('the end edge is NOT quiet (exclusive)', !day.inQuietHours(720));
    _chk('before the window is not quiet', !day.inQuietHours(hm(9, 0)));
    _chk('a check-in in quiet hours is held', !day.shouldDeliver(NotifyCategory.checkIn, hm(11, 0)));
    _chk('a check-in outside quiet hours delivers', day.shouldDeliver(NotifyCategory.checkIn, hm(13, 0)));
  }

  // ---- Quiet hours (overnight window) ----
  {
    const night = NotificationPrefs(quietStart: 1320, quietEnd: 420); // 22:00–07:00
    _chk('23:00 is quiet (overnight)', night.inQuietHours(hm(23, 0)));
    _chk('03:00 is quiet (overnight)', night.inQuietHours(hm(3, 0)));
    _chk('12:00 is not quiet (overnight)', !night.inQuietHours(hm(12, 0)));
    _chk('07:00 end edge is not quiet', !night.inQuietHours(hm(7, 0)));
    _chk('but SOS still delivers at 03:00', night.shouldDeliver(NotifyCategory.sos, hm(3, 0)));
  }

  // ---- Zero-length / half-specified windows are "off" ----
  {
    const zero = NotificationPrefs(quietStart: 480, quietEnd: 480);
    _chk('a zero-length window is off', !zero.inQuietHours(480));
    final half = NotificationPrefs.fromJson({'quietStart': 480}); // no end
    _chk('a half-specified window decodes to off', !half.hasQuietHours);
  }

  // ---- JSON round-trip ----
  {
    const p = NotificationPrefs(zoneEvents: false, checkIn: true, lowBattery: false, updates: false, quietStart: 1320, quietEnd: 420);
    final r = NotificationPrefs.fromJson(p.toJson());
    _chk('round-trip preserves toggles', !r.zoneEvents && r.checkIn && !r.lowBattery && !r.updates);
    _chk('round-trip preserves quiet hours', r.quietStart == hm(22, 0) && r.quietEnd == hm(7, 0));
    _chk('empty json → safe defaults', () {
      final d = NotificationPrefs.fromJson({});
      return d.zoneEvents && d.checkIn && d.lowBattery && d.updates && !d.hasQuietHours;
    }());
  }

  // ---- copyWith ----
  {
    const p = NotificationPrefs(quietStart: 100, quietEnd: 200);
    _chk('copyWith clears quiet hours', !p.copyWith(clearQuietHours: true).hasQuietHours);
    _chk('copyWith toggles a category', !p.copyWith(zoneEvents: false).zoneEvents);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
