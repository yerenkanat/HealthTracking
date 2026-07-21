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
import 'dart:convert';

import '../ble/calibration.dart';
import '../core/triage.dart';
import '../core/geofence.dart';
import '../data/sample_store.dart';
import '../data/api_client.dart';
import '../data/app_store.dart';
import '../data/persisted_config.dart';
import '../domain/emergency_confirmation.dart';
import '../domain/notification_ids.dart';
import '../domain/error_log.dart';
import '../domain/zone_hysteresis.dart';
import '../domain/appointment.dart';
import '../domain/battery.dart';
import '../domain/chat_controller.dart';
import '../domain/contraction.dart';
import '../domain/cycle_log.dart';
import '../domain/cycle_predictions.dart';
import '../domain/family.dart';
import '../domain/geofence_alerts.dart';
import '../domain/health_monitor.dart';
import '../domain/health_series.dart';
import '../domain/hydration.dart';
import '../domain/kick_session.dart';
import '../domain/manual_vitals.dart';
import '../domain/medication.dart';
import '../domain/weight.dart';
import '../domain/manual_sleep.dart';
import '../domain/sleep.dart';
import '../domain/onboarding_controller.dart';
import '../l10n/l10n.dart';
import '../net/telemetry_batcher.dart';

enum AppRoute { home, emergency }

/// Default labels for the emergency call buttons.
///
/// These are matched BY STRING in app.dart to choose a localized label, so
/// they must be referenced rather than retyped: a stray edit on either side
/// falls through to the default case and ships English straight to the
/// emergency screen — the one screen where that matters most.
class EmergencyLabels {
  static const ambulance = 'Call ambulance';
  static const doctor = 'Call your doctor';

  /// Kazakhstan's ambulance number. The app's target market; a deployment
  /// elsewhere has to revisit this.
  static const ambulanceTel = '103';

  static const all = {ambulance, doctor};
}

class EmergencyView {
  /// Triage code for on-device emergencies (UI localizes it). Null for
  /// server-driven chat emergencies, where [message] is already localized.
  final String? code;
  final String message;
  final List<({String label, String tel})> callButtons;

  /// Which measurement set this off — 'bp', 'temp', 'spo2', 'hr' — and its
  /// value, formatted but locale-neutral ("152/96", "38.6").
  ///
  /// Shown on the emergency screen so she has a number to give the dispatcher
  /// or her doctor. Kept as raw parts rather than a sentence for the same
  /// reason as the call-button labels: the controller stays free of language,
  /// and app.dart localizes.
  final String? readingKind;
  final String? readingValue;

  const EmergencyView({
    this.code,
    required this.message,
    required this.callButtons,
    this.readingKind,
    this.readingValue,
  });
}

class ChildLocationView {
  final Coordinates coords;
  final DateTime at;
  const ChildLocationView(this.coords, this.at);
}

/// A request for the runtime to schedule or cancel an OS reminder notification.
/// [at] == null means "cancel the notification with this id". Keeps the pure
/// controller free of any Flutter-plugin dependency (same pattern as newAlerts).
class ReminderCommand {
  final int id;
  final DateTime? at;
  final String? title;
  final String? body;
  const ReminderCommand.schedule(this.id, DateTime this.at, String this.title, String this.body);
  const ReminderCommand.cancel(this.id)
      : at = null,
        title = null,
        body = null;
}

class AppController {
  final SampleStore store;

  /// Recent errors, for diagnostics. Lives here rather than as a global in
  /// main.dart so it has an owner and a consumer: the runtime's error handlers
  /// write to it, and exportJson carries it.
  final ErrorLog errorLog;

  final DateTime Function() _now;
  final _changes = StreamController<void>.broadcast();
  final _alertStream = StreamController<SafetyAlert>.broadcast();
  final _reminderStream = StreamController<ReminderCommand>.broadcast();
  final _waterReminderStream = StreamController<int?>.broadcast(); // minutes-of-day or null=off
  final _medReminderStream = StreamController<int?>.broadcast(); // minutes-of-day or null=off

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
  int? _avgCycleLength;
  int? _avgPeriodLength;
  final Map<String, DayLog> _dayLogs = {};
  final List<KickSessionRecord> _kickSessions = []; // completed timed sessions (oldest→newest)
  static const _maxKickSessions = 50;
  final List<ContractionSessionRecord> _contractionSessions = []; // oldest→newest
  final Map<String, int> _waterLog = {}; // dateKey → glasses today
  int? _waterGoal;
  final List<Appointment> _appointments = [];
  int _apptSeq = 0; // disambiguates ids created within the same microsecond
  List<WeightEntry> _weights = [];
  double? _weightGoalKg;
  final Map<String, int> _childBattery = {}; // childId → tracker battery %
  final Map<String, List<BatteryReading>> _batteryHistory = {}; // childId → readings (oldest-first)
  final List<Medication> _medications = [];
  MedLog _medLog = {}; // dateKey → medId → doses taken
  int? _waterReminderMinutes; // daily water reminder time (minutes of day); null = off
  int? _medReminderMinutes; // daily medication reminder time; null = off
  bool _periodReminderEnabled = false;
  bool _fertileReminderEnabled = false;
  static const _periodReminderId = NotifyIds.period;
  static const _fertileReminderId = NotifyIds.fertile;

  AppLocale _locale;
  final AppStore? _persistStore;

  AppController({
    SampleStore? store,
    DateTime Function()? now,
    AppLocale? locale,
    AppStore? persistStore,
    ErrorLog? errorLog,
  })  : store = store ?? SampleStore(),
        errorLog = errorLog ?? ErrorLog(),
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
    _applyConfig(cfg);
    _notify();
  }

  /// Replace all in-memory state from [cfg]. Shared by restore(), import and
  /// reset.
  ///
  /// This replaces EVERY persisted field, including [onboarded] — it was the
  /// one thing left out, because restore() only calls this when the saved
  /// config was already onboarded and so never noticed. That gap meant a reset
  /// expressed as "apply an empty config" left the user inside the app instead
  /// of returning them to first-run.
  void _applyConfig(PersistedConfig cfg) {
    _onboarded = cfg.onboarded;
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
    _avgCycleLength = cfg.avgCycleLength;
    _avgPeriodLength = cfg.avgPeriodLength;
    _dayLogs
      ..clear()
      ..addAll(cfg.dayLogs);
    _kickSessions
      ..clear()
      ..addAll(cfg.kickSessions);
    _contractionSessions
      ..clear()
      ..addAll(cfg.contractionSessions);
    _waterLog
      ..clear()
      ..addAll(cfg.waterLog);
    _waterGoal = cfg.waterGoal;
    _appointments
      ..clear()
      ..addAll(cfg.appointments);
    _weights = List.of(cfg.weights);
    _weightGoalKg = cfg.weightGoalKg;
    _childBattery
      ..clear()
      ..addAll(cfg.childBattery);
    _batteryHistory
      ..clear()
      ..addAll({for (final e in cfg.childBatteryHistory.entries) e.key: List.of(e.value)});
    _waterReminderMinutes = cfg.waterReminderMinutes;
    _medReminderMinutes = cfg.medReminderMinutes;
    _periodReminderEnabled = cfg.periodReminderEnabled;
    _fertileReminderEnabled = cfg.fertileReminderEnabled;
    _lastExportAt = cfg.lastExportAt;
    _medications
      ..clear()
      ..addAll(cfg.medications);
    _medLog = {for (final e in cfg.medLog.entries) e.key: Map<String, int>.from(e.value)};
    // Re-seed the (transient) sample store with the readings the user typed, so
    // the dashboard looks the same after a restart as it did before one.
    _manualSamples
      ..clear()
      ..addAll(cfg.manualSamples);
    for (final s in _manualSamples) {
      store.addSample(s);
    }
    // Hand-logged nights go back into the sleep history too, so the sleep card
    // and its averages read the same after a restart as they did before one.
    _manualSleep
      ..clear()
      ..addAll(cfg.manualSleep);
    for (final n in _manualSleep) {
      addSleepSummary(n);
    }
    _alerts
      ..clear()
      ..addAll(cfg.alerts);
    _lastChildZone = cfg.lastChildZone;
    // NOT `_onboarded = true` — that was here because restore() only ever
    // called this with an already-onboarded config, so forcing it looked
    // harmless. It silently overrode the value set from cfg at the top, which
    // made a reset land the user back inside the app rather than at first-run.
  }

  /// Restore all durable data from a JSON backup (the [exportJson] format).
  /// Returns true on success; false if the text isn't valid backup JSON — the
  /// current state is left untouched on failure.
  bool importJson(String json) {
    PersistedConfig cfg;
    try {
      // Every config field has a default, so any JSON object decodes into a
      // valid-but-EMPTY config — and applying that would wipe everything the
      // user has. Reject anything that isn't recognisably one of our backups
      // before touching state (picking the wrong file must not cost data).
      final decoded = jsonDecode(json);
      if (!looksLikeBackup(decoded)) return false;
      cfg = PersistedConfig.fromJson((decoded as Map).cast<String, dynamic>());
      // How much of the file could not be read.
      //
      // The parse tolerates a bad entry rather than failing wholesale, which is
      // right for HER OWN saved data — the alternative is losing all of it. But
      // for a file she deliberately chose to restore, silence would be a lie:
      // she would be told the backup restored and never learn that three
      // appointments in it were unreadable and are simply gone.
      _lastImportDropped = PersistedConfig.lastDroppedEntries;
    } catch (_) {
      return false;
    }
    // Revoke the reminders belonging to the data being REPLACED, while their
    // ids can still be derived. Without this the phone keeps firing reminders
    // for appointments the import just deleted.
    _cancelAllReminders();
    _applyConfig(cfg);
    // Re-arm reminder notifications for the imported appointments.
    rescheduleReminders();
    _reconcileCycleReminders();
    _persist(immediate: true); // irreversible — do not risk the debounce window
    _notify();
    return true;
  }

  /// Entries the last [importJson] could not read. Zero after a clean import.
  int _lastImportDropped = 0;
  int get lastImportDropped => _lastImportDropped;

  PersistedConfig _snapshot() => PersistedConfig(
        onboarded: _onboarded,
        locale: _locale,
        profile: _profile,
        children: List.of(_children),
        devices: List.of(_devices),
        bpCalibration: _bpCalibration,
        notificationsEnabled: _notificationsEnabled,
        avgCycleLength: _avgCycleLength,
        avgPeriodLength: _avgPeriodLength,
        dayLogs: Map.of(_dayLogs),
        alerts: List.of(_alerts),
        lastChildZone: _lastChildZone,
        kickSessions: List.of(_kickSessions),
        contractionSessions: List.of(_contractionSessions),
        waterLog: Map.of(_waterLog),
        waterGoal: _waterGoal,
        appointments: List.of(_appointments),
        weights: List.of(_weights),
        weightGoalKg: _weightGoalKg,
        childBattery: Map.of(_childBattery),
        childBatteryHistory: {for (final e in _batteryHistory.entries) e.key: List.of(e.value)},
        waterReminderMinutes: _waterReminderMinutes,
        medReminderMinutes: _medReminderMinutes,
        periodReminderEnabled: _periodReminderEnabled,
        fertileReminderEnabled: _fertileReminderEnabled,
        lastExportAt: _lastExportAt,
        medications: List.of(_medications),
        medLog: {for (final e in _medLog.entries) e.key: Map<String, int>.from(e.value)},
        manualSamples: List.of(_manualSamples),
        manualSleep: List.of(_manualSleep),
      );

  /// How long to wait for the typing to stop before writing to disk.
  ///
  /// Short enough that a process death loses almost nothing, long enough that a
  /// burst of taps becomes one write.
  static const _persistDebounce = Duration(milliseconds: 300);
  Timer? _persistTimer;

  /// Save, coalescing bursts.
  ///
  /// Every mutation used to snapshot and re-encode the WHOLE config
  /// synchronously. For a user with three years of history that is ~158 KB of
  /// JSON, measured at roughly 7 ms per tap on a desktop — and the kick counter
  /// is a rapid-tap control on a phone several times slower, where that is a
  /// visible stutter on the one screen designed to be tapped quickly. Twenty
  /// taps meant twenty full encodes.
  ///
  /// The cost grows with her history, so it gets worse the longer she uses the
  /// app — the users who care most feel it most.
  ///
  /// The trade is explicit: a crash within the window loses at most 300ms of
  /// input. [flushPendingSave] exists for the moments where that is not
  /// acceptable, and destructive operations still write immediately.
  void _persist({bool immediate = false}) {
    final s = _persistStore;
    if (s == null) return;
    _persistTimer?.cancel();
    if (immediate) {
      _persistTimer = null;
      unawaited(s.save(_snapshot()));
      return;
    }
    _persistTimer = Timer(_persistDebounce, () {
      _persistTimer = null;
      unawaited(s.save(_snapshot()));
    });
  }

  /// Write any pending save now — for app pause/detach, where the process may
  /// not be alive when the timer would have fired.
  void flushPendingSave() {
    if (_persistTimer == null) return;
    _persistTimer!.cancel();
    _persistTimer = null;
    final s = _persistStore;
    if (s != null) unawaited(s.save(_snapshot()));
  }

  /// A human-readable, pretty-printed JSON backup of all durable app data
  /// (profile, children, devices, cycle logs, kick sessions, water, weights,
  /// appointments, battery, alerts). Leads with metadata (app + version + export
  /// time); the rest is the PersistedConfig shape, so a backup round-trips on
  /// import (the extra metadata keys are ignored). Telemetry samples are excluded.
  String exportJson() {
    final at = _now();
    final map = <String, dynamic>{
      'app': 'Umay',
      'appVersion': appVersion,
      'exportedAt': at.toIso8601String(),
      ..._snapshot().toJson(),
      // Recent failures travel with the backup.
      //
      // There is no crash reporting service and no keys for one, so this is
      // the only route an error has off the device — and the export is already
      // the thing support asks a user to send. Omitted entirely when nothing
      // has gone wrong, so a clean install does not carry an empty key that
      // reads as "diagnostics unavailable".
      if (!errorLog.isEmpty) 'diagnostics': errorLog.toJson(),
    };
    // Exporting IS backing up — remember when, so Settings can show freshness.
    _lastExportAt = at;
    _persist();
    _notify();
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  DateTime? _lastExportAt;

  /// When the user last exported (backed up) their data; null if never.
  DateTime? get lastExportAt => _lastExportAt;

  static const appVersion = '0.1.0';

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
    final removed = _children[i].geofences.where((f) => f.id == fenceId).firstOrNull;
    final zones = _children[i].geofences.where((f) => f.id != fenceId).toList();
    _children[i] = _children[i].copyWith(geofences: zones);
    // Forget the child's remembered zone if this deletion is what emptied it.
    // The next location fix compares against that memory, so a zone deleted
    // while the child was inside it produced a "left Home" alert — a departure
    // from somewhere that no longer exists, pushed to the parent and taking up
    // a slot in a capped safety feed. Only clear when no zone of that name
    // remains, so deleting one of two same-named zones keeps the memory.
    if (removed != null &&
        _lastChildZone == removed.name &&
        !zones.any((f) => f.name == removed.name)) {
      _lastChildZone = null;
    }
    _persist(immediate: true); // irreversible — do not risk the debounce window
    _notify();
  }

  void removeChild(String id) {
    _children.removeWhere((c) => c.id == id);
    // Tags tied to that child go too.
    _devices.removeWhere((d) => d.childId == id);
    if (_selectedChildId == id) {
      _selectedChildId = _children.isNotEmpty ? _children.first.id : null;
    }
    _persist(immediate: true); // irreversible — do not risk the debounce window
    _notify();
  }

  void removeDevice(String id) {
    _devices.removeWhere((d) => d.id == id);
    _persist(immediate: true); // irreversible — do not risk the debounce window
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
    _reconcileCycleReminders(); // a period change moves the prediction
    _persist();
    _notify();
  }

  void toggleMoodFor(DateTime day, Mood m) => setDayLog(logFor(day).withMoodToggled(m));
  void toggleSymptomFor(DateTime day, Symptom s) => setDayLog(logFor(day).toggleSymptom(s));
  void addKickFor(DateTime day, [int by = 1]) => setDayLog(logFor(day).addKick(by));
  void resetKicksFor(DateTime day) => setDayLog(logFor(day).resetKicks());

  /// Completed timed sessions, newest first (for the pregnancy history list).
  List<KickSessionRecord> get kickSessions => _kickSessions.reversed.toList(growable: false);

  /// Clear the kick-session history.
  void clearKickSessions() {
    if (_kickSessions.isEmpty) return;
    _kickSessions.clear();
    _persist();
    _notify();
  }

  /// Record a finished timed session AND fold its movements into [day]'s counter,
  /// so the day dot/total stays in sync with the history. Oldest entries are
  /// trimmed past [_maxKickSessions].
  void logKickSession(DateTime day, int count, Duration elapsed) {
    if (count <= 0) return;
    _kickSessions.add(KickSessionRecord(endedAt: _now(), count: count, durationSec: elapsed.inSeconds));
    if (_kickSessions.length > _maxKickSessions) {
      _kickSessions.removeRange(0, _kickSessions.length - _maxKickSessions);
    }
    _dayLogs[dateKey(day)] = logFor(day).addKick(count);
    _persist();
    _notify();
  }

  // ---- Contraction sessions (labour-timing history) ----
  /// Completed contraction sessions, newest first.
  List<ContractionSessionRecord> get contractionSessions =>
      _contractionSessions.reversed.toList(growable: false);

  /// Clear the contraction-session history.
  void clearContractionSessions() {
    if (_contractionSessions.isEmpty) return;
    _contractionSessions.clear();
    _persist();
    _notify();
  }

  /// Record a finished contraction session summary. Trimmed past 50.
  void logContractionSession(int count, Duration avgDuration, Duration avgInterval) {
    if (count <= 0) return;
    _contractionSessions.add(ContractionSessionRecord(
      endedAt: _now(),
      count: count,
      avgDurationSec: avgDuration.inSeconds,
      avgIntervalSec: avgInterval.inSeconds,
    ));
    if (_contractionSessions.length > 50) {
      _contractionSessions.removeRange(0, _contractionSessions.length - 50);
    }
    _persist();
    _notify();
  }

  // ---- Hydration (glasses of water per day) ----
  /// The full water log (dateKey → glasses), for the weekly trend view.
  Map<String, int> get waterLog => Map.unmodifiable(_waterLog);

  /// Glasses logged on [day] (0 if none).
  int waterFor(DateTime day) => _waterLog[dateKey(day)] ?? 0;

  /// The daily target (defaults to [defaultWaterGoal] until the user changes it).
  int get waterGoal => _waterGoal ?? defaultWaterGoal;

  /// Add [by] glasses to [day] (won't go below zero); drops the entry at zero.
  void addWater(DateTime day, [int by = 1]) {
    final next = (waterFor(day) + by).clamp(0, 30);
    if (next == 0) {
      _waterLog.remove(dateKey(day));
    } else {
      _waterLog[dateKey(day)] = next;
    }
    _persist();
    _notify();
  }

  void setWaterGoal(int glasses) {
    _waterGoal = clampWaterGoal(glasses);
    _persist();
    _notify();
  }

  /// Daily water-reminder time as minutes-of-day, or null when off.
  int? get waterReminderMinutes => _waterReminderMinutes;

  /// Schedule/cancel commands for the runtime's daily water notification (the new
  /// minutes-of-day, or null to cancel).
  Stream<int?> get waterReminderCommands => _waterReminderStream.stream;

  /// Set (or clear, with null) the daily water reminder time.
  void setWaterReminder(int? minutesOfDay) {
    _waterReminderMinutes = minutesOfDay?.clamp(0, 24 * 60 - 1);
    if (!_waterReminderStream.isClosed) _waterReminderStream.add(_waterReminderMinutes);
    _persist();
    _notify();
  }

  /// Re-emit the current water-reminder setting so the runtime can (re)schedule it
  /// on boot after attaching its listener.
  void reconcileWaterReminder() {
    if (!_waterReminderStream.isClosed) _waterReminderStream.add(_waterReminderMinutes);
  }

  /// Daily medication reminder time (minutes of day); null = off.
  int? get medReminderMinutes => _medReminderMinutes;

  /// Schedule/cancel commands for the runtime's daily medication notification.
  Stream<int?> get medReminderCommands => _medReminderStream.stream;

  /// Set (or clear, with null) the daily medication reminder time.
  void setMedReminder(int? minutesOfDay) {
    _medReminderMinutes = minutesOfDay?.clamp(0, 24 * 60 - 1);
    if (!_medReminderStream.isClosed) _medReminderStream.add(_medReminderMinutes);
    _persist();
    _notify();
  }

  /// Re-emit the current medication-reminder setting so the runtime can
  /// (re)schedule it on boot after attaching its listener.
  void reconcileMedReminder() {
    if (!_medReminderStream.isClosed) _medReminderStream.add(_medReminderMinutes);
  }

  // ---- Appointments / reminders ----
  List<Appointment> get appointments => List.unmodifiable(_appointments);

  /// The soonest upcoming appointment (for the profile entry preview), or null.
  Appointment? get nextAppt => nextAppointment(_appointments, _now());

  /// Schedule/cancel commands for the runtime to raise OS reminder notifications.
  Stream<ReminderCommand> get reminderCommands => _reminderStream.stream;

  /// Stable notification id for an appointment (positive 31-bit).
  /// Notification id for a per-appointment reminder.
  ///
  /// Mapped into a reserved block so it can NEVER equal one of the fixed
  /// reminder ids (period 800001, fertile 800002, water 900001, medication
  /// 900002). Previously this was a raw 31-bit hash, which could in principle
  /// land on one of them and silently cancel or overwrite a cycle/water/
  /// medication reminder. The odds were negligible, but the block makes it
  /// impossible by construction — and keeps any fixed id added later safe too.
  ///
  /// Appointment-to-appointment collisions remain birthday-bound within the
  /// block; at realistic counts (hundreds) that stays vanishingly small.
  /// Block layout now lives in domain/notification_ids.dart, with every other
  /// block the app allocates, so a new one landing on this range is a test
  /// failure rather than a reminder that silently never arrives.
  static const int appointmentIdBase = NotifyIds.appointmentBase;
  static const int appointmentIdSpan = NotifyIds.appointmentSpan;
  static int reminderIdFor(String appointmentId) => NotifyIds.forAppointment(appointmentId);

  ReminderCommand _scheduleCommandFor(Appointment a) {
    final l = L10n(_locale);
    final body = a.note.isNotEmpty ? a.note : l.t('appt_notif_body');
    return ReminderCommand.schedule(reminderIdFor(a.id), a.at, a.title, body);
  }

  // ---- Medications & supplements ----
  /// The medicines/supplements the user tracks, in the order they added them.
  List<Medication> get medications => List.unmodifiable(_medications);

  /// Doses taken, keyed by dateKey then medication id.
  MedLog get medLog => {for (final e in _medLog.entries) e.key: Map.unmodifiable(e.value)};

  int _medSeq = 0;

  void addMedication(String name, {String dose = '', int perDay = 1}) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    _medications.add(Medication(
      id: 'med-${_now().microsecondsSinceEpoch}-${_medSeq++}',
      name: trimmed,
      dose: dose.trim(),
      perDay: Medication.clampPerDay(perDay),
    ));
    _persist();
    _notify();
  }

  void updateMedication(String id, {String? name, String? dose, int? perDay}) {
    final i = _medications.indexWhere((m) => m.id == id);
    if (i < 0) return;
    _medications[i] = _medications[i].copyWith(name: name?.trim(), dose: dose?.trim(), perDay: perDay);
    _persist();
    _notify();
  }

  /// Remove a medication and every dose recorded against it, so a deleted
  /// medicine can't keep skewing adherence.
  void removeMedication(String id) {
    _medications.removeWhere((m) => m.id == id);
    final pruned = <String, Map<String, int>>{};
    for (final e in _medLog.entries) {
      final day = Map<String, int>.from(e.value)..remove(id);
      if (day.isNotEmpty) pruned[e.key] = day;
    }
    _medLog = pruned;
    _persist(immediate: true); // irreversible — do not risk the debounce window
    _notify();
  }

  void takeMedicationDose(String id, [DateTime? day]) {
    final med = _medications.where((m) => m.id == id).firstOrNull;
    if (med == null) return;
    _medLog = takeDose(_medLog, day ?? _now(), med);
    _persist();
    _notify();
  }

  void undoMedicationDose(String id, [DateTime? day]) {
    _medLog = undoDose(_medLog, day ?? _now(), id);
    _persist();
    _notify();
  }

  void addAppointment(String title, DateTime at, {String note = ''}) {
    final id = 'apt-${_now().microsecondsSinceEpoch}-${_apptSeq++}';
    final appt = Appointment(id: id, title: title.trim(), at: at, note: note.trim());
    _appointments.add(appt);
    if (at.isAfter(_now()) && !_reminderStream.isClosed) {
      _reminderStream.add(_scheduleCommandFor(appt));
    }
    _persist();
    _notify();
  }

  void removeAppointment(String id) {
    _appointments.removeWhere((a) => a.id == id);
    if (!_reminderStream.isClosed) _reminderStream.add(ReminderCommand.cancel(reminderIdFor(id)));
    _persist(immediate: true); // irreversible — do not risk the debounce window
    _notify();
  }

  /// Edit an existing appointment in place (keeping its id). Reschedules its
  /// reminder for the new time, or cancels it if the new time is in the past.
  void updateAppointment(String id, String title, DateTime at, {String note = ''}) {
    final i = _appointments.indexWhere((a) => a.id == id);
    if (i < 0) return;
    final appt = Appointment(id: id, title: title.trim(), at: at, note: note.trim());
    _appointments[i] = appt;
    if (!_reminderStream.isClosed) {
      _reminderStream.add(at.isAfter(_now())
          ? _scheduleCommandFor(appt)
          : ReminderCommand.cancel(reminderIdFor(id)));
    }
    _persist();
    _notify();
  }

  /// Re-emit schedule commands for every still-future appointment. Called by the
  /// runtime after it attaches its listener, so OS reminders survive reinstalls
  /// or a device reboot that dropped pending alarms.
  void rescheduleReminders() {
    if (_reminderStream.isClosed) return;
    final now = _now();
    for (final a in _appointments) {
      if (a.at.isAfter(now)) _reminderStream.add(_scheduleCommandFor(a));
    }
  }

  /// Cancel every reminder this app has armed with the OS.
  ///
  /// Scheduling is one-way: the OS keeps a notification until it fires or is
  /// cancelled, and it does not care that the appointment behind it no longer
  /// exists. So replacing the data — an import, or an erase — must revoke the
  /// old notifications first, or the phone goes on announcing appointments the
  /// user has deleted. After an erase that is worse than untidy: she wiped the
  /// app and it still tells her about her gynaecologist.
  ///
  /// Call BEFORE the lists are replaced, while the ids are still derivable.
  void _cancelAllReminders() {
    if (_reminderStream.isClosed) return;
    for (final a in _appointments) {
      _reminderStream.add(ReminderCommand.cancel(reminderIdFor(a.id)));
    }
    _reminderStream
      ..add(const ReminderCommand.cancel(_periodReminderId))
      ..add(const ReminderCommand.cancel(_fertileReminderId));
    // The recurring daily ones are addressed by "null means off".
    if (!_waterReminderStream.isClosed) _waterReminderStream.add(null);
    if (!_medReminderStream.isClosed) _medReminderStream.add(null);
  }

  // ---- Weight log (one entry per day) ----
  List<WeightEntry> get weights => List.unmodifiable(_weights);
  WeightStats? get weightStats => computeWeightStats(_weights);

  /// Record [kg] for [day] (replaces any existing same-day entry).
  void logWeight(DateTime day, double kg) {
    _weights = upsertWeight(_weights, day, kg);
    _persist();
    _notify();
  }

  void removeWeightEntry(String dateKeyToRemove) {
    _weights = removeWeight(_weights, dateKeyToRemove);
    _persist(immediate: true); // irreversible — do not risk the debounce window
    _notify();
  }

  /// The user-set target weight (kg), or null.
  double? get weightGoalKg => _weightGoalKg;

  /// Set (or clear, with null) the target weight.
  void setWeightGoal(double? kg) {
    _weightGoalKg = kg;
    _persist();
    _notify();
  }

  // ---- Child tracker battery ----
  /// Last-known tracker battery % for [childId] (null if unknown).
  int? batteryFor(String? childId) => childId == null ? null : _childBattery[childId];

  /// The selected child's tracker battery %, or null.
  int? get selectedChildBattery => batteryFor(selectedChild?.id);

  /// Recorded battery readings for [childId], oldest-first (empty if unknown).
  List<BatteryReading> batteryHistoryFor(String? childId) =>
      childId == null ? const [] : (_batteryHistory[childId] ?? const []);

  /// The selected child's battery reading history, oldest-first.
  List<BatteryReading> get selectedChildBatteryHistory => batteryHistoryFor(selectedChild?.id);

  /// Update a child tracker's battery reading (from device telemetry). When the
  /// reading first crosses into the low range, raise a low-battery alert (feed +
  /// OS notification) — but not repeatedly while it stays low.
  void setChildBattery(String childId, int pct) {
    final next = clampPct(pct);
    final prev = _childBattery[childId];
    // Fires on each WORSENING step, so 20%% → 5%% is announced too. It used to
    // treat low and critical as one bucket, so the tracker going from "low" to
    // "about to die" was the one transition that said nothing.
    final crossedIntoLow = batteryWarningWorsened(prev, next);
    _childBattery[childId] = next;
    _batteryHistory[childId] = appendBatteryReading(_batteryHistory[childId] ?? const [], next, _now());
    if (crossedIntoLow) {
      String name = childName;
      for (final c in _children) {
        if (c.id == childId) {
          name = c.name;
          break;
        }
      }
      final alert = SafetyAlert(kind: AlertKind.lowBattery, childName: name, zoneName: '$next', at: _now());
      _alerts.insert(0, alert);
      _trimAlerts();
      if (_notificationsEnabled && !_alertStream.isClosed) _alertStream.add(alert);
    }
    _persist();
    _notify();
  }
  void toggleFlowFor(DateTime day, Flow f) => setDayLog(logFor(day).withFlowToggled(f));
  void setNoteFor(DateTime day, String note) => setDayLog(logFor(day).withNote(note));

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

  /// User-set cycle baseline (used until ≥2 cycles are logged and derived).
  int get avgCycleLength => _avgCycleLength ?? 28;
  int get avgPeriodLength => _avgPeriodLength ?? 5;
  void setCycleBaseline({int? cycle, int? period}) {
    if (cycle != null) _avgCycleLength = cycle;
    if (period != null) _avgPeriodLength = period;
    _reconcileCycleReminders(); // baseline shifts the prediction
    _persist();
    _notify();
  }

  // ---- Cycle reminders (period + fertile window notifications) ----
  bool get periodReminderEnabled => _periodReminderEnabled;
  bool get fertileReminderEnabled => _fertileReminderEnabled;

  void setPeriodReminder(bool enabled) {
    _periodReminderEnabled = enabled;
    _reconcileCycleReminders();
    _persist();
    _notify();
  }

  void setFertileReminder(bool enabled) {
    _fertileReminderEnabled = enabled;
    _reconcileCycleReminders();
    _persist();
    _notify();
  }

  /// Schedule a one-off reminder for [at] at 10:00 (or cancel [id]) when [enabled]
  /// and the date is in the future; [at] null means no prediction → cancel.
  void _scheduleCycleReminder(int id, bool enabled, DateTime? at, String title, String body) {
    if (_reminderStream.isClosed) return;
    if (enabled && at != null) {
      final when = DateTime(at.year, at.month, at.day, 10);
      if (when.isAfter(_now())) {
        final l = L10n(_locale);
        _reminderStream.add(ReminderCommand.schedule(id, when, l.t(title), l.t(body)));
        return;
      }
    }
    _reminderStream.add(ReminderCommand.cancel(id));
  }

  /// (Re)compute both cycle reminders: period ~2 days before the next period, and
  /// the fertile-window opening. Emits schedule/cancel on the reminder stream.
  void _reconcileCycleReminders() {
    final info = cycle;
    final next = info.nextPeriodStart;
    _scheduleCycleReminder(_periodReminderId, _periodReminderEnabled && info.hasData,
        next?.subtract(const Duration(days: 2)), 'period_reminder_title', 'period_reminder_body');
    _scheduleCycleReminder(_fertileReminderId, _fertileReminderEnabled && info.hasData,
        info.fertileStart, 'fertile_reminder_title', 'fertile_reminder_body');
  }

  /// Re-emit the cycle reminders on boot (after the runtime attaches its listener).
  void reconcileCycleReminders() => _reconcileCycleReminders();

  /// Predicted cycle info from logged periods (empty until the user logs a period).
  CycleInfo get cycle =>
      computeCycle(periodDays, _now(), defaultCycle: avgCycleLength, defaultPeriod: avgPeriodLength);

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
  /// Store a fresh cuff calibration. Returns false, changing nothing, when the
  /// cuff and the sensor disagree too widely to be calibration — keeping the
  /// previous offsets is always safer than adopting ones that would distort
  /// every later reading.
  bool calibrateBp({
    required int cuffSystolic,
    required int cuffDiastolic,
    required int ppgSystolic,
    required int ppgDiastolic,
    DateTime? at,
  }) {
    final o = computeBpOffsets(cuffSystolic, cuffDiastolic, ppgSystolic, ppgDiastolic);
    if (!o.accepted) return false;
    _bpCalibration = BpCalibration(o.systolicOffset, o.diastolicOffset, at ?? _now());
    // TODO(auth): POST to /calibration/bp once we have a signed-in userId.
    _persist(immediate: true); // irreversible — do not risk the debounce window
    _notify();
    return true;
  }

  /// Wipe the session and return to onboarding (Settings → "Reset").
  /// Erase everything and return to onboarding.
  ///
  /// Defined as "apply an EMPTY config" rather than as a list of things to
  /// clear. The hand-written list cleared nine fields and silently left behind
  /// her weights, medications, appointments, hand-entered vitals, water log,
  /// kick and contraction sessions, battery history and cycle settings — so a
  /// reset performed before selling a phone, or to exercise a right to
  /// erasure, left most of the record in place.
  ///
  /// Going through _applyConfig means every field the app persists is covered
  /// by construction: a new one added to PersistedConfig is reset without
  /// anyone remembering to come back here. That is the same lesson as the
  /// destructive-action allowlist — a list maintained by hand falls behind.
  /// Erase everything, here and on the server.
  ///
  /// Returns false when the server copy could NOT be erased — offline, or the
  /// request failed. The phone is still wiped either way, but the caller must
  /// be able to tell her the truth: the dialog promises "all data will be
  /// erased", and until this existed that sentence was false. Nothing on the
  /// server was ever deleted, so her blood-pressure history, her child's name
  /// and date of birth, and the coordinates of her home and her child's school
  /// outlived the account she thought she had removed.
  Future<bool> resetApp() async {
    // Server first, while the session is still usable.
    //
    // Ordering matters: clearing local state can drop whatever identifies her
    // to the backend, and then there is nothing left to ask it to delete.
    var serverErased = true;
    if (_api != null) {
      try {
        serverErased = await _api!.deleteAccount();
      } catch (_) {
        serverErased = false;
      }
    }

    // Before anything is cleared, while the reminder ids are still derivable.
    // Erasing her data and leaving the OS to keep announcing her appointments
    // would make the erase look like it had not worked — and would leak the
    // very thing she asked to remove, onto her lock screen.
    _cancelAllReminders();
    _applyConfig(PersistedConfig(
      onboarded: false,
      // Her language survives. It is not personal data, it is how she reads
      // the screen — flipping the UI to Russian under an English speaker in
      // the middle of erasing her account would be a strange parting gift.
      locale: _locale,
      profile: const UserProfile(),
      children: const [],
      devices: const [],
    ));
    // _applyConfig deliberately restores state, so it does not touch these:
    // the in-memory sample ring and whatever is on disk.
    store.clear();
    _confirmation.clear();
    _awaitingRepeat = null;
    await _persistStore?.clear();
    _notify();
    return serverErased;
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
    // No child when the step was skipped, which is the ordinary case for a
    // first-time expectant mother. Adding an empty one would put a nameless
    // entry in her family list and a nameless chip on the tracking screen.
    // She can add a child from Settings whenever there is one to add.
    _children.clear();
    if (r.child != null) {
      _children.add(r.child!);
      _selectedChildId = r.child!.id;
    } else {
      _selectedChildId = null;
    }
    if (r.bandId != null) {
      _devices.add(PairedDevice(id: r.bandId!, name: 'Band', kind: DeviceKind.band));
    }
    _onboarded = true;
    _onboarding?.dispose();
    _onboarding = null;
    _persist(immediate: true); // irreversible — do not risk the debounce window
    _notify();
  }

  /// Record a hand-entered reading (cuff, thermometer, oximeter) for users
  /// without a band. Returns false — changing nothing — if the reading doesn't
  /// validate.
  ///
  /// Manual readings run through the SAME triage as band telemetry: a typed
  /// 190/120 must raise the same emergency guidance a measured one would. The
  /// app never treats a reading as safer because a human typed it.
  bool logManualVitals(ManualVitals v) {
    if (!vitalsAreValid(v)) return false;
    final t = BandTelemetry(
      heartRateBpm: v.heartRate,
      spo2Pct: v.spo2,
      systolicMmHg: v.systolic,
      diastolicMmHg: v.diastolic,
      coreTempC: v.temperature,
    );
    // Remember it durably. Band telemetry is transient because the band
    // re-supplies it on the next connection; a reading someone typed by hand
    // has no such source, so it must survive a restart.
    _manualSamples.add(HealthSample(
      at: _now(),
      heartRate: v.heartRate?.toDouble(),
      spo2: v.spo2?.toDouble(),
      systolic: v.systolic?.toDouble(),
      diastolic: v.diastolic?.toDouble(),
      coreTemp: v.temperature,
    ));
    if (_manualSamples.length > _maxManualSamples) {
      _manualSamples.removeRange(0, _manualSamples.length - _maxManualSamples);
    }
    // She measured this herself, off a real cuff. Not an estimate — act on it.
    final triage = assessTelemetry(t);
    onTelemetry(t, triage, source: ReadingSource.manual);

    // Make it the reading the assistant sees.
    //
    // AiChatService attaches monitor.latest to every chat message, and the
    // server uses it to bypass the LLM and escalate when the reading is
    // critical. Only band readings ever set it, and the band is not wired yet
    // — so she could enter 175/118, ask "I have a headache, is that normal?",
    // and the request carried no reading at all. record() rather than handle()
    // because this reading is queued and triaged here; handle() would send it
    // a second time.
    _monitor?.record(t, triage);

    // Send it. Nothing did.
    //
    // The batcher's only feeder was HealthMonitor, and the monitor is fed by
    // the BLE stream, which is not wired yet — so the single real source of
    // health data the app has today never left the phone. A mother could
    // record a week of cuff readings, watch them appear on her dashboard, and
    // her clinician's view would show nothing at all. Nothing anywhere said so.
    //
    // Sensor readings are deliberately NOT enqueued here: once the band is
    // paired HealthMonitor enqueues those, and doing both would double-send.
    _batcher?.enqueueTelemetry(
      {
        // No device produced this, so there is none to name. The server
        // attributes a manual reading to the authenticated caller.
        'deviceId': '',
        'source': 'manual',
        'recordedAt': _now().toUtc().toIso8601String(),
        ...t.toJson(),
      },
      urgent: triage.forceEmergencyScreen,
    );
    _persist();
    return true;
  }

  final List<HealthSample> _manualSamples = [];
  static const _maxManualSamples = 500;

  /// Hand-entered readings, oldest first. These are the only samples that
  /// persist across restarts.
  List<HealthSample> get manualSamples => List.unmodifiable(_manualSamples);

  /// Holds a first emergency-level sensor crossing until a second confirms it.
  /// See emergency_confirmation.dart for why one estimate is not enough.
  final _confirmation = EmergencyConfirmation();

  /// The measurement a repeat reading has been asked for, if any — 'bp',
  /// 'fever', 'spo2', 'hr'. Null when nothing is waiting.
  String? _awaitingRepeat;
  String? get awaitingRepeat => _awaitingRepeat;

  /// From BLEDeviceManager.onTelemetry (via HealthMonitor). Records the reading
  /// and latches emergency if triage says so.
  void onTelemetry(
    BandTelemetry t,
    TriageResult triage, {
    ReadingSource source = ReadingSource.sensor,
  }) {
    store.addSample(HealthSample(
      at: _now(),
      heartRate: t.heartRateBpm?.toDouble(),
      spo2: t.spo2Pct?.toDouble(),
      systolic: t.systolicMmHg?.toDouble(),
      diastolic: t.diastolicMmHg?.toDouble(),
      coreTemp: t.coreTempC,
      duringSleep: t.duringSleep,
    ));
    final f = triage.findings.isNotEmpty ? triage.findings.first : null;
    final decision = _confirmation.consider(
      code: f?.code,
      isEmergency: triage.forceEmergencyScreen,
      source: source,
      at: _now(),
    );

    if (decision.shouldAskToRepeat) {
      // One estimate is not enough to take over her screen. Ask for another,
      // and escalate if the condition is still there a couple of minutes on.
      _awaitingRepeat = emergencyFamily(decision.code);
      _notify();
      return;
    }

    if (decision.shouldEscalate) {
      _awaitingRepeat = null;
      final reading = _readingFor(f?.metric, t);
      _raiseEmergency(EmergencyView(
        code: f?.code, // UI localizes the code
        message: f?.message ?? 'Urgent health alert.',
        readingKind: reading?.kind,
        readingValue: reading?.value,
        callButtons: [
          if (_profile.hasDoctor) (label: EmergencyLabels.doctor, tel: _profile.doctorPhone),
          const (label: EmergencyLabels.ambulance, tel: EmergencyLabels.ambulanceTel),
        ],
      ));
      return;
    }

    _notify();
  }

  /// The reading behind a finding, as a kind + a locale-neutral value.
  ///
  /// Blood pressure reports the pair even though the finding names only the
  /// side that crossed: "152/96" is what a dispatcher asks for, and "152" alone
  /// is the kind of half-answer that costs time on a phone call.
  ({String kind, String value})? _readingFor(String? metric, BandTelemetry t) {
    switch (metric) {
      case 'systolicMmHg':
      case 'diastolicMmHg':
        final s = t.systolicMmHg, d = t.diastolicMmHg;
        if (s == null && d == null) return null;
        return (kind: 'bp', value: '${s ?? '—'}/${d ?? '—'}');
      case 'coreTempC':
        final c = t.coreTempC;
        return c == null ? null : (kind: 'temp', value: c.toStringAsFixed(1));
      case 'spo2Pct':
        final o = t.spo2Pct;
        return o == null ? null : (kind: 'spo2', value: '$o');
      case 'heartRateBpm':
        final h = t.heartRateBpm;
        return h == null ? null : (kind: 'hr', value: '$h');
      default:
        return null; // e.g. SYMPTOM_RED_FLAG — there is no number to show
    }
  }

  /// From the AI chat service when the server escalates a message (already localized).
  /// [code] is set when the server escalated on telemetry, whose messages come
  /// from the shared triage rules and are English. Passing it lets the UI
  /// localize exactly as it does an on-device emergency. Null for a text red
  /// flag — the guardrail writes those in her language already.
  void onChatEmergency(
    String message,
    List<({String label, String tel})> callButtons, {
    String? code,
  }) {
    _raiseEmergency(EmergencyView(
      code: code,
      message: message,
      callButtons: callButtons.isEmpty
          ? const [(label: EmergencyLabels.ambulance, tel: EmergencyLabels.ambulanceTel)]
          : callButtons,
    ));
  }

  // ---- Child safety alerts (zone enter/exit history) ----
  String? _lastChildZone;
  ZoneHysteresisState _zoneHysteresis = ZoneHysteresisState.idle;
  final List<SafetyAlert> _alerts = [];
  List<SafetyAlert> get alerts => List.unmodifiable(_alerts);

  /// Hold the feed at its cap, ageing out routine alerts before critical ones.
  /// See [trimAlerts] — trimming by age alone let zone traffic erase old SOSes.
  void _trimAlerts() {
    if (_alerts.length <= maxAlerts) return;
    final kept = trimAlerts(_alerts);
    _alerts
      ..clear()
      ..addAll(kept);
  }

  void clearAlerts() {
    if (_alerts.isEmpty) return;
    _alerts.clear();
    _persist();
    _notify();
  }

  /// Dismiss a single alert from the feed.
  void removeAlert(SafetyAlert alert) {
    final next = removeAlertFrom(_alerts, alert);
    if (next.length == _alerts.length) return; // nothing matched
    _alerts
      ..clear()
      ..addAll(next);
    _persist();
    _notify();
  }

  /// Record a manual child event (check-in or SOS) for the selected child. It
  /// lands at the top of the safety feed and, when notifications are on, is
  /// emitted for an OS notification — the same path geofence alerts take.
  void logChildEvent(AlertKind kind) {
    final child = selectedChild;
    final alert = SafetyAlert(
      kind: kind,
      childName: child?.name ?? childName,
      zoneName: _lastChildZone ?? '',
      at: _now(),
    );
    _alerts.insert(0, alert);
    _trimAlerts();
    if (_notificationsEnabled && !_alertStream.isClosed) _alertStream.add(alert);
    _persist();
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

  /// A new position for the selected child.
  ///
  /// [at] is when the fix was OBSERVED, which for a server-supplied one is not
  /// now: it may have been recorded minutes ago and only just fetched. Passing
  /// it through is what lets the tracking screen say "8 minutes ago" honestly
  /// instead of calling a stale position live — see freshnessOf, which refuses
  /// to call anything live once the clocks disagree.
  ///
  /// A fix OLDER than the one already held is ignored. Polling can answer out
  /// of order, and a late reply carrying an earlier position would walk the
  /// child backwards on the map and could re-fire a zone alert they already
  /// left.
  void onChildLocation(Coordinates coords, {DateTime? at}) {
    final observedAt = at ?? _now();
    final current = _childLocation;
    if (current != null && observedAt.isBefore(current.at)) return;
    _childLocation = ChildLocationView(coords, observedAt);
    final child = selectedChild;
    if (child != null) {
      final r = alertsForFix(
        prevZone: _lastChildZone,
        location: coords,
        fences: child.geofences,
        childName: child.name,
        at: _now(),
        hysteresis: _zoneHysteresis,
      );
      _lastChildZone = r.zone;
      // Carried across fixes, not persisted: a pending zone change is evidence
      // gathered over the last minute or two, and after a restart it is stale.
      // Starting fresh costs one extra confirmation; restoring it could fire a
      // transition on evidence from before the app was closed.
      _zoneHysteresis = r.state;
      if (r.alerts.isNotEmpty) {
        // Newest first; the just-entered zone sits at the top.
        _alerts.insertAll(0, r.alerts.reversed);
        _trimAlerts();
        // Emit chronologically for OS notifications (gated by the preference).
        if (_notificationsEnabled && !_alertStream.isClosed) {
          for (final a in r.alerts) {
            _alertStream.add(a);
          }
        }
        _persist(); // survive restart (feed + last zone, so we don't re-fire)
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

  /// Debug/demo only: skip onboarding so the seeded demo shows the app directly.
  void debugMarkOnboarded() {
    _onboarded = true;
    _notify();
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

  /// Record a night the user typed in themselves, replacing any existing entry
  /// for the same wake date. Returns false if the entry doesn't describe a
  /// usable night (see [validateSleepEntry]).
  ///
  /// Unlike band summaries these are persisted: the band re-sends its own on
  /// the next sync, but nothing re-supplies a night someone entered by hand —
  /// the same reason hand-entered vitals are durable.
  bool logManualSleep(SleepEntry e) {
    if (!sleepEntryIsValid(e)) return false;
    final summary = SleepSummary.manual(
      night: sleepEntryNight(e),
      asleepMin: e.asleepMin,
      awakeMin: e.awakeMin,
    );
    addSleepSummary(summary);
    _manualSleep.removeWhere((n) => _sameNight(n.night, summary.night));
    _manualSleep.add(summary);
    if (_manualSleep.length > _maxManualNights) {
      _manualSleep.removeRange(0, _manualSleep.length - _maxManualNights);
    }
    _persist();
    return true;
  }

  static bool _sameNight(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  final List<SleepSummary> _manualSleep = [];
  static const _maxManualNights = 400; // over a year of hand-logged nights
  List<SleepSummary> get manualSleep => List.unmodifiable(_manualSleep);

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
    // A debounced save still pending when we shut down would simply be lost.
    flushPendingSave();
    await _monitor?.dispose();
    await _chat?.dispose();
    await _alertStream.close();
    await _reminderStream.close();
    await _waterReminderStream.close();
    await _medReminderStream.close();
    await _changes.close();
  }
}
