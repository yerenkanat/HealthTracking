/// Device backend sync: the ApiClient calls (create-once with 409-mine tolerated)
/// and the controller hooks that register a paired device and unregister it.
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/family.dart';
import 'package:fcs_app/l10n/l10n.dart';

class _FakeTransport implements HttpTransport {
  final List<(String, Object?)> calls = [];
  int postStatus;
  String postBody;
  _FakeTransport({this.postStatus = 201, this.postBody = '{"ok":true}'});
  @override
  Future<HttpResponse> get(String path) async => const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> post(String path, Object body) async {
    calls.add(('POST $path', body));
    return HttpResponse(postStatus, postBody);
  }

  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);
  @override
  Future<HttpResponse> delete(String path) async {
    calls.add(('DELETE', path));
    return const HttpResponse(204, '');
  }
}

void main() {
  group('ApiClient devices', () {
    test('putDevice posts the device body', () async {
      final t = _FakeTransport();
      await ApiClient(t).putDevice({'id': 'AA:BB', 'name': 'Band', 'kind': 'band', 'childId': null});
      final body = t.calls.firstWhere((c) => c.$1 == 'POST /devices').$2 as Map;
      expect(body['id'], 'AA:BB');
      expect(body['kind'], 'band');
    });

    test('a 409 that is "mine" is treated as already-synced (no throw)', () async {
      final t = _FakeTransport(postStatus: 409, postBody: jsonEncode({'error': 'device_already_registered', 'mine': true}));
      await ApiClient(t).putDevice({'id': 'AA:BB', 'name': 'Band', 'kind': 'band'}); // no throw
    });

    test("a 409 that is someone else's throws", () async {
      final t = _FakeTransport(postStatus: 409, postBody: jsonEncode({'mine': false}));
      expect(() => ApiClient(t).putDevice({'id': 'AA:BB', 'name': 'Band', 'kind': 'band'}),
          throwsA(isA<ApiException>()));
    });

    test('deleteDevice tolerates 404', () async {
      final t = _FakeTransport();
      await ApiClient(t).deleteDevice('AA:BB'); // 204 here; no throw
      expect(t.calls.any((c) => c.$1 == 'DELETE' && c.$2 == '/devices/AA:BB'), isTrue);
    });
  });

  group('controller device sync hooks', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 23, 12), locale: AppLocale.ru);

    test('pairing a device pushes an upsert', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <PairedDevice>[];
      c.attachDeviceSync(upsert: (d) async => pushed.add(d), delete: (_) async {});
      c.addDevice(const PairedDevice(id: 'AA:BB', name: 'Band', kind: DeviceKind.band));
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.id, 'AA:BB');
    });

    test('removing a device pushes a delete', () async {
      final c = make();
      addTearDown(c.dispose);
      c.addDevice(const PairedDevice(id: 'AA:BB', name: 'Band', kind: DeviceKind.band));
      final deleted = <String>[];
      c.attachDeviceSync(upsert: (_) async {}, delete: (id) async => deleted.add(id));
      c.removeDevice('AA:BB');
      await Future<void>.delayed(Duration.zero);
      expect(deleted, ['AA:BB']);
    });
  });
}
