/// Real HttpTransport over package:http. Kept separate from ApiClient so the
/// client logic stays pure/testable. Adds base URL + bearer auth + JSON headers.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class HttpApiTransport implements HttpTransport {
  final Uri baseUrl;
  final Future<String?> Function() getToken; // e.g. Firebase Auth ID token

  /// Dev-only identity for the local backend, whose auth stub trusts an
  /// `x-user-id` header until Firebase token verification is in place.
  ///
  /// Set from `--dart-define=DEV_USER_ID=...`, which is empty in any build that
  /// does not explicitly pass it — so a release build cannot send this. It is
  /// also only used when there is no real token, so it can never override one.
  final String devUserId;

  /// How long to wait before giving up on a request.
  ///
  /// There was no timeout at all. A server that accepts the connection and then
  /// never answers — a hung worker, a captive portal, a flaky mobile network —
  /// left every caller awaiting a future that would never complete:
  ///
  ///   * the chat spinner span for ever, with no error and no retry;
  ///   * the child-location poll blocked its own loop, silently ending tracking
  ///     for the session;
  ///   * the telemetry batcher held its in-flight latch, so nothing uploaded
  ///     again — the same permanent stall a failing disk used to cause, through
  ///     a different door.
  ///
  /// Generous, because the assistant genuinely takes tens of seconds: the point
  /// is to bound the wait, not to be strict about it. Callers that want less
  /// pass their own.
  final Duration timeout;

  final http.Client _client;

  HttpApiTransport({
    required this.baseUrl,
    required this.getToken,
    this.devUserId = '',
    this.timeout = const Duration(seconds: 30),
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
      if (token == null && devUserId.isNotEmpty) 'x-user-id': devUserId,
    };
  }

  @override
  Future<HttpResponse> post(String path, Object jsonBody) async {
    final res = await _client
        .post(baseUrl.resolve(path), headers: await _headers(), body: jsonEncode(jsonBody))
        .timeout(timeout);
    return HttpResponse(res.statusCode, res.body);
  }

  @override
  Future<HttpResponse> put(String path, Object jsonBody) async {
    final res = await _client
        .put(baseUrl.resolve(path), headers: await _headers(), body: jsonEncode(jsonBody))
        .timeout(timeout);
    return HttpResponse(res.statusCode, res.body);
  }

  @override
  Future<HttpResponse> get(String path) async {
    final res =
        await _client.get(baseUrl.resolve(path), headers: await _headers()).timeout(timeout);
    return HttpResponse(res.statusCode, res.body);
  }

  @override
  Future<HttpResponse> delete(String path) async {
    final res =
        await _client.delete(baseUrl.resolve(path), headers: await _headers()).timeout(timeout);
    return HttpResponse(res.statusCode, res.body);
  }
}
