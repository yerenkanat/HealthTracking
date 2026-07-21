/// Geofence enter/exit alerting — PURE Dart, unit-testable via
/// `dart run tool/verify_alerts.dart`. Given the child's previous zone and a new
/// location fix, it derives "entered X" / "left Y" events. These feed the in-app
/// alerts feed now and are the exact events OS notifications will fire on later.
library;

import '../core/geofence.dart';
import 'zone_hysteresis.dart';

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

/// When the most recent [kind] event happened, from the alert feed ([alerts]
/// newest-first). A null/empty [childName] matches any child (mirroring
/// [filterAlertsByChild]). Null if there's no such event.
DateTime? lastAlertOfKind(List<SafetyAlert> alerts, String? childName, AlertKind kind) {
  final anyChild = childName == null || childName.isEmpty;
  for (final a in alerts) {
    if (a.kind == kind && (anyChild || a.childName == childName)) return a.at;
  }
  return null;
}

/// When [childName] was last heard from at all — the newest alert of any kind.
/// A null/empty name matches any child. Null when there's no activity yet.
DateTime? lastActivityAt(List<SafetyAlert> alerts, String? childName) {
  final anyChild = childName == null || childName.isEmpty;
  for (final a in alerts) {
    if (anyChild || a.childName == childName) return a.at;
  }
  return null;
}

/// When [childName] last checked in. Null if they haven't checked in.
DateTime? lastCheckIn(List<SafetyAlert> alerts, String childName) =>
    lastAlertOfKind(alerts, childName, AlertKind.checkIn);

/// Whole days since [childName]'s last [kind] event, or null if it never
/// happened. Clamped at 0 (a future-stamped event reads as today).
int? daysSinceKind(List<SafetyAlert> alerts, String? childName, AlertKind kind, DateTime now) {
  final at = lastAlertOfKind(alerts, childName, kind);
  if (at == null) return null;
  final days = DateTime(now.year, now.month, now.day)
      .difference(DateTime(at.year, at.month, at.day))
      .inDays;
  return days < 0 ? 0 : days;
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

/// Remove the FIRST alert matching [target] on every field, returning a new
/// list. Alerts carry no id, so identity is the whole record; matching only the
/// first keeps genuine duplicates (two identical events) from vanishing together.
List<SafetyAlert> removeAlertFrom(List<SafetyAlert> alerts, SafetyAlert target) {
  var removed = false;
  final out = <SafetyAlert>[];
  for (final a in alerts) {
    if (!removed &&
        a.kind == target.kind &&
        a.childName == target.childName &&
        a.zoneName == target.zoneName &&
        a.at == target.at) {
      removed = true;
      continue;
    }
    out.add(a);
  }
  return out;
}

/// How many alerts the safety feed keeps.
const int maxAlerts = 50;

/// Alerts that must not be lost to routine traffic. An SOS is the whole reason
/// this app exists; a low battery is why a child stops being trackable at all.
bool isCriticalAlert(SafetyAlert a) =>
    a.kind == AlertKind.sos || a.kind == AlertKind.lowBattery;

/// Trim [alerts] (newest first) to [maxAlerts], dropping the OLDEST entries —
/// but never an SOS or low-battery alert while an ordinary one could go instead.
///
/// The feed used to trim purely by age, and zone enter/left events are by far
/// the highest-volume kind: a child crossing a few zones a few times a day fills
/// all 50 slots within a week. That silently erased older SOS alerts — the one
/// record a parent would ever go back for, and one the feed offers a dedicated
/// SOS filter for, which would then show nothing at all.
///
/// Ordinary alerts still age out oldest-first, so the feed stays fresh. Only
/// when there is nothing routine left to drop does a critical alert age out.
List<SafetyAlert> trimAlerts(List<SafetyAlert> alerts, {int max = maxAlerts}) {
  if (alerts.length <= max) return List.of(alerts);
  final over = alerts.length - max;
  // Walk oldest→newest picking routine alerts to drop, then criticals if the
  // feed is all-critical and still over the cap.
  final drop = <int>{};
  for (var i = alerts.length - 1; i >= 0 && drop.length < over; i--) {
    if (!isCriticalAlert(alerts[i])) drop.add(i);
  }
  for (var i = alerts.length - 1; i >= 0 && drop.length < over; i--) {
    drop.add(i);
  }
  return [
    for (var i = 0; i < alerts.length; i++)
      if (!drop.contains(i)) alerts[i],
  ];
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
({String? zone, List<SafetyAlert> alerts, ZoneHysteresisState state}) alertsForFix({
  required String? prevZone,
  required Coordinates location,
  required List<Geofence> fences,
  required String childName,
  required DateTime at,
  ZoneHysteresisState hysteresis = ZoneHysteresisState.idle,
}) {
  // Was: currentZone(location, fences) — a bare "is this point inside", with no
  // buffer, no confirmation and no accuracy check. A child standing still near
  // a boundary therefore changed zone on GPS noise, and every flip wrote a
  // "left School" and an "entered School" to the feed and pushed both to a
  // parent. The machinery to prevent exactly this already existed in
  // core/geofence.dart and was wired to nothing.
  final decision = resolveZone(
    prevZone: prevZone,
    location: location,
    fences: fences,
    state: hysteresis,
  );
  final alerts = [
    for (final t in zoneTransitions(prevZone, decision.zone))
      SafetyAlert(kind: t.kind, childName: childName, zoneName: t.zone, at: at),
  ];
  return (zone: decision.zone, alerts: alerts, state: decision.state);
}
