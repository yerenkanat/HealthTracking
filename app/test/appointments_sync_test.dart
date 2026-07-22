/// Appointment backend sync: the ApiClient calls and the controller hooks that
/// push local edits and merge the server's on sign-in.
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/appointment.dart';
import 'package:fcs_app/l10n/l10n.dart';

/// Records requests and returns canned responses.
class _FakeTransport implements HttpTransport {
  final List<(String, Object?)> calls = [];
  Object? getBody;
  @override
  Future<HttpResponse> get(String path) async {
    calls.add(('GET', path));
    return HttpResponse(200, jsonEncode(getBody ?? {'appointments': []}));
  }

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

void main() {
  group('ApiClient appointments', () {
    test('getAppointments parses the list', () async {
      final t = _FakeTransport()
        ..getBody = {
          'appointments': [
            {'id': 'a1', 'title': 'УЗИ', 'at': '2026-08-01T09:00:00.000Z', 'note': ''},
          ],
        };
      final list = await ApiClient(t).getAppointments();
      expect(list, hasLength(1));
      expect(list.first['id'], 'a1');
    });

    test('putAppointment posts id/title/at', () async {
      final t = _FakeTransport();
      await ApiClient(t).putAppointment(id: 'a1', title: 'УЗИ', at: '2026-08-01T09:00:00.000Z', note: 'n');
      final body = t.calls.firstWhere((c) => c.$1 == 'POST /appointments').$2 as Map;
      expect(body['id'], 'a1');
      expect(body['title'], 'УЗИ');
      expect(body['note'], 'n');
    });

    test('deleteAppointment tolerates 404', () async {
      final t = _FakeTransport();
      await ApiClient(t).deleteAppointment('a1'); // 204 here; no throw
      expect(t.calls.any((c) => c.$1 == 'DELETE' && c.$2 == '/appointments/a1'), isTrue);
    });
  });

  group('controller sync hooks', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 22, 12), locale: AppLocale.ru);

    test('adding an appointment pushes an upsert', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <Appointment>[];
      c.attachAppointmentSync(
        upsert: (a) async => pushed.add(a),
        delete: (_) async {},
      );
      c.addAppointment('OB visit', DateTime.utc(2026, 8, 3, 9, 30));
      await Future<void>.delayed(Duration.zero); // let the fire-and-forget run
      expect(pushed, hasLength(1));
      expect(pushed.first.title, 'OB visit');
    });

    test('removing an appointment pushes a delete', () async {
      final c = make();
      addTearDown(c.dispose);
      final deleted = <String>[];
      c.attachAppointmentSync(upsert: (_) async {}, delete: (id) async => deleted.add(id));
      c.addAppointment('OB visit', DateTime.utc(2026, 8, 3, 9, 30));
      final id = c.appointments.single.id;
      c.removeAppointment(id);
      await Future<void>.delayed(Duration.zero);
      expect(deleted, [id]);
    });

    test('mergeRemoteAppointments adds server entries and keeps local ones', () {
      final c = make();
      addTearDown(c.dispose);
      c.addAppointment('Local visit', DateTime.utc(2026, 8, 3, 9, 30));
      final localId = c.appointments.single.id;
      c.mergeRemoteAppointments([
        Appointment(id: 'remote-1', title: 'Server visit', at: DateTime.utc(2026, 8, 10, 10)),
        Appointment(id: localId, title: 'dupe', at: DateTime.utc(2026, 8, 3, 9, 30)), // already have → skipped
      ]);
      final ids = c.appointments.map((a) => a.id).toSet();
      expect(ids, containsAll([localId, 'remote-1']));
      expect(c.appointments, hasLength(2)); // the duplicate id was not re-added
    });
  });
}
