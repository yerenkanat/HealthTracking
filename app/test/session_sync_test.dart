/// Timed-session backend sync: the ApiClient calls and the controller hooks that
/// mirror completed fetal-movement and contraction sessions to the server.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
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
  group('ApiClient sessions', () {
    test('putKickSession posts endedAt/count/durationSec', () async {
      final t = _FakeTransport();
      await ApiClient(t).putKickSession({'endedAt': '2026-07-20T10:00:00.000Z', 'count': 10, 'durationSec': 600});
      final body = t.calls.firstWhere((c) => c.$1 == 'POST /kick-sessions').$2 as Map;
      expect(body['count'], 10);
      expect(body['durationSec'], 600);
    });

    test('putContractionSession posts the timing fields', () async {
      final t = _FakeTransport();
      await ApiClient(t).putContractionSession({'endedAt': '2026-07-22T02:00:00.000Z', 'count': 6, 'avgDurationSec': 55, 'avgIntervalSec': 300});
      final body = t.calls.firstWhere((c) => c.$1 == 'POST /contraction-sessions').$2 as Map;
      expect(body['avgIntervalSec'], 300);
    });
  });

  group('controller session sync hooks', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 23, 12), locale: AppLocale.ru);

    test('a finished kick session pushes an upsert', () async {
      final c = make();
      addTearDown(c.dispose);
      var pushed = 0;
      c.attachSessionSync(kick: (s) async => pushed++, contraction: (_) async {});
      c.logKickSession(DateTime(2026, 7, 23), 10, const Duration(minutes: 10));
      await Future<void>.delayed(Duration.zero);
      expect(pushed, 1);
      expect(c.kickSessions.first.count, 10);
    });

    test('a finished contraction session pushes an upsert', () async {
      final c = make();
      addTearDown(c.dispose);
      var pushed = 0;
      c.attachSessionSync(kick: (_) async {}, contraction: (s) async => pushed++);
      c.logContractionSession(6, const Duration(seconds: 55), const Duration(minutes: 5));
      await Future<void>.delayed(Duration.zero);
      expect(pushed, 1);
      expect(c.contractionSessions.first.avgInterval, const Duration(minutes: 5));
    });
  });
}
