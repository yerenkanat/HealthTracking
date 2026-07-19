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

  // ---- Per-child filtering ----
  final multi = [
    SafetyAlert(kind: AlertKind.entered, childName: 'Aisha', zoneName: 'Home', at: DateTime(2026, 7, 16, 9)),
    SafetyAlert(kind: AlertKind.sos, childName: 'Timur', zoneName: '', at: DateTime(2026, 7, 16, 8)),
    SafetyAlert(kind: AlertKind.left, childName: 'Aisha', zoneName: 'School', at: DateTime(2026, 7, 16, 7)),
    SafetyAlert(kind: AlertKind.checkIn, childName: '', zoneName: '', at: DateTime(2026, 7, 16, 6)),
  ];
  _chk('child names distinct, first-seen order', childNamesInAlerts(multi).join(',') == 'Aisha,Timur');
  _chk('filter by child keeps only that child', filterAlertsByChild(multi, 'Aisha').length == 2);
  _chk('filter by child preserves order', filterAlertsByChild(multi, 'Aisha').first.kind == AlertKind.entered);
  _chk('null child = all', filterAlertsByChild(multi, null).length == 4);
  _chk('empty child = all', filterAlertsByChild(multi, '').length == 4);
  _chk('unknown child = none', filterAlertsByChild(multi, 'Nobody').isEmpty);

  // ---- Zone entry time (dwell) ----
  final feed2 = [
    // Newest-first, as the controller stores them.
    SafetyAlert(kind: AlertKind.entered, childName: 'Aisha', zoneName: 'School', at: DateTime(2026, 7, 16, 9)),
    SafetyAlert(kind: AlertKind.left, childName: 'Aisha', zoneName: 'Home', at: DateTime(2026, 7, 16, 8, 30)),
    SafetyAlert(kind: AlertKind.entered, childName: 'Aisha', zoneName: 'Home', at: DateTime(2026, 7, 15, 18)),
    SafetyAlert(kind: AlertKind.entered, childName: 'Timur', zoneName: 'School', at: DateTime(2026, 7, 16, 8)),
  ];
  _chk('entry time = most recent matching entered', zoneEntryTime(feed2, 'Aisha', 'School') == DateTime(2026, 7, 16, 9));
  _chk('entry time matches per child', zoneEntryTime(feed2, 'Timur', 'School') == DateTime(2026, 7, 16, 8));
  _chk('entry time null when never entered', zoneEntryTime(feed2, 'Aisha', 'Park') == null);
  _chk('left events are ignored', zoneEntryTime(feed2, 'Aisha', 'Home') == DateTime(2026, 7, 15, 18));

  // ---- Zone visit counts ----
  final visitFeed = [
    SafetyAlert(kind: AlertKind.entered, childName: 'Aisha', zoneName: 'School', at: DateTime(2026, 7, 16, 9)),
    SafetyAlert(kind: AlertKind.left, childName: 'Aisha', zoneName: 'School', at: DateTime(2026, 7, 16, 8)), // exits ignored
    SafetyAlert(kind: AlertKind.entered, childName: 'Aisha', zoneName: 'Home', at: DateTime(2026, 7, 15, 18)),
    SafetyAlert(kind: AlertKind.entered, childName: 'Aisha', zoneName: 'School', at: DateTime(2026, 7, 15, 9)),
    SafetyAlert(kind: AlertKind.entered, childName: 'Timur', zoneName: 'Park', at: DateTime(2026, 7, 15, 9)),
  ];
  final visits = zoneVisitCounts(visitFeed, 'Aisha');
  _chk('most-visited first', visits.first.zone == 'School' && visits.first.visits == 2);
  _chk('exits are not counted', visits.firstWhere((v) => v.zone == 'Home').visits == 1);
  _chk('only this child counted', !visits.any((v) => v.zone == 'Park'));
  _chk('single-zone lookup', visitsToZone(visitFeed, 'Aisha', 'School') == 2);
  _chk('never-entered zone → 0', visitsToZone(visitFeed, 'Aisha', 'Park') == 0);

  // ---- Last check-in ----
  final checkinFeed = [
    SafetyAlert(kind: AlertKind.checkIn, childName: 'Aisha', zoneName: '', at: DateTime(2026, 7, 16, 9)),
    SafetyAlert(kind: AlertKind.entered, childName: 'Aisha', zoneName: 'Home', at: DateTime(2026, 7, 16, 8)),
    SafetyAlert(kind: AlertKind.checkIn, childName: 'Aisha', zoneName: '', at: DateTime(2026, 7, 15, 18)),
    SafetyAlert(kind: AlertKind.checkIn, childName: 'Timur', zoneName: '', at: DateTime(2026, 7, 16, 7)),
  ];
  _chk('last check-in = most recent for child', lastCheckIn(checkinFeed, 'Aisha') == DateTime(2026, 7, 16, 9));
  _chk('last check-in per child', lastCheckIn(checkinFeed, 'Timur') == DateTime(2026, 7, 16, 7));
  _chk('no check-in → null', lastCheckIn(checkinFeed, 'Nobody') == null);

  // Generalized kind lookup + days-since.
  final sosFeed = [
    SafetyAlert(kind: AlertKind.checkIn, childName: 'Aisha', zoneName: '', at: DateTime(2026, 7, 16, 9)),
    SafetyAlert(kind: AlertKind.sos, childName: 'Aisha', zoneName: '', at: DateTime(2026, 7, 4, 15)),
    SafetyAlert(kind: AlertKind.sos, childName: 'Aisha', zoneName: '', at: DateTime(2026, 6, 1, 9)),
  ];
  final asOf = DateTime(2026, 7, 16, 20);
  _chk('last SOS is the most recent', lastAlertOfKind(sosFeed, 'Aisha', AlertKind.sos) == DateTime(2026, 7, 4, 15));
  _chk('days since last SOS', daysSinceKind(sosFeed, 'Aisha', AlertKind.sos, asOf) == 12);
  _chk('days since ignores time of day', daysSinceKind(sosFeed, 'Aisha', AlertKind.checkIn, asOf) == 0);
  _chk('never happened → null', daysSinceKind(sosFeed, 'Aisha', AlertKind.lowBattery, asOf) == null);
  _chk('null child matches any', lastAlertOfKind(sosFeed, null, AlertKind.sos) == DateTime(2026, 7, 4, 15));
  _chk('empty child matches any', daysSinceKind(sosFeed, '', AlertKind.sos, asOf) == 12);
  _chk('future event clamps to 0',
      daysSinceKind([SafetyAlert(kind: AlertKind.sos, childName: 'A', zoneName: '', at: DateTime(2026, 8, 1))], 'A', AlertKind.sos, asOf) == 0);

  // ---- Today's activity summary ----
  final today = DateTime(2026, 7, 16, 12);
  final dayFeed = [
    SafetyAlert(kind: AlertKind.entered, childName: 'A', zoneName: 'Home', at: DateTime(2026, 7, 16, 9)),
    SafetyAlert(kind: AlertKind.left, childName: 'A', zoneName: 'School', at: DateTime(2026, 7, 16, 8)),
    SafetyAlert(kind: AlertKind.checkIn, childName: 'A', zoneName: '', at: DateTime(2026, 7, 16, 7)),
    SafetyAlert(kind: AlertKind.entered, childName: 'A', zoneName: 'Park', at: DateTime(2026, 7, 15, 9)), // yesterday
  ];
  final todays = alertsOnDay(dayFeed, today);
  _chk('today filters to same calendar day', todays.length == 3);
  final counts = alertKindCounts(todays);
  _chk('counts entered today', counts[AlertKind.entered] == 1);
  _chk('counts left today', counts[AlertKind.left] == 1);
  _chk('counts check-in today', counts[AlertKind.checkIn] == 1);
  _chk('absent kind omitted', !counts.containsKey(AlertKind.sos));

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
