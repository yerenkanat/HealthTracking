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
    _trim();
  }

  /// Merge a batch of samples that may be OLDER than what is already here.
  ///
  /// Live readings arrive in time order and are simply appended. A backfill from
  /// the watch does not: it delivers last Monday after today, and appending it
  /// would leave the list unsorted. Everything downstream — [latest], the
  /// series builder, the sparklines, the trend arrows — reads this list as
  /// oldest-to-newest, so an out-of-order append draws the week backwards and
  /// makes a value from four days ago the "current" reading.
  ///
  /// Sorted after merging, and trimmed from the front, so a backfill bigger than
  /// the buffer drops the oldest days rather than the newest.
  void addSamples(Iterable<HealthSample> batch) {
    if (batch.isEmpty) return;
    _samples.addAll(batch);
    _samples.sort((a, b) => a.at.compareTo(b.at));
    _trim();
  }

  void _trim() {
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
