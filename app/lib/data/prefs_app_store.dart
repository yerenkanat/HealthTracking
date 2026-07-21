/// Real AppStore backed by shared_preferences (a single JSON blob under one key).
/// Kept separate from AppStore so the controller stays plugin-free and testable.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_store.dart';
import 'persisted_config.dart';

class PrefsAppStore implements AppStore {
  static const _key = 'fcs_app_config_v1';

  @override
  Future<PersistedConfig?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    try {
      final cfg = PersistedConfig.decode(raw);
      if (PersistedConfig.lastDroppedEntries > 0) {
        // Individual entries are dropped now rather than the whole config, so
        // this is the only place anyone would learn it happened. Silence here
        // would mean an appointment or a weight entry quietly disappearing
        // from her history with no explanation anywhere.
        debugPrint(
          'config: ${PersistedConfig.lastDroppedEntries} saved entr'
          '${PersistedConfig.lastDroppedEntries == 1 ? 'y' : 'ies'} could not be '
          'read and were skipped; the rest was restored',
        );
      }
      return cfg;
    } catch (_) {
      // Reachable only if the JSON itself will not decode, or a field outside
      // the per-entry guards throws. Every list and map inside is tolerant, so
      // this no longer fires for one bad appointment — which used to send a
      // woman back to first-run onboarding with all her data still on disk.
      return null;
    }
  }

  @override
  Future<void> save(PersistedConfig config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, config.encode());
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
