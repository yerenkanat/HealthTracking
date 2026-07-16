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

import '../ble/calibration.dart';
import '../core/triage.dart';
import '../core/geofence.dart';
import '../data/sample_store.dart';
import '../data/api_client.dart';
import '../data/app_store.dart';
import '../data/persisted_config.dart';
import '../domain/chat_controller.dart';
import '../domain/cycle_log.dart';
import '../domain/cycle_predictions.dart';
import '../domain/family.dart';
import '../domain/geofence_alerts.dart';
import '../domain/health_monitor.dart';
import '../domain/health_series.dart';
import '../domain/sleep.dart';
import '../domain/onboarding_controller.dart';
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
  final _alertStream = StreamController<SafetyAlert>.broadcast();

  bool _emergencyActive = false;
  EmergencyView? _emergency;
  ChildLocationView? _childLocation;
  bool _onboarded = false;
  UserProfile _profile = const UserProfile();
  final List<ChildProfile> _children = [];
  String? _selectedChildId;
  final List<PairedDevice> _devices = [];
  BpCalibration? _bpCalibration;
  bool _notificationsEnabled = true;
  final Map<String, DayLog> _dayLogs = {};

  AppLocale _locale;
  final AppStore? _persistStore;

  AppController({
    SampleStore? store,
    DateTime Function()? now,
    AppLocale? locale,
    AppStore? persistStore,
  })  : store = store ?? SampleStore(),
        _now = now ?? DateTime.now,
        _persistStore = persistStore,
        _locale = locale ?? resolveInitialLocale(null); // default: Russian

  AppLocale get locale => _locale;
  String? get bandId {
    for (final d in _devices) {
      if (d.kind == DeviceKind.band) return d.id;
    }
    return null;
  }

  void setLocale(AppLocale l) {
    if (l == _locale) return;
    _locale = l;
    _persist();
    _notify();
  }

  /// Load any saved config on boot. Call before the first frame's logic; if the
  /// user completed onboarding previously, they skip straight into the app.
  Future<void> restore() async {
    final cfg = await _persistStore?.load();
    if (cfg == null || !cfg.onboarded) return;
    _locale = cfg.locale;
    _profile = cfg.profile;
    _children
      ..clear()
      ..addAll(cfg.children);
    _selectedChildId = cfg.children.isNotEmpty ? cfg.children.first.id : null;
    _devices
      ..clear()
      ..addAll(cfg.devices);
    _bpCalibration = cfg.bpCalibration;
    _notificationsEnabled = cfg.notificationsEnabled;
    _dayLogs
      ..clear()
      ..addAll(cfg.dayLogs);
    _onboarded = true;
    _notify();
  }

  PersistedConfig _snapshot() => PersistedConfig(
        onboarded: _onboarded,
        locale: _locale,
        profile: _profile,
        children: List.of(_children),
        devices: List.of(_devices),
        bpCalibration: _bpCalibration,
        notificationsEnabled: _notificationsEnabled,
        dayLogs: Map.of(_dayLogs),
      );

  void _persist() {
    final s = _persistStore;
    if (s == null) return;
    unawaited(s.save(_snapshot()));
  }

  /// Fires whenever any observable state changes (UI rebuilds on this).
  Stream<void> get changes => _changes.stream;

  AppRoute get route => _emergencyActive ? AppRoute.emergency : AppRoute.home;
  bool get emergencyActive => _emergencyActive;
  EmergencyView? get emergency => _emergency;
  ChildLocationView? get childLocation => _childLocation;
  List<HealthSample> get samples => store.all;
  bool get onboarded => _onboarded;
  UserProfile get profile => _profile;
  String get displayName => _profile.displayName;
  List<ChildProfile> get children => List.unmodifiable(_children);
  List<PairedDevice> get devices => List.unmodifiable(_devices);

  ChildProfile? get selectedChild {
    if (_children.isEmpty) return null;
    return _children.firstWhere((c) => c.id == _selectedChildId, orElse: () => _children.first);
  }

  String get childName => selectedChild?.name ?? 'your child';
  List<Geofence> get geofences => selectedChild?.geofences ?? const [];

  void selectChild(String id) {
    if (_children.any((c) => c.id == id)) {
      _selectedChildId = id;
      _notify();
    }
  }

  void addChild(ChildProfile child) {
    _children.add(child);
    _selectedChildId ??= child.id;
    _persist();
    _notify();
  }

  void addDevice(PairedDevice device) {
    _devices.add(device);
    _persist();
    _notify();
  }

  /// Replace an existing child (edit name / DOB / photo / zones).
  void updateChild(ChildProfile child) {
    final i = _children.indexWhere((c) => c.id == child.id);
    if (i < 0) return;
    _children[i] = child;
    _persist();
    _notify();
  }

  // ---- Geofence zones (per child) ----
  /// Add or replace a zone on [childId] (matched by geofence id).
  void upsertGeofence(String childId, Geofence fence) {
    final i = _children.indexWhere((c) => c.id == childId);
    if (i < 0) return;
    final zones = List<Geofence>.from(_children[i].geofences);
    final z = zones.indexWhere((f) => f.id == fence.id);
    if (z >= 0) {
      zones[z] = fence;
    } else {
      zones.add(fence);
    }
    _children[i] = _children[i].copyWith(geofences: zones);
    _persist();
    _notify();
  }

  void removeGeofence(String childId, String fenceId) {
    final i = _children.indexWhere((c) => c.id == childId);
    if (i < 0) return;
    final zones = _children[i].geofences.where((f) => f.id != fenceId).toList();
    _children[i] = _children[i].copyWith(geofences: zones);
    _persist();
    _notify();
  }

  void removeChild(String id) {
    _children.removeWhere((c) => c.id == id);
    // Tags tied to that child go too.
    _devices.removeWhere((d) => d.childId == id);
    if (_selectedChildId == id) {
      _selectedChildId = _children.isNotEmpty ? _children.first.id : null;
    }
    _persist();
    _notify();
  }

  void removeDevice(String id) {
    _devices.removeWhere((d) => d.id == id);
    _persist();
    _notify();
  }

  void updateProfile(UserProfile p) {
    _profile = p;
    _persist();
    _notify();
  }

  // ---- Women's-health day logging (mood / symptoms / fetal kicks) ----
  Map<String, DayLog> get dayLogs => Map.unmodifiable(_dayLogs);

  /// The log for [day] (never null — an empty entry when nothing is recorded).
  DayLog logFor(DateTime day) => _dayLogs[dateKey(day)] ?? DayLog(date: dateKey(day));

  /// Persist [log], dropping it from storage entirely when it becomes empty so
  /// the calendar doesn't show a dot for a day the user cleared.
  void setDayLog(DayLog log) {
    if (log.isEmpty) {
      _dayLogs.remove(log.date);
    } else {
      _dayLogs[log.date] = log;
    }
    _persist();
    _notify();
  }

  void toggleMoodFor(DateTime day, Mood m) => setDayLog(logFor(day).withMoodToggled(m));
  void toggleSymptomFor(DateTime day, Symptom s) => setDayLog(logFor(day).toggleSymptom(s));
  void addKickFor(DateTime day, [int by = 1]) => setDayLog(logFor(day).addKick(by));
  void resetKicksFor(DateTime day) => setDayLog(logFor(day).resetKicks());
  void toggleFlowFor(DateTime day, Flow f) => setDayLog(logFor(day).withFlowToggled(f));

  // ---- Menstrual cycle (used when NOT pregnant) ----
  /// Whether the app is in pregnancy mode (a due date is set) vs cycle mode.
  bool get isPregnant => _profile.dueDate != null;

  /// The set of days a period flow was logged (for cycle prediction + calendar).
  Set<DateTime> get periodDays {
    final out = <DateTime>{};
    for (final log in _dayLogs.values) {
      if (log.hasPeriod) {
        final d = dateFromKey(log.date);
        if (d != null) out.add(d);
      }
    }
    return out;
  }

  /// Predicted cycle info from logged periods (empty until the user logs a period).
  CycleInfo get cycle => computeCycle(periodDays, _now());

  /// Estimated due date and the derived gestation (null until the mother sets one).
  DateTime? get dueDate => _profile.dueDate;
  GestationInfo? get gestation => gestationFor(_profile.dueDate, _now());

  void setDueDate(DateTime? date) {
    _profile = _profile.copyWith(dueDate: date, clearDueDate: date == null);
    _persist();
    _notify();
  }

  // ---- Blood-pressure calibration (weekly manual tonometer reading) ----
  BpCalibration? get bpCalibration => _bpCalibration;

  /// Latest PPG blood-pressure reading from the band, used as the calibration
  /// reference. Null if no BP sample yet.
  ({int systolic, int diastolic})? get latestBp {
    final s = store.latest;
    if (s == null || s.systolic == null || s.diastolic == null) return null;
    return (systolic: s.systolic!.round(), diastolic: s.diastolic!.round());
  }

  /// Record a cuff reading against the band's PPG reading → store the offsets.
  void calibrateBp({
    required int cuffSystolic,
    required int cuffDiastolic,
    required int ppgSystolic,
    required int ppgDiastolic,
    DateTime? at,
  }) {
    final o = computeBpOffsets(cuffSystolic, cuffDiastolic, ppgSystolic, ppgDiastolic);
    _bpCalibration = BpCalibration(o.systolicOffset, o.diastolicOffset, at ?? _now());
    // TODO(auth): POST to /calibration/bp once we have a signed-in userId.
    _persist();
    _notify();
  }

  /// Wipe the session and return to onboarding (Settings → "Reset").
  Future<void> resetApp() async {
    _children.clear();
    _devices.clear();
    _selectedChildId = null;
    _profile = const UserProfile();
    _bpCalibration = null;
    _dayLogs.clear();
    _alerts.clear();
    _lastChildZone = null;
    _onboarded = false;
    store.clear();
    await _persistStore?.clear();
    _notify();
  }

  // One long-lived onboarding controller so first-run progress survives rebuilds.
  OnboardingController? _onboarding;
  OnboardingController get onboarding =>
      _onboarding ??= OnboardingController(initialLocale: _locale);

  /// Demo/seed helper: replace children with a single configured child.
  void configureChild({required String name, required List<Geofence> fences, DateTime? dateOfBirth}) {
    _children
      ..clear()
      ..add(ChildProfile(id: 'child-1', name: name, geofences: fences, dateOfBirth: dateOfBirth));
    _selectedChildId = 'child-1';
    _notify();
  }

  /// Apply the first-run onboarding result and enter the main app.
  void completeOnboarding(OnboardingResult r) {
    _locale = r.locale;
    _profile = r.profile;
    _children
      ..clear()
      ..add(r.child);
    _selectedChildId = r.child.id;
    if (r.bandId != null) {
      _devices.add(PairedDevice(id: r.bandId!, name: 'Band', kind: DeviceKind.band));
    }
    _onboarded = true;
    _onboarding?.dispose();
    _onboarding = null;
    _persist();
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
      duringSleep: t.duringSleep,
    ));
    if (triage.forceEmergencyScreen) {
      final f = triage.findings.isNotEmpty ? triage.findings.first : null;
      _raiseEmergency(EmergencyView(
        code: f?.code, // UI localizes the code
        message: f?.message ?? 'Urgent health alert.',
        callButtons: [
          if (_profile.hasDoctor) (label: 'Call your doctor', tel: _profile.doctorPhone),
          const (label: 'Call ambulance', tel: '103'),
        ],
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

  // ---- Child safety alerts (zone enter/exit history) ----
  String? _lastChildZone;
  final List<SafetyAlert> _alerts = [];
  List<SafetyAlert> get alerts => List.unmodifiable(_alerts);

  void clearAlerts() {
    if (_alerts.isEmpty) return;
    _alerts.clear();
    _notify();
  }

  /// Each newly generated alert (for the runtime to raise an OS notification).
  /// Only emits while notifications are enabled; the in-app feed fills regardless.
  Stream<SafetyAlert> get newAlerts => _alertStream.stream;

  bool get notificationsEnabled => _notificationsEnabled;
  void setNotificationsEnabled(bool v) {
    if (v == _notificationsEnabled) return;
    _notificationsEnabled = v;
    _persist();
    _notify();
  }

  void onChildLocation(Coordinates coords) {
    _childLocation = ChildLocationView(coords, _now());
    final child = selectedChild;
    if (child != null) {
      final r = alertsForFix(
        prevZone: _lastChildZone,
        location: coords,
        fences: child.geofences,
        childName: child.name,
        at: _now(),
      );
      _lastChildZone = r.zone;
      if (r.alerts.isNotEmpty) {
        // Newest first; the just-entered zone sits at the top.
        _alerts.insertAll(0, r.alerts.reversed);
        if (_alerts.length > 50) _alerts.removeRange(50, _alerts.length);
        // Emit chronologically for OS notifications (gated by the preference).
        if (_notificationsEnabled && !_alertStream.isClosed) {
          for (final a in r.alerts) {
            _alertStream.add(a);
          }
        }
      }
    }
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

  /// Debug/demo only: inject pre-built samples (used by --dart-define=DEMO=true).
  void debugSeed(List<HealthSample> samples) {
    for (final s in samples) {
      store.addSample(s);
    }
    _notify();
  }

  // ---- Sleep (nightly summaries from the band; not persisted — like samples) ----
  final List<SleepSummary> _sleep = [];
  List<SleepSummary> get sleepNights => List.unmodifiable(_sleep);
  SleepSummary? get lastNight => latestNight(_sleep);

  /// Record a nightly sleep summary (replaces any existing entry for that date).
  void addSleepSummary(SleepSummary s) {
    _sleep.removeWhere((n) =>
        n.night.year == s.night.year && n.night.month == s.night.month && n.night.day == s.night.day);
    _sleep.add(s);
    _notify();
  }

  /// Debug/demo only: seed a run of nightly sleep summaries.
  void debugSeedSleep(List<SleepSummary> nights) {
    _sleep.addAll(nights);
    _notify();
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
    await _alertStream.close();
    await _changes.close();
  }
}
