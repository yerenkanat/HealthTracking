/// Loads the bundled week-by-week pregnancy calendar asset once and caches it.
///
/// Offline-first by design: the calendar ships as an asset so the week screen
/// always has content, with no network. (A future refresh from GET
/// /pregnancy/weeks can update the cache, mirroring the content catalogue.)
library;

import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;

import '../domain/pregnancy_week_content.dart';

const pregnancyWeeksAsset = 'assets/data/pregnancy_weeks.json';

List<PregnancyWeekContent>? _cache;

/// The parsed calendar. Loaded from the asset on first call, cached after.
/// Returns an empty list (never throws) if the asset is missing or malformed —
/// the week screen then simply omits the card.
Future<List<PregnancyWeekContent>> loadPregnancyWeeks() async {
  if (_cache != null) return _cache!;
  try {
    final raw = await rootBundle.loadString(pregnancyWeeksAsset);
    _cache = parsePregnancyWeeks(jsonDecode(raw) as Map<String, dynamic>);
  } catch (_) {
    _cache = const [];
  }
  return _cache!;
}

/// Test seam: inject a calendar so widgets can render without the asset bundle.
void debugSetPregnancyWeeks(List<PregnancyWeekContent> weeks) => _cache = weeks;
