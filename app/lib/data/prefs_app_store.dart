/// Real AppStore backed by shared_preferences (a single JSON blob under one key).
/// Kept separate from AppStore so the controller stays plugin-free and testable.
library;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_store.dart';
import 'persisted_config.dart';

class PrefsAppStore implements AppStore {
  static const _key = 'fcs_app_config_v1';

  /// Where an unreadable config is set aside.
  ///
  /// Returning null from [load] tells the app there is nothing saved, so it
  /// shows first-run onboarding — and the first thing that onboarding does is
  /// save, overwriting the very bytes that could not be read. Whatever was
  /// wrong with them, they were the only copy of her history, and the app
  /// destroyed them a few taps after failing to read them.
  ///
  /// Copying them aside first costs one key and keeps recovery possible: the
  /// diagnostics screen can report it, support can ask for it, and a fixed
  /// parser could still read it later.
  static const _quarantineKey = 'fcs_app_config_v1_unreadable';

  /// Whether the last [load] set aside a config it could not read.
  ///
  /// Static for the same reason PersistedConfig.lastDroppedEntries is: the
  /// store is constructed where nothing is listening, and this has to reach the
  /// diagnostics screen.
  static bool lastLoadQuarantined = false;

  @override
  Future<PersistedConfig?> load() async {
    lastLoadQuarantined = false;
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
      //
      // It still sends her to onboarding, and onboarding saves, which would
      // overwrite the unreadable bytes within a few taps. Set them aside first:
      // they are the only copy of her history, and a parser fixed in a later
      // build could still read them.
      try {
        // Only the FIRST failure is kept. A later one would be quarantining a
        // blob onboarding has already overwritten — newer, emptier, and no use
        // to anyone — on top of the one that actually held her history.
        if (prefs.getString(_quarantineKey) == null) {
          await prefs.setString(_quarantineKey, raw);
        }
        lastLoadQuarantined = true;
      } catch (_) {
        // Could not set it aside. Nothing further to try, and failing to load
        // must not become failing to start.
      }
      debugPrint('config: saved data could not be read; kept a copy under $_quarantineKey');
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
    // The quarantined copy goes too. "All data will be erased" has to include
    // the copy the app made for itself — leaving her health history behind in
    // a key she was never told about would make that dialog a lie.
    await prefs.remove(_quarantineKey);
    lastLoadQuarantined = false;
  }
}
