/// Timed-session backend sync: the ApiClient calls and the controller hooks that
/// mirror completed fetal-movement and contraction sessions to the server.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/app/app_controller.dart';
import 'package:fcs_app/data/api_client.dart';
import 'package:fcs_app/data/app_store.dart';
import 'package:fcs_app/domain/phone_auth.dart';
import 'package:fcs_app/l10n/l10n.dart';

class _FakeTransport implements HttpTransport {
  final List<(String, Object?)> calls = [];
  /// Simulates a dead network: the sign-out must stand regardless.
  bool throwOnPost = false;
  @override
  Future<HttpResponse> get(String path) async => const HttpResponse(200, '{}');
  @override
  Future<HttpResponse> post(String path, Object body) async {
    if (throwOnPost) throw Exception('no network');
    calls.add(('POST $path', body));
    return const HttpResponse(201, '{"ok":true}');
  }

  @override
  Future<HttpResponse> put(String path, Object body) => post(path, body);
  @override
  Future<HttpResponse> delete(String path) async => const HttpResponse(204, '');
}

void main() {
  group('ApiClient sessions', () {
    test('putKickSession posts endedAt/count/durationSec', () async {
      final t = _FakeTransport();
      await ApiClient(t).putKickSession({'endedAt': '2026-07-20T10:00:00.000Z', 'count': 10, 'durationSec': 600});
      final body = t.calls.firstWhere((c) => c.$1 == 'POST /kick-sessions').$2 as Map;
      expect(body['count'], 10);
      expect(body['durationSec'], 600);
    });

    test('putContractionSession posts the timing fields', () async {
      final t = _FakeTransport();
      await ApiClient(t).putContractionSession({'endedAt': '2026-07-22T02:00:00.000Z', 'count': 6, 'avgDurationSec': 55, 'avgIntervalSec': 300});
      final body = t.calls.firstWhere((c) => c.$1 == 'POST /contraction-sessions').$2 as Map;
      expect(body['avgIntervalSec'], 300);
    });
  });

  /// Signing out has to reach the server.
  ///
  /// It used to clear the token here and tell nobody, so the session stayed
  /// valid for its full ninety days: a phone handed on, sold or restored from
  /// a backup still carried a working key to her account, her children and
  /// their locations, after the app had said "Выйти".
  group('signing out', () {
    AppController signedIn(_FakeTransport t) {
      final c = AppController(now: () => DateTime.utc(2026, 8, 6, 12), locale: AppLocale.ru);
      c.attachRuntime(api: ApiClient(t));
      c.signIn(AuthSession(
        userId: 'u1',
        phoneE164: '+77001112233',
        token: 'the-session-token',
        signedInAt: DateTime.utc(2026, 8, 1),
      ));
      return c;
    }

    test('revokes the session on the server', () async {
      final t = _FakeTransport();
      final c = signedIn(t);
      addTearDown(c.dispose);

      c.signOut();
      await Future<void>.delayed(Duration.zero);

      final call = t.calls.where((x) => x.$1 == 'POST /auth/logout');
      expect(call, hasLength(1), reason: 'the server was never told');
      // The token goes in the BODY: by now the app has forgotten it, so a
      // transport building an Authorization header would find nothing there.
      expect((call.single.$2 as Map)['token'], 'the-session-token');
    });

    test('signs out locally at once, without waiting for the server', () {
      // A dead network must not keep her signed in.
      final t = _FakeTransport();
      final c = signedIn(t);
      addTearDown(c.dispose);

      c.signOut();
      expect(c.isSignedIn, isFalse);
      expect(c.authSession, isNull);
    });

    test('stays signed out when the server cannot be reached', () async {
      final t = _FakeTransport()..throwOnPost = true;
      final c = signedIn(t);
      addTearDown(c.dispose);

      c.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(c.isSignedIn, isFalse, reason: 'a failed revoke undid the sign-out');
    });

    test('keeps the token when the revoke fails, and retries it', () async {
      // The one write nothing else repairs. Every other synced type is
      // re-pushed wholesale at startup; after signing out, nothing will ever
      // revoke this session again — so a failed revoke would leave a working
      // key to her account on a phone she has stopped using, for ninety days.
      final t = _FakeTransport()..throwOnPost = true;
      final c = signedIn(t);
      addTearDown(c.dispose);

      c.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(t.calls, isEmpty, reason: 'the fake refused the request');

      // Network back.
      t.throwOnPost = false;
      await c.flushPendingLogouts();

      final call = t.calls.where((x) => x.$1 == 'POST /auth/logout');
      expect(call, hasLength(1), reason: 'the revoke was never retried');
      expect((call.single.$2 as Map)['token'], 'the-session-token');
    });

    test('stops retrying once the server has taken it', () async {
      final t = _FakeTransport();
      final c = signedIn(t);
      addTearDown(c.dispose);

      c.signOut();
      await Future<void>.delayed(Duration.zero);
      await c.flushPendingLogouts();
      await c.flushPendingLogouts();

      expect(t.calls.where((x) => x.$1 == 'POST /auth/logout'), hasLength(1));
    });

    test('the pending revoke survives a restart', () async {
      // Written to storage, not held in memory: the failure case is a phone
      // that is offline now and may not be opened again for days.
      final store = InMemoryAppStore();
      final t = _FakeTransport()..throwOnPost = true;
      final first = AppController(
          now: () => DateTime.utc(2026, 8, 6, 12),
          locale: AppLocale.ru,
          persistStore: store);
      first.attachRuntime(api: ApiClient(t));
      // restore() bails on a config that never finished onboarding, so the
      // fixture has to be a real account rather than a bare session.
      first.debugMarkOnboarded();
      first.signIn(AuthSession(
        userId: 'u1', phoneE164: '+77001112233',
        token: 'the-session-token', signedInAt: DateTime.utc(2026, 8, 1),
      ));
      first.signOut();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await first.dispose();

      expect((await store.load())!.pendingLogouts, ['the-session-token']);

      // Next launch, network back: it goes out without her doing anything.
      final t2 = _FakeTransport();
      final second = AppController(
          now: () => DateTime.utc(2026, 8, 7, 12),
          locale: AppLocale.ru,
          persistStore: store);
      addTearDown(second.dispose);
      second.attachRuntime(api: ApiClient(t2));
      await second.restore();
      await second.flushPendingLogouts();

      expect(t2.calls.where((x) => x.$1 == 'POST /auth/logout'), hasLength(1));
      expect((await store.load())!.pendingLogouts, isEmpty);
    });

    test('signing out twice does not call it twice', () async {
      final t = _FakeTransport();
      final c = signedIn(t);
      addTearDown(c.dispose);

      c.signOut();
      c.signOut();
      await Future<void>.delayed(Duration.zero);
      expect(t.calls.where((x) => x.$1 == 'POST /auth/logout'), hasLength(1));
    });
  });

  group('controller session sync hooks', () {
    AppController make() => AppController(now: () => DateTime.utc(2026, 7, 23, 12), locale: AppLocale.ru);

    test('a finished kick session pushes an upsert', () async {
      final c = make();
      addTearDown(c.dispose);
      var pushed = 0;
      c.attachSessionSync(kick: (s) async => pushed++, contraction: (_) async {});
      c.logKickSession(DateTime(2026, 7, 23), 10, const Duration(minutes: 10));
      await Future<void>.delayed(Duration.zero);
      expect(pushed, 1);
      expect(c.kickSessions.first.count, 10);
    });

    test('a finished contraction session pushes an upsert', () async {
      final c = make();
      addTearDown(c.dispose);
      var pushed = 0;
      c.attachSessionSync(kick: (_) async {}, contraction: (s) async => pushed++);
      c.logContractionSession(6, const Duration(seconds: 55), const Duration(minutes: 5));
      await Future<void>.delayed(Duration.zero);
      expect(pushed, 1);
      expect(c.contractionSessions.first.avgInterval, const Duration(minutes: 5));
    });
  });
}
