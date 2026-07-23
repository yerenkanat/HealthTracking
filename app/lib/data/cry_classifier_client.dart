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

/// Uploads [bytes] as a file field named `file` to [url] and returns the raw
/// response body. Throws [CryClassifierException] on a non-2xx response.
typedef CryUploader = Future<String> Function(Uri url, List<int> bytes, String filename);

class CryClassifierException implements Exception {
  final String message;
  const CryClassifierException(this.message);
  @override
  String toString() => 'CryClassifierException: $message';
}

class CryClassifierClient {
  /// Base URL of the cry service, e.g. http://10.0.2.2:8000 on the emulator.
  final Uri baseUrl;
  final CryUploader _upload;

  CryClassifierClient({required this.baseUrl, CryUploader? uploader})
      : _upload = uploader ?? _httpUpload;

  /// Send a recorded clip and get back the analysis. [filename] only hints the
  /// server at the format (it decodes by content, not extension).
  Future<CryAnalysis> analyze(List<int> audioBytes, {String filename = 'cry.m4a'}) async {
    if (audioBytes.isEmpty) {
      throw const CryClassifierException('empty recording');
    }
    final url = baseUrl.resolve('/api/v1/predict-cry');
    final body = await _upload(url, audioBytes, filename);
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
Future<String> _httpUpload(Uri url, List<int> bytes, String filename) async {
  final req = http.MultipartRequest('POST', url)
    ..files.add(http.MultipartFile.fromBytes('file', bytes, filename: filename));
  final streamed = await req.send();
  final res = await http.Response.fromStream(streamed);
  if (res.statusCode < 200 || res.statusCode >= 300) {
    throw CryClassifierException('HTTP ${res.statusCode}');
  }
  return res.body;
}
