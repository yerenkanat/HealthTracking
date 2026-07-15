/// Real AppStore backed by shared_preferences (a single JSON blob under one key).
/// Kept separate from AppStore so the controller stays plugin-free and testable.
library;

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
      return PersistedConfig.decode(raw);
    } catch (_) {
      return null; // corrupt/incompatible → treat as first run
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
