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

  /// PUT, for the routes that replace a whole record rather than append.
  ///
  /// The body here is a default, but it does NOT spare implementers: a class
  /// that `implements HttpTransport` must still declare every member, default
  /// or not. It only spares anyone who `extends`. Written down because the
  /// first version of this comment claimed otherwise and three fakes stopped
  /// compiling.
  Future<HttpResponse> put(String path, Object jsonBody) => post(path, jsonBody);

  /// DELETE. Like [put], a default body here does NOT spare a class that
  /// `implements` this — only one that `extends` it.
  Future<HttpResponse> delete(String path) => get(path);
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
        // Parsed defensively, and deliberately so.
        //
        // Every field here used to be a hard cast, so ONE call button missing
        // its number threw — and the throw landed in the chat controller's
        // network handler, which shows "could not reach the assistant" and
        // invites her to try again. The server had already decided this was an
        // emergency. The app turned it into a connection problem.
        //
        // Nothing malformed in the decoration is worth discarding the
        // escalation for: the emergency screen localizes its heading from the
        // triage code, and the controller substitutes the ambulance when no
        // usable button survives.
        return EmergencyChatOutcome(
          message: (j['message'] as String?)?.trim() ?? '',
          // The triage code was already on the wire and simply discarded, so a
          // server-side telemetry emergency arrived as English prose the app
          // had no way to translate. With the code, l.triageMessage() localizes
          // it exactly as it does an on-device one — and no medical copy has to
          // be duplicated in the backend.
          code: _firstTriageCode(j),
          callButtons: _callButtons(j['callButtons']),
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

/// The call buttons an emergency carries, skipping any that could not be used.
///
/// A button with no number is a button that cannot be pressed, so it is
/// dropped — but it does not take the other buttons, or the emergency itself,
/// with it.
List<({String label, String tel})> _callButtons(Object? raw) {
  if (raw is! List) return const [];
  final out = <({String label, String tel})>[];
  for (final b in raw) {
    if (b is! Map) continue;
    final label = b['label'];
    final tel = b['tel'];
    if (label is! String || tel is! String) continue;
    if (tel.trim().isEmpty) continue;
    out.add((label: label, tel: tel));
  }
  return out;
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

  /// Push the profile to the backend.
  ///
  /// [birthDate] and [city] are optional in the app and optional here — null
  /// means she declined, which is a supported answer all the way through to the
  /// back-office, where it renders as "не указано" rather than a blank.
  ///
  /// NOT CALLED YET: profile sync waits on sign-in, like the rest of the CRUD
  /// surface. It exists so the layers line up — the schema, the route and the
  /// panel all carry these fields, and this is the last link. See
  /// docs/INTEGRATION_STATUS.md.
  Future<void> putProfile({
    required String displayName,
    String? phone,
    DateTime? dueDate,
    DateTime? birthDate,
    String? city,
    String? locale,
  }) async {
    String? day(DateTime? d) =>
        d == null ? null : '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final res = await transport.put('/profile', {
      'displayName': displayName,
      'phone': phone,
      'dueDate': day(dueDate),
      'birthDate': day(birthDate),
      'city': (city ?? '').trim().isEmpty ? null : city!.trim(),
      if (locale != null) 'locale': locale,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
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

  // ---- Appointments (user-scoped; the id is client-supplied) ----
  /// The caller's appointments, as raw maps ({id, title, at, note}).
  Future<List<Map<String, dynamic>>> getAppointments() async {
    final res = await transport.get('/appointments');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['appointments'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// Create or update an appointment. Idempotent on the id, so re-syncing the
  /// same appointment updates rather than duplicates.
  Future<void> putAppointment({
    required String id,
    required String title,
    required String at,
    String note = '',
  }) async {
    final res = await transport.post('/appointments', {
      'id': id,
      'title': title,
      'at': at,
      if (note.isNotEmpty) 'note': note,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Delete an appointment. A 404 counts as done (already gone).
  Future<void> deleteAppointment(String id) async {
    final res = await transport.delete('/appointments/$id');
    if (res.ok || res.statusCode == 404) return;
    throw ApiException(res.statusCode, res.body);
  }

  /// Erase this account and everything belonging to it.
  ///
  /// Returns true when the server confirms. A 404 means there was nothing
  /// there to erase, which is the same end state and so also counts as done —
  /// telling her the erase failed because she had never synced would be both
  /// wrong and alarming.
  ///
  /// Identity comes from the session; there is no id to pass, so this can
  /// never be aimed at another account.
  Future<bool> deleteAccount() async {
    final res = await transport.delete('/account');
    if (res.ok || res.statusCode == 404) return true;
    throw ApiException(res.statusCode, res.body);
  }

  /// Returns null on 404 (no recent fix), throws on other errors.
  Future<Map<String, dynamic>?> lastLocation(String childId) async {
    final res = await transport.get('/children/$childId/location');
    if (res.statusCode == 404) return null;
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
