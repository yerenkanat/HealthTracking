/// Safe-zone (geofence) backend sync: the ApiClient calls and the controller
/// hooks that push zone adds/edits and delete removals, so the back-office sees
/// real zones and the server can raise enter/exit alerts.
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/core/geofence.dart';
import 'package:fcs_app/core/uuid.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';

class _FakeTransport implements HttpTransport {
  final List<(String, Object?)> calls = [];
  @override
  Future<HttpResponse> get(String path) async => const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> post(String path, Object body) async {
    calls.add(('POST $path', body));
    return const HttpResponse(201, '{"ok":true}');
  }

  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);
  @override
  Future<HttpResponse> delete(String path) async {
    calls.add(('DELETE', path));
    return const HttpResponse(204, '');
  }
}

Geofence _zone(String id) => Geofence.circle(id, 'Дом', const Coordinates(43.24, 76.9), 100);

void main() {
  group('ApiClient geofences', () {
    test('putGeofence posts the zone body under the child', () async {
      final t = _FakeTransport();
      await ApiClient(t).putGeofence('child-uuid', {
        'id': 'gf-uuid', 'name': 'Дом', 'shape': 'circle',
        'center': {'lat': 43.24, 'lng': 76.9}, 'radiusM': 100,
      });
      final call = t.calls.firstWhere((c) => c.$1 == 'POST /children/child-uuid/geofences');
      final body = call.$2 as Map;
      expect(body['id'], 'gf-uuid');
      expect(body['shape'], 'circle');
      expect((body['center'] as Map)['lat'], 43.24);
    });

    test('deleteGeofence tolerates 404', () async {
      final t = _FakeTransport();
      await ApiClient(t).deleteGeofence('gf-1'); // 204 here; no throw
      expect(t.calls.any((c) => c.$1 == 'DELETE' && c.$2 == '/geofences/gf-1'), isTrue);
    });
  });

  group('controller geofence sync hooks', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 23, 12), locale: AppLocale.ru);

    test('adding a zone pushes an upsert with the child id', () async {
      final c = make();
      addTearDown(c.dispose);
      final childId = uuidV4();
      c.addChild(ChildProfile(id: childId, name: 'Sultan'));
      final pushed = <(String, Geofence)>[];
      c.attachGeofenceSync(upsert: (cid, g) async => pushed.add((cid, g)), delete: (_) async {});
      final zid = uuidV4();
      c.upsertGeofence(childId, _zone(zid));
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.$1, childId);
      expect(pushed.first.$2.id, zid);
    });

    test('removing a zone pushes a delete', () async {
      final c = make();
      addTearDown(c.dispose);
      final childId = uuidV4();
      final zid = uuidV4();
      c.addChild(ChildProfile(id: childId, name: 'Sultan', geofences: [_zone(zid)]));
      final deleted = <String>[];
      c.attachGeofenceSync(upsert: (_, __) async {}, delete: (id) async => deleted.add(id));
      c.removeGeofence(childId, zid);
      await Future<void>.delayed(Duration.zero);
      expect(deleted, [zid]);
    });
  });
}
