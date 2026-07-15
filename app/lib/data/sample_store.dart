/// SampleStore — bounded, offline-first in-memory buffer of health samples that
/// feeds the dashboard. Pure Dart → unit-testable. A persistent implementation
/// (MMKV/sqlite) can implement the same [addSample]/[recent] shape later.
///
/// Bounded so continuous banding for hours can't grow memory without limit
/// (Code Optimizer). Newest-last ordering; O(1) amortised insert.
library;

import '../domain/health_series.dart';

class SampleStore {
  final int capacity;
  final List<HealthSample> _samples = [];

  SampleStore({this.capacity = 5000});

  void addSample(HealthSample s) {
    _samples.add(s);
    // Trim from the front when over capacity (drop oldest).
    if (_samples.length > capacity) {
      _samples.removeRange(0, _samples.length - capacity);
    }
  }

  /// All samples, oldest → newest.
  List<HealthSample> get all => List.unmodifiable(_samples);

  int get length => _samples.length;

  HealthSample? get latest => _samples.isEmpty ? null : _samples.last;

  /// Samples within [window] of [now] (for "last 24h" style views).
  List<HealthSample> recent(Duration window, DateTime now) {
    final cutoff = now.subtract(window);
    return _samples.where((s) => s.at.isAfter(cutoff)).toList(growable: false);
  }

  void clear() => _samples.clear();
}
