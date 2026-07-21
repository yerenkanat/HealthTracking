/// What identity the app puts on the wire.
///
/// The dev backend trusts an `x-user-id` header outright, so the rules about
/// when that header is sent are a security boundary, not a convenience: it must
/// never appear in a build that did not ask for it, and never displace a real
/// token.
library;

import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:fcs_app/data/http_transport.dart';

/// Records the headers of the last request and answers with an empty object.
class _Spy extends http.BaseClient {
  Map<String, String> lastHeaders = const {};

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    lastHeaders = Map.of(request.headers);
    return http.StreamedResponse(const Stream.empty(), 200);
  }
}

void main() {
  final base = Uri.parse('http://localhost:8080');

  Future<Map<String, String>> headersFrom({
    String? token,
    String devUserId = '',
  }) async {
    final spy = _Spy();
    await HttpApiTransport(
      baseUrl: base,
      getToken: () async => token,
      devUserId: devUserId,
      client: spy,
    ).get('/content');
    return spy.lastHeaders.map((k, v) => MapEntry(k.toLowerCase(), v));
  }

  test('a build that did not opt in sends no identity at all', () async {
    // The default is the empty string, which is what any release build gets.
    final h = await headersFrom();
    expect(h.containsKey('x-user-id'), isFalse);
    expect(h.containsKey('authorization'), isFalse);
  });

  test('the dev identity is sent when it was explicitly configured', () async {
    final h = await headersFrom(devUserId: 'dev-1');
    expect(h['x-user-id'], 'dev-1');
  });

  test('a real token wins and the dev identity stays off the wire', () async {
    // Otherwise a stray define in a signed build would let the header ride
    // along beside a genuine credential.
    final h = await headersFrom(token: 'id-token', devUserId: 'dev-1');
    expect(h['authorization'], 'Bearer id-token');
    expect(h.containsKey('x-user-id'), isFalse);
  });

  group('a server that never answers', () {
    // There was no timeout at all. A hung request left the chat spinner
    // spinning for ever, blocked the child-location poll's own loop, and held
    // the telemetry batcher's in-flight latch so nothing uploaded again — the
    // same permanent stall a failing disk used to cause, by another route.
    test('a hung GET gives up instead of hanging for ever', () async {
      final t = HttpApiTransport(
        baseUrl: base,
        getToken: () async => null,
        timeout: const Duration(milliseconds: 50),
        client: _NeverAnswers(),
      );
      await expectLater(t.get('/content'), throwsA(isA<TimeoutException>()));
    });

    test('a hung POST gives up too', () async {
      final t = HttpApiTransport(
        baseUrl: base,
        getToken: () async => null,
        timeout: const Duration(milliseconds: 50),
        client: _NeverAnswers(),
      );
      await expectLater(t.post('/ai/chat', {'a': 1}), throwsA(isA<TimeoutException>()));
    });

    test('a prompt reply is untouched by the timeout', () async {
      final t = HttpApiTransport(
        baseUrl: base,
        getToken: () async => null,
        timeout: const Duration(seconds: 5),
        client: _Spy(),
      );
      expect((await t.get('/content')).statusCode, 200);
    });
  });
}

/// Accepts the request and then says nothing, for ever — a hung worker, a
/// captive portal, a network that dropped the reply.
class _NeverAnswers extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      Completer<http.StreamedResponse>().future;
}
