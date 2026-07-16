/// Geofence enter/exit alerting — PURE Dart, unit-testable via
/// `dart run tool/verify_alerts.dart`. Given the child's previous zone and a new
/// location fix, it derives "entered X" / "left Y" events. These feed the in-app
/// alerts feed now and are the exact events OS notifications will fire on later.
library;

import '../core/geofence.dart';
import 'child_tracker_state.dart' show currentZone;

enum AlertKind { entered, left }

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
        kind: j['kind'] == 'entered' ? AlertKind.entered : AlertKind.left,
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
