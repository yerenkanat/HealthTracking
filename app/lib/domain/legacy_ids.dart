/// Re-issuing the ids that could never sync.
///
/// Onboarding used to mint the literal strings `child-1`, `home` and `school`.
/// The server requires a UUID for a child and for a geofence, so every one of
/// those was refused with a 400 — and the push is fire-and-forget, so nothing
/// ever said so. Fixing onboarding helps the next install; it does nothing for
/// a phone that already has one of these on it, and that is every phone the
/// app has been installed on so far.
///
/// So the ids are re-issued once, on load. This is data the mother typed in —
/// her child's name and date of birth, the coordinates of her home and her
/// child's school — so it is renamed, never dropped.
///
/// PURE Dart: no Flutter, no storage, no clock. Everything about it is decided
/// by its inputs, which is what lets the awkward part — that a child id is
/// referenced from seven other places — be checked exhaustively.
library;

import '../core/geofence.dart';
import '../core/uuid.dart';
import 'family.dart';

/// Does this id look like something the server will accept?
///
/// Deliberately the same shape the backend's zod schema tests for. Anything
/// else is an id that cannot be written to a UUID column, whatever it is.
final _uuid = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
    caseSensitive: false);
bool isSyncableId(String id) => _uuid.hasMatch(id);

/// What a migration produced: the rewritten children, and the id changes so a
/// caller can carry every side table across.
class ReissuedIds {
  final List<ChildProfile> children;

  /// old child id → new child id. Empty when nothing needed changing.
  final Map<String, String> childIds;

  /// old geofence id → new geofence id, across all children.
  final Map<String, String> geofenceIds;

  const ReissuedIds({
    required this.children,
    required this.childIds,
    required this.geofenceIds,
  });

  /// True when nothing was rewritten — the common case after the first run,
  /// and the signal to skip an otherwise pointless save.
  bool get isEmpty => childIds.isEmpty && geofenceIds.isEmpty;
}

/// Give every child and zone a syncable id, keeping the ones that already are.
///
/// [newId] is injectable so a test can produce a predictable sequence; leave it
/// out and it mints real UUIDs.
ReissuedIds reissueUnsyncableIds(
  List<ChildProfile> children, {
  String Function()? newId,
}) {
  final mint = newId ?? uuidV4;
  final childIds = <String, String>{};
  final geofenceIds = <String, String>{};

  final rewritten = <ChildProfile>[];
  for (final child in children) {
    // An id that is already a UUID is LEFT ALONE. Re-issuing it would orphan
    // the copy the server already has and duplicate the child in the back
    // office — the opposite of the point.
    final childId = isSyncableId(child.id) ? child.id : mint();
    if (childId != child.id) childIds[child.id] = childId;

    final zones = <Geofence>[];
    for (final zone in child.geofences) {
      if (isSyncableId(zone.id)) {
        zones.add(zone);
        continue;
      }
      final zoneId = mint();
      geofenceIds[zone.id] = zoneId;
      // Built field by field rather than through a copyWith: ChildProfile and
      // Geofence both deliberately refuse to change an id, because everywhere
      // else in the app that would be a bug. This is the one place it is the
      // point, so it is spelled out.
      zones.add(Geofence(
        id: zoneId,
        name: zone.name,
        shape: zone.shape,
        center: zone.center,
        radiusM: zone.radiusM,
        vertices: zone.vertices,
      ));
    }

    rewritten.add(ChildProfile(
      id: childId,
      name: child.name,
      geofences: zones,
      tagId: child.tagId,
      dateOfBirth: child.dateOfBirth,
      photoPath: child.photoPath,
      gender: child.gender,
    ));
  }

  return ReissuedIds(children: rewritten, childIds: childIds, geofenceIds: geofenceIds);
}

/// Move the values of a childId-keyed map onto the new ids.
///
/// Every side table the app keeps about a child — battery, battery history,
/// growth, the newborn log, vaccinations — is keyed by the child's id, so a
/// migration that renamed only the child would silently orphan all of it: her
/// baby's weight chart and vaccination record would go blank on upgrade, which
/// is a worse bug than the one being fixed.
Map<String, V> remapKeys<V>(Map<String, V> byChildId, Map<String, String> renamed) {
  if (renamed.isEmpty) return byChildId;
  return {
    for (final e in byChildId.entries) renamed[e.key] ?? e.key: e.value,
  };
}

/// A day the server will accept, out of whatever an older build wrote.
///
/// A day log is keyed by `yyyy-MM-dd`, and both places that write one today
/// use [dateKey]. An older build stored full ISO timestamps —
/// `2026-05-21T00:00:00.000Z` — and those rows are still on the handset. The
/// server requires `^\d{4}-\d{2}-\d{2}$`, so every one of them is refused with
/// a 400: months of her cycle diary that can never reach the back office.
///
/// Returns null for anything that is not a date at all, so a corrupt key is
/// dropped rather than sent.
String? normaliseDayKey(String key) {
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(key)) return key;
  // Take the calendar day, in whatever zone it was written in. The alternative
  // — parsing and converting — moves entries across midnight and rewrites the
  // day she recorded something on.
  final m = RegExp(r'^(\d{4}-\d{2}-\d{2})T').firstMatch(key);
  return m?.group(1);
}

/// Rewrite a day-keyed map so every key is one the server accepts.
///
/// [withDate] rebuilds a value whose own `date` field has to match its key —
/// a DayLog carries the day twice, and fixing only the key would send a body
/// the server refuses for the same reason.
///
/// When both forms of the same day exist, the one already in the accepted
/// format wins: it was written by the current code and is the later of the
/// two.
Map<String, V> normaliseDayKeys<V>(
  Map<String, V> byDay,
  V Function(V value, String day) withDate,
) {
  final out = <String, V>{};
  final wasAlreadyFine = <String>{};
  for (final e in byDay.entries) {
    final day = normaliseDayKey(e.key);
    if (day == null) continue; // not a date; nothing can be done with it
    final alreadyFine = day == e.key;
    if (out.containsKey(day) && !alreadyFine) continue;
    if (out.containsKey(day) && wasAlreadyFine.contains(day)) continue;
    if (alreadyFine) wasAlreadyFine.add(day);
    out[day] = alreadyFine ? e.value : withDate(e.value, day);
  }
  return out;
}

/// Point devices at the child's new id.
List<PairedDevice> remapDeviceChildIds(
    List<PairedDevice> devices, Map<String, String> renamed) {
  if (renamed.isEmpty) return devices;
  return [
    for (final d in devices)
      d.childId == null || renamed[d.childId] == null
          ? d
          : PairedDevice(id: d.id, name: d.name, kind: d.kind, childId: renamed[d.childId]),
  ];
}
