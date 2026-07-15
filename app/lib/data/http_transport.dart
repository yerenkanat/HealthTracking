/// Real HttpTransport over package:http. Kept separate from ApiClient so the
/// client logic stays pure/testable. Adds base URL + bearer auth + JSON headers.
library;

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';

class HttpApiTransport implements HttpTransport {
  final Uri baseUrl;
  final Future<String?> Function() getToken; // e.g. Firebase Auth ID token
  final http.Client _client;

  HttpApiTransport({
    required this.baseUrl,
    required this.getToken,
    http.Client? client,
  }) : _client = client ?? http.Client();

  Future<Map<String, String>> _headers() async {
    final token = await getToken();
    return {
      'content-type': 'application/json',
      if (token != null) 'authorization': 'Bearer $token',
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
