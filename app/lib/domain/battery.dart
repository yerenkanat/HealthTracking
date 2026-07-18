/// Tracker battery status — pure classification of a child tracker's battery
/// percentage into levels the UI colours + labels. Fed by device telemetry (real
/// later; seeded demo values for now). PURE Dart → unit-testable via
/// verify_battery.dart.
library;

enum BatteryLevel { critical, low, ok, full }

/// Classify a 0..100 percentage. <=10 critical, <=25 low, <=80 ok, else full.
BatteryLevel batteryLevel(int pct) {
  final p = pct < 0 ? 0 : (pct > 100 ? 100 : pct);
  if (p <= 10) return BatteryLevel.critical;
  if (p <= 25) return BatteryLevel.low;
  if (p <= 80) return BatteryLevel.ok;
  return BatteryLevel.full;
}

/// Worth surfacing a warning (critical or low).
bool isLowBattery(int pct) {
  final l = batteryLevel(pct);
  return l == BatteryLevel.critical || l == BatteryLevel.low;
}

/// Clamp a raw reading into 0..100.
int clampPct(int pct) => pct < 0 ? 0 : (pct > 100 ? 100 : pct);

/// A single timestamped battery reading, kept in a per-child history. Pure + JSON.
class BatteryReading {
  final DateTime at;
  final int pct;
  const BatteryReading(this.at, this.pct);

  Map<String, dynamic> toJson() => {'at': at.toIso8601String(), 'pct': pct};

  factory BatteryReading.fromJson(Map<String, dynamic> j) =>
      BatteryReading(DateTime.parse(j['at'] as String), (j['pct'] as num).toInt());
}

/// Append [pct] at [at] to [history] (oldest-first), collapsing a same-percentage
/// reading in a row (no point storing "62, 62, 62") and capping the list at
/// [cap] most-recent entries. Returns a new list.
List<BatteryReading> appendBatteryReading(List<BatteryReading> history, int pct, DateTime at, {int cap = 30}) {
  final p = clampPct(pct);
  if (history.isNotEmpty && history.last.pct == p) return history;
  final next = [...history, BatteryReading(at, p)];
  if (next.length > cap) return next.sublist(next.length - cap);
  return next;
}

/// Net change across a reading history (last − first). 0 for fewer than 2.
int batteryChange(List<BatteryReading> history) =>
    history.length < 2 ? 0 : history.last.pct - history.first.pct;

/// Whether the tracker is draining over the recorded window (net change < 0).
bool batteryDraining(List<BatteryReading> history) => batteryChange(history) < 0;
