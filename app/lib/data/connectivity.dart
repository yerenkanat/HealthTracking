/// Connectivity, behind a tiny interface so the plugin stays out of the widget
/// tree and the tests. `connectivity_plus` was a declared-but-unused dependency;
/// this is the one place that touches it. main.dart subscribes, updates the
/// controller's online flag (drives the offline banner) and, on reconnect, flushes
/// the telemetry batcher — the `onConnectivityRestored` hook that was never called.
library;

import 'package:connectivity_plus/connectivity_plus.dart';

/// Emits the current online state and every change to it.
abstract interface class ConnectivityService {
  Future<bool> isOnline();
  Stream<bool> get onlineChanges;
}

class PlatformConnectivity implements ConnectivityService {
  final Connectivity _c = Connectivity();

  // Online when any interface is up — "none" is the only offline result.
  static bool _up(List<ConnectivityResult> r) =>
      r.any((x) => x != ConnectivityResult.none) && r.isNotEmpty;

  @override
  Future<bool> isOnline() async {
    try {
      return _up(await _c.checkConnectivity());
    } catch (_) {
      return true; // assume online rather than show a false offline banner
    }
  }

  @override
  Stream<bool> get onlineChanges => _c.onConnectivityChanged.map(_up).distinct();
}
