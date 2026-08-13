/// Where screen 37's emergency scenarios come from.
///
/// Three layers, and the order matters — the same ladder as
/// pregnancy_weeks_repository.dart, deliberately:
///
///   1. `assets/data/emergency_help.json` — the shared contract, shipped with
///      the build. The BASELINE. Always loaded, never replaced.
///   2. the last server response, cached in prefs, so a cold launch with no
///      signal still shows what the back office published.
///   3. `GET /emergency-help`, fetched after first paint.
///
/// Layers 2 and 3 are applied SCENARIO BY SCENARIO over layer 1 — a server
/// response that covers seven scenarios does not blank the other two. That is
/// the whole difference between this and "fetch and replace", and on this
/// screen it is not a nicety: it is opened by somebody deciding whether to call
/// an ambulance, and an empty list at that moment is the worst thing this app
/// can do.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/emergency_help.dart';
import 'api_client.dart';

const emergencyHelpAsset = 'assets/data/emergency_help.json';

/// Key under which the last good `/emergency-help` response is cached.
const emergencyHelpCacheKey = 'emergency_help_json';

/// Somewhere to keep the last good response. An interface rather than a direct
/// dependency on shared_preferences, so the layering is testable in plain Dart.
abstract class EmergencyHelpCache {
  Future<String?> read();
  Future<void> write(String json);
}

/// [EmergencyHelpCache] over shared_preferences — the same store the rest of
/// the app's durable state uses.
class PrefsEmergencyHelpCache implements EmergencyHelpCache {
  const PrefsEmergencyHelpCache();

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(emergencyHelpCacheKey);

  @override
  Future<void> write(String json) async =>
      (await SharedPreferences.getInstance()).setString(emergencyHelpCacheKey, json);
}

/// The bundled contract. Loaded once; this is what everything else layers over.
EmergencyHelp? _asset;

/// Scenarios the server has changed, by id. Empty until a refresh lands.
final Map<String, EmergencyScenario> _overlay = {};

/// [_asset] with [_overlay] applied. Rebuilt whenever either changes.
EmergencyHelp? _merged;

void _remerge() {
  final base = _asset;
  if (base == null) {
    _merged = null;
    return;
  }
  if (_overlay.isEmpty) {
    _merged = base;
    return;
  }
  final scenarios = [for (final s in base.scenarios) _overlay[s.id] ?? s]
    ..sort((a, b) {
      final bySort = a.sort.compareTo(b.sort);
      return bySort != 0 ? bySort : a.id.compareTo(b.id);
    });
  _merged = EmergencyHelp(version: base.version, tel: base.tel, scenarios: scenarios);
}

/// The list in use: the bundled scenarios, with any server-published one
/// layered on top.
///
/// Returns [EmergencyHelp.empty] (never throws) if the asset is missing or
/// malformed — the screen then still shows the 103 card, the address and the
/// pediatrician, which is the half of it that saves the most time anyway.
Future<EmergencyHelp> loadEmergencyHelp() async {
  if (_merged != null) return _merged!;
  try {
    final raw = await rootBundle.loadString(emergencyHelpAsset);
    _asset = parseEmergencyHelp(jsonDecode(raw) as Map<String, dynamic>);
  } catch (e) {
    debugPrint('emergency help: the bundled asset is unusable — $e');
    _asset = EmergencyHelp.empty;
  }
  _remerge();
  return _merged!;
}

/// Apply the last cached server response, if there is one.
///
/// Called at startup BEFORE the network refresh, so a launch with no signal
/// still shows the newest text this phone ever received rather than falling all
/// the way back to the build's asset. Silent when there is no cache — that is
/// an ordinary first launch, not a degradation.
Future<void> primeEmergencyHelpFromCache(EmergencyHelpCache cache) async {
  try {
    final raw = await cache.read();
    if (raw == null) return;
    final help = _parse(raw);
    if (help == null) return;
    _layer(help.scenarios);
  } catch (e) {
    debugPrint('emergency help: cached copy unusable, keeping the asset — $e');
  }
}

/// Fetch `/emergency-help` and layer it over the bundled list.
///
/// Returns how many scenarios the server changed, or null if it could not be
/// reached — the caller keeps whatever it already had, which is the point of
/// loading the asset first. A failure is logged and never surfaces as an empty
/// screen.
Future<int?> refreshEmergencyHelpFromApi({
  required ApiClient api,
  EmergencyHelpCache? cache,
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    final raw = await api.fetchEmergencyHelpJson().timeout(timeout);
    final help = _parse(raw);
    if (help == null || help.isEmpty) return null;
    // The exact bytes, not a re-encode, so a field this build does not
    // understand still survives to the next launch.
    unawaited(cache?.write(raw));
    _layer(help.scenarios);
    return help.scenarios.length;
  } catch (e) {
    debugPrint('emergency help: refresh failed, keeping what we have — $e');
    return null;
  }
}

/// Put [scenarios] into the overlay, one at a time.
///
/// Never `clear()`s first. A response missing «кровотечение» means "unchanged",
/// not "there is no such scenario" — the server merges the contract into what
/// it serves, and if it ever did not, the bundled entry is still the better
/// answer than nothing.
void _layer(List<EmergencyScenario> scenarios) {
  for (final s in scenarios) {
    // Skip an entry with no text at all rather than overwriting a real bundled
    // scenario with three empty strings. `en` falls back to `ru` in textFor(),
    // so "usable" means the Russian half says something.
    if (s.ru.isEmpty) continue;
    _overlay[s.id] = s;
  }
  _remerge();
}

EmergencyHelp? _parse(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final help = parseEmergencyHelp(decoded.cast<String, dynamic>());
    return help.isEmpty ? null : help;
  } catch (e) {
    debugPrint('emergency help: could not parse a payload — $e');
    return null;
  }
}

/// Test seam: inject a list so widgets can render without the asset bundle.
/// Sets the BASELINE and drops any overlay, so a test starts from a known state.
void debugSetEmergencyHelp(EmergencyHelp help) {
  _asset = help;
  _overlay.clear();
  _remerge();
}
