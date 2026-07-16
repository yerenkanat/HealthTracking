/// PersistedConfig — durable app state across restarts: onboarding done, language,
/// the mother's profile (name + phone), her children (multiple, each with zones),
/// and paired devices. Pure Dart (JSON in/out) → round-trip testable.
library;

import 'dart:convert';

import '../ble/calibration.dart';
import '../core/geofence.dart';
import '../domain/cycle_log.dart';
import '../domain/family.dart';
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
      'geofences': [for (final f in c.geofences) geofenceToJson(f)],
    };

ChildProfile childFromJson(Map<String, dynamic> j) => ChildProfile(
      id: j['id'] as String,
      name: (j['name'] as String?) ?? '',
      tagId: j['tagId'] as String?,
      dateOfBirth: j['dateOfBirth'] is String ? DateTime.tryParse(j['dateOfBirth'] as String) : null,
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

  const PersistedConfig({
    required this.onboarded,
    required this.locale,
    required this.profile,
    required this.children,
    required this.devices,
    this.bpCalibration,
    this.dayLogs = const {},
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
      );

  String encode() => jsonEncode(toJson());
  static PersistedConfig decode(String s) =>
      PersistedConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
