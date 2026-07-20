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

  /// Most items sent in ONE request. The server rejects a batch over 500
  /// (`batchSchema.max(500)`), and the whole queue used to go in a single
  /// flush — so once a spell offline pushed the backlog past 500, every flush
  /// came back 400, requeued, and retried forever. Sync never recovered, and
  /// the retries went on burning radio. Kept well under the server's limit so
  /// the two can drift apart without meeting.
  final int maxFlushItems;

  /// Most items held at all. An indefinite offline stretch would otherwise
  /// grow the queue — and its disk mirror — without limit. When it overflows
  /// the OLDEST ordinary items go first and urgent ones are kept, the same
  /// rule the safety feed uses: drop the least important, not the newest.
  final int maxQueue;

  const BatcherConfig({
    required this.maxBatch,
    required this.maxDelay,
    required this.flush,
    required this.persist,
    required this.restore,
    this.maxFlushItems = 200,
    this.maxQueue = 5000,
  });
}

class TelemetryBatcher {
  final BatcherConfig cfg;
  List<QueuedItem> _queue = [];
  Timer? _timer;
  bool _flushing = false;
  bool _flushAgain = false;

  TelemetryBatcher(this.cfg);

  Future<void> init() async {
    _queue = await cfg.restore();
    if (_queue.isNotEmpty) _scheduleFlush();
  }

  void enqueueTelemetry(Map<String, dynamic> t, {bool urgent = false}) {
    _queue.add(QueuedItem('telemetry', t, urgent: urgent));
    _trim();
    unawaited(cfg.persist(_queue));
    if (urgent || _queue.length >= cfg.maxBatch) {
      unawaited(_flushNow());
    } else {
      _scheduleFlush();
    }
  }

  void enqueueLocation(Map<String, dynamic> fix) {
    _queue.add(QueuedItem('location', fix));
    _trim();
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
    // A flush is already running. Remember that another was asked for, so the
    // in-flight one re-runs when it finishes: anything enqueued mid-flush used
    // to be stranded with no timer armed, waiting on the NEXT enqueue to move
    // it. An urgent reading arriving during a flush was delayed indefinitely.
    if (_flushing) {
      _flushAgain = true;
      return;
    }
    _timer?.cancel();
    _timer = null;
    if (_queue.isEmpty) return;

    _flushing = true;
    // Only as much as the server will accept in one request; the rest stays
    // queued and goes in the next pass.
    final take = _queue.length < cfg.maxFlushItems ? _queue.length : cfg.maxFlushItems;
    final batch = _queue.sublist(0, take);
    _queue = _queue.sublist(take);
    try {
      await cfg.flush(batch);
      await cfg.persist(_queue); // mirror what's actually left
    } catch (_) {
      // Requeue at the front, back off; nothing lost (offline-first).
      _queue = [...batch, ..._queue];
      _trim();
      await cfg.persist(_queue);
      _timer = Timer(cfg.maxDelay * 2, () => unawaited(_flushNow()));
      _flushing = false;
      return;
    }
    _flushing = false;
    // Keep going while there is a backlog, and honour any request that arrived
    // while this flush was in flight.
    if (_queue.isNotEmpty || _flushAgain) {
      _flushAgain = false;
      unawaited(_flushNow());
    }
  }

  /// Enforce [BatcherConfig.maxQueue], discarding the oldest ORDINARY items
  /// first and keeping urgent ones — an emergency reading is the last thing
  /// that should be dropped to make room.
  void _trim() {
    if (_queue.length <= cfg.maxQueue) return;
    final over = _queue.length - cfg.maxQueue;
    var toDrop = over;
    final kept = <QueuedItem>[];
    for (final item in _queue) {
      if (toDrop > 0 && !item.urgent) {
        toDrop--;
        continue;
      }
      kept.add(item);
    }
    // Still over only if the excess is all urgent; then the oldest give way.
    _queue = kept.length <= cfg.maxQueue
        ? kept
        : kept.sublist(kept.length - cfg.maxQueue);
  }

  int get pending => _queue.length;
}
