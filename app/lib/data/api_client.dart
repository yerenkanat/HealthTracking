/// Typed client for the backend HTTP surface.
/// Depends on an abstract [HttpTransport] (not package:http directly) so it is
/// pure Dart and unit-testable with a fake transport. The real transport lives in
/// http_transport.dart. Owned by Mobile Architect + Backend Engineer.
library;

import 'dart:convert';
import '../domain/course_lesson.dart';

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

/// What the vision model read off a photo. Every field is optional — a photo of
/// a glucometer yields only glucose — and [note] is a short human line (which
/// device was seen, or that nothing was legible).
class ExtractedReading {
  final int? heartRate;
  final int? spo2;
  final int? systolic;
  final int? diastolic;
  final double? temperature;
  final double? glucose;
  final String? note;
  const ExtractedReading({this.heartRate, this.spo2, this.systolic, this.diastolic, this.temperature, this.glucose, this.note});

  bool get isEmpty =>
      heartRate == null && spo2 == null && systolic == null && diastolic == null && temperature == null && glucose == null;
}

/// What the vision model read off a photo of a prescription / label / box.
class ExtractedMedication {
  final String? name;
  final String? dose;
  final int? perDay;
  final String? note;
  const ExtractedMedication({this.name, this.dose, this.perDay, this.note});

  bool get isEmpty => (name == null || name!.isEmpty) && (dose == null || dose!.isEmpty) && perDay == null;
}

/// What the vision model read off a photo of a referral slip / talon. [date] is
/// YYYY-MM-DD and [time] is HH:MM (24h) when present, or null.
class ExtractedAppointment {
  final String? title;
  final String? date;
  final String? time;
  final String? place;
  final String? note;
  const ExtractedAppointment({this.title, this.date, this.time, this.place, this.note});

  bool get isEmpty =>
      (title == null || title!.isEmpty) && date == null && time == null && (place == null || place!.isEmpty);
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

  /// Read vitals off a photo of a home device or a lab slip (Claude vision on the
  /// server). [bytes] is the already-downscaled image; [mediaType] is one of
  /// image/jpeg|png|webp. Returns whatever could be read — every field may be
  /// null — for the caller to pre-fill and let the user confirm before saving.
  Future<ExtractedReading> extractVitalsFromImage(List<int> bytes, String mediaType) async {
    final res = await transport.post('/vitals/extract', {
      'imageBase64': base64Encode(bytes),
      'mediaType': mediaType,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ExtractedReading(
      heartRate: (j['heartRate'] as num?)?.toInt(),
      spo2: (j['spo2'] as num?)?.toInt(),
      systolic: (j['systolic'] as num?)?.toInt(),
      diastolic: (j['diastolic'] as num?)?.toInt(),
      temperature: (j['temperature'] as num?)?.toDouble(),
      glucose: (j['glucose'] as num?)?.toDouble(),
      note: j['note'] as String?,
    );
  }

  /// Read a medication off a photo of a prescription, label, or box (Claude
  /// vision on the server). Returns name/dose/times-a-day for the editor to
  /// pre-fill; any field may be null.
  Future<ExtractedMedication> extractMedicationFromImage(List<int> bytes, String mediaType) async {
    final res = await transport.post('/medications/extract', {
      'imageBase64': base64Encode(bytes),
      'mediaType': mediaType,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ExtractedMedication(
      name: j['name'] as String?,
      dose: j['dose'] as String?,
      perDay: (j['perDay'] as num?)?.toInt(),
      note: j['note'] as String?,
    );
  }

  /// Read an appointment off a photo of a referral slip or talon (Claude vision
  /// on the server). Returns title/date/time/place for the editor to pre-fill;
  /// any field may be null.
  Future<ExtractedAppointment> extractAppointmentFromImage(List<int> bytes, String mediaType) async {
    final res = await transport.post('/appointments/extract', {
      'imageBase64': base64Encode(bytes),
      'mediaType': mediaType,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ExtractedAppointment(
      title: j['title'] as String?,
      date: j['date'] as String?,
      time: j['time'] as String?,
      place: j['place'] as String?,
      note: j['note'] as String?,
    );
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
  /// The caller's saved profile ({displayName, phone, dueDate, birthDate, city,
  /// locale}), or null if the server has none (404). For restoring it on a new
  /// device — the push-only backup was never readable before.
  Future<Map<String, dynamic>?> getProfile() async {
    final res = await transport.get('/profile');
    if (res.statusCode == 404) return null;
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['profile'] as Map<String, dynamic>?;
  }

  Future<void> putProfile({
    required String displayName,
    String? phone,
    DateTime? dueDate,
    DateTime? birthDate,
    String? city,
    String? locale,
    String? doctorPhone,
    int? avgCycleLength,
    int? avgPeriodLength,
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
      'doctorPhone': (doctorPhone ?? '').trim().isEmpty ? null : doctorPhone!.trim(),
      'avgCycleLength': avgCycleLength,
      'avgPeriodLength': avgPeriodLength,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Push a weekly BP calibration (manual cuff vs the band's PPG). Identity comes
  /// from the session, so there is no userId to pass and it can never be aimed at
  /// another account. The server derives the offsets (cuff − ppg) itself.
  Future<void> submitBpCalibration({
    required int cuffSystolic,
    required int cuffDiastolic,
    required int ppgSystolic,
    required int ppgDiastolic,
    required String measuredAt,
  }) async {
    final res = await transport.post('/calibration/bp', {
      'cuffSystolic': cuffSystolic,
      'cuffDiastolic': cuffDiastolic,
      'ppgSystolic': ppgSystolic,
      'ppgDiastolic': ppgDiastolic,
      'measuredAt': measuredAt,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// The caller's latest BP calibration ({systolicOffset, diastolicOffset,
  /// calibratedAt, ...}), or null. For restoring it on a new device.
  Future<Map<String, dynamic>?> getBpCalibration() async {
    final res = await transport.get('/calibration/bp');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['calibration'] as Map<String, dynamic>?;
  }

  // ---- App version policy (public; checked on launch) ----
  /// The server's minimum/latest build. Returns (minBuild, latestBuild); a
  /// missing or malformed field reads as 0, which blocks nobody.
  Future<({int minBuild, int latestBuild})> getAppVersion() async {
    final res = await transport.get('/app/version');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    int asInt(Object? v) => v is num ? v.toInt() : 0;
    return (minBuild: asInt(j['minBuild']), latestBuild: asInt(j['latestBuild']));
  }

  // ---- Restore on a new device (pull what was pushed) ----
  /// The caller's children ({id, name, gender, dateOfBirth}). For restoring the
  /// family after a reinstall.

  /// The Ма!Ма! course, and whether this account owns it.
  ///
  /// The server decides: a non-buyer gets entitled:false and an empty list, so
  /// the lessons cannot be read out of the response. A paywall the client
  /// enforces is one anybody can read the JSON around.
  Future<CourseAccess> getCourse() async {
    final res = await transport.get('/course/lessons');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return CourseAccess.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
  }

  /// Revoke the session on the SERVER, not just on this phone.
  ///
  /// Signing out used to clear the token locally and tell nobody, so the
  /// session row stayed valid for its full ninety days. Anyone still holding
  /// that token — a phone handed on, sold, or restored from a backup — kept
  /// reading her account, her children and their locations, from an app that
  /// had said "Выйти".
  ///
  /// The token is passed IN, not read from the session: by the time this is
  /// called the app has already forgotten it, and it has to, because a sign-out
  /// that waits for the network is a sign-out that fails on a dead one.
  ///
  /// Never throws. The local sign-out has already happened and must stand
  /// whatever the server says.
  Future<bool> logout(String token) async {
    try {
      final res = await transport.post('/auth/logout', {'token': token});
      return res.ok;
    } catch (_) {
      return false;
    }
  }

  /// Records where the player got to.
  ///
  /// Never throws: this fires while a video is playing, and a failed write must
  /// not interrupt the lesson or show an error over it. Losing a position is
  /// recoverable — the next tick sends a later one — so silence is right here
  /// and nowhere else.
  Future<bool> putCourseProgress({
    required String lessonId,
    required int positionSeconds,
    int? durationSeconds,
    bool completed = false,
  }) async {
    try {
      final res = await transport.post('/course/progress', {
        'lessonId': lessonId,
        'positionSeconds': positionSeconds,
        if (durationSeconds != null) 'durationSeconds': durationSeconds,
        'completed': completed,
      });
      return res.ok;
    } catch (_) {
      return false;
    }
  }

  /// The public storefront contact — the WhatsApp number staff set in the back
  /// office, and the Kaspi link.
  ///
  /// Public and unauthenticated, like the landing page reads it. The app needs
  /// it for one thing: the course offer tells somebody who has not bought the
  /// комплект to get in touch, and until this existed it gave her no way to.
  /// Never throws — a missing contact hides a button, it does not break a
  /// screen.
  Future<({String whatsapp, String kaspiUrl})> getShopContact() async {
    try {
      final res = await transport.get('/shop/config');
      if (!res.ok) return (whatsapp: '', kaspiUrl: '');
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      return (
        whatsapp: (j['whatsapp'] as String?) ?? '',
        kaspiUrl: (j['kaspiUrl'] as String?) ?? '',
      );
    } catch (_) {
      return (whatsapp: '', kaspiUrl: '');
    }
  }

  Future<List<Map<String, dynamic>>> getChildren() async {
    final res = await transport.get('/children');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['children'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// A child's safe zones, as raw geofence maps (id/name/shape/center/radiusM).
  Future<List<Map<String, dynamic>>> getChildGeofences(String childId) async {
    final res = await transport.get('/children/$childId/geofences');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['geofences'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// The caller's medications ({id, name, dose, perDay}).
  Future<List<Map<String, dynamic>>> getMedications() async {
    final res = await transport.get('/medications');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['medications'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// Push the doses of [medId] taken on a day ({date, count}), so a clinician
  /// sees adherence against the med's target. Upsert per medication per day.
  Future<void> putDose(String medId, Map<String, dynamic> body) async {
    final res = await transport.put('/medications/$medId/doses', body);
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// The caller's medication adherence log ({medId, date, count}). For restoring
  /// it on a new device.
  Future<List<Map<String, dynamic>>> getDoses() async {
    final res = await transport.get('/doses');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['doses'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// The caller's weight log ({date, kg}). For restoring the trend on a reinstall.
  Future<List<Map<String, dynamic>>> getWeight() async {
    final res = await transport.get('/weight?limit=365');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['entries'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// The caller's sleep nights ({night, deepMin, ...}).
  Future<List<Map<String, dynamic>>> getSleep() async {
    final res = await transport.get('/sleep?limit=90');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['nights'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// The caller's saved cry-analysis results ({reason, confidence, at}), newest
  /// first. For restoring the cry history on a new device.
  Future<List<Map<String, dynamic>>> getCryResults() async {
    final res = await transport.get('/cry/results?limit=50');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['results'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// Push one cry-analysis result so the history survives a device change.
  /// Push-only, like sleep: the device is the source of truth.
  Future<void> putCryResult({
    required String at, // ISO instant of the analysis
    required String reason,
    required double confidence,
  }) async {
    final res = await transport.post('/cry/results', {
      'at': at,
      'reason': reason,
      'confidence': confidence,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// The caller's own hand-entered readings (HealthSample wire shape). For
  /// restoring a typed vitals/glucose history on a new device — the server only
  /// returns device-less rows, so band readings are never pulled back.
  Future<List<Map<String, dynamic>>> getManualVitals() async {
    final res = await transport.get('/vitals/manual');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['readings'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// The caller's women's-health day logs in [from]..[to] (yyyy-MM-dd). For
  /// restoring the cycle history that drives predictions.
  Future<List<Map<String, dynamic>>> getDayLogs({required String from, required String to}) async {
    final res = await transport.get('/cycle/days?from=$from&to=$to');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['days'] as List?) ?? const []).cast<Map<String, dynamic>>();
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

  /// Push one night of sleep so staff see the same sleep the mother does (the
  /// admin wellness view). Push-only, like the profile: the watch/app is the
  /// source of truth, the server just mirrors it. Minutes are per stage.
  Future<void> putSleep({
    required String night, // ISO date of the wake day
    required int deepMin,
    required int remMin,
    required int lightMin,
    required int awakeMin,
  }) async {
    final res = await transport.post('/sleep', {
      'night': night,
      'deepMin': deepMin,
      'remMin': remMin,
      'lightMin': lightMin,
      'awakeMin': awakeMin,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Push a medication/supplement (id / name / dose / perDay) so staff can see
  /// what the mother is taking — a real safety concern in pregnancy. Upsert on
  /// the client id.
  Future<void> putMedication(Map<String, dynamic> body) async {
    final res = await transport.post('/medications', body);
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Delete a medication. A 404 counts as done (already gone).
  Future<void> deleteMedication(String id) async {
    final res = await transport.delete('/medications/$id');
    if (res.ok || res.statusCode == 404) return;
    throw ApiException(res.statusCode, res.body);
  }

  /// Push one day's weight (date / kg) so staff see the same weight trend the
  /// mother tracks. Push-only, upsert by date.
  Future<void> putWeight({required String date, required double kg}) async {
    final res = await transport.post('/weight', {'date': date, 'kg': kg});
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Push a completed fetal-movement session, so the clinician sees the trend
  /// (reduced movement is a safety signal). Upsert by endedAt.
  Future<void> putKickSession(Map<String, dynamic> body) async {
    final res = await transport.post('/kick-sessions', body);
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Push a completed labour-timing session (the 5-1-1 signal). Upsert by endedAt.
  Future<void> putContractionSession(Map<String, dynamic> body) async {
    final res = await transport.post('/contraction-sessions', body);
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Prove a device is ours with the code printed on its box.
  ///
  /// The way through a `device_not_ours` refusal for a genuine unit whose
  /// serial nobody recorded at intake. Returns the serial the server knows it
  /// by, so pairing can be retried without asking a customer to read a MAC
  /// address off a sticker.
  ///
  /// Returns null when the code matches nothing — the one refusal she can fix
  /// by looking at the box again. Everything else throws, because "already
  /// claimed" and "blocked" need different words and a different next step.
  Future<Map<String, dynamic>?> claimDevice(String code) async {
    final res = await transport.post('/devices/claim', {'code': code});
    if (res.ok) return jsonDecode(res.body) as Map<String, dynamic>;
    if (res.statusCode == 404) return null;
    throw ApiException(res.statusCode, res.body);
  }

  /// Register a paired device (band/tag) so it appears in the back-office fleet.
  /// Create-once server-side: a 409 that is "mine" means it is already synced, so
  /// that counts as done; a 409 that is someone else's is a real conflict.
  Future<void> putDevice(Map<String, dynamic> body) async {
    final res = await transport.post('/devices', body);
    if (res.ok) return;
    if (res.statusCode == 409) {
      try {
        if (jsonDecode(res.body)['mine'] == true) return; // already registered to me
      } catch (_) {/* fall through to throw */}
    }
    throw ApiException(res.statusCode, res.body);
  }

  /// Unregister a device. A 404 counts as done (already gone).
  Future<void> deleteDevice(String id) async {
    final res = await transport.delete('/devices/$id');
    if (res.ok || res.statusCode == 404) return;
    throw ApiException(res.statusCode, res.body);
  }

  /// Push a newborn care event (feed / diaper / sleep) for [childId], so the
  /// admin sees the feeding + hydration pattern. Push-only, upsert on (at, kind).
  Future<void> putNewbornEvent(String childId, Map<String, dynamic> body) async {
    final res = await transport.post('/children/$childId/newborn-events', body);
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Push a child's emergency medical-ID (blood type / allergies / conditions /
  /// doctor / contact) so a clinician or responder can see it. Upsert per child.
  Future<void> putChildEmergency(String childId, Map<String, dynamic> body) async {
    final res = await transport.put('/children/$childId/emergency', body);
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Push a child growth measurement ({at, weightKg?, heightCm?}), so the child's
  /// growth curve reaches the clinician like the mother's weight does. Upsert per
  /// child per day.
  Future<void> putGrowth(String childId, Map<String, dynamic> body) async {
    final res = await transport.post('/children/$childId/growth', body);
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Mark a vaccine done/undone for a child ({vaccineKey, done}), so the
  /// clinician sees the immunization record.
  Future<void> putVaccine(String childId, String vaccineKey, {required bool done}) async {
    final res = await transport.put('/children/$childId/vaccines', {'vaccineKey': vaccineKey, 'done': done});
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// The caller's child vaccination record ({childId, vaccineKey}). For restoring
  /// it on a new device.
  Future<List<Map<String, dynamic>>> getVaccines() async {
    final res = await transport.get('/vaccines');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['vaccines'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// The caller's child growth measurements across all children, each tagged with
  /// its childId ({childId, at, weightKg, heightCm}). For restoring the curve on
  /// a new device.
  Future<List<Map<String, dynamic>>> getGrowth() async {
    final res = await transport.get('/growth');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['growth'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// A child's emergency medical-ID, or null if none was saved. For restoring
  /// the card on a new device.
  Future<Map<String, dynamic>?> getChildEmergency(String childId) async {
    final res = await transport.get('/children/$childId/emergency');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return j['medicalId'] as Map<String, dynamic>?;
  }

  /// Push a safe zone for [childId] (upsert on the client id) so the back-office
  /// sees real zones and the server can raise enter/exit alerts.
  Future<void> putGeofence(String childId, Map<String, dynamic> body) async {
    final res = await transport.post('/children/$childId/geofences', body);
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Delete a safe zone. A 404 counts as done (already gone).
  Future<void> deleteGeofence(String id) async {
    final res = await transport.delete('/geofences/$id');
    if (res.ok || res.statusCode == 404) return;
    throw ApiException(res.statusCode, res.body);
  }

  /// Push a child (id / name / gender / dateOfBirth) so the family the mother
  /// manages appears in the back-office — the kids demographics dashboard is
  /// built from these. Upsert on the client id; idempotent.
  Future<void> putChild(Map<String, dynamic> body) async {
    final res = await transport.post('/children', body);
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// Push one day's women's-health log (flow / mood / symptoms / kicks) so staff
  /// see the same diary the mother keeps (admin wellness view). Push-only and
  /// idempotent on the date; the note stays local (the server schema drops it).
  Future<void> putDayLog(Map<String, dynamic> body) async {
    final res = await transport.put('/cycle/days', body);
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// The caller's registered devices ({id, name, kind, childId}). For bringing
  /// paired trackers/bands back on a new phone.
  Future<List<Map<String, dynamic>>> getDevices() async {
    final res = await transport.get('/devices');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['devices'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// The caller's completed fetal-movement sessions ({endedAt, count, durationSec}).
  Future<List<Map<String, dynamic>>> getKickSessions() async {
    final res = await transport.get('/kick-sessions?limit=200');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['sessions'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// The caller's completed contraction-timing sessions
  /// ({endedAt, count, avgDurationSec, avgIntervalSec}).
  Future<List<Map<String, dynamic>>> getContractionSessions() async {
    final res = await transport.get('/contraction-sessions?limit=200');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['sessions'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// The caller's safety alerts ({childId, kind, zoneName, at}) — zone crossings
  /// the server detected, including ones from a tracker tag while the phone
  /// wasn't the device that saw them.
  Future<List<Map<String, dynamic>>> getAlerts() async {
    final res = await transport.get('/alerts?limit=100');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['alerts'] as List?) ?? const []).cast<Map<String, dynamic>>();
  }

  /// The caller's newborn-care events across all her children, each tagged with
  /// its childId ({childId, at, kind, detail, durationMin}). For restoring the
  /// baby log on a new device.
  Future<List<Map<String, dynamic>>> getNewbornEvents() async {
    final res = await transport.get('/newborn-events');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['events'] as List?) ?? const []).cast<Map<String, dynamic>>();
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

  // ---- Family access (screen 40) ----

  /// Who has been let in, the open invitations, and whose children I can see.
  Future<Map<String, dynamic>> familyAccess() async {
    final res = await transport.get('/family/access');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// «Пригласить». The token comes back ONCE and is never recoverable — the
  /// server stores only its hash — so the caller must show it immediately.
  Future<Map<String, dynamic>> createFamilyInvite({
    required String level,
    String label = '',
  }) async {
    final res = await transport.post('/family/invites', {'level': level, 'label': label});
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Accepting a link. Returns the refusal reason on 409 rather than throwing:
  /// an expired link and a used one need different words on screen.
  Future<({bool ok, String? reason})> acceptFamilyInvite(String token) async {
    final res = await transport.post('/family/invites/accept', {'token': token});
    if (res.ok) return (ok: true, reason: null);
    if (res.statusCode == 409) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (ok: false, reason: '${body['error']}');
    }
    throw ApiException(res.statusCode, res.body);
  }

  Future<bool> revokeFamilyInvite(String tokenHash) async {
    final res = await transport.delete('/family/invites/$tokenHash');
    return res.ok;
  }

  Future<bool> removeFamilyMember(String memberUserId) async {
    final res = await transport.delete('/family/access/$memberUserId');
    return res.ok;
  }

  /// One day of a child's movements — screens 47/48.
  ///
  /// [day] is YYYY-MM-DD. The server thins the trail and sums the distance, so
  /// the number the screen prints is the length of the line the screen draws;
  /// re-deriving either here would give a second answer to the same question.
  Future<Map<String, dynamic>> childDay(String childId, String day) async {
    final res = await transport.get('/children/$childId/day?day=$day');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Returns null on 404 (no recent fix), throws on other errors.
  Future<Map<String, dynamic>?> lastLocation(String childId) async {
    final res = await transport.get('/children/$childId/location');
    if (res.statusCode == 404) return null;
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
