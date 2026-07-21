/// Typed client for the backend HTTP surface.
/// Depends on an abstract [HttpTransport] (not package:http directly) so it is
/// pure Dart and unit-testable with a fake transport. The real transport lives in
/// http_transport.dart. Owned by Mobile Architect + Backend Engineer.
library;

import 'dart:convert';

class HttpResponse {
  final int statusCode;
  final String body;
  const HttpResponse(this.statusCode, this.body);
  bool get ok => statusCode >= 200 && statusCode < 300;
}

abstract class HttpTransport {
  Future<HttpResponse> post(String path, Object jsonBody);
  Future<HttpResponse> get(String path);
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  ApiException(this.statusCode, this.message);
  @override
  String toString() => 'ApiException($statusCode): $message';
}

// ---- /ai/chat outcome (mirrors backend GuardrailOutcome) ----
sealed class ChatOutcome {
  const ChatOutcome();
  factory ChatOutcome.fromJson(Map<String, dynamic> j) {
    switch (j['kind']) {
      case 'emergency':
        return EmergencyChatOutcome(
          message: j['message'] as String,
          // The triage code was already on the wire and simply discarded, so a
          // server-side telemetry emergency arrived as English prose the app
          // had no way to translate. With the code, l.triageMessage() localizes
          // it exactly as it does an on-device one — and no medical copy has to
          // be duplicated in the backend.
          code: _firstTriageCode(j),
          callButtons: [
            for (final b in (j['callButtons'] as List? ?? const []))
              (label: b['label'] as String, tel: b['tel'] as String),
          ],
        );
      case 'blocked':
        return BlockedChatOutcome(
            message: j['message'] as String, reason: j['reason'] as String? ?? 'blocked');
      case 'chat':
        final message = (j['message'] as String? ?? '').trim();
        // An empty reply is a FAILURE, not an answer. Defaulting to '' put a
        // blank bubble in the conversation — the assistant appearing to say
        // nothing, which reads as a broken app and offers her nothing to do.
        // Throwing reaches the caller's existing handling, which shows the
        // localized "could not reach the assistant" message and lets her retry.
        if (message.isEmpty) {
          throw const FormatException('chat reply carried no message');
        }
        return ChatReply(message: message, grounded: (j['grounded'] as bool?) ?? false);
      default:
        // A kind this build does not know. Treating it as chat meant a future
        // server adding an outcome would render whatever happened to be in
        // `message` — or nothing at all — rather than admitting it could not
        // understand the reply.
        throw FormatException('unknown chat outcome "${j['kind']}"');
    }
  }
}

class ChatReply extends ChatOutcome {
  final String message;
  final bool grounded;
  const ChatReply({required this.message, required this.grounded});
}

/// The triage code from a server emergency, if it sent one.
///
/// Tolerant by design: a shape change upstream must degrade to "no code" — and
/// the server's own message — rather than throwing on the emergency path.
String? _firstTriageCode(Map<String, dynamic> j) {
  final triage = j['triage'];
  if (triage is! Map) return null;
  final findings = triage['findings'];
  if (findings is! List || findings.isEmpty) return null;
  final first = findings.first;
  if (first is! Map) return null;
  final code = first['code'];
  return code is String && code.isNotEmpty ? code : null;
}

class EmergencyChatOutcome extends ChatOutcome {
  final String message;

  /// Triage code when the server sent one, so the app can localize; null for
  /// a text red flag, where [message] is already in the user's language.
  final String? code;

  final List<({String label, String tel})> callButtons;
  const EmergencyChatOutcome({required this.message, this.code, required this.callButtons});
}

class BlockedChatOutcome extends ChatOutcome {
  final String message;
  final String reason;
  const BlockedChatOutcome({required this.message, required this.reason});
}

class IngestSummary {
  final int telemetryCount;
  final int locationCount;
  final int emergencies;
  final int rejected;
  const IngestSummary(this.telemetryCount, this.locationCount, this.emergencies, this.rejected);
  factory IngestSummary.fromJson(Map<String, dynamic> j) => IngestSummary(
        (j['telemetryCount'] as num?)?.toInt() ?? 0,
        (j['locationCount'] as num?)?.toInt() ?? 0,
        (j['emergencies'] as num?)?.toInt() ?? 0,
        (j['rejected'] as num?)?.toInt() ?? 0,
      );
}

class ApiClient {
  final HttpTransport transport;
  const ApiClient(this.transport);

  /// Batched telemetry + location flush (called by TelemetryBatcher.flush).
  Future<IngestSummary> ingestBatch(List<Map<String, dynamic>> items) async {
    final res = await transport.post('/ingest/batch', {'items': items});
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return IngestSummary.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// The published timeline catalogue (lessons + products per stage).
  ///
  /// Returns the raw JSON so the caller can cache the exact bytes it received
  /// — re-encoding a parsed catalogue risks the cache and the server drifting
  /// apart over a field this client doesn't know about yet.
  Future<String> fetchContentCatalogJson() async {
    final res = await transport.get('/content');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return res.body;
  }

  /// Guardrailed assistant. `latestTelemetry` lets the server bypass the LLM on
  /// a critical reading and return an emergency outcome.
  Future<ChatOutcome> chat({
    required String userId,
    required String locale,
    required String message,
    Map<String, dynamic>? latestTelemetry,
  }) async {
    final res = await transport.post('/ai/chat', {
      'userId': userId,
      'locale': locale,
      'message': message,
      if (latestTelemetry != null) 'latestTelemetry': latestTelemetry,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return ChatOutcome.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  Future<void> submitBpCalibration({
    required String userId,
    required int cuffSystolic,
    required int cuffDiastolic,
    required int ppgSystolic,
    required int ppgDiastolic,
    required String measuredAt,
  }) async {
    final res = await transport.post('/calibration/bp', {
      'userId': userId,
      'cuffSystolic': cuffSystolic,
      'cuffDiastolic': cuffDiastolic,
      'ppgSystolic': ppgSystolic,
      'ppgDiastolic': ppgDiastolic,
      'measuredAt': measuredAt,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Returns null on 404 (no recent fix), throws on other errors.
  Future<Map<String, dynamic>?> lastLocation(String childId) async {
    final res = await transport.get('/children/$childId/location');
    if (res.statusCode == 404) return null;
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
