/// Talks to the cry-classifier service (packages/cry-classifier), a SEPARATE
/// Python/FastAPI service from the main backend — different base URL, and a
/// multipart audio upload rather than a JSON body. So it has its own tiny client
/// instead of riding on ApiClient/HttpTransport.
///
/// The actual multipart POST is injected ([uploader]) so the parsing and error
/// handling are unit-testable without a socket; the default uploader uses the
/// `http` package.
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/cry_analysis.dart';

/// Uploads [bytes] as a file field named `file` to [url] with [headers] and
/// returns the raw response body. Throws [CryClassifierException] on a non-2xx
/// response.
typedef CryUploader = Future<String> Function(Uri url, List<int> bytes, String filename, Map<String, String> headers);

/// A plain GET used only by [CryClassifierClient.checkAvailability]. Returns the
/// status and body rather than throwing, because "the server answered 401" and
/// "no server answered" have to stay distinguishable here.
typedef CryProbe = Future<({int status, String body})> Function(Uri url, Map<String, String> headers);

/// WHY a cry analysis failed — which is the difference between advice a mother
/// can act on and advice that wastes another five seconds of her baby's voice.
///
/// Three genuinely different situations used to arrive as one flat `HTTP 502`:
/// see `packages/backend/src/cry/upstream.ts`, which is the other half of this.
enum CryFailure {
  /// The analyser answered, and what it answered is that it cannot analyse at
  /// all — today because no `model.pkl` has ever been trained
  /// (`docs/INTEGRATION_STATUS.md:34`). Recording again is a guaranteed
  /// failure, so the screen must stop offering it.
  unavailable,

  /// The clip reached the analyser and could not be made into audio, or the
  /// phone captured nothing. This one IS about the recording, and another
  /// attempt may well work.
  unreadable,

  /// Nothing reached the analyser: no connection, a timeout, a proxy error. The
  /// recording was never analysed — it also never left, which is a different
  /// sentence from "we could not work it out".
  unreachable,
}

/// Whether the analyser can answer at all, as of the last time we asked.
enum CryServiceStatus {
  /// It said it is ready.
  available,

  /// It said it cannot analyse. Do not open the microphone for this.
  unavailable,

  /// We could not ask. NOT the same as [unavailable] — a mother in a lift must
  /// not be told the feature is gone, and a failed probe is not evidence about
  /// the service.
  unknown,
}

/// Map an HTTP status from the proxy onto what the screen may conclude.
///
/// Kept as a pure top-level function so the mapping is testable on its own and
/// cannot drift between the uploader and the screen.
CryFailure cryFailureForStatus(int status) {
  // 503: the proxy passes the classifier's own "I have no model" through.
  if (status == 503) return CryFailure.unavailable;
  // 400/413/415/422: the request itself was the problem — unreadable or
  // oversized audio. 408 and 429 are deliberately absent: a timeout or a rate
  // limit is ours, and blaming her clip for it sends her to re-record for
  // nothing.
  if (status == 400 || status == 413 || status == 415 || status == 422) {
    return CryFailure.unreadable;
  }
  return CryFailure.unreachable;
}

class CryClassifierException implements Exception {
  final String message;

  /// What the screen may tell her, and whether another recording is worth it.
  final CryFailure failure;

  const CryClassifierException(this.message, {this.failure = CryFailure.unreachable});
  @override
  String toString() => 'CryClassifierException: $message';
}

class CryClassifierClient {
  /// Base URL of the API, e.g. the Node backend (http://10.0.2.2:8080) which
  /// proxies to the classifier — one authenticated surface for the app.
  final Uri baseUrl;

  /// The upload path on [baseUrl]. Defaults to the Node proxy route; point it at
  /// `/api/v1/predict-cry` to talk to the Python service directly.
  final String path;

  /// The "can you answer at all?" path on [baseUrl]. Carries no audio.
  final String availabilityPath;

  /// Resolves the bearer token for the request, or null when signed out.
  final Future<String?> Function()? authToken;

  /// How long [checkAvailability] may take before it gives up and answers
  /// [CryServiceStatus.unknown]. Bounded so the screen can never sit on a
  /// spinner that does not resolve.
  final Duration probeTimeout;

  final CryUploader _upload;
  final CryProbe _probe;

  CryClassifierClient({
    required this.baseUrl,
    this.path = '/cry/analyze',
    this.availabilityPath = '/cry/availability',
    this.authToken,
    this.probeTimeout = const Duration(seconds: 6),
    CryUploader? uploader,
    CryProbe? prober,
  })  : _upload = uploader ?? _httpUpload,
        _probe = prober ?? _httpProbe;

  /// Ask whether the analyser can answer, WITHOUT sending any audio.
  ///
  /// Called before the microphone opens. Never throws and never hangs: every
  /// way of not getting an answer collapses to [CryServiceStatus.unknown],
  /// which leaves the screen offering the recording — refusing on the strength
  /// of a failed probe would be inventing a state.
  ///
  /// The reply also carries a reason field (model_unavailable /
  /// not_configured) and it is deliberately NOT read: both mean the same thing
  /// to the person holding the baby, and the difference is an operator-facing
  /// one. Printing it would be showing her the HTTP code in words.
  Future<CryServiceStatus> checkAvailability() async {
    try {
      final token = await authToken?.call();
      final headers = <String, String>{
        if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      };
      final res = await _probe(baseUrl.resolve(availabilityPath), headers).timeout(probeTimeout);
      if (res.status < 200 || res.status >= 300) return CryServiceStatus.unknown;
      final json = jsonDecode(res.body) as Map<String, dynamic>;
      return json['available'] == true ? CryServiceStatus.available : CryServiceStatus.unavailable;
    } catch (_) {
      return CryServiceStatus.unknown;
    }
  }

  /// Send a recorded clip and get back the analysis. [filename] only hints the
  /// server at the format (it decodes by content, not extension).
  Future<CryAnalysis> analyze(List<int> audioBytes, {String filename = 'cry.m4a'}) async {
    if (audioBytes.isEmpty) {
      throw const CryClassifierException('empty recording', failure: CryFailure.unreadable);
    }
    final url = baseUrl.resolve(path);
    final token = await authToken?.call();
    final headers = <String, String>{if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'};
    final String body;
    try {
      body = await _upload(url, audioBytes, filename, headers);
    } on CryClassifierException {
      rethrow; // already classified by the uploader
    } catch (e) {
      // A socket that never connected, a DNS failure, a dropped connection: the
      // clip never reached the analyser, so this is not the analyser refusing.
      throw CryClassifierException('transport: $e', failure: CryFailure.unreachable);
    }
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw const CryClassifierException('bad response', failure: CryFailure.unreachable);
    }
    return CryAnalysis.fromJson(json);
  }
}

/// Default uploader — a real multipart POST via the `http` package.
Future<String> _httpUpload(Uri url, List<int> bytes, String filename, Map<String, String> headers) async {
  final req = http.MultipartRequest('POST', url)
    ..headers.addAll(headers)
    ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
  final streamed = await req.send();
  final res = await http.Response.fromStream(streamed);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw CryClassifierException('HTTP ${res.statusCode}',
        failure: cryFailureForStatus(res.statusCode));
  }
  return res.body;
}

/// Default availability probe — a plain authenticated GET.
Future<({int status, String body})> _httpProbe(Uri url, Map<String, String> headers) async {
  final res = await http.get(url, headers: headers);
  return (status: res.statusCode, body: res.body);
}
