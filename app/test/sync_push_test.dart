/// Telling "we are offline" apart from "we are sending something wrong".
///
/// Every sync in this app is fire-and-forget, which is right for a mother on a
/// bus with no signal. It also meant a 400 — the server understanding us
/// perfectly and refusing — looked exactly like a lost packet. That is how a
/// child called 'child-1' went unsynced on every handset for months: the
/// dashboard was empty, the log said nothing, and the app looked healthy.
///
/// A refusal will fail identically on every retry until somebody changes the
/// code, so it is the one case that has to be loud.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:fcs_app/data/api_client.dart' show ApiException;
import 'package:fcs_app/data/sync_push.dart';
import 'package:fcs_app/domain/error_log.dart';

void main() {
  late List<String> logged;
  late ErrorLog errors;

  setUp(() {
    debugResetSyncReports();
    logged = [];
    errors = ErrorLog();
  });

  Future<void> push(Object? throws, {String what = 'child'}) => pushed(
        what,
        () async {
          if (throws != null) throw throws;
        },
        errorLog: errors,
        now: () => DateTime(2026, 8, 6),
        log: logged.add,
      );

  group('a refusal is our bug, and says so', () {
    test('a 400 is reported', () async {
      await push(ApiException(400, '{"error":"invalid uuid"}'));

      expect(errors.length, 1);
      expect(logged.single, contains('child'));
      // The wording matters: "400" alone sends people to look at the network,
      // and the network worked perfectly.
      expect(logged.single, contains('not a connection problem'));
      expect(logged.single, contains('retrying will not fix it'));
    });

    test('so is a 403 and a 404', () async {
      await push(ApiException(403, ''), what: 'safe zone');
      await push(ApiException(404, ''), what: 'growth measurement');
      expect(errors.length, 2);
    });

    test('and it names the thing, not the endpoint', () async {
      await push(ApiException(400, ''), what: 'safe zone');
      expect(logged.single, contains('safe zone'));
      expect(logged.single, isNot(contains('/geofences')));
    });
  });

  group('what is NOT our bug stays quiet', () {
    test('being offline', () async {
      await push(Exception('SocketException: failed host lookup'));
      expect(errors.isEmpty, isTrue);
      expect(logged, isEmpty);
    });

    test('the server having a bad minute', () async {
      await push(ApiException(500, ''));
      await push(ApiException(502, ''));
      expect(logged, isEmpty, reason: 'a 5xx is transient and retrying is the right answer');
    });

    test('an expired session', () async {
      // Signing in again fixes a 401 without anybody changing code, so it is
      // not a contract error — and it would otherwise fire for every synced
      // type at once the moment a token lapsed.
      await push(ApiException(401, ''));
      expect(logged, isEmpty);
    });

    test('the server asking us to slow down', () async {
      await push(ApiException(429, ''));
      expect(logged, isEmpty);
    });
  });

  group('it does not become the noise it replaced', () {
    test('the same refusal is reported once, not once per child', () async {
      // A family with three children, or a screen that retries on a timer,
      // must not fill a 20-record log with one sentence and push out
      // everything else support needs.
      for (var i = 0; i < 5; i++) {
        await push(ApiException(400, ''));
      }
      expect(errors.length, 1);
      expect(logged, hasLength(1));
    });

    test('but a different kind of refusal is still reported', () async {
      await push(ApiException(400, ''), what: 'child');
      await push(ApiException(400, ''), what: 'safe zone');
      await push(ApiException(403, ''), what: 'child');
      expect(logged, hasLength(3));
    });
  });

  test('a refused push never takes down the caller', () async {
    // These are unawaited at every call site precisely so a sync cannot break
    // the app; throwing out of here would defeat that.
    await expectLater(push(ApiException(400, '')), completes);
    await expectLater(push(Exception('boom')), completes);
  });

  test('a push that works is silent', () async {
    await push(null);
    expect(logged, isEmpty);
    expect(errors.isEmpty, isTrue);
  });
}
