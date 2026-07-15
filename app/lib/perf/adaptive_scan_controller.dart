/// AdaptiveScanController — battery-aware BLE/GPS duty cycling.
/// Pure Dart → unit-testable. Owned by the Code Optimizer.
///
/// Continuous BLE scan + high-accuracy GPS are the top battery drains. This drops
/// both to low power when the phone is backgrounded AND still, and only ramps up
/// on foreground or sustained motion (accelerometer-gated, debounced).
library;

enum Activity { stationary, moving }

enum AppVisibility { foreground, background }

enum BleScanMode { foreground, background }

enum LocationAccuracy { high, balanced, low }

class ScanPlan {
  final BleScanMode bleScanMode;
  final int locationIntervalMs;
  final LocationAccuracy locationAccuracy;
  const ScanPlan(this.bleScanMode, this.locationIntervalMs, this.locationAccuracy);
}

const _plans = <String, ScanPlan>{
  'foreground|moving':
      ScanPlan(BleScanMode.foreground, 5000, LocationAccuracy.high),
  'foreground|stationary':
      ScanPlan(BleScanMode.foreground, 20000, LocationAccuracy.balanced),
  'background|moving':
      ScanPlan(BleScanMode.background, 30000, LocationAccuracy.balanced),
  'background|stationary':
      ScanPlan(BleScanMode.background, 120000, LocationAccuracy.low),
};

class AdaptiveScanController {
  final void Function(ScanPlan plan) apply;
  Activity _activity = Activity.stationary;
  AppVisibility _visibility = AppVisibility.foreground;
  int _lastMotionMs = 0;
  ScanPlan _current = _plans['foreground|stationary']!;

  AdaptiveScanController(this.apply);

  ScanPlan get current => _current;

  /// Feed |acceleration| in g. Needs sustained motion to flip; 60s still to relax.
  void onAccelerometer(double magnitudeG, int nowMs) {
    const movingThresholdG = 1.15;
    if (magnitudeG > movingThresholdG) {
      _lastMotionMs = nowMs;
      _setActivity(Activity.moving);
    } else if (nowMs - _lastMotionMs > 60000) {
      _setActivity(Activity.stationary);
    }
  }

  void onAppState(AppVisibility visibility) {
    if (visibility == _visibility) return;
    _visibility = visibility;
    _recompute();
  }

  void _setActivity(Activity a) {
    if (a == _activity) return;
    _activity = a;
    _recompute();
  }

  void _recompute() {
    final plan = _plans['${_visibility.name}|${_activity.name}']!;
    if (identical(plan, _current)) return;
    _current = plan;
    apply(plan);
  }
}
