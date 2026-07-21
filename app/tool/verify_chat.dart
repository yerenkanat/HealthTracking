/// Pure-Dart verification of ChatController message handling + outcome routing.
/// `dart run tool/verify_chat.dart`
library;

import 'dart:convert';
import 'dart:io';

import '../lib/data/api_client.dart';
import '../lib/domain/ai_chat_service.dart';
import '../lib/domain/chat_controller.dart';
import '../lib/domain/health_monitor.dart';
import '../lib/domain/manual_vitals.dart';
import '../lib/app/app_controller.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

class FakeTransport implements HttpTransport {
  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);

  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, "");

  final HttpResponse Function(String path, Object body) handler;
  FakeTransport(this.handler);
  @override
  Future<HttpResponse> post(String path, Object body) async => handler(path, body);
  @override
  Future<HttpResponse> get(String path) async => const HttpResponse(404, '');
}

ChatController build(HttpResponse Function(String, Object) handler,
    {void Function()? onEmergency, int maxMessages = 200}) {
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
    maxMessages: maxMessages,
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

  // ---- a failed question can be tried again ----
  // It used to be gone: the user message stayed in the transcript with an
  // error under it, and she had to remember and retype the question — the one
  // she typed out during a bad moment of signal.
  {
    var fail = true;
    final c = build((_, __) {
      if (fail) throw StateError('down');
      return json({'kind': 'chat', 'message': 'here is an answer', 'grounded': true});
    });
    await c.send('is 150/95 dangerous?');
    _chk('a failure is remembered', c.lastFailed == 'is 150/95 dangerous?');
    fail = false;
    await c.retryLast();
    _chk('retrying gets an answer', c.messages.last.text == 'here is an answer');
    _chk('and clears the failure', c.lastFailed == null);
    _chk('without duplicating the question',
        c.messages.where((m) => m.text == 'is 150/95 dangerous?').length == 1);
    _chk('and without leaving the error bubble behind',
        !c.messages.any((m) => m.text == 'NET_ERROR'));
    _chk('a successful send remembers no failure', c.lastFailed == null);
    await c.dispose();
  }

  {
    final c = build((_, __) => json({'kind': 'chat', 'message': 'ok', 'grounded': false}));
    await c.retryLast();
    _chk('retrying with nothing to retry does nothing', c.messages.isEmpty);
    await c.dispose();
  }

  // ---- the transcript is bounded ----
  {
    final c = build((_, __) => json({'kind': 'chat', 'message': 'ok', 'grounded': false}),
        maxMessages: 6);
    for (var i = 0; i < 10; i++) {
      await c.send('question $i');
    }
    _chk('the transcript stops growing', c.messages.length <= 6);
    // Trimming an odd number would leave an answer at the top with the
    // question it answered gone — which reads as the assistant volunteering
    // medical advice nobody asked for.
    _chk('it never starts mid-exchange', c.messages.first.role == ChatRole.user);
    _chk('the newest exchange survives', c.messages.last.text == 'ok');
    _chk('the oldest question is dropped',
        !c.messages.any((m) => m.text == 'question 0'));
    await c.dispose();
  }

  // ---- the assistant is told what she just measured ----
  //
  // AiChatService attaches monitor.latest to every message, and the SERVER
  // uses it to bypass the LLM and escalate when the reading is critical. Only
  // band readings ever set it, and the band is not wired yet — so a mother
  // could enter 175/118, ask "I have a headache, is this normal?", and the
  // request carried no reading at all. The guardrail's most important input
  // was always null.
  {
    Object? lastBody;
    final api = ApiClient(FakeTransport((path, body) {
      lastBody = body;
      return json({'kind': 'chat', 'message': 'ok', 'grounded': true});
    }));
    final monitor = HealthMonitor(
        deviceId: 'd', enqueue: (_, {required urgent}) {}, onEmergency: (_, __) {});
    final service = AiChatService(
        api: api, userId: 'u', locale: 'ru-KZ', monitor: monitor, onEmergency: (_) {});
    final chat = ChatController(
        service: service,
        networkErrorText: () => 'NET_ERROR',
        emergencyNoteText: () => 'EMERGENCY_NOTE');

    await chat.send('is this normal?');
    _chk('with no reading, none is attached',
        (lastBody as Map)['latestTelemetry'] == null);

    final ctl = AppController(now: () => DateTime(2026, 7, 21, 10));
    ctl.attachRuntime(monitor: monitor);
    ctl.logManualVitals(const ManualVitals(systolic: 175, diastolic: 118));

    _chk('a hand-entered reading becomes the latest', monitor.latest?.systolicMmHg == 175);
    await chat.send('I have a headache, is this normal?');
    final attached = (lastBody as Map)['latestTelemetry'] as Map?;
    _chk('and it reaches the assistant', attached != null);
    _chk('with the reading that matters', attached?['systolicMmHg'] == 175);

    await ctl.dispose();
    await chat.dispose();
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
