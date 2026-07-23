/// Newborn-care backend sync: the ApiClient PUT and the controller hook that
/// mirrors each logged feed/diaper/sleep to the server (the admin care log).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/newborn_log.dart';
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
  test('putNewbornEvent posts the event under the child', () async {
    final t = _FakeTransport();
    await ApiClient(t).putNewbornEvent('child-1', {'at': '2026-07-21T08:00:00.000Z', 'kind': 'feed', 'detail': 'left'});
    final call = t.calls.firstWhere((c) => c.$1 == 'POST /children/child-1/newborn-events');
    final body = call.$2 as Map;
    expect(body['kind'], 'feed');
    expect(body['detail'], 'left');
  });

  group('controller newborn sync hook', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 23, 12), locale: AppLocale.ru);

    test('logging a newborn event pushes an upsert with the child id', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <(String, NewbornEvent)>[];
      c.attachNewbornSync(upsert: (id, e) async => pushed.add((id, e)));
      c.logNewbornEvent('child-1', NewbornEvent(at: DateTime(2026, 7, 23, 8), kind: NewbornEventKind.feed, detail: 'left'));
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.$1, 'child-1');
      expect(pushed.first.$2.kind, NewbornEventKind.feed);
      // Serialises to the wire shape.
      expect(pushed.first.$2.toJson()['kind'], 'feed');
    });
  });
}
