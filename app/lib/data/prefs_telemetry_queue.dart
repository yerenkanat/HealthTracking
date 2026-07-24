/// Disk mirror for the TelemetryBatcher's offline queue, backed by
/// shared_preferences (one JSON array under one key). Kept separate from the
/// batcher so that stays plugin-free and unit-testable — the batcher only calls
/// [save] / [load] through its persist/restore hooks.
///
/// Why this exists: the hooks were no-ops (`persist: (_) async {}`), so the
/// queue was memory-only. Any telemetry buffered while offline — a spell without
/// signal, an emergency reading queued the instant before a crash — was lost the
/// moment the app was killed, and the clinician's view simply never saw it. The
/// batcher was written expecting a real mirror; this is it.
library;

import 'dart:convert';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import '../net/telemetry_batcher.dart';

class PrefsTelemetryQueue {
  static const _key = 'fcs_telemetry_queue_v1';

  /// Mirror the current queue. An empty queue clears the key rather than storing
  /// "[]", so a delivered backlog leaves nothing behind to restore.
  Future<void> save(List<QueuedItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    if (items.isEmpty) {
      await prefs.remove(_key);
      return;
    }
    await prefs.setString(_key, jsonEncode([for (final i in items) i.toJson()]));
  }

  /// Restore the queue on startup. Returns empty when there is nothing saved.
  Future<List<QueuedItem>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
      return [for (final m in list) QueuedItem.fromJson(m)];
    } catch (_) {
      // A buffer that will not decode must not stop startup or lose the app.
      // Undelivered telemetry is not worth a failed boot — drop it and say so.
      debugPrint('telemetry queue: saved buffer could not be read; discarded');
      try {
        await prefs.remove(_key);
      } catch (_) {}
      return [];
    }
  }
}
