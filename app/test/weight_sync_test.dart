/// Weight backend sync: the ApiClient POST and the controller hook that mirrors
/// each logged weight to the server (the admin wellness weight trend).
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/weight.dart';
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
  test('putWeight POSTs date + kg to /weight', () async {
    final t = _FakeTransport();
    await ApiClient(t).putWeight(date: '2026-07-20', kg: 64.5);
    final body = t.calls.firstWhere((c) => c.$1 == 'POST /weight').$2 as Map;
    expect(body['date'], '2026-07-20');
    expect(body['kg'], 64.5);
  });

  group('controller weight sync hook', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 20, 12), locale: AppLocale.ru);

    test('logging a weight pushes an upsert with the clamped value', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <WeightEntry>[];
      c.attachWeightSync(upsert: (w) async => pushed.add(w));
      c.logWeight(DateTime(2026, 7, 20), 64.5);
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(1));
      expect(pushed.first.date, '2026-07-20');
      expect(pushed.first.kg, 64.5);
    });

    test('re-logging the same day pushes the updated value (upsert)', () async {
      final c = make();
      addTearDown(c.dispose);
      final pushed = <WeightEntry>[];
      c.attachWeightSync(upsert: (w) async => pushed.add(w));
      c.logWeight(DateTime(2026, 7, 20), 64.5);
      c.logWeight(DateTime(2026, 7, 20), 64.9);
      await Future<void>.delayed(Duration.zero);
      expect(pushed, hasLength(2));
      expect(pushed.last.kg, 64.9);
      expect(c.weights, hasLength(1)); // still one entry for the day locally
    });
  });
}
