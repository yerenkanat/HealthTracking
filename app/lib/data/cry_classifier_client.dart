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

class CryClassifierException implements Exception {
  final String message;
  const CryClassifierException(this.message);
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

  /// Resolves the bearer token for the request, or null when signed out.
  final Future<String?> Function()? authToken;

  final CryUploader _upload;

  CryClassifierClient({
    required this.baseUrl,
    this.path = '/cry/analyze',
    this.authToken,
    CryUploader? uploader,
  }) : _upload = uploader ?? _httpUpload;

  /// Send a recorded clip and get back the analysis. [filename] only hints the
  /// server at the format (it decodes by content, not extension).
  Future<CryAnalysis> analyze(List<int> audioBytes, {String filename = 'cry.m4a'}) async {
    if (audioBytes.isEmpty) {
      throw const CryClassifierException('empty recording');
    }
    final url = baseUrl.resolve(path);
    final token = await authToken?.call();
    final headers = <String, String>{if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token'};
    final body = await _upload(url, audioBytes, filename, headers);
    final Map<String, dynamic> json;
    try {
      json = jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      throw const CryClassifierException('bad response');
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
    throw CryClassifierException('HTTP ${res.statusCode}');
  }
  return res.body;
}
