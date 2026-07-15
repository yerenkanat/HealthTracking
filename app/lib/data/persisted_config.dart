/// PersistedConfig — the durable slice of app state that must survive a restart:
/// whether onboarding is done, the chosen language, the mother's display name, and
/// the child's name + geofences. Pure Dart (JSON in/out) → round-trip testable.
library;

import 'dart:convert';

import '../core/geofence.dart';
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

class PersistedConfig {
  final bool onboarded;
  final AppLocale locale;
  final String displayName;
  final String childName;
  final String? bandId;
  final List<Geofence> geofences;

  const PersistedConfig({
    required this.onboarded,
    required this.locale,
    required this.displayName,
    required this.childName,
    required this.bandId,
    required this.geofences,
  });

  Map<String, dynamic> toJson() => {
        'version': 1,
        'onboarded': onboarded,
        'locale': locale.name,
        'displayName': displayName,
        'childName': childName,
        'bandId': bandId,
        'geofences': [for (final f in geofences) geofenceToJson(f)],
      };

  factory PersistedConfig.fromJson(Map<String, dynamic> j) => PersistedConfig(
        onboarded: (j['onboarded'] as bool?) ?? false,
        locale: appLocaleFromCode(j['locale'] as String?) ?? AppLocale.ru,
        displayName: (j['displayName'] as String?) ?? '',
        childName: (j['childName'] as String?) ?? '',
        bandId: j['bandId'] as String?,
        geofences: [
          for (final f in (j['geofences'] as List? ?? const []))
            geofenceFromJson((f as Map).cast<String, dynamic>())
        ],
      );

  String encode() => jsonEncode(toJson());
  static PersistedConfig decode(String s) =>
      PersistedConfig.fromJson(jsonDecode(s) as Map<String, dynamic>);
}
