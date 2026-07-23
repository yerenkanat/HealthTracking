/// Child backend sync: the ApiClient POST and the controller hook that mirrors
/// each added/edited child to the server (so the kids dashboard is real).
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
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
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');
}

void main() {
  test('putChild POSTs id/name/gender/dob to /children', () async {
    final t = _FakeTransport();
    await ApiClient(t).putChild({'id': uuidV4(), 'name': 'Aruzhan', 'gender': 'girl', 'dateOfBirth': '2024-03-01'});
    final body = t.calls.firstWhere((c) => c.$1 == 'POST /children').$2 as Map;
    expect(body['name'], 'Aruzhan');
    expect(body['gender'], 'girl');
    expect(body['dateOfBirth'], '2024-03-01');
  });

  group('controller child sync hook', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 23), locale: AppLocale.ru);

    test('adding a child pushes an upsert', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <ChildProfile>[];
      c.attachChildSync(upsert: (ch) async => pushed.add(ch));
      c.addChild(ChildProfile(id: uuidV4(), name: 'Sultan', gender: Gender.boy, dateOfBirth: DateTime(2025, 1, 1)));
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.name, 'Sultan');
      expect(pushed.first.gender, Gender.boy);
    });

    test('editing a child pushes the update', () async {
      final c = make();
      addTearDown(c.dispose);
      final id = uuidV4();
      c.addChild(ChildProfile(id: id, name: 'Sultan'));
      final pushed = <ChildProfile>[];
      c.attachChildSync(upsert: (ch) async => pushed.add(ch));
      c.updateChild(ChildProfile(id: id, name: 'Sultan B.', gender: Gender.boy));
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.name, 'Sultan B.');
    });
  });
}
