/// AppController — the single source of app-wide UI state. Pure Dart (uses only
/// dart:async Streams, which Flutter's StreamBuilder consumes directly), so the
/// whole navigation + emergency decision surface is unit-testable without Flutter.
///
/// Responsibilities:
///   • collect incoming band telemetry into the SampleStore (feeds the dashboard);
///   • latch the emergency state when triage (on-device OR server chat) escalates;
///   • expose the current top-level route so the shell knows when to force the
///     Emergency Rescue screen over everything else;
///   • hold the child's latest location for the tracking screen.
library;

import 'dart:async';

import '../core/triage.dart';
import '../core/geofence.dart';
import '../data/sample_store.dart';
import '../data/api_client.dart';
import '../domain/chat_controller.dart';
import '../domain/health_monitor.dart';
import '../domain/health_series.dart';
import '../l10n/l10n.dart';
import '../net/telemetry_batcher.dart';

enum AppRoute { home, emergency }

class EmergencyView {
  /// Triage code for on-device emergencies (UI localizes it). Null for
  /// server-driven chat emergencies, where [message] is already localized.
  final String? code;
  final String message;
  final List<({String label, String tel})> callButtons;
  const EmergencyView({this.code, required this.message, required this.callButtons});
}

class ChildLocationView {
  final Coordinates coords;
  final DateTime at;
  const ChildLocationView(this.coords, this.at);
}

class AppController {
  final SampleStore store;
  final DateTime Function() _now;
  final _changes = StreamController<void>.broadcast();

  bool _emergencyActive = false;
  EmergencyView? _emergency;
  ChildLocationView? _childLocation;
  List<Geofence> _geofences = const [];
  String _childName = 'your child';

  AppLocale _locale;

  AppController({SampleStore? store, DateTime Function()? now, AppLocale? locale})
      : store = store ?? SampleStore(),
        _now = now ?? DateTime.now,
        _locale = locale ?? resolveInitialLocale(null); // default: Russian

  AppLocale get locale => _locale;
  void setLocale(AppLocale l) {
    if (l == _locale) return;
    _locale = l;
    _notify();
  }

  /// Fires whenever any observable state changes (UI rebuilds on this).
  Stream<void> get changes => _changes.stream;

  AppRoute get route => _emergencyActive ? AppRoute.emergency : AppRoute.home;
  bool get emergencyActive => _emergencyActive;
  EmergencyView? get emergency => _emergency;
  ChildLocationView? get childLocation => _childLocation;
  List<HealthSample> get samples => store.all;
  List<Geofence> get geofences => _geofences;
  String get childName => _childName;

  /// Loaded once from the backend after sign-in (child profile + zones).
  void configureChild({required String name, required List<Geofence> fences}) {
    _childName = name;
    _geofences = fences;
    _notify();
  }

  /// From BLEDeviceManager.onTelemetry (via HealthMonitor). Records the reading
  /// and latches emergency if triage says so.
  void onTelemetry(BandTelemetry t, TriageResult triage) {
    store.addSample(HealthSample(
      at: _now(),
      heartRate: t.heartRateBpm?.toDouble(),
      spo2: t.spo2Pct?.toDouble(),
      systolic: t.systolicMmHg?.toDouble(),
      diastolic: t.diastolicMmHg?.toDouble(),
      coreTemp: t.coreTempC,
    ));
    if (triage.forceEmergencyScreen) {
      final f = triage.findings.isNotEmpty ? triage.findings.first : null;
      _raiseEmergency(EmergencyView(
        code: f?.code, // UI localizes the code
        message: f?.message ?? 'Urgent health alert.',
        callButtons: const [(label: 'Call ambulance', tel: '103')],
      ));
    } else {
      _notify();
    }
  }

  /// From the AI chat service when the server escalates a message (already localized).
  void onChatEmergency(String message, List<({String label, String tel})> callButtons) {
    _raiseEmergency(EmergencyView(
      message: message,
      callButtons: callButtons.isEmpty
          ? const [(label: 'Call ambulance', tel: '103')]
          : callButtons,
    ));
  }

  void onChildLocation(Coordinates coords) {
    _childLocation = ChildLocationView(coords, _now());
    _notify();
  }

  /// Deliberate dismissal from the Emergency Rescue screen (already confirmed).
  void dismissEmergency() {
    if (!_emergencyActive) return;
    _emergencyActive = false;
    _emergency = null;
    _notify();
  }

  void _raiseEmergency(EmergencyView view) {
    _emergencyActive = true;
    _emergency = view;
    _notify();
  }

  void _notify() {
    if (!_changes.isClosed) _changes.add(null);
  }

  // ---- Runtime lifecycle (owned here so main.dart stays a thin entry point) ----
  HealthMonitor? _monitor;
  TelemetryBatcher? _batcher;
  ApiClient? _api;

  void attachRuntime({HealthMonitor? monitor, TelemetryBatcher? batcher, ApiClient? api}) {
    _monitor = monitor;
    _batcher = batcher;
    _api = api;
  }

  ApiClient? get api => _api;
  TelemetryBatcher? get batcher => _batcher;

  ChatController? _chat;
  ChatController? get chat => _chat;

  /// Attach the assistant once the runtime is wired (async, post first-paint).
  void attachChat(ChatController chat) {
    _chat = chat;
    _notify(); // reveal the Assistant tab
  }

  Future<void> dispose() async {
    await _monitor?.dispose();
    await _chat?.dispose();
    await _changes.close();
  }
}
