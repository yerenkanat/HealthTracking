/// TelemetryBatcher — coalesce network writes to save radio wake-ups (battery).
/// Offline-first: buffer persists to disk; EMERGENCY records bypass the batch.
/// Pure Dart (dart:async) → unit-testable. Owned by Code Optimizer + Backend.
library;

import 'dart:async';

class QueuedItem {
  final String type; // 'telemetry' | 'location'
  final Map<String, dynamic> payload;
  final bool urgent;
  const QueuedItem(this.type, this.payload, {this.urgent = false});

  Map<String, dynamic> toJson() =>
      {'type': type, 'payload': payload, 'urgent': urgent};
  factory QueuedItem.fromJson(Map<String, dynamic> j) => QueuedItem(
        j['type'] as String,
        (j['payload'] as Map).cast<String, dynamic>(),
        urgent: (j['urgent'] as bool?) ?? false,
      );
}

class BatcherConfig {
  final int maxBatch;
  final Duration maxDelay;
  final Future<void> Function(List<QueuedItem> items) flush; // POST /ingest/batch
  final Future<void> Function(List<QueuedItem> items) persist; // disk mirror
  final Future<List<QueuedItem>> Function() restore;
  const BatcherConfig({
    required this.maxBatch,
    required this.maxDelay,
    required this.flush,
    required this.persist,
    required this.restore,
  });
}

class TelemetryBatcher {
  final BatcherConfig cfg;
  List<QueuedItem> _queue = [];
  Timer? _timer;
  bool _flushing = false;

  TelemetryBatcher(this.cfg);

  Future<void> init() async {
    _queue = await cfg.restore();
    if (_queue.isNotEmpty) _scheduleFlush();
  }

  void enqueueTelemetry(Map<String, dynamic> t, {bool urgent = false}) {
    _queue.add(QueuedItem('telemetry', t, urgent: urgent));
    unawaited(cfg.persist(_queue));
    if (urgent || _queue.length >= cfg.maxBatch) {
      unawaited(_flushNow());
    } else {
      _scheduleFlush();
    }
  }

  void enqueueLocation(Map<String, dynamic> fix) {
    _queue.add(QueuedItem('location', fix));
    unawaited(cfg.persist(_queue));
    if (_queue.length >= cfg.maxBatch) {
      unawaited(_flushNow());
    } else {
      _scheduleFlush();
    }
  }

  /// Call when connectivity is restored (e.g. connectivity_plus stream).
  void onConnectivityRestored() {
    if (_queue.isNotEmpty) unawaited(_flushNow());
  }

  void _scheduleFlush() {
    if (_timer != null || _flushing) return;
    _timer = Timer(cfg.maxDelay, () => unawaited(_flushNow()));
  }

  Future<void> _flushNow() async {
    if (_flushing) return;
    _timer?.cancel();
    _timer = null;
    if (_queue.isEmpty) return;

    _flushing = true;
    final batch = _queue;
    _queue = [];
    try {
      await cfg.flush(batch);
      await cfg.persist(_queue); // clear disk mirror
    } catch (_) {
      // Requeue at the front, back off; nothing lost (offline-first).
      _queue = [...batch, ..._queue];
      await cfg.persist(_queue);
      _timer = Timer(cfg.maxDelay * 2, () => unawaited(_flushNow()));
    } finally {
      _flushing = false;
    }
  }

  int get pending => _queue.length;
}
