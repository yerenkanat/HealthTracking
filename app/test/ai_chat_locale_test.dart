/// The assistant's reply language must follow the in-app language switch.
///
/// It used to be frozen to whatever the locale was when the service was built
/// at startup: change the app to Kazakh and the assistant kept answering in
/// Russian. The locale is now a callback read on every send.
library;

import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/domain/ai_chat_service.dart';
import 'package:fcs_app/domain/health_monitor.dart';

/// Captures the locale field of each posted /ai/chat body.
class _CapturingTransport implements HttpTransport {
  final List<String> sentLocales = [];
  @override
  Future<HttpResponse> post(String path, Object body) async {
    sentLocales.add((body as Map)['locale'] as String);
    return HttpResponse(200, jsonEncode({'kind': 'chat', 'message': 'ok', 'grounded': true}));
  }

  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);
  @override
  Future<HttpResponse> get(String path) async => const HttpResponse(404, '');
  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');
}

void main() {
  test('the chat sends the current locale, not the startup one', () async {
    final transport = _CapturingTransport();
    var locale = 'ru'; // the app language, changed at runtime below
    final service = AiChatService(
      api: ApiClient(transport),
      userId: 'u',
      locale: () => locale,
      monitor: HealthMonitor(deviceId: 'd', enqueue: (_, {required urgent}) {}, onEmergency: (_, __) {}),
      onEmergency: (_) {},
    );

    await service.send('привет');
    locale = 'kk'; // she switches the app to Kazakh
    await service.send('сәлем');
    locale = 'en';
    await service.send('hi');

    expect(transport.sentLocales, ['ru', 'kk', 'en']);
  });
}
