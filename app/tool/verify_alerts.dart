/// Pure-Dart verification of geofence enter/exit alerting.
/// `dart run tool/verify_alerts.dart`
library;

import 'dart:io';
import '../lib/app/app_controller.dart';
import '../lib/core/geofence.dart';
import '../lib/domain/geofence_alerts.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

void main() {
  // ---- Transition logic ----
  _chk('no change → no events', zoneTransitions('Home', 'Home').isEmpty);
  _chk('null → null → none', zoneTransitions(null, null).isEmpty);
  final enter = zoneTransitions(null, 'School');
  _chk('outside → School = entered', enter.length == 1 && enter.first.kind == AlertKind.entered && enter.first.zone == 'School');
  final leave = zoneTransitions('Home', null);
  _chk('Home → outside = left', leave.length == 1 && leave.first.kind == AlertKind.left && leave.first.zone == 'Home');
  final swap = zoneTransitions('Home', 'School');
  _chk('Home → School = left+entered', swap.length == 2 &&
      swap[0].kind == AlertKind.left && swap[0].zone == 'Home' &&
      swap[1].kind == AlertKind.entered && swap[1].zone == 'School');

  // ---- alertsForFix against real fences ----
  final home = Geofence.circle('home', 'Home', const Coordinates(43.238949, 76.889709), 100);
  final school = Geofence.circle('school', 'School', const Coordinates(43.25, 76.95), 120);
  final at = DateTime(2026, 7, 16, 9);

  // First fix inside School, no previous zone → "entered School".
  final r1 = alertsForFix(prevZone: null, location: school.center!, fences: [home, school], childName: 'Sultan', at: at);
  _chk('fix in School → zone School', r1.zone == 'School');
  _chk('fix in School → entered alert', r1.alerts.length == 1 && r1.alerts.first.kind == AlertKind.entered &&
      r1.alerts.first.zoneName == 'School' && r1.alerts.first.childName == 'Sultan');

  // Move from School to Home → left School + entered Home.
  final r2 = alertsForFix(prevZone: 'School', location: home.center!, fences: [home, school], childName: 'Sultan', at: at);
  _chk('School → Home = 2 alerts', r2.zone == 'Home' && r2.alerts.length == 2 &&
      r2.alerts[0].kind == AlertKind.left && r2.alerts[1].kind == AlertKind.entered);

  // Staying in Home → no alerts.
  final r3 = alertsForFix(prevZone: 'Home', location: home.center!, fences: [home, school], childName: 'Sultan', at: at);
  _chk('staying in Home → no alerts', r3.zone == 'Home' && r3.alerts.isEmpty);

  // Leaving all zones → left Home.
  final r4 = alertsForFix(prevZone: 'Home', location: const Coordinates(44.0, 78.0), fences: [home, school], childName: 'Sultan', at: at);
  _chk('leaving to nowhere → left Home', r4.zone == null && r4.alerts.length == 1 && r4.alerts.first.kind == AlertKind.left);

  // Round-trip.
  final rt = SafetyAlert.fromJson(r1.alerts.first.toJson());
  _chk('alert round-trip', rt.kind == AlertKind.entered && rt.zoneName == 'School' && rt.at == at);

  // ---- Controller integration: location updates build the alert history ----
  final ctl = AppController(now: () => at);
  ctl.configureChild(name: 'Sultan', fences: [home, school]);
  ctl.onChildLocation(home.center!); // entered Home
  ctl.onChildLocation(school.center!); // left Home + entered School
  _chk('controller built 3 alerts', ctl.alerts.length == 3);
  _chk('newest alert = entered School', ctl.alerts.first.kind == AlertKind.entered && ctl.alerts.first.zoneName == 'School');
  ctl.onChildLocation(school.center!); // staying → no new alert
  _chk('no alert when staying', ctl.alerts.length == 3);
  ctl.clearAlerts();
  _chk('clearAlerts empties feed', ctl.alerts.isEmpty);

  // ---- Alert filtering ----
  final feed = [
    SafetyAlert(kind: AlertKind.entered, childName: 'A', zoneName: 'Home', at: DateTime(2026, 7, 16, 9)),
    SafetyAlert(kind: AlertKind.left, childName: 'A', zoneName: 'School', at: DateTime(2026, 7, 16, 8)),
    SafetyAlert(kind: AlertKind.sos, childName: 'A', zoneName: '', at: DateTime(2026, 7, 16, 7)),
    SafetyAlert(kind: AlertKind.lowBattery, childName: 'A', zoneName: '8', at: DateTime(2026, 7, 16, 6)),
  ];
  _chk('filter all keeps everything', filterAlerts(feed, AlertFilter.all).length == 4);
  _chk('filter zones = entered + left', filterAlerts(feed, AlertFilter.zones).length == 2);
  _chk('filter sos = one', filterAlerts(feed, AlertFilter.sos).length == 1 && filterAlerts(feed, AlertFilter.sos).first.kind == AlertKind.sos);
  _chk('filter battery = one', filterAlerts(feed, AlertFilter.battery).single.kind == AlertKind.lowBattery);
  _chk('filter check-ins = none here', filterAlerts(feed, AlertFilter.checkIns).isEmpty);
  _chk('present filters exclude empty check-ins',
      presentAlertFilters(feed).contains(AlertFilter.zones) &&
          presentAlertFilters(feed).contains(AlertFilter.sos) &&
          presentAlertFilters(feed).contains(AlertFilter.battery) &&
          !presentAlertFilters(feed).contains(AlertFilter.checkIns));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
