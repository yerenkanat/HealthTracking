/// Verification of the HTTP transport: URL building, auth headers, and what
/// happens when something never answers.
/// `dart run tool/verify_transport.dart`
library;

import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import '../lib/data/http_transport.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

/// Run [body], reporting failure if it does not settle in [limit].
///
/// A test for "this must not wait for ever" fails by waiting for ever, which
/// is the least useful failure available: the runner hangs, prints no summary,
/// and CI reports a timeout rather than a defect. Found the hard way — with the
/// fix reverted, the token case hung instead of failing.
Future<bool> settles(Future<void> Function() body,
    {Duration limit = const Duration(seconds: 3)}) async {
  final done = Completer<bool>();
  final watchdog = Timer(limit, () {
    if (!done.isCompleted) done.complete(false);
  });
  unawaited(body().then((_) {
    if (!done.isCompleted) done.complete(true);
  }).catchError((_) {
    if (!done.isCompleted) done.complete(true);
  }));
  final ok = await done.future;
  watchdog.cancel();
  return ok;
}

Future<void> main() async {
  // ---- URL building ----
  {
    // Works today because API_BASE has no path. It will not stay that way: a
    // backend behind /v1 is the ordinary case, and Uri.resolve treats a leading
    // slash as absolute — so the prefix was silently dropped and every request
    // 404'd.
    final t = HttpApiTransport(
      baseUrl: Uri.parse('https://api.umay.kz/v1'),
      getToken: () async => null,
    );
    _chk('a base path prefix is kept',
        t.uriFor('/children/abc').toString() == 'https://api.umay.kz/v1/children/abc');
    _chk('a path without a leading slash resolves the same',
        t.uriFor('children/abc').toString() == 'https://api.umay.kz/v1/children/abc');
    _chk('a query string survives',
        t.uriFor('/metrics?metric=hr').toString() == 'https://api.umay.kz/v1/metrics?metric=hr');
  }
  {
    final t = HttpApiTransport(baseUrl: Uri.parse('http://10.0.2.2:8080'), getToken: () async => null);
    _chk('a bare host is unchanged',
        t.uriFor('/ingest/batch').toString() == 'http://10.0.2.2:8080/ingest/batch');
    final slash = HttpApiTransport(baseUrl: Uri.parse('http://10.0.2.2:8080/'), getToken: () async => null);
    _chk('a trailing slash on the base makes no difference',
        slash.uriFor('/ingest/batch').toString() == 'http://10.0.2.2:8080/ingest/batch');
  }

  // ---- Auth headers ----
  {
    Map<String, String>? seen;
    final client = MockClient((req) async {
      seen = req.headers;
      return http.Response('{"ok":true}', 200);
    });
    final t = HttpApiTransport(
      baseUrl: Uri.parse('http://x'),
      getToken: () async => 'tok-123',
      devUserId: 'dev-1',
      client: client,
    );
    await t.get('/health');
    _chk('a real token is sent as a bearer', seen?['authorization'] == 'Bearer tok-123');
    // The dev header must never override a real identity.
    _chk('the dev stub is suppressed when a token exists', !seen!.containsKey('x-user-id'));
  }
  {
    Map<String, String>? seen;
    final client = MockClient((req) async {
      seen = req.headers;
      return http.Response('{}', 200);
    });
    final t = HttpApiTransport(
      baseUrl: Uri.parse('http://x'),
      getToken: () async => null,
      devUserId: 'dev-1',
      client: client,
    );
    await t.get('/health');
    _chk('the dev stub is used only with no token', seen?['x-user-id'] == 'dev-1');
    _chk('no bearer is invented', !seen!.containsKey('authorization'));
  }
  {
    // A build that did not pass DEV_USER_ID sends neither — it must not fall
    // back to some default identity.
    Map<String, String>? seen;
    final client = MockClient((req) async {
      seen = req.headers;
      return http.Response('{}', 200);
    });
    final t = HttpApiTransport(baseUrl: Uri.parse('http://x'), getToken: () async => null, client: client);
    await t.get('/health');
    _chk('a release build sends no identity at all',
        !seen!.containsKey('authorization') && !seen!.containsKey('x-user-id'));
  }

  // ---- Nothing may wait for ever ----
  {
    // A server that accepts the connection and then never answers.
    final client = MockClient((_) => Completer<http.Response>().future);
    final t = HttpApiTransport(
      baseUrl: Uri.parse('http://x'),
      getToken: () async => null,
      timeout: const Duration(milliseconds: 60),
      client: client,
    );
    var timedOut = false;
    try {
      await t.get('/health');
    } on TimeoutException {
      timedOut = true;
    }
    _chk('a hung server times out', timedOut);
  }
  {
    // A hanging TOKEN fetch. getToken is a Firebase ID-token refresh, which
    // goes over the network and stalls on a dead connection exactly like a hung
    // server — and it used to be awaited as an argument, OUTSIDE the timeout.
    // Every symptom the timeout was added to prevent came back through the door
    // beside it.
    final client = MockClient((_) async => http.Response('{}', 200));
    final t = HttpApiTransport(
      baseUrl: Uri.parse('http://x'),
      getToken: () => Completer<String?>().future,
      timeout: const Duration(milliseconds: 60),
      client: client,
    );
    var timedOut = false;
    final settled = await settles(() async {
      try {
        await t.post('/ingest/batch', {'items': []});
      } on TimeoutException {
        timedOut = true;
      }
    });
    _chk('a hung token refresh settles at all', settled);
    _chk('a hung token refresh times out too', settled && timedOut);
  }
  {
    // Every verb, not just the one that happened to be tested.
    final client = MockClient((_) => Completer<http.Response>().future);
    final t = HttpApiTransport(
      baseUrl: Uri.parse('http://x'),
      getToken: () async => null,
      timeout: const Duration(milliseconds: 40),
      client: client,
    );
    for (final (name, call) in <(String, Future<dynamic> Function())>[
      ('get', () => t.get('/x')),
      ('post', () => t.post('/x', {})),
      ('put', () => t.put('/x', {})),
      ('delete', () => t.delete('/x')),
    ]) {
      var timedOut = false;
      try {
        await call();
      } on TimeoutException {
        timedOut = true;
      }
      _chk('$name is bounded', timedOut);
    }
  }

  // ---- The response is passed through as-is ----
  {
    final client = MockClient((_) async => http.Response('{"error":"nope"}', 403));
    final t = HttpApiTransport(baseUrl: Uri.parse('http://x'), getToken: () async => null, client: client);
    final res = await t.get('/admin/bi');
    _chk('a failing status is reported, not thrown', res.statusCode == 403);
    _chk('the body is handed back for the caller to read', res.body.contains('nope'));
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
