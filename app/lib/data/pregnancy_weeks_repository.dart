/// Where the week-by-week pregnancy calendar comes from.
///
/// Three layers, and the order matters:
///
///   1. `assets/data/pregnancy_weeks.json` — the shared contract, shipped with
///      the build. The BASELINE. Always loaded, never replaced.
///   2. the last server response, cached in prefs, so a cold launch with no
///      signal still shows what the back office published.
///   3. `GET /pregnancy/weeks`, fetched after first paint.
///
/// Layers 2 and 3 are applied WEEK BY WEEK over layer 1 — a server response
/// that covers thirty weeks does not blank the other ten. That is the whole
/// difference between this and "fetch and replace": the calendar is the only
/// content every pregnant user sees, and a woman at week 34 opening the app in
/// a village with no signal must read week 34, not an apology.
///
/// The comment this file used to carry promised a server refresh «mirroring the
/// content catalogue» and nothing ever built one, so every edit in the back
/// office stopped at the panel. This is that refresh, and it mirrors
/// content_repository.dart deliberately: same fallback ladder, same
/// cache-the-exact-bytes rule, same "a failure keeps what we have".
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/pregnancy_week_content.dart';
import 'api_client.dart';

const pregnancyWeeksAsset = 'assets/data/pregnancy_weeks.json';

/// Key under which the last good `/pregnancy/weeks` response is cached.
const pregnancyWeeksCacheKey = 'pregnancy_weeks_json';

/// Somewhere to keep the last good response. An interface rather than a direct
/// dependency on shared_preferences, so the layering is testable in plain Dart.
abstract class PregnancyWeeksCache {
  Future<String?> read();
  Future<void> write(String json);
}

/// [PregnancyWeeksCache] over shared_preferences — the same store the rest of
/// the app's durable state uses.
class PrefsPregnancyWeeksCache implements PregnancyWeeksCache {
  const PrefsPregnancyWeeksCache();

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(pregnancyWeeksCacheKey);

  @override
  Future<void> write(String json) async =>
      (await SharedPreferences.getInstance()).setString(pregnancyWeeksCacheKey, json);
}

/// The bundled contract. Loaded once; this is what everything else layers over.
List<PregnancyWeekContent>? _asset;

/// Weeks the server has changed, by week number. Empty until a refresh lands.
final Map<int, PregnancyWeekContent> _overlay = {};

/// [_asset] with [_overlay] applied. Rebuilt whenever either changes.
List<PregnancyWeekContent>? _merged;

void _remerge() {
  final base = _asset;
  if (base == null) {
    _merged = null;
    return;
  }
  _merged = _overlay.isEmpty
      ? base
      : [
          for (final w in base) _overlay[w.week] ?? w,
        ];
}

/// The calendar in use: the bundled weeks, with any server-published week
/// layered on top.
///
/// Returns an empty list (never throws) if the asset is missing or malformed —
/// the week screen then simply omits the card.
Future<List<PregnancyWeekContent>> loadPregnancyWeeks() async {
  if (_merged != null) return _merged!;
  try {
    final raw = await rootBundle.loadString(pregnancyWeeksAsset);
    _asset = parsePregnancyWeeks(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    _asset = const [];
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
Future<void> primePregnancyWeeksFromCache(PregnancyWeeksCache cache) async {
  try {
    final raw = await cache.read();
    if (raw == null) return;
    final weeks = _parse(raw);
    if (weeks == null) return;
    _layer(weeks);
  } catch (e) {
    debugPrint('pregnancy weeks: cached copy unusable, keeping the asset — $e');
  }
}

/// Fetch `/pregnancy/weeks` and layer it over the bundled calendar.
///
/// Returns how many weeks the server changed, or null if it could not be
/// reached — the caller keeps whatever it already had, which is the point of
/// loading the asset first. A failure is logged and never surfaces as an empty
/// screen: content is not worth a blank page about somebody's pregnancy.
Future<int?> refreshPregnancyWeeksFromApi({
  required ApiClient api,
  PregnancyWeeksCache? cache,
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    final raw = await api.fetchPregnancyWeeksJson().timeout(timeout);
    final weeks = _parse(raw);
    if (weeks == null || weeks.isEmpty) return null;
    // The exact bytes, not a re-encode, so a field this build does not
    // understand still survives to the next launch.
    unawaited(cache?.write(raw));
    _layer(weeks);
    return weeks.length;
  } catch (e) {
    debugPrint('pregnancy weeks: refresh failed, keeping what we have — $e');
    return null;
  }
}

/// Put [weeks] into the overlay, one week at a time.
///
/// Never `clear()`s first. A response missing week 7 means "week 7 is
/// unchanged", not "week 7 is now empty" — the server merges the contract into
/// what it serves, and if it ever did not, the bundled week is still the
/// better answer than nothing.
void _layer(List<PregnancyWeekContent> weeks) {
  for (final w in weeks) {
    // Skip an entry with no text at all rather than overwriting a real bundled
    // week with three empty strings. `en` falls back to `ru` in textFor(), so
    // "usable" means the Russian half says something.
    if (w.ru.isEmpty) continue;
    _overlay[w.week] = w;
  }
  _remerge();
}

List<PregnancyWeekContent>? _parse(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final weeks = parsePregnancyWeeks(decoded.cast<String, dynamic>());
    return weeks.isEmpty ? null : weeks;
  } catch (e) {
    debugPrint('pregnancy weeks: could not parse a payload — $e');
    return null;
  }
}

/// Test seam: inject a calendar so widgets can render without the asset bundle.
/// Sets the BASELINE and drops any overlay, so a test starts from a known state.
void debugSetPregnancyWeeks(List<PregnancyWeekContent> weeks) {
  _asset = weeks;
  _overlay.clear();
  _remerge();
}
