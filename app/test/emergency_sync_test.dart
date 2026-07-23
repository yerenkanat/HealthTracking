/// Child emergency medical-ID backend sync: the ApiClient PUT and the controller
/// hook that mirrors a child's medical-ID to the server (the admin can then show
/// it to a clinician / responder).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/child_emergency.dart';
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
  Future<HttpResponse> put(String path, Object body) async {
    calls.add(('PUT $path', body));
    return const HttpResponse(200, '{"ok":true}');
  }

  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');
}

void main() {
  test('putChildEmergency PUTs the medical-ID under the child', () async {
    final t = _FakeTransport();
    await ApiClient(t).putChildEmergency('child-1', {'bloodType': 'O+', 'allergies': 'penicillin'});
    final call = t.calls.firstWhere((c) => c.$1 == 'PUT /children/child-1/emergency');
    final body = call.$2 as Map;
    expect(body['bloodType'], 'O+');
    expect(body['allergies'], 'penicillin');
  });

  group('controller emergency sync hook', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 23, 12), locale: AppLocale.ru);

    test('setting a child medical-ID pushes an upsert', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <(String, ChildEmergencyInfo)>[];
      c.attachEmergencySync(upsert: (id, info) async => pushed.add((id, info)));
      c.setEmergencyInfo('child-1', const ChildEmergencyInfo(bloodType: 'O+', allergies: 'penicillin'));
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.$1, 'child-1');
      expect(pushed.first.$2.allergies, 'penicillin');
    });

    test('clearing a card still pushes (empty upsert clears the server copy)', () async {
      final c = make();
      addTearDown(c.dispose);
      c.setEmergencyInfo('child-1', const ChildEmergencyInfo(bloodType: 'O+'));
      final pushed = <ChildEmergencyInfo>[];
      c.attachEmergencySync(upsert: (id, info) async => pushed.add(info));
      c.setEmergencyInfo('child-1', const ChildEmergencyInfo()); // emptied
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.isEmpty, isTrue);
    });
  });
}
