/// AppStore — persistence seam for [PersistedConfig]. The controller depends on
/// this interface, not on a plugin, so it's testable with the in-memory fake.
/// The real shared_preferences implementation lives in prefs_app_store.dart.
library;

import 'persisted_config.dart';

abstract class AppStore {
  Future<PersistedConfig?> load();
  Future<void> save(PersistedConfig config);
  Future<void> clear();
}

/// Test/default fake — keeps the encoded string in memory (mirrors the real one's
/// encode/decode path so serialization bugs surface in tests too).
class InMemoryAppStore implements AppStore {
  String? _raw;
  InMemoryAppStore([PersistedConfig? seed]) {
    if (seed != null) _raw = seed.encode();
  }

  @override
  Future<PersistedConfig?> load() async => _raw == null ? null : PersistedConfig.decode(_raw!);

  @override
  Future<void> save(PersistedConfig config) async => _raw = config.encode();

  @override
  Future<void> clear() async => _raw = null;
}
