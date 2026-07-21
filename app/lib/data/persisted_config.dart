/// PersistedConfig — durable app state across restarts: onboarding done, language,
/// the mother's profile (name + phone), her children (multiple, each with zones),
/// and paired devices. Pure Dart (JSON in/out) → round-trip testable.
library;

import 'dart:convert';

import '../ble/calibration.dart';
import '../core/geofence.dart';
import '../domain/appointment.dart';
import '../domain/battery.dart';
import '../domain/contraction.dart';
import '../domain/cycle_log.dart';
import '../domain/family.dart';
import '../domain/geofence_alerts.dart';
import '../domain/health_series.dart';
import '../domain/kick_session.dart';
import '../domain/medication.dart';
import '../domain/sleep.dart';
import '../domain/child_growth.dart';
import '../domain/weight.dart';
import '../l10n/l10n.dart';

// ---- Geofence (de)serialization (circle + polygon) ----
Map<String, dynamic> geofenceToJson(Geofence f) => switch (f.shape) {
      GeofenceShape.circle => {
          'id': f.id,
          'name': f.name,
          'shape': 'circle',
          'lat': f.center!.lat,
          'lng': f.center!.lng,
          'radiusM': f.radiusM,
        },
      GeofenceShape.polygon => {
          'id': f.id,
          'name': f.name,
          'shape': 'polygon',
          'vertices': [for (final v in f.vertices!) [v.lat, v.lng]],
        },
    };

/// Read one zone, refusing shapes that could never fire.
///
/// A polygon needs three points to enclose anything; a circle of radius zero
/// has no inside. Both parse cleanly and are geometrically dead — kept, they
/// sit in her zone list looking like protection that works, and no alert ever
/// comes. Throwing hands them to the tolerant list parser, which drops the
/// zone and counts it, so the loss is reported rather than silent.
///
/// Reachable because the app exports and imports its own backup as JSON, and
/// because the zone editor's 50m minimum radius is a UI rule, not a data one.
Geofence geofenceFromJson(Map<String, dynamic> j) {
  final id = j['id'] as String;
  final name = j['name'] as String;
  if (j['shape'] == 'polygon') {
    final verts = [
      for (final p in (j['vertices'] as List))
        Coordinates((p[0] as num).toDouble(), (p[1] as num).toDouble())
    ];
    if (verts.length < 3) {
      throw FormatException('polygon zone "$id" has ${verts.length} vertices, needs 3');
    }
    return Geofence.polygon(id, name, verts);
  }
  final radius = (j['radiusM'] as num).toDouble();
  if (!radius.isFinite || radius <= 0) {
    throw FormatException('circle zone "$id" has no usable radius ($radius)');
  }
  final lat = (j['lat'] as num).toDouble();
  final lng = (j['lng'] as num).toDouble();
  if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
    throw FormatException('circle zone "$id" is not on Earth ($lat, $lng)');
  }
  return Geofence.circle(id, name, Coordinates(lat, lng), radius);
}

Map<String, dynamic> childToJson(ChildProfile c) => {
      'id': c.id,
      'name': c.name,
      'tagId': c.tagId,
      if (c.dateOfBirth != null) 'dateOfBirth': c.dateOfBirth!.toIso8601String(),
      if (c.photoPath != null) 'photoPath': c.photoPath,
      if (c.gender != null) 'gender': c.gender!.name,
      'geofences': [for (final f in c.geofences) geofenceToJson(f)],
    };

ChildProfile childFromJson(Map<String, dynamic> j) => ChildProfile(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? '',
      tagId: j['tagId'] as String?,
      dateOfBirth: j['dateOfBirth'] is String ? DateTime.tryParse(j['dateOfBirth'] as String) : null,
      photoPath: j['photoPath'] as String?,
      gender: genderFromName(j['gender'] as String?),
      // Tolerantly, and NOT inline.
      //
      // These were parsed in place, so one unreadable zone threw and the outer
      // list dropped the whole child — her name, her date of birth, her photo
      // and every other zone she had drawn — to save one corrupted circle.
      // A bad zone should cost that zone.
      geofences: geofencesFromJson(j['geofences']),
    );

/// Read a list of zones, dropping and counting the ones that cannot be used.
List<Geofence> geofencesFromJson(Object? raw) {
  if (raw is! List) return const [];
  final out = <Geofence>[];
  for (final f in raw) {
    if (f is! Map) {
      PersistedConfig.lastDroppedEntries++;
      continue;
    }
    try {
      out.add(geofenceFromJson(f.cast<String, dynamic>()));
    } catch (_) {
      PersistedConfig.lastDroppedEntries++;
    }
  }
  return out;
}

/// Does this decoded JSON actually look like an Umay backup?
///
/// Every field of [PersistedConfig] is optional with a default, so ANY JSON
/// object decodes into a valid-but-empty config. Applying one of those would
/// wipe the user's data — so an import must check the payload is ours first.
///
/// Accepts either the export marker, or the two keys `toJson` always writes
/// (so backups made before the marker existed still restore).
bool looksLikeBackup(Object? decoded) {
  if (decoded is! Map) return false;
  if (decoded['app'] == 'Umay') return true;
  return decoded.containsKey('locale') && decoded.containsKey('profile');
}

class PersistedConfig {
  final bool onboarded;
  final AppLocale locale;
  final UserProfile profile;
  final List<ChildProfile> children;
  final List<PairedDevice> devices;
  final BpCalibration? bpCalibration;
  final Map<String, DayLog> dayLogs; // dateKey → women's-health day entry
  final bool notificationsEnabled;
  final List<SafetyAlert> alerts; // recent zone enter/exit history
  final String? lastChildZone; // last known zone (avoids re-firing on restart)
  final int? avgCycleLength; // user-set baseline until ≥2 cycles are logged
  final int? avgPeriodLength;
  final List<KickSessionRecord> kickSessions; // completed timed sessions (newest last)
  final List<ContractionSessionRecord> contractionSessions; // completed labour-timing sessions
  final Map<String, int> waterLog; // dateKey → glasses drunk that day
  final int? waterGoal; // daily target (glasses); null → default
  final List<Appointment> appointments; // the mother's dated reminders
  final List<WeightEntry> weights; // weight log (one per day)
  final double? weightGoalKg; // user-set target weight (null = none)
  final Map<String, int> childBattery; // childId → tracker battery % (last known)
  final Map<String, List<BatteryReading>> childBatteryHistory; // childId → readings (oldest-first)
  final Map<String, List<GrowthPoint>> childGrowth; // childId → weight/height measurements (oldest-first)
  final int? waterReminderMinutes; // daily reminder time (minutes since midnight); null = off
  final int? medReminderMinutes; // daily medication reminder time; null = off
  final bool periodReminderEnabled; // remind ~2 days before the predicted period
  final bool fertileReminderEnabled; // remind when the fertile window opens
  final DateTime? lastExportAt; // when data was last exported (= backed up)
  final List<Medication> medications; // supplements/medicines the user tracks
  final MedLog medLog; // dateKey → medId → doses taken
  /// Hand-entered readings only. Band telemetry stays transient because the band
  /// re-supplies it each session; nothing re-supplies a reading a person typed.
  final List<HealthSample> manualSamples;

  /// Hand-entered nights only, for the same reason as [manualSamples]: the band
  /// re-sends its own summaries on the next sync, but nothing re-supplies a
  /// night the user typed in themselves.
  final List<SleepSummary> manualSleep;

  const PersistedConfig({
    required this.onboarded,
    required this.locale,
    required this.profile,
    required this.children,
    required this.devices,
    this.bpCalibration,
    this.dayLogs = const {},
    this.notificationsEnabled = true,
    this.alerts = const [],
    this.lastChildZone,
    this.avgCycleLength,
    this.avgPeriodLength,
    this.kickSessions = const [],
    this.contractionSessions = const [],
    this.waterLog = const {},
    this.waterGoal,
    this.appointments = const [],
    this.weights = const [],
    this.weightGoalKg,
    this.childBattery = const {},
    this.childBatteryHistory = const {},
    this.childGrowth = const {},
    this.waterReminderMinutes,
    this.medReminderMinutes,
    this.periodReminderEnabled = false,
    this.fertileReminderEnabled = false,
    this.lastExportAt,
    this.medications = const [],
    this.medLog = const {},
    this.manualSamples = const [],
    this.manualSleep = const [],
  });

  Map<String, dynamic> toJson() => {
        'version': 4,
        'onboarded': onboarded,
        'locale': locale.name,
        'profile': profile.toJson(),
        'children': [for (final c in children) childToJson(c)],
        'devices': [for (final d in devices) d.toJson()],
        if (bpCalibration != null) 'bpCalibration': bpCalibration!.toJson(),
        if (dayLogs.isNotEmpty) 'dayLogs': dayLogsToJson(dayLogs),
        'notificationsEnabled': notificationsEnabled,
        if (alerts.isNotEmpty) 'alerts': [for (final a in alerts) a.toJson()],
        if (lastChildZone != null) 'lastChildZone': lastChildZone,
        if (avgCycleLength != null) 'avgCycleLength': avgCycleLength,
        if (avgPeriodLength != null) 'avgPeriodLength': avgPeriodLength,
        if (kickSessions.isNotEmpty) 'kickSessions': [for (final k in kickSessions) k.toJson()],
        if (contractionSessions.isNotEmpty) 'contractionSessions': [for (final s in contractionSessions) s.toJson()],
        if (waterLog.isNotEmpty) 'waterLog': waterLog,
        if (waterGoal != null) 'waterGoal': waterGoal,
        if (appointments.isNotEmpty) 'appointments': [for (final a in appointments) a.toJson()],
        if (weights.isNotEmpty) 'weights': [for (final w in weights) w.toJson()],
        if (weightGoalKg != null) 'weightGoalKg': weightGoalKg,
        if (childBattery.isNotEmpty) 'childBattery': childBattery,
        if (childGrowth.isNotEmpty)
          'childGrowth': {
            for (final e in childGrowth.entries) e.key: [for (final p in e.value) p.toJson()]
          },
        if (childBatteryHistory.isNotEmpty)
          'childBatteryHistory': {
            for (final e in childBatteryHistory.entries) e.key: [for (final r in e.value) r.toJson()]
          },
        if (waterReminderMinutes != null) 'waterReminderMinutes': waterReminderMinutes,
        if (medReminderMinutes != null) 'medReminderMinutes': medReminderMinutes,
        if (periodReminderEnabled) 'periodReminderEnabled': periodReminderEnabled,
        if (fertileReminderEnabled) 'fertileReminderEnabled': fertileReminderEnabled,
        if (lastExportAt != null) 'lastExportAt': lastExportAt!.toIso8601String(),
        if (medications.isNotEmpty) 'medications': [for (final m in medications) m.toJson()],
        if (medLog.isNotEmpty) 'medLog': medLogToJson(medLog),
        if (manualSamples.isNotEmpty) 'manualSamples': [for (final s in manualSamples) s.toJson()],
        if (manualSleep.isNotEmpty) 'manualSleep': [for (final n in manualSleep) n.toJson()],
      };

  /// How many entries the last [fromJson] had to discard.
  ///
  /// Exposed so the caller can say "two appointments could not be read" rather
  /// than let them vanish unremarked. Reset on every parse.
  static int lastDroppedEntries = 0;

  /// Parse one item, or drop it.
  ///
  /// WHY EACH ITEM IS ISOLATED
  ///
  /// Every list here used to be all-or-nothing: one appointment with an
  /// unparseable date, or one weight entry whose number arrived as a string,
  /// threw out of the whole constructor. PrefsAppStore.load catches that and
  /// returns null, restore() then returns early — and the app shows FIRST-RUN
  /// ONBOARDING. Her pregnancy, her children, their zones and her entire
  /// history are still on the disk, unreachable, while the app behaves as
  /// though she had never used it.
  ///
  /// This is her only copy. A single bad field must cost her that field, not
  /// everything.
  static List<T> _items<T>(Object? raw, T Function(Map<String, dynamic>) parse) {
    if (raw is! List) return const [];
    final out = <T>[];
    for (final e in raw) {
      if (e is! Map) {
        lastDroppedEntries++;
        continue;
      }
      try {
        out.add(parse(e.cast<String, dynamic>()));
      } catch (_) {
        lastDroppedEntries++;
      }
    }
    return out;
  }

  /// As [_items], for a map of id → int (water log, battery levels).
  static Map<String, int> _intMap(Object? raw) {
    if (raw is! Map) return const {};
    final out = <String, int>{};
    for (final e in raw.entries) {
      final v = e.value;
      if (v is num) {
        out['${e.key}'] = v.toInt();
      } else {
        lastDroppedEntries++;
      }
    }
    return out;
  }

  factory PersistedConfig.fromJson(Map<String, dynamic> j) {
    lastDroppedEntries = 0;
    return _fromJson(j);
  }

  static PersistedConfig _fromJson(Map<String, dynamic> j) => PersistedConfig(
        onboarded: (j['onboarded'] as bool?) ?? false,
        locale: appLocaleFromCode(j['locale'] as String?) ?? AppLocale.ru,
        profile: j['profile'] is Map
            ? UserProfile.fromJson((j['profile'] as Map).cast<String, dynamic>())
            : const UserProfile(),
        children: _items(j['children'], childFromJson),
        devices: _items(j['devices'], PairedDevice.fromJson),
        bpCalibration: j['bpCalibration'] is Map
            ? BpCalibration.fromJson((j['bpCalibration'] as Map).cast<String, dynamic>())
            : null,
        dayLogs: dayLogsFromJson(
            j['dayLogs'] is Map ? (j['dayLogs'] as Map).cast<String, dynamic>() : null),
        notificationsEnabled: (j['notificationsEnabled'] as bool?) ?? true,
        alerts: _items(j['alerts'], SafetyAlert.fromJson),
        lastChildZone: j['lastChildZone'] as String?,
        avgCycleLength: (j['avgCycleLength'] as num?)?.toInt(),
        avgPeriodLength: (j['avgPeriodLength'] as num?)?.toInt(),
        kickSessions: _items(j['kickSessions'], KickSessionRecord.fromJson),
        contractionSessions: _items(j['contractionSessions'], ContractionSessionRecord.fromJson),
        waterLog: _intMap(j['waterLog']),
        waterGoal: (j['waterGoal'] as num?)?.toInt(),
        appointments: _items(j['appointments'], Appointment.fromJson),
        weights: _items(j['weights'], WeightEntry.fromJson),
        weightGoalKg: (j['weightGoalKg'] as num?)?.toDouble(),
        childBattery: _intMap(j['childBattery']),
        childBatteryHistory: j['childBatteryHistory'] is Map
            ? {
                for (final e in (j['childBatteryHistory'] as Map).entries)
                  '${e.key}': [
                    for (final r in (e.value as List)) BatteryReading.fromJson((r as Map).cast<String, dynamic>())
                  ]
              }
            : const {},
        // Tolerant per-visit: a corrupt measurement drops that visit and is
        // counted, not the whole child — same contract as every other list here.
        childGrowth: j['childGrowth'] is Map
            ? {
                for (final e in (j['childGrowth'] as Map).entries)
                  '${e.key}': _items(e.value, GrowthPoint.fromJson)
              }
            : const {},
        waterReminderMinutes: (j['waterReminderMinutes'] as num?)?.toInt(),
        medReminderMinutes: (j['medReminderMinutes'] as num?)?.toInt(),
        periodReminderEnabled: (j['periodReminderEnabled'] as bool?) ?? false,
        fertileReminderEnabled: (j['fertileReminderEnabled'] as bool?) ?? false,
        lastExportAt: j['lastExportAt'] is String ? DateTime.tryParse(j['lastExportAt'] as String) : null,
        medications: [
          for (final m in (j['medications'] as List? ?? const []))
            Medication.fromJson((m as Map).cast<String, dynamic>())
        ],
        medLog: j['medLog'] is Map ? medLogFromJson((j['medLog'] as Map).cast<String, dynamic>()) : const {},
        manualSamples: [
          for (final s in (j['manualSamples'] as List? ?? const []))
            HealthSample.fromJson((s as Map).cast<String, dynamic>())
        ],
        manualSleep: [
          for (final n in (j['manualSleep'] as List? ?? const []))
            SleepSummary.fromJson((n as Map).cast<String, dynamic>())
        ],
      );

  String encode() => jsonEncode(toJson());
  static PersistedConfig decode(String s) =>
      PersistedConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
