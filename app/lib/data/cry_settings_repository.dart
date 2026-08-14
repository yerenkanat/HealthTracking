/// Where the cry detector's confidence threshold comes from.
///
/// Three layers, the same ladder as pregnancy_weeks_repository.dart and
/// emergency_help_repository.dart, deliberately:
///
///   1. [kCryMinConfidenceDefault] — the shipped constant, mirrored from the
///      backend. The BASELINE, applied before anything has been fetched.
///   2. the last server answer, cached in prefs, so a cold launch with no
///      signal still applies the threshold the back office chose.
///   3. `GET /protocols/cry`, fetched after first paint.
///
/// Why this exists at all: below the threshold the app must NOT name a reason —
/// it says «не уверены» and asks for another recording. That number used to be
/// a Dart constant, so «модель стала хуже на шумных записях, поднимите порог»
/// meant a store rollout for every phone. Now it is one field in the back
/// office (кадр 17c) and this is the wire that carries it.
///
/// A failure NEVER produces "no threshold": every path here falls back to the
/// shipped default, because zero would silently switch the rule off and let a
/// 12 %-confidence guess be announced to a mother as the reason her baby cries.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/cry_analysis.dart';
import 'api_client.dart';

/// Key under which the last good `/protocols/cry` threshold is cached.
const cryThresholdCacheKey = 'cry_min_confidence';

/// Somewhere to keep the last good answer. An interface rather than a direct
/// dependency on shared_preferences, so the layering is testable in plain Dart.
abstract class CryThresholdCache {
  Future<double?> read();
  Future<void> write(double value);
}

/// [CryThresholdCache] over shared_preferences — the same store the rest of the
/// app's durable state uses.
class PrefsCryThresholdCache implements CryThresholdCache {
  const PrefsCryThresholdCache();

  @override
  Future<double?> read() async =>
      (await SharedPreferences.getInstance()).getDouble(cryThresholdCacheKey);

  @override
  Future<void> write(double value) async =>
      (await SharedPreferences.getInstance()).setDouble(cryThresholdCacheKey, value);
}

/// The threshold in force. Starts at the shipped default and is only ever
/// replaced by a value that parsed.
double _minConfidence = kCryMinConfidenceDefault;

/// What the app applies right now: the shipped default until a cached or
/// fetched value has replaced it.
double cryMinConfidence() => _minConfidence;

/// Anything outside 0..0.95 is not a threshold this app will apply.
///
/// The server enforces the same ceiling, and both do it rather than one: a
/// value of 1.0 arriving from anywhere would turn the screen into a permanent
/// «не уверены», which is the feature switching itself off silently.
double? _sane(Object? raw) {
  final v = raw is num ? raw.toDouble() : null;
  if (v == null || v.isNaN || v < 0 || v > 0.95) return null;
  return v;
}

/// Apply the last cached answer, if there is one.
///
/// Called at startup BEFORE the network refresh, so a launch with no signal
/// applies the newest threshold this phone ever received rather than falling
/// all the way back to the build's constant. Silent when there is no cache —
/// that is an ordinary first launch, not a degradation.
Future<void> primeCryThresholdFromCache(CryThresholdCache cache) async {
  try {
    final v = _sane(await cache.read());
    if (v != null) _minConfidence = v;
  } catch (e) {
    debugPrint('cry threshold: cached copy unusable, keeping ${_minConfidence.toStringAsFixed(2)} — $e');
  }
}

/// Fetch `/protocols/cry` and adopt the threshold it serves.
///
/// Returns the value now in force, or null if the server could not be reached —
/// in which case whatever was already applied stays applied. Unauthenticated,
/// so it works on a fresh install before she has onboarded.
Future<double?> refreshCryThresholdFromApi({
  required ApiClient api,
  CryThresholdCache? cache,
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    final raw = await api.fetchCryThresholdJson().timeout(timeout);
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final v = _sane(decoded['minConfidence']);
    if (v == null) return null;
    _minConfidence = v;
    unawaited(cache?.write(v));
    return v;
  } catch (e) {
    debugPrint('cry threshold: refresh failed, keeping ${_minConfidence.toStringAsFixed(2)} — $e');
    return null;
  }
}

/// Test seam: set the threshold directly, without a cache or a socket.
void debugSetCryMinConfidence(double v) {
  _minConfidence = _sane(v) ?? kCryMinConfidenceDefault;
}
