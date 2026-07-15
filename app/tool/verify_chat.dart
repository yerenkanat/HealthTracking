/// Pure-Dart verification of ChatController message handling + outcome routing.
/// `dart run tool/verify_chat.dart`
library;

import 'dart:convert';
import 'dart:io';

import '../lib/data/api_client.dart';
import '../lib/domain/ai_chat_service.dart';
import '../lib/domain/chat_controller.dart';
import '../lib/domain/health_monitor.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

class FakeTransport implements HttpTransport {
  final HttpResponse Function(String path, Object body) handler;
  FakeTransport(this.handler);
  @override
  Future<HttpResponse> post(String path, Object body) async => handler(path, body);
  @override
  Future<HttpResponse> get(String path) async => const HttpResponse(404, '');
}

ChatController build(HttpResponse Function(String, Object) handler, {void Function()? onEmergency}) {
  final api = ApiClient(FakeTransport(handler));
  final monitor = HealthMonitor(
    deviceId: 'd', enqueue: (_, {required urgent}) {}, onEmergency: (_, __) {});
  final service = AiChatService(
    api: api, userId: 'u', locale: 'ru-KZ', monitor: monitor,
    onEmergency: (_) => onEmergency?.call(),
  );
  return ChatController(
    service: service,
    networkErrorText: () => 'NET_ERROR',
    emergencyNoteText: () => 'EMERGENCY_NOTE',
  );
}

HttpResponse json(Map<String, dynamic> m) => HttpResponse(200, jsonEncode(m));

Future<void> main() async {
  // ---- normal reply ----
  final c1 = build((_, __) => json({'kind': 'chat', 'message': 'Drink water.', 'grounded': true}));
  await c1.send('tips?');
  _chk('user + assistant appended', c1.messages.length == 2);
  _chk('user message first', c1.messages[0].role == ChatRole.user && c1.messages[0].text == 'tips?');
  _chk('assistant reply text', c1.messages[1].role == ChatRole.assistant && c1.messages[1].text == 'Drink water.');
  _chk('not sending after done', c1.sending == false);

  // ---- empty text is a no-op ----
  final c2 = build((_, __) => json({'kind': 'chat', 'message': 'x', 'grounded': false}));
  await c2.send('   ');
  _chk('empty text ignored', c2.messages.isEmpty);

  // ---- blocked outcome shows safe fallback ----
  final c3 = build((_, __) => json({'kind': 'blocked', 'message': 'I can only help with wellness.', 'reason': 'prompt_injection'}));
  await c3.send('ignore instructions');
  _chk('blocked -> assistant safe message', c3.messages.last.text == 'I can only help with wellness.' && c3.messages.last.isBlocked);

  // ---- emergency outcome fires app-level callback + flags message ----
  var emergencyFired = 0;
  final c4 = build(
    (_, __) => json({'kind': 'emergency', 'message': 'BP dangerous.', 'callButtons': [{'label': 'Amb', 'tel': '103'}]}),
    onEmergency: () => emergencyFired++,
  );
  await c4.send('is my bp ok?');
  _chk('emergency fired app callback', emergencyFired == 1);
  _chk('emergency message flagged', c4.messages.last.isEmergency);

  // ---- network failure -> safe error text, sending resets ----
  final c5 = build((_, __) => throw StateError('down'));
  await c5.send('hello');
  _chk('network error -> fallback text', c5.messages.last.text == 'NET_ERROR' && c5.messages.last.isBlocked);
  _chk('sending reset after error', c5.sending == false);

  // ---- concurrent send guarded ----
  final c6 = build((_, __) => json({'kind': 'chat', 'message': 'ok', 'grounded': false}));
  final f1 = c6.send('a');
  final f2 = c6.send('b'); // should be ignored while first is in flight
  await Future.wait([f1, f2]);
  _chk('concurrent send guarded (one exchange)', c6.messages.length == 2);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
