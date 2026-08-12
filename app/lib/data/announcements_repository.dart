/// Where «Центр уведомлений» gets its рассылки — the app end of admin frame 06.
///
/// Two layers, in this order, and the order is the point:
///
///   1. the last server response, cached in prefs, applied BEFORE first paint;
///   2. `GET /announcements`, fetched after `runApp`.
///
/// There is no bundled asset layer, unlike the pregnancy calendar: nothing can
/// be shipped in the build about a message written last Tuesday. What replaces
/// it is the rule that a failed refresh KEEPS what is on screen — a woman who
/// opens the app on a bus with no signal reads the message she was sent, and
/// never an apology where it used to be.
///
/// Deliberately NOT a global singleton like pregnancy_weeks_repository: that
/// calendar is identical for everybody, and this is one woman's mail. The
/// functions return what they read and the caller hands it to the controller,
/// so there is no process-wide list for a second account to inherit — and
/// [clearAnnouncementsCache] exists so signing out takes the copy with it.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/announcement.dart';
import 'api_client.dart';

/// Key under which the last good `/announcements` response is cached.
const announcementsCacheKey = 'announcements_json';

/// Somewhere to keep the last good response. An interface rather than a direct
/// dependency on shared_preferences, so the layering is testable in plain Dart.
abstract class AnnouncementsCache {
  Future<String?> read();
  Future<void> write(String json);
  Future<void> clear();
}

/// [AnnouncementsCache] over shared_preferences — the store the rest of the
/// app's durable state uses.
class PrefsAnnouncementsCache implements AnnouncementsCache {
  const PrefsAnnouncementsCache();

  @override
  Future<String?> read() async =>
      (await SharedPreferences.getInstance()).getString(announcementsCacheKey);

  @override
  Future<void> write(String json) async =>
      (await SharedPreferences.getInstance()).setString(announcementsCacheKey, json);

  @override
  Future<void> clear() async =>
      (await SharedPreferences.getInstance()).remove(announcementsCacheKey);
}

/// What this phone last received, from disk.
///
/// Called at startup BEFORE the network refresh, so a launch with no signal
/// still shows the messages she already has. Returns an empty list when there
/// is no cache — an ordinary first launch, not a degradation, and never null,
/// because a caller that has to distinguish the two would be tempted to show a
/// spinner over a notification centre that also holds her child's SOS alerts.
Future<List<Announcement>> primeAnnouncementsFromCache(AnnouncementsCache cache) async {
  try {
    final raw = await cache.read();
    if (raw == null) return const [];
    return _parse(raw) ?? const [];
  } catch (e) {
    debugPrint('announcements: cached copy unusable — $e');
    return const [];
  }
}

/// Fetch `/announcements` and cache the exact bytes.
///
/// Returns null when the server could not be reached OR answered an error, so
/// the caller keeps whatever it already had. That is not the same as an empty
/// list, which is a real answer meaning «ей ничего не присылали» — and the
/// difference matters, because collapsing them would let one failed request
/// wipe the cached copy of a message she has not read yet.
///
/// A 503 is the honest case here: the route answers one when migration 037 has
/// not run, precisely so the notification centre keeps its safety alerts rather
/// than going down with a marketing table.
Future<List<Announcement>?> refreshAnnouncementsFromApi({
  required ApiClient api,
  AnnouncementsCache? cache,
  Duration timeout = const Duration(seconds: 8),
}) async {
  try {
    final raw = await api.fetchAnnouncementsJson().timeout(timeout);
    final items = _parse(raw);
    if (items == null) return null;
    // The exact bytes, not a re-encode, so a field this build does not
    // understand still survives to the next launch.
    unawaited(cache?.write(raw));
    return items;
  } catch (e) {
    debugPrint('announcements: refresh failed, keeping what we have — $e');
    return null;
  }
}

/// Forget them. Signing out is not erasing her local data in general, but this
/// is mail addressed to the account that just left the phone.
Future<void> clearAnnouncementsCache(AnnouncementsCache cache) async {
  try {
    await cache.clear();
  } catch (e) {
    debugPrint('announcements: could not clear the cache — $e');
  }
}

List<Announcement>? _parse(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    return parseAnnouncements(decoded.cast<String, dynamic>());
  } catch (e) {
    debugPrint('announcements: could not parse a payload — $e');
    return null;
  }
}
