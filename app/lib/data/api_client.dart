/// Typed client for the backend HTTP surface.
/// Depends on an abstract [HttpTransport] (not package:http directly) so it is
/// pure Dart and unit-testable with a fake transport. The real transport lives in
/// http_transport.dart. Owned by Mobile Architect + Backend Engineer.
library;

import 'dart:convert';
import '../domain/course_lesson.dart';
import '../domain/shop_catalogue.dart';
import '../domain/zone_crossing.dart';

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

// ExtractedReading and extractVitalsFromImage ('/vitals/extract') are gone.
// They existed for one caller: the «Сфотографировать тонометр» card, which
// photographed a home device's display and pre-filled the typed-vitals sheet.
// Hand entry of readings was removed on 2026-08-17, so there is no form for a
// scan to fill. The server route is untouched — see packages/ — and the other
// two vision extractors (medications, appointments) fill forms that still
// exist and are unaffected.

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

  /// Watch activity snapshots stored (steps, calories, stress, battery…).
  final int wearableCount;

  /// Readings the server already had — a resend of a batch whose response was
  /// lost. Stored once, counted here, and NOT a failure.
  final int duplicates;

  const IngestSummary(
    this.telemetryCount,
    this.locationCount,
    this.emergencies,
    this.rejected, {
    this.wearableCount = 0,
    this.duplicates = 0,
  });
  factory IngestSummary.fromJson(Map<String, dynamic> j) => IngestSummary(
        (j['telemetryCount'] as num?)?.toInt() ?? 0,
        (j['locationCount'] as num?)?.toInt() ?? 0,
        (j['emergencies'] as num?)?.toInt() ?? 0,
        (j['rejected'] as num?)?.toInt() ?? 0,
        wearableCount: (j['wearableCount'] as num?)?.toInt() ?? 0,
        duplicates: (j['duplicates'] as num?)?.toInt() ?? 0,
      );

  /// True when the server took NOTHING and refused something. A 200 with this
  /// shape is the quietest failure the sync path has: the request succeeded,
  /// the data did not land, and every retry will fail identically.
  bool get storedNothing =>
      rejected > 0 && telemetryCount == 0 && locationCount == 0 && wearableCount == 0 && duplicates == 0;
}

/// Somewhere to keep the last good response of a public GET.
///
/// A three-line interface rather than a dependency on shared_preferences,
/// because this file is pure Dart on purpose and must stay unit-testable
/// without Flutter. [PrefsShopCatalogueCache] is the real one.
abstract class JsonCache {
  Future<String?> read();
  Future<void> write(String json);
}

class ApiClient {
  final HttpTransport transport;

  /// Where the last good shop catalogue is kept, so the shop still shows
  /// prices — and says how old they are — on a phone with no signal. Optional:
  /// without it the app degrades to its compile-time constants, labelled as
  /// approximate, which is the same behaviour as a first run.
  final JsonCache? catalogueCache;

  const ApiClient(this.transport, {this.catalogueCache});

  /// Batched telemetry + location flush (called by TelemetryBatcher.flush).
  Future<IngestSummary> ingestBatch(List<Map<String, dynamic>> items) async {
    final res = await transport.post('/ingest/batch', {'items': items});
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return IngestSummary.fromJson(jsonDecode(res.body) as Map<String, dynamic>);
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

  /// The week-by-week pregnancy calendar as the server serves it: the shared
  /// contract with whatever the back office has edited on top.
  ///
  /// Raw JSON for the same reason as the catalogue above — the caller caches
  /// the exact bytes it received, so a field this build does not know about
  /// still survives to the next launch. Unauthenticated: this is reference
  /// content, identical for everyone.
  Future<String> fetchPregnancyWeeksJson() async {
    final res = await transport.get('/pregnancy/weeks');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return res.body;
  }

  /// The childhood immunisation calendar as the server serves it: the shared
  /// contract with whatever the back office has edited on top, plus the
  /// catch-up window (admin frames 15/15a/15b).
  ///
  /// Raw JSON, cached byte-for-byte by [refreshVaccinationScheduleFromApi], for
  /// the same reason as the calendar above. Unauthenticated: it is the national
  /// schedule, identical for everyone, and it names nobody — the app carries
  /// the same calendar as a constant, so a phone with no signal still shows the
  /// whole thing rather than an apology.
  Future<String> fetchVaccinationScheduleJson() async {
    final res = await transport.get('/vaccination/schedule');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return res.body;
  }

  /// The cry detector's confidence threshold, as the server serves it: the
  /// shipped default with whatever the back office has chosen on top (кадр 17c).
  ///
  /// Raw JSON, cached by [refreshCryThresholdFromApi], for the same reason as
  /// the calendar above. Unauthenticated: it is one number about the model,
  /// identical for everyone, and it must reach a phone that has not signed in.
  Future<String> fetchCryThresholdJson() async {
    final res = await transport.get('/protocols/cry');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return res.body;
  }

  /// Screen 37's emergency scenarios as the server serves them: the shared
  /// contract with whatever the back office has edited on top (admin frame 16b).
  ///
  /// Raw JSON, cached byte-for-byte by [refreshEmergencyHelpFromApi], for the
  /// same reason as the calendar above. Unauthenticated: this is reference
  /// content, identical for everyone, and the one screen that must not depend
  /// on a session being valid.
  Future<String> fetchEmergencyHelpJson() async {
    final res = await transport.get('/emergency-help');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return res.body;
  }

  /// The рассылки this account has been sent — admin frame 06 → screen 39.
  ///
  /// AUTHENTICATED and user-scoped, unlike the calendar above: the server
  /// answers off the delivery ledger, so she sees a message because a row says
  /// it was sent to her. Re-running the segment later — after her due date
  /// passes, after she changes language — cannot take a message off her screen.
  ///
  /// Raw JSON, cached byte-for-byte by [refreshAnnouncementsFromApi] for the
  /// same reason as the catalogue.
  Future<String> fetchAnnouncementsJson({int limit = 20}) async {
    final res = await transport.get('/announcements?limit=$limit');
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

  /// Back up the editable half of the profile.
  ///
  /// No phone: the number is the sign-in credential, it comes from
  /// POST /auth/phone, and the server refuses to let a profile save change it —
  /// sending one only ever meant claiming somebody else's account. GET /profile
  /// still returns it, which is where the app reads it from.
  Future<void> putProfile({
    required String displayName,
    DateTime? dueDate,
    DateTime? birthDate,
    String? city,
    String? locale,
    String? doctorPhone,
    /// Where an ambulance is sent — screen 37's dispatcher card. Backed up like
    /// everything else here so it survives a reinstall: the one moment she
    /// needs it is the one moment she cannot be typing it in.
    String? address,
    int? avgCycleLength,
    int? avgPeriodLength,
  }) async {
    String? day(DateTime? d) =>
        d == null ? null : '${d.year.toString().padLeft(4, '0')}-'
            '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final res = await transport.put('/profile', {
      'displayName': displayName,
      'dueDate': day(dueDate),
      'birthDate': day(birthDate),
      'city': (city ?? '').trim().isEmpty ? null : city!.trim(),
      if (locale != null) 'locale': locale,
      'doctorPhone': (doctorPhone ?? '').trim().isEmpty ? null : doctorPhone!.trim(),
      'address': (address ?? '').trim().isEmpty ? null : address!.trim(),
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

  /// The live shop catalogue — screen 41 «Магазин» and screen 34's price card.
  ///
  /// Public and unauthenticated, exactly like [getShopContact]: the storefront
  /// takes orders from people who are not signed in, and a shop that 401s is a
  /// shop with no prices in it.
  ///
  /// **Never throws.** In order of preference:
  ///
  ///   1. what the server just said, cached on the way past;
  ///   2. the last good payload, marked as coming from the cache and carrying
  ///      the date it was fetched, so the screen can say how old it is;
  ///   3. [ShopCatalogue.empty] — and the screen falls back to its compile-time
  ///      constants, labelled approximate.
  ///
  /// A 200 carrying an EMPTY list does not overwrite the cache and does not
  /// beat it. Every product being withdrawn at once is indistinguishable on the
  /// wire from a half-deployed server, and of the two readings the one that
  /// keeps real prices on screen is the safer.
  Future<ShopCatalogue> getShopCatalogue() async {
    try {
      final res = await transport.get('/shop/products');
      if (res.ok) {
        final fresh = ShopCatalogue.fromJson(
          jsonDecode(res.body) as Map<String, dynamic>,
          fetchedAt: DateTime.now(),
        );
        if (fresh.products.isNotEmpty) {
          // Best effort: a cache that cannot be written must not cost the
          // caller the catalogue it already has in hand.
          try {
            await catalogueCache?.write(jsonEncode(fresh.toJson()));
          } catch (_) {}
          return fresh;
        }
      }
    } catch (_) {
      // Offline, DNS, a truncated body — all the same to the shop screen.
    }
    return _cachedCatalogue();
  }

  Future<ShopCatalogue> _cachedCatalogue() async {
    try {
      final raw = await catalogueCache?.read();
      if (raw == null || raw.isEmpty) return ShopCatalogue.empty;
      final j = jsonDecode(raw) as Map<String, dynamic>;
      final cached = ShopCatalogue.fromJson(j, fromCache: true);
      // A cache with no date is a cache that cannot be labelled, and an
      // unlabelled price is the thing this whole path exists to avoid.
      if (cached.products.isEmpty || cached.fetchedAt == null) {
        return ShopCatalogue.empty;
      }
      return cached;
    } catch (_) {
      return ShopCatalogue.empty;
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

  /// A child's zone crossings, as the SERVER recorded them.
  ///
  /// `GET /children/:id/events` — guarded by `child_zones`, so it answers for a
  /// family member as well as the owner. That is the difference that makes it
  /// worth calling: `GET /alerts` is keyed to the OWNER's user id and is pulled
  /// once at sign-in, so an invited father's feed is empty by construction and
  /// says «Пока нет оповещений» about a child who crossed the school boundary
  /// this morning.
  ///
  /// THROWS on a bad status rather than returning an empty list. A failed load
  /// and a child who crossed nothing are different facts, and the screen shows
  /// them differently — it cannot, if this flattens one into the other.
  ///
  /// `limit` is capped at 200 by the route; asking for more silently gets 200,
  /// so the screen says which it got rather than implying it has everything.
  Future<List<ZoneCrossing>> getZoneCrossings(String childId,
      {int limit = 50}) async {
    final res = await transport.get('/children/$childId/events?limit=$limit');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ZoneCrossing.listFromJson(
        ((j['events'] as List?) ?? const []).cast<Map<String, dynamic>>());
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

  /// «Это было верно?» — her verdict on one analysis (кадр 17c).
  ///
  /// The ONLY ground truth this product has about why a baby cried: nothing
  /// reads a clinic, and the recording is never stored, so without this the
  /// back office's «точность» could only ever be the model's opinion of itself.
  ///
  /// [at] identifies the analysis; the server 404s when the caller has no such
  /// row, which is why this throws rather than reporting success — a rating
  /// that silently went nowhere is worse than one that was never offered.
  Future<void> postCryVerdict({
    required String at, // ISO instant of the analysis
    required String verdict, // CryVerdict.correct | CryVerdict.wrong
    String? actualReason,
  }) async {
    final res = await transport.post(
      '/cry/results/${Uri.encodeComponent(at)}/verdict',
      {'verdict': verdict, if (actualReason != null) 'actualReason': actualReason},
    );
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

  /// Push one completed postpartum screening. Idempotent on the client id.
  ///
  /// The body is {id, takenAt, score, band} and NOTHING ELSE — see
  /// domain/epds.dart. The ten answers do not leave the handset, and the server
  /// has no column to receive them if they did.
  Future<void> putEpds(Map<String, dynamic> body) async {
    final res = await transport.put('/epds', body);
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// The caller's screening history ({id, takenAt, score, band}), newest first.
  /// For bringing it back on a new phone.
  Future<List<Map<String, dynamic>>> getEpds() async {
    final res = await transport.get('/epds?limit=50');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    return ((j['results'] as List?) ?? const []).cast<Map<String, dynamic>>();
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

  /// Record a safety alert the PHONE raised — an SOS or a check-in.
  ///
  /// `POST /alerts` has existed, and been tested, since the alert kinds were
  /// widened to five, with no caller anywhere in the app: `getAlerts` was the
  /// only half wired. So an SOS pressed on this phone reached the safety feed
  /// on this phone and nothing else — not the back-office safety view, not the
  /// family, not her own second device. This is the other half.
  ///
  /// Zone crossings deliberately do NOT come through here: the server derives
  /// its own from the tracker's fixes, and sending ours as well would double
  /// every arrival.
  Future<void> postAlert({
    required String childId,
    required String kind,
    required String zoneName,
    required String at,
  }) async {
    final res = await transport.post('/alerts', {
      'childId': childId,
      'kind': kind,
      'zoneName': zoneName,
      'at': at,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
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

  /// Her notification switches and quiet hours, as the SERVER holds them.
  ///
  /// This is the half that made the screen mean anything. The switches lived in
  /// SharedPrefs and gated only the notifications this phone raised for itself;
  /// a zone crossing the server derived from a tracker fix, an operator's
  /// answer and a рассылка ignored them completely.
  ///
  /// Returns null when the server cannot answer (503 on an unmigrated
  /// database), so the caller keeps the local copy rather than adopting
  /// invented defaults over something she chose.
  Future<Map<String, dynamic>?> getNotificationSettings() async {
    final res = await transport.get('/notifications/settings');
    if (res.statusCode == 503 || res.statusCode == 404) return null;
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    final j = jsonDecode(res.body) as Map<String, dynamic>;
    final s = j['settings'];
    return s is Map ? s.cast<String, dynamic>() : null;
  }

  /// Save them. A full replace, not a patch — the screen holds every switch at
  /// once, so there is no partial write to get wrong, and a cleared quiet
  /// window has to travel as an explicit null rather than as a missing key.
  Future<void> putNotificationSettings(Map<String, dynamic> body) async {
    final res = await transport.put('/notifications/settings', body);
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

  /// Her own orders — screen 42.
  Future<Map<String, dynamic>> myOrders() async {
    final res = await transport.get('/shop/my-orders');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Call one off. Returns the server's verdict: `too_late` means the courier
  /// already has it, which needs different words from a failure.
  Future<({bool ok, String? reason})> cancelMyOrder(String orderId) async {
    final res = await transport.post('/shop/my-orders/$orderId/cancel', const {});
    if (res.ok) return (ok: true, reason: null);
    if (res.statusCode == 409) {
      final body = jsonDecode(res.body) as Map<String, dynamic>;
      return (ok: false, reason: '${body['error']}');
    }
    return (ok: false, reason: null);
  }

  // ---- Support (screen 43 · «Поддержка · оператор») ----

  /// Her support threads, newest first, each with its replies.
  ///
  /// The replies come WITH the tickets: a list that made her tap to discover
  /// whether anybody had answered would be the same silence in a new shape.
  Future<Map<String, dynamic>> supportThreads() async {
    final res = await transport.get('/support');
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  /// Raise one. Returns its id.
  ///
  /// [appContext] is what the app can say about itself — version, device,
  /// whether she was offline — composed by [SupportContext] so the operator
  /// does not have to spend three messages asking.
  ///
  /// Neither the name nor the phone is sent: the server takes both from the
  /// session's profile, so a ticket can never be filed under somebody else's
  /// number.
  Future<String> createSupportTicket({
    required String subject,
    required String body,
    String? appContext,
  }) async {
    final res = await transport.post('/support', {
      'subject': subject,
      'body': body,
      if (appContext != null && appContext.isNotEmpty) 'appContext': appContext,
    });
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return '${(jsonDecode(res.body) as Map<String, dynamic>)['id']}';
  }

  /// Write back into a thread. Throws on failure — the screen must be able to
  /// say «не отправилось» rather than showing the message as delivered.
  Future<void> replyToSupportTicket(String ticketId, String body) async {
    final res = await transport.post('/support/$ticketId/reply', {'body': body});
    if (!res.ok) throw ApiException(res.statusCode, res.body);
  }

  /// She has read this thread — the only way the «Есть ответ поддержки» badge
  /// on «Помощь» goes down.
  ///
  /// The badge counts answers newer than this instant, so a later reply lights
  /// it again. Throws on failure like everything else here: the caller decides
  /// whether a badge that stayed lit is worth telling her about (it is not —
  /// it is the old behaviour, not a lost message).
  Future<void> markSupportThreadRead(String ticketId) async {
    final res = await transport.post('/support/$ticketId/read', const {});
    if (!res.ok) throw ApiException(res.statusCode, res.body);
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

  /// Frame 48 «Сохранить отметку» — close an SOS with the parent's verdict.
  ///
  /// Returns whether the server recorded it. False rather than a throw: the
  /// only caller is a button that has to say «не удалось» either way, and the
  /// commonest failure here is being offline in the morning.
  Future<bool> saveSosOutcome(String childId, DateTime at, String outcome) async {
    try {
      final res = await transport.post(
        '/children/$childId/day/outcome',
        {'at': at.toUtc().toIso8601String(), 'outcome': outcome},
      );
      return res.ok;
    } catch (_) {
      return false;
    }
  }

  /// Returns null on 404 (no recent fix), throws on other errors.
  Future<Map<String, dynamic>?> lastLocation(String childId) async {
    final res = await transport.get('/children/$childId/location');
    if (res.statusCode == 404) return null;
    if (!res.ok) throw ApiException(res.statusCode, res.body);
    return jsonDecode(res.body) as Map<String, dynamic>;
  }
}
