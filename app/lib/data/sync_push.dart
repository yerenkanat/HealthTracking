/// Pushing something to the server, and noticing when it is refused.
///
/// Every sync in this app is fire-and-forget: `unawaited(api.putChild(...))`.
/// That is right for the ordinary case — she is on a bus with no signal, and
/// the push will be retried — but it treats two very different things
/// identically.
///
///   * A 5xx, a timeout, no network. Transient, nobody's fault, retry later.
///     Silence is correct; a warning per lost packet would be noise.
///   * A 4xx. The server understood and REFUSED. That is a contract error —
///     our bug — and it will fail exactly the same way on every retry until
///     somebody changes the code. Silence here is how a child called
///     'child-1' went unsynced on every handset for months while the log said
///     nothing and the app looked healthy.
///
/// So this splits them: a refusal is recorded where support can see it and
/// printed once per kind, and everything else stays quiet.
library;

import 'dart:async';

import '../domain/error_log.dart';
import 'api_client.dart' show ApiException;

/// One report per (what, status), so a screen that retries on a timer cannot
/// fill the log with the same sentence.
final _reported = <String>{};

/// Reset between tests.
void debugResetSyncReports() => _reported.clear();

/// Send [push], and make a refusal visible.
///
/// [what] names the thing being synced in a way that means something in a
/// support log — 'child', 'safe zone', 'weight' — not the endpoint.
///
/// Never throws: a sync failure must not take down the caller, which is the
/// whole reason these are unawaited in the first place.
Future<void> pushed(
  String what,
  Future<void> Function() push, {
  ErrorLog? errorLog,
  DateTime Function() now = DateTime.now,
  void Function(String) log = print,
}) async {
  try {
    await push();
  } catch (e) {
    final status = e is ApiException ? e.statusCode : null;

    // 401 is not a contract error: the session expired, and signing in again
    // fixes it without anybody changing code.
    // 429 is the server asking us to slow down, which is also not a bug.
    final refused = status != null && status >= 400 && status < 500 && status != 401 && status != 429;
    if (!refused) return; // offline, or the server having a bad minute

    final key = '$what:$status';
    if (!_reported.add(key)) return;

    // Worded for whoever reads it next. "400" alone has sent people looking at
    // the network; the point is that the network worked perfectly.
    final message =
        'sync refused: the server rejected this $what with $status. '
        'This is not a connection problem and retrying will not fix it — '
        'the app is sending something the server will not accept.';
    log(message);
    errorLog?.add(source: AppErrorSource.app, error: message, at: now());
  }
}
