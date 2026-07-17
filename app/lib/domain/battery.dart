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
