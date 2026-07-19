/// Geofence enter/exit alerting — PURE Dart, unit-testable via
/// `dart run tool/verify_alerts.dart`. Given the child's previous zone and a new
/// location fix, it derives "entered X" / "left Y" events. These feed the in-app
/// alerts feed now and are the exact events OS notifications will fire on later.
library;

import '../core/geofence.dart';
import 'child_tracker_state.dart' show currentZone;

/// entered/left are geofence transitions; checkIn/sos are manual events the
/// parent (or child) raises from the tracking screen; lowBattery fires when a
/// child tracker's battery drops into the low range.
enum AlertKind { entered, left, checkIn, sos, lowBattery }

/// Categories the alerts feed can filter by.
enum AlertFilter { all, zones, sos, checkIns, battery }

bool alertMatchesFilter(SafetyAlert a, AlertFilter f) => switch (f) {
      AlertFilter.all => true,
      AlertFilter.zones => a.kind == AlertKind.entered || a.kind == AlertKind.left,
      AlertFilter.sos => a.kind == AlertKind.sos,
      AlertFilter.checkIns => a.kind == AlertKind.checkIn,
      AlertFilter.battery => a.kind == AlertKind.lowBattery,
    };

/// Alerts matching [f], preserving order.
List<SafetyAlert> filterAlerts(List<SafetyAlert> alerts, AlertFilter f) =>
    [for (final a in alerts) if (alertMatchesFilter(a, f)) a];

/// Which category filters (besides `all`) actually have alerts — for showing only
/// relevant chips.
Set<AlertFilter> presentAlertFilters(List<SafetyAlert> alerts) => {
      for (final f in [AlertFilter.zones, AlertFilter.sos, AlertFilter.checkIns, AlertFilter.battery])
        if (alerts.any((a) => alertMatchesFilter(a, f))) f,
    };

/// Distinct child names present in [alerts], in first-seen order.
List<String> childNamesInAlerts(List<SafetyAlert> alerts) {
  final seen = <String>{};
  final out = <String>[];
  for (final a in alerts) {
    if (a.childName.isNotEmpty && seen.add(a.childName)) out.add(a.childName);
  }
  return out;
}

/// Alerts for [childName] (order preserved); a null/empty name means all children.
List<SafetyAlert> filterAlertsByChild(List<SafetyAlert> alerts, String? childName) =>
    (childName == null || childName.isEmpty)
        ? alerts
        : [for (final a in alerts) if (a.childName == childName) a];

/// When [childName] most recently ENTERED [zoneName], from the alert feed
/// ([alerts] newest-first, as the controller stores them). Null if there's no
/// such entry event — used to show how long a child has been in their zone.
DateTime? zoneEntryTime(List<SafetyAlert> alerts, String childName, String zoneName) {
  for (final a in alerts) {
    if (a.kind == AlertKind.entered && a.childName == childName && a.zoneName == zoneName) return a.at;
  }
  return null;
}

/// When [childName] last checked in (their most recent check-in event), from the
/// alert feed ([alerts] newest-first). Null if they haven't checked in.
DateTime? lastCheckIn(List<SafetyAlert> alerts, String childName) {
  for (final a in alerts) {
    if (a.kind == AlertKind.checkIn && a.childName == childName) return a.at;
  }
  return null;
}

/// How many times [childName] has ENTERED each zone, most-visited first. Only
/// entry events count, so a visit isn't double-counted by its matching exit.
List<({String zone, int visits})> zoneVisitCounts(List<SafetyAlert> alerts, String childName) {
  final counts = <String, int>{};
  for (final a in alerts) {
    if (a.kind != AlertKind.entered || a.childName != childName || a.zoneName.isEmpty) continue;
    counts[a.zoneName] = (counts[a.zoneName] ?? 0) + 1;
  }
  final out = [for (final e in counts.entries) (zone: e.key, visits: e.value)];
  out.sort((a, b) => b.visits.compareTo(a.visits));
  return out;
}

/// Visit count for a single zone (0 when never entered).
int visitsToZone(List<SafetyAlert> alerts, String childName, String zoneName) {
  for (final e in zoneVisitCounts(alerts, childName)) {
    if (e.zone == zoneName) return e.visits;
  }
  return 0;
}

/// Alerts stamped on the same calendar day as [day].
List<SafetyAlert> alertsOnDay(List<SafetyAlert> alerts, DateTime day) => [
      for (final a in alerts)
        if (a.at.year == day.year && a.at.month == day.month && a.at.day == day.day) a,
    ];

/// Count of each alert kind present in [alerts] (kinds with zero are omitted).
Map<AlertKind, int> alertKindCounts(List<SafetyAlert> alerts) {
  final counts = <AlertKind, int>{};
  for (final a in alerts) {
    counts[a.kind] = (counts[a.kind] ?? 0) + 1;
  }
  return counts;
}

AlertKind alertKindFromName(String? s) => switch (s) {
      'entered' => AlertKind.entered,
      'checkIn' => AlertKind.checkIn,
      'sos' => AlertKind.sos,
      'lowBattery' => AlertKind.lowBattery,
      _ => AlertKind.left,
    };

class SafetyAlert {
  final AlertKind kind;
  final String childName;
  final String zoneName;
  final DateTime at;
  const SafetyAlert({required this.kind, required this.childName, required this.zoneName, required this.at});

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'childName': childName,
        'zoneName': zoneName,
        'at': at.toIso8601String(),
      };

  factory SafetyAlert.fromJson(Map<String, dynamic> j) => SafetyAlert(
        kind: alertKindFromName(j['kind'] as String?),
        childName: (j['childName'] as String?) ?? '',
        zoneName: (j['zoneName'] as String?) ?? '',
        at: DateTime.parse(j['at'] as String),
      );
}

/// Zone transitions from [prevZone] → [newZone] (each is a geofence name, or null
/// when between zones). Emits a "left" for the old zone and/or an "entered" for
/// the new one; nothing when the zone is unchanged.
List<({AlertKind kind, String zone})> zoneTransitions(String? prevZone, String? newZone) {
  if (prevZone == newZone) return const [];
  return [
    if (prevZone != null) (kind: AlertKind.left, zone: prevZone),
    if (newZone != null) (kind: AlertKind.entered, zone: newZone),
  ];
}

/// Given a new [location] and the child's [fences], compute the resulting alerts
/// relative to [prevZone], stamped [childName]/[at]. Returns (newZone, alerts) so
/// the caller can persist the updated zone state.
({String? zone, List<SafetyAlert> alerts}) alertsForFix({
  required String? prevZone,
  required Coordinates location,
  required List<Geofence> fences,
  required String childName,
  required DateTime at,
}) {
  final zone = currentZone(location, fences);
  final alerts = [
    for (final t in zoneTransitions(prevZone, zone))
      SafetyAlert(kind: t.kind, childName: childName, zoneName: t.zone, at: at),
  ];
  return (zone: zone, alerts: alerts);
}
