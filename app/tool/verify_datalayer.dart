/// Pure-Dart verification of the app data/orchestration layer.
/// `dart run tool/verify_datalayer.dart` — no package:http/flutter needed
/// (ApiClient uses an injected transport; HealthMonitor uses injected callbacks).
library;

import 'dart:convert';
import 'dart:io';

import '../lib/data/api_client.dart';
import '../lib/domain/health_monitor.dart';
import '../lib/domain/ai_chat_service.dart';
import '../lib/core/triage.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

/// Fake transport: canned responses keyed by path, records the last body posted.
class FakeTransport implements HttpTransport {
  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);

  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, "");

  final Map<String, HttpResponse> responses;
  Object? lastBody;
  String? lastPath;
  FakeTransport(this.responses);
  @override
  Future<HttpResponse> post(String path, Object jsonBody) async {
    lastPath = path;
    lastBody = jsonBody;
    return responses[path] ?? const HttpResponse(500, 'no stub');
  }
  @override
  Future<HttpResponse> get(String path) async {
    lastPath = path;
    return responses[path] ?? const HttpResponse(500, 'no stub');
  }
}

Future<void> main() async {
  // ---- ChatOutcome parsing ----
  final emJson = ChatOutcome.fromJson({
    'kind': 'emergency',
    'message': 'High blood pressure detected.',
    'callButtons': [
      {'label': 'Call ambulance', 'tel': '103'}
    ],
  });
  _chk('parse emergency outcome', emJson is EmergencyChatOutcome &&
      (emJson).callButtons.first.tel == '103');
  _chk('parse chat reply', ChatOutcome.fromJson({'kind': 'chat', 'message': 'hi', 'grounded': true})
      is ChatReply);
  _chk('parse blocked outcome',
      ChatOutcome.fromJson({'kind': 'blocked', 'message': 'no', 'reason': 'prompt_injection'})
          is BlockedChatOutcome);

  // ---- ApiClient over a fake transport ----
  final api = ApiClient(FakeTransport({
    '/ai/chat': HttpResponse(200,
        jsonEncode({'kind': 'emergency', 'message': 'BP high', 'callButtons': [{'label': 'Amb', 'tel': '103'}]})),
    '/ingest/batch': HttpResponse(200,
        jsonEncode({'telemetryCount': 2, 'locationCount': 1, 'emergencies': 1, 'rejected': 0})),
    '/children/c1/location': const HttpResponse(404, ''),
  }));
  final chatOut = await api.chat(userId: 'u', locale: 'en', message: 'hello');
  _chk('api.chat returns emergency outcome', chatOut is EmergencyChatOutcome);
  final summary = await api.ingestBatch([{'type': 'telemetry', 'payload': {}}]);
  _chk('api.ingestBatch parses summary', summary.telemetryCount == 2 && summary.emergencies == 1);
  final loc = await api.lastLocation('c1');
  _chk('api.lastLocation 404 -> null', loc == null);

  // non-200 throws
  final apiErr = ApiClient(FakeTransport({'/ingest/batch': const HttpResponse(400, 'bad')}));
  var threw = false;
  try {
    await apiErr.ingestBatch([]);
  } on ApiException catch (e) {
    threw = e.statusCode == 400;
  }
  _chk('api non-200 throws ApiException', threw);

  // ---- HealthMonitor routing ----
  final fixedClock = () => DateTime.parse('2026-07-15T10:00:00Z');
  final enqueued = <({Map<String, dynamic> t, bool urgent})>[];
  var emergencyFired = 0;
  final monitor = HealthMonitor(
    deviceId: 'band-1',
    enqueue: (t, {required urgent}) => enqueued.add((t: t, urgent: urgent)),
    onEmergency: (_, __) => emergencyFired++,
    now: fixedClock,
  );

  // normal reading → enqueue non-urgent, no emergency
  monitor.handle(const BandTelemetry(heartRateBpm: 80),
      assessTelemetry(const BandTelemetry(heartRateBpm: 80)));
  _chk('normal: enqueued non-urgent', enqueued.last.urgent == false);
  _chk('normal: no emergency fired', emergencyFired == 0);
  _chk('normal: wire has deviceId + recordedAt', enqueued.last.t['deviceId'] == 'band-1' &&
      enqueued.last.t['recordedAt'] == '2026-07-15T10:00:00.000Z');
  _chk('normal: latest telemetry stored', monitor.latest?.heartRateBpm == 80);

  // emergency reading (BP 150/95) → urgent enqueue + emergency fired
  final emT = const BandTelemetry(systolicMmHg: 150, diastolicMmHg: 95);
  monitor.handle(emT, assessTelemetry(emT));
  _chk('emergency: enqueued URGENT', enqueued.last.urgent == true);
  _chk('emergency: onEmergency fired', emergencyFired == 1);

  // ---- AiChatService routes emergency + attaches latest telemetry ----
  final fake = FakeTransport({
    '/ai/chat': HttpResponse(200,
        jsonEncode({'kind': 'emergency', 'message': 'BP high', 'callButtons': [{'label': 'Amb', 'tel': '103'}]})),
  });
  var svcEmergency = 0;
  final svc = AiChatService(
    api: ApiClient(fake),
    userId: 'u',
    locale: () => 'ru-KZ',
    monitor: monitor, // latest is the emergency BP reading
    onEmergency: (_) => svcEmergency++,
  );
  final out = await svc.send('is everything ok?');
  _chk('chat service returns emergency outcome', out is EmergencyChatOutcome);
  _chk('chat service fired onEmergency', svcEmergency == 1);
  final sentBody = (fake.lastBody as Map)['latestTelemetry'] as Map?;
  _chk('chat service attached latest telemetry', sentBody != null && sentBody['systolicMmHg'] == 150);

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
