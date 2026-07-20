/// Where timeline content comes from.
///
/// In order of preference:
///   1. the backend, when reachable — what the back-office published
///   2. the last response we cached, so an offline launch still shows it
///   3. `assets/content/catalog.json`, the catalogue shipped with the build
///   4. the seeded demo catalogue
///
/// Every step down is a degradation, not a failure: content is never worth a
/// crash or an empty screen. Which one was used is reported in [LoadedCatalog]
/// so a build can say plainly what it is showing.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart' show rootBundle;

import '../domain/timeline_content.dart';
import 'api_client.dart';
import 'demo_content.dart';

/// Where the authored catalogue lives, relative to the app bundle.
const contentCatalogAsset = 'assets/content/catalog.json';

/// Key under which the last good API response is cached.
const contentCacheKey = 'content_catalog_json';

/// How the catalogue in use was obtained.
enum CatalogSource { api, cache, asset, demo }

class LoadedCatalog {
  final ContentCatalog catalog;
  final CatalogSource source;

  /// Why a lower-priority source was used. Null when the API answered.
  final String? fallbackReason;

  const LoadedCatalog(this.catalog, this.source, {this.fallbackReason});
}

/// Somewhere to keep the last good response. A tiny interface rather than a
/// dependency on shared_preferences, so this stays testable without Flutter.
abstract class ContentCache {
  Future<String?> read();
  Future<void> write(String json);
}

/// Everything available WITHOUT the network: the cached response, then the
/// bundled asset, then the seeded catalogue.
///
/// Startup uses this so first paint never waits on a request. The API refresh
/// happens afterwards and swaps the result in when it lands.
Future<LoadedCatalog> loadCatalogFast({ContentCache? cache}) =>
    loadCatalog(cache: cache);

/// Fetch the published catalogue and cache it. Returns null when the API is
/// unreachable or gave nothing usable — the caller keeps what it already has,
/// which is the whole point of loading locally first.
Future<ContentCatalog?> refreshCatalogFromApi({
  required ApiClient api,
  ContentCache? cache,
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    final raw = await api.fetchContentCatalogJson().timeout(timeout);
    final parsed = _parse(raw);
    if (parsed == null) return null;
    // Cache the exact bytes, not a re-encode, so a field this build does not
    // understand still survives to the next launch.
    unawaited(cache?.write(raw));
    return parsed;
  } catch (e) {
    debugPrint('content: refresh failed, keeping what we have — $e');
    return null;
  }
}

/// Read the catalogue, preferring fresher sources but never failing outright.
///
/// [api] is optional: with no backend configured the app still works from the
/// bundled asset. The network call is bounded by [timeout] because content is
/// not worth delaying first paint — the caller can refresh later.
Future<LoadedCatalog> loadCatalog({
  ApiClient? api,
  ContentCache? cache,
  Duration timeout = const Duration(seconds: 4),
}) async {
  final reasons = <String>[];

  // 1. The backend.
  if (api != null) {
    try {
      final raw = await api.fetchContentCatalogJson().timeout(timeout);
      final parsed = _parse(raw);
      if (parsed != null) {
        // Cache the exact bytes, not a re-encode, so a field this build does
        // not understand still survives to the next launch.
        unawaited(cache?.write(raw));
        return LoadedCatalog(parsed, CatalogSource.api);
      }
      reasons.add('the API returned no usable stages');
    } catch (e) {
      reasons.add('the API was unreachable ($e)');
    }
  }

  // 2. The last good response.
  if (cache != null) {
    try {
      final raw = await cache.read();
      if (raw != null) {
        final parsed = _parse(raw);
        if (parsed != null) {
          return LoadedCatalog(parsed, CatalogSource.cache,
              fallbackReason: reasons.join('; '));
        }
      }
    } catch (e) {
      reasons.add('the cache could not be read ($e)');
    }
  }

  // 3. The bundled asset.
  try {
    final raw = await rootBundle.loadString(contentCatalogAsset);
    final parsed = _parse(raw);
    if (parsed != null) {
      return LoadedCatalog(parsed, CatalogSource.asset,
          fallbackReason: reasons.isEmpty ? null : reasons.join('; '));
    }
    reasons.add('$contentCatalogAsset contained no usable stages');
  } catch (_) {
    reasons.add('no $contentCatalogAsset in the bundle');
  }

  // 4. Seeded content, so the feature is never simply blank.
  return LoadedCatalog(demoContentCatalog(), CatalogSource.demo,
      fallbackReason: reasons.join('; '));
}

/// Parse a catalogue payload, accepting either the API's `{"stages": {...}}`
/// envelope or a bare map of stages as the asset file stores it.
///
/// Returns null when nothing usable came out — an empty result almost always
/// means every stage key was unrecognised or the file is a stub, and showing
/// nothing would look like the feature is broken.
ContentCatalog? _parse(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = decoded.cast<String, dynamic>();
    final stages = map['stages'] is Map
        ? (map['stages'] as Map).cast<String, dynamic>()
        : map;
    final catalog = ContentCatalog.fromJson(stages);
    return catalog.byStage.isEmpty ? null : catalog;
  } catch (e) {
    debugPrint('content: could not parse a catalogue payload — $e');
    return null;
  }
}
