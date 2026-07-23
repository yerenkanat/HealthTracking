/// New-device restore: Geofence.fromJson parsing, the ApiClient pull calls, and
/// the controller merges that bring children + zones + medications back from the
/// server without clobbering local data.
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/core/uuid.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/domain/medication.dart';
import 'package:fcs_app/l10n/l10n.dart';

class _FakeTransport implements HttpTransport {
  Map<String, Object?> bodies = {};
  @override
  Future<HttpResponse> get(String path) async => HttpResponse(200, jsonEncode(bodies[path] ?? {}));
  @override
  Future<HttpResponse> post(String path, Object body) async => const HttpResponse(201, '{}');
  @override
  Future<HttpResponse> put(String path, Object body) async => const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');
}

void main() {
  group('Geofence.fromJson', () {
    test('parses a circle', () {
      final g = Geofence.fromJson({'id': 'z1', 'name': 'Дом', 'shape': 'circle', 'center': {'lat': 43.2, 'lng': 76.9}, 'radiusM': 100});
      expect(g.shape, GeofenceShape.circle);
      expect(g.center!.lat, 43.2);
      expect(g.radiusM, 100);
    });

    test('parses a polygon', () {
      final g = Geofence.fromJson({'id': 'z2', 'name': 'Школа', 'shape': 'polygon', 'vertices': [
        {'lat': 1, 'lng': 1}, {'lat': 1, 'lng': 2}, {'lat': 2, 'lng': 2},
      ]});
      expect(g.shape, GeofenceShape.polygon);
      expect(g.vertices, hasLength(3));
    });

    test('throws on an unusable row (so the caller can drop it)', () {
      expect(() => Geofence.fromJson({'id': 'z', 'name': 'x', 'shape': 'circle'}), throwsFormatException);
    });
  });

  group('ApiClient pulls', () {
    test('getChildren parses id/name/gender/dateOfBirth', () async {
      final t = _FakeTransport()..bodies['/children'] = {'children': [
        {'id': 'c1', 'name': 'Aisha', 'gender': 'girl', 'dateOfBirth': '2024-03-01'},
      ]};
      final kids = await ApiClient(t).getChildren();
      expect(kids.first['gender'], 'girl');
      expect(kids.first['dateOfBirth'], '2024-03-01');
    });

    test('getChildGeofences parses the zone list', () async {
      final t = _FakeTransport()..bodies['/children/c1/geofences'] = {'geofences': [
        {'id': 'z1', 'name': 'Дом', 'shape': 'circle', 'center': {'lat': 1, 'lng': 2}, 'radiusM': 50},
      ]};
      final zones = await ApiClient(t).getChildGeofences('c1');
      expect(zones.first['name'], 'Дом');
    });
  });

  group('controller merges', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 23, 12), locale: AppLocale.ru);

    test('mergeRemoteChildren adds server children and keeps local', () {
      final c = make();
      addTearDown(c.dispose);
      final localId = uuidV4();
      c.addChild(ChildProfile(id: localId, name: 'Local'));
      final remoteId = uuidV4();
      c.mergeRemoteChildren([
        ChildProfile(id: remoteId, name: 'Restored', gender: Gender.girl, geofences: [Geofence.circle('z', 'Дом', const Coordinates(1, 2), 50)]),
        ChildProfile(id: localId, name: 'dupe'), // already have → skipped
      ]);
      final ids = c.children.map((x) => x.id).toSet();
      expect(ids, containsAll([localId, remoteId]));
      expect(c.children, hasLength(2));
      final restored = c.children.firstWhere((x) => x.id == remoteId);
      expect(restored.geofences, hasLength(1)); // zones restored too
    });

    test('mergeRemoteMedications adds missing, keeps local', () {
      final c = make();
      addTearDown(c.dispose);
      c.addMedication('Local med');
      final localMedId = c.medications.single.id;
      c.mergeRemoteMedications([
        const Medication(id: 'remote-1', name: 'Iron', dose: '30mg', perDay: 2),
        Medication(id: localMedId, name: 'dupe'), // skipped
      ]);
      expect(c.medications.map((m) => m.id), containsAll([localMedId, 'remote-1']));
      expect(c.medications, hasLength(2));
    });
  });
}
