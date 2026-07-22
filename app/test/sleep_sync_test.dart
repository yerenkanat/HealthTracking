/// Sleep backend sync: the ApiClient POST /sleep call and the controller hook
/// that mirrors each recorded night to the server (the admin wellness view).
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/manual_sleep.dart';
import 'package:fcs_app/domain/sleep.dart';
import 'package:fcs_app/l10n/l10n.dart';

class _FakeTransport implements HttpTransport {
  final List<(String, Object?)> calls = [];
  @override
  Future<HttpResponse> get(String path) async {
    calls.add(('GET', path));
    return const HttpResponse(200, '{}');
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
  group('ApiClient sleep', () {
    test('putSleep posts the night and stage minutes', () async {
      final t = _FakeTransport();
      await ApiClient(t).putSleep(night: '2026-07-21', deepMin: 95, remMin: 105, lightMin: 280, awakeMin: 25);
      final body = t.calls.firstWhere((c) => c.$1 == 'POST /sleep').$2 as Map;
      expect(body['night'], '2026-07-21');
      expect(body['deepMin'], 95);
      expect(body['remMin'], 105);
      expect(body['lightMin'], 280);
      expect(body['awakeMin'], 25);
    });
  });

  group('controller sleep sync hook', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 22, 12), locale: AppLocale.ru);

    test('recording a night pushes an upsert', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <SleepSummary>[];
      c.attachSleepSync(upsert: (s) async => pushed.add(s));
      c.addSleepSummary(SleepSummary(
        night: DateTime(2026, 7, 21), deepMin: 95, remMin: 105, lightMin: 280, awakeMin: 25));
      await Future<void>.delayed(Duration.zero); // let the fire-and-forget run
      expect(pushed, hasLength(1));
      expect(pushed.first.deepMin, 95);
    });

    test('a hand-logged night still syncs, its whole total as asleep minutes', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <SleepSummary>[];
      c.attachSleepSync(upsert: (s) async => pushed.add(s));
      // Manual entry: 7h asleep, 30m awake, no stage split.
      c.logManualSleep(SleepEntry(
        bedAt: DateTime(2026, 7, 20, 23, 0),
        wokeAt: DateTime(2026, 7, 21, 6, 30),
        awakeMin: 30));
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      // asleepMin - deep - rem = the light figure the sync sends; for a manual
      // night deep/rem are 0, so the full asleep total is preserved.
      final s = pushed.first;
      expect(s.asleepMin - s.deepMin - s.remMin, s.asleepMin);
      expect(s.asleepMin, greaterThan(0));
    });
  });
}
