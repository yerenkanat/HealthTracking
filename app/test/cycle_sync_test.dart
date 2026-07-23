/// Women's-health day-log backend sync: the ApiClient PUT and the controller
/// hook that mirrors each changed day to the server (the admin wellness diary).
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/cycle_log.dart';
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
  group('ApiClient day logs', () {
    test('putDayLog PUTs the diary body to /cycle/days', () async {
      final t = _FakeTransport();
      await ApiClient(t).putDayLog({'date': '2026-07-20', 'flow': 'medium', 'kicks': 12});
      final call = t.calls.firstWhere((c) => c.$1 == 'PUT /cycle/days');
      final body = call.$2 as Map;
      expect(body['date'], '2026-07-20');
      expect(body['flow'], 'medium');
      expect(body['kicks'], 12);
    });
  });

  group('controller cycle sync hook', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 20, 12), locale: AppLocale.ru);

    test('logging a day pushes an upsert with the wire shape', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <DayLog>[];
      c.attachCycleSync(upsert: (log) async => pushed.add(log));
      c.toggleFlowFor(DateTime(2026, 7, 20), Flow.medium);
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.flow, Flow.medium);
      // The pushed log serialises to exactly what the backend accepts.
      final json = pushed.first.toJson();
      expect(json['flow'], 'medium');
      expect(json['date'], '2026-07-20');
    });

    test('a kick session also mirrors the updated day', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <DayLog>[];
      c.attachCycleSync(upsert: (log) async => pushed.add(log));
      c.logKickSession(DateTime(2026, 7, 20), 8, const Duration(minutes: 30));
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.kicks, 8);
    });

    test('clearing a day still pushes (empty upsert)', () async {
      final c = make();
      addTearDown(c.dispose);
      c.attachCycleSync(upsert: (_) async {});
      c.toggleFlowFor(DateTime(2026, 7, 20), Flow.light); // set
      final pushed = <DayLog>[];
      c.attachCycleSync(upsert: (log) async => pushed.add(log));
      c.toggleFlowFor(DateTime(2026, 7, 20), Flow.light); // toggle off → cleared
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.isEmpty, isTrue); // an empty day is still mirrored
    });
  });
}
