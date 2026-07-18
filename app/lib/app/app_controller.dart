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
import '../domain/weight.dart';
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
  final DateTime Function() _now;
  final _changes = StreamController<void>.broadcast();
  final _alertStream = StreamController<SafetyAlert>.broadcast();
  final _reminderStream = StreamController<ReminderCommand>.broadcast();
  final _waterReminderStream = StreamController<int?>.broadcast(); // minutes-of-day or null=off

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
  int? _waterReminderMinutes; // daily water reminder time (minutes of day); null = off
  bool _periodReminderEnabled = false;
  bool _fertileReminderEnabled = false;
  static const _periodReminderId = 800001;
  static const _fertileReminderId = 800002;

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
    _applyConfig(cfg);
    _notify();
  }

  /// Replace all in-memory state from [cfg]. Shared by restore() and import.
  void _applyConfig(PersistedConfig cfg) {
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
    _waterReminderMinutes = cfg.waterReminderMinutes;
    _periodReminderEnabled = cfg.periodReminderEnabled;
    _fertileReminderEnabled = cfg.fertileReminderEnabled;
    _alerts
      ..clear()
      ..addAll(cfg.alerts);
    _lastChildZone = cfg.lastChildZone;
    _onboarded = true;
  }

  /// Restore all durable data from a JSON backup (the [exportJson] format).
  /// Returns true on success; false if the text isn't valid backup JSON — the
  /// current state is left untouched on failure.
  bool importJson(String json) {
    PersistedConfig cfg;
    try {
      cfg = PersistedConfig.decode(json);
    } catch (_) {
      return false;
    }
    _applyConfig(cfg);
    // Re-arm reminder notifications for the imported appointments.
    rescheduleReminders();
    _persist();
    _notify();
    return true;
  }

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
        waterReminderMinutes: _waterReminderMinutes,
        periodReminderEnabled: _periodReminderEnabled,
        fertileReminderEnabled: _fertileReminderEnabled,
      );

  void _persist() {
    final s = _persistStore;
    if (s == null) return;
    unawaited(s.save(_snapshot()));
  }

  /// A human-readable, pretty-printed JSON backup of all durable app data
  /// (profile, children, devices, cycle logs, kick sessions, water, weights,
  /// appointments, battery, alerts). Same shape PersistedConfig round-trips, so a
  /// backup can be restored. Health telemetry samples are excluded (regenerated).
  String exportJson() => const JsonEncoder.withIndent('  ').convert(_snapshot().toJson());

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

  // ---- Appointments / reminders ----
  List<Appointment> get appointments => List.unmodifiable(_appointments);

  /// The soonest upcoming appointment (for the profile entry preview), or null.
  Appointment? get nextAppt => nextAppointment(_appointments, _now());

  /// Schedule/cancel commands for the runtime to raise OS reminder notifications.
  Stream<ReminderCommand> get reminderCommands => _reminderStream.stream;

  /// Stable notification id for an appointment (positive 31-bit).
  static int reminderIdFor(String appointmentId) => appointmentId.hashCode & 0x7fffffff;

  ReminderCommand _scheduleCommandFor(Appointment a) {
    final l = L10n(_locale);
    final body = a.note.isNotEmpty ? a.note : l.t('appt_notif_body');
    return ReminderCommand.schedule(reminderIdFor(a.id), a.at, a.title, body);
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
    _persist();
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
    _persist();
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

  /// Update a child tracker's battery reading (from device telemetry). When the
  /// reading first crosses into the low range, raise a low-battery alert (feed +
  /// OS notification) — but not repeatedly while it stays low.
  void setChildBattery(String childId, int pct) {
    final next = clampPct(pct);
    final prev = _childBattery[childId];
    final crossedIntoLow = isLowBattery(next) && (prev == null || !isLowBattery(prev));
    _childBattery[childId] = next;
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
      if (_alerts.length > 50) _alerts.removeRange(50, _alerts.length);
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
    if (_alerts.length > 50) _alerts.removeRange(50, _alerts.length);
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
    await _reminderStream.close();
    await _waterReminderStream.close();
    await _changes.close();
  }
}
