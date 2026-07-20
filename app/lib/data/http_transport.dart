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

  final http.Client _client;

  HttpApiTransport({
    required this.baseUrl,
    required this.getToken,
    this.devUserId = '',
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
    final res = await _client.post(
      baseUrl.resolve(path),
      headers: await _headers(),
      body: jsonEncode(jsonBody),
    );
    return HttpResponse(res.statusCode, res.body);
  }

  @override
  Future<HttpResponse> get(String path) async {
    final res = await _client.get(baseUrl.resolve(path), headers: await _headers());
    return HttpResponse(res.statusCode, res.body);
  }
}
