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
    if (_queue.isEmpty) return;
    // A restored backlog normally waits for the ordinary window — it is old by
    // definition and the app has just started, which is the worst moment to
    // spend battery. An emergency reading in it is different: it was queued
    // before the app died and has been undelivered ever since, so it goes now.
    // Waiting the full window would add that delay on top of however long the
    // app was closed, and the server's push to the guardian waits with it.
    if (_queue.any((i) => i.urgent)) {
      unawaited(_flushNow());
    } else {
      _scheduleFlush();
    }
  }

  void enqueueTelemetry(Map<String, dynamic> t, {bool urgent = false}) {
    _queue.add(QueuedItem('telemetry', t, urgent: urgent));
    _trim();
    unawaited(_persistQuietly());
    if (urgent || _queue.length >= cfg.maxBatch) {
      unawaited(_flushNow());
    } else {
      _scheduleFlush();
    }
  }

  void enqueueLocation(Map<String, dynamic> fix) {
    _queue.add(QueuedItem('location', fix));
    _trim();
    unawaited(_persistQuietly());
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
    // try/FINALLY, because _flushing is a latch: anything that escapes this
    // method leaves it stuck true and no flush ever runs again. It used to be
    // cleared on each exit path by hand, which held only as long as nothing
    // unexpected threw — and cfg.persist writes to a disk, which can be full or
    // revoked. One failed write and telemetry stopped uploading for the rest of
    // the process, silently, urgent readings included.
    try {
      // Only as much as the server will accept in one request; the rest stays
      // queued and goes in the next pass. Urgent readings lead.
      final batch = _selectBatch();
      final inBatch = Set<QueuedItem>.identity()..addAll(batch);
      _queue = [
        for (final item in _queue)
          if (!inBatch.contains(item)) item
      ];
      try {
        await cfg.flush(batch);
        await _persistQuietly(); // mirror what's actually left
      } catch (_) {
        // Requeue at the front, back off; nothing lost (offline-first).
        _queue = [...batch, ..._queue];
        _trim();
        await _persistQuietly();
        _timer = Timer(cfg.maxDelay * 2, () => unawaited(_flushNow()));
        return; // the finally still releases the latch
      }
    } finally {
      _flushing = false;
    }
    // Keep going while there is a backlog, and honour any request that arrived
    // while this flush was in flight.
    if (_queue.isNotEmpty || _flushAgain) {
      _flushAgain = false;
      unawaited(_flushNow());
    }
  }

  /// The next batch to send: urgent readings first, then the rest, oldest-first
  /// within each group.
  ///
  /// `urgent` used to mean only "flush now" — it started a flush immediately
  /// and protected the item from being trimmed, but the batch itself was taken
  /// oldest-first. So after a spell offline an emergency reading sat behind
  /// however much routine traffic had piled up and needed one round trip per
  /// [BatcherConfig.maxFlushItems] to get out. The server raises the guardian's
  /// emergency push when it INGESTS the reading, so that push waited too. The
  /// promise that urgent bypasses the batch was true only of the timer.
  ///
  /// Routine readings keep their relative order: the queue is a record of when
  /// things were measured, and shuffling it would misreport a trend.
  List<QueuedItem> _selectBatch() {
    final limit = cfg.maxFlushItems;
    if (_queue.length <= limit) return List.of(_queue);
    final batch = <QueuedItem>[];
    for (final item in _queue) {
      if (item.urgent && batch.length < limit) batch.add(item);
    }
    for (final item in _queue) {
      if (batch.length >= limit) break;
      if (!item.urgent) batch.add(item);
    }
    return batch;
  }

  /// Mirror the queue to disk, tolerating a disk that will not take it.
  ///
  /// The mirror is a convenience — it lets a restart resume where it left off.
  /// The NETWORK path is the one that matters, and a full disk must not stop
  /// it. Callers also fire this without awaiting, where an escaping error
  /// becomes an unhandled async exception that killed the isolate outright in
  /// a plain Dart run.
  Future<void> _persistQuietly() async {
    try {
      await cfg.persist(_queue);
    } catch (_) {
      // Nothing useful to do: the readings are still in memory and will be
      // sent. Losing the disk mirror costs a restart's worth of backlog.
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
