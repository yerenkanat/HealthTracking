/// PersistedConfig — durable app state across restarts: onboarding done, language,
/// the mother's profile (name + phone), her children (multiple, each with zones),
/// and paired devices. Pure Dart (JSON in/out) → round-trip testable.
library;

import 'dart:convert';

import '../ble/calibration.dart';
import '../core/geofence.dart';
import '../domain/appointment.dart';
import '../domain/contraction.dart';
import '../domain/cycle_log.dart';
import '../domain/family.dart';
import '../domain/geofence_alerts.dart';
import '../domain/kick_session.dart';
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

Geofence geofenceFromJson(Map<String, dynamic> j) {
  if (j['shape'] == 'polygon') {
    final verts = [
      for (final p in (j['vertices'] as List))
        Coordinates((p[0] as num).toDouble(), (p[1] as num).toDouble())
    ];
    return Geofence.polygon(j['id'] as String, j['name'] as String, verts);
  }
  return Geofence.circle(
    j['id'] as String,
    j['name'] as String,
    Coordinates((j['lat'] as num).toDouble(), (j['lng'] as num).toDouble()),
    (j['radiusM'] as num).toDouble(),
  );
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
      geofences: [
        for (final f in (j['geofences'] as List? ?? const []))
          geofenceFromJson((f as Map).cast<String, dynamic>())
      ],
    );

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
  final int? waterReminderMinutes; // daily reminder time (minutes since midnight); null = off
  final bool periodReminderEnabled; // remind ~2 days before the predicted period

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
    this.waterReminderMinutes,
    this.periodReminderEnabled = false,
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
        if (waterReminderMinutes != null) 'waterReminderMinutes': waterReminderMinutes,
        if (periodReminderEnabled) 'periodReminderEnabled': periodReminderEnabled,
      };

  factory PersistedConfig.fromJson(Map<String, dynamic> j) => PersistedConfig(
        onboarded: (j['onboarded'] as bool?) ?? false,
        locale: appLocaleFromCode(j['locale'] as String?) ?? AppLocale.ru,
        profile: j['profile'] is Map
            ? UserProfile.fromJson((j['profile'] as Map).cast<String, dynamic>())
            : const UserProfile(),
        children: [
          for (final c in (j['children'] as List? ?? const []))
            childFromJson((c as Map).cast<String, dynamic>())
        ],
        devices: [
          for (final d in (j['devices'] as List? ?? const []))
            PairedDevice.fromJson((d as Map).cast<String, dynamic>())
        ],
        bpCalibration: j['bpCalibration'] is Map
            ? BpCalibration.fromJson((j['bpCalibration'] as Map).cast<String, dynamic>())
            : null,
        dayLogs: dayLogsFromJson(
            j['dayLogs'] is Map ? (j['dayLogs'] as Map).cast<String, dynamic>() : null),
        notificationsEnabled: (j['notificationsEnabled'] as bool?) ?? true,
        alerts: [
          for (final a in (j['alerts'] as List? ?? const []))
            SafetyAlert.fromJson((a as Map).cast<String, dynamic>())
        ],
        lastChildZone: j['lastChildZone'] as String?,
        avgCycleLength: (j['avgCycleLength'] as num?)?.toInt(),
        avgPeriodLength: (j['avgPeriodLength'] as num?)?.toInt(),
        kickSessions: [
          for (final k in (j['kickSessions'] as List? ?? const []))
            KickSessionRecord.fromJson((k as Map).cast<String, dynamic>())
        ],
        contractionSessions: [
          for (final s in (j['contractionSessions'] as List? ?? const []))
            ContractionSessionRecord.fromJson((s as Map).cast<String, dynamic>())
        ],
        waterLog: j['waterLog'] is Map
            ? {for (final e in (j['waterLog'] as Map).entries) '${e.key}': (e.value as num).toInt()}
            : const {},
        waterGoal: (j['waterGoal'] as num?)?.toInt(),
        appointments: [
          for (final a in (j['appointments'] as List? ?? const []))
            Appointment.fromJson((a as Map).cast<String, dynamic>())
        ],
        weights: [
          for (final w in (j['weights'] as List? ?? const []))
            WeightEntry.fromJson((w as Map).cast<String, dynamic>())
        ],
        weightGoalKg: (j['weightGoalKg'] as num?)?.toDouble(),
        childBattery: j['childBattery'] is Map
            ? {for (final e in (j['childBattery'] as Map).entries) '${e.key}': (e.value as num).toInt()}
            : const {},
        waterReminderMinutes: (j['waterReminderMinutes'] as num?)?.toInt(),
        periodReminderEnabled: (j['periodReminderEnabled'] as bool?) ?? false,
      );

  String encode() => jsonEncode(toJson());
  static PersistedConfig decode(String s) =>
      PersistedConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
