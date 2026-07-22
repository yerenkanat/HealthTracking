/// Loads the bundled week-by-week baby-development calendar asset once and caches
/// it.
///
/// Offline-first by design: the calendar ships as an asset so the development
/// screen always has content, with no network. (A future refresh from GET
/// /child/development can update the cache, mirroring the content catalogue.)
library;

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../domain/baby_development_content.dart';

const babyDevelopmentAsset = 'assets/data/baby_development.json';

ChildDevCalendar? _cache;

/// The parsed calendar. Loaded from the asset on first call, cached after.
/// Returns an empty calendar (never throws) if the asset is missing or malformed
/// — the development card then simply omits itself.
Future<ChildDevCalendar> loadBabyDevelopment() async {
  if (_cache != null) return _cache!;
  try {
    final raw = await rootBundle.loadString(babyDevelopmentAsset);
    _cache = parseChildDevelopment(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    _cache = ChildDevCalendar.empty;
  }
  return _cache!;
}

/// Test seam: inject a calendar so widgets can render without the asset bundle.
void debugSetBabyDevelopment(ChildDevCalendar calendar) => _cache = calendar;
