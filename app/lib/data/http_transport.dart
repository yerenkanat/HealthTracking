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

  /// Resolve a path against the base URL, KEEPING any prefix the base carries.
  ///
  /// Uri.resolve treats a leading slash as absolute, so a base of
  /// `https://api.umay.kz/v1` and a path of `/children/x` gave
  /// `https://api.umay.kz/children/x` — the version prefix silently dropped,
  /// and every request 404ing the moment the backend moved behind one. It
  /// works today only because API_BASE has no path.
  Uri uriFor(String path) {
    final base = baseUrl.path.endsWith('/')
        ? baseUrl
        : baseUrl.replace(path: '${baseUrl.path}/');
    return base.resolve(path.startsWith('/') ? path.substring(1) : path);
  }

  /// Run one request under [timeout], INCLUDING fetching the auth header.
  ///
  /// The timeout used to wrap only the HTTP call, because `await _headers()`
  /// was evaluated as an argument before the request future existed. getToken
  /// is a Firebase ID-token fetch, which refreshes over the network and hangs
  /// on a dead connection exactly like a hung server — so every symptom the
  /// timeout was added to prevent came straight back through the door beside
  /// it: a chat spinner that never stops, a location poll that blocks its own
  /// loop, a batcher that holds its in-flight latch and never uploads again.
  Future<HttpResponse> _send(Future<http.Response> Function(Map<String, String>) send) async {
    final res = await Future(() async => send(await _headers())).timeout(timeout);
    return HttpResponse(res.statusCode, res.body);
  }

  @override
  Future<HttpResponse> post(String path, Object jsonBody) =>
      _send((h) => _client.post(uriFor(path), headers: h, body: jsonEncode(jsonBody)));

  @override
  Future<HttpResponse> put(String path, Object jsonBody) =>
      _send((h) => _client.put(uriFor(path), headers: h, body: jsonEncode(jsonBody)));

  @override
  Future<HttpResponse> get(String path) => _send((h) => _client.get(uriFor(path), headers: h));

  @override
  Future<HttpResponse> delete(String path) =>
      _send((h) => _client.delete(uriFor(path), headers: h));

  /// Release the underlying connection pool.
  void dispose() => _client.close();
}
