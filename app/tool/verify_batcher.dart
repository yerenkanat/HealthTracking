/// Pure-Dart verification of the offline-first TelemetryBatcher: buffering, urgent
/// bypass, size-cap flush, flush-failure requeue, disk restore, reconnect flush.
/// `dart run tool/verify_batcher.dart`
library;

import 'dart:async';
import 'dart:io';
import '../lib/net/telemetry_batcher.dart';

int _pass = 0, _fail = 0;
void _chk(String n, bool ok) {
  ok ? _pass++ : _fail++;
  print('${ok ? 'PASS' : 'FAIL'}  $n');
}

Future<void> _tick() => Future<void>.delayed(const Duration(milliseconds: 15));

Future<void> main() async {
  // ---- urgent bypasses the batch and flushes immediately ----
  {
    final flushed = <List<QueuedItem>>[];
    var persists = 0;
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 5,
      maxDelay: const Duration(seconds: 30),
      flush: (items) async => flushed.add(items),
      persist: (_) async => persists++,
      restore: () async => [],
    ));
    await b.init();
    _chk('empty init: no flush', flushed.isEmpty && b.pending == 0);

    b.enqueueTelemetry({'hr': 80}, urgent: false);
    await _tick();
    _chk('non-urgent buffered (not flushed)', flushed.isEmpty && b.pending == 1);
    _chk('enqueue persisted to disk', persists >= 1);

    b.enqueueTelemetry({'systolicMmHg': 150}, urgent: true);
    await _tick();
    _chk('urgent flushes the whole buffer', flushed.length == 1 && flushed.first.length == 2 && b.pending == 0);
  }

  // ---- size cap triggers a flush ----
  {
    final flushed = <List<QueuedItem>>[];
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 2,
      maxDelay: const Duration(seconds: 30),
      flush: (items) async => flushed.add(items),
      persist: (_) async {},
      restore: () async => [],
    ));
    await b.init();
    b.enqueueLocation({'lat': 1});
    b.enqueueLocation({'lat': 2}); // hits maxBatch=2
    await _tick();
    _chk('maxBatch triggers flush', flushed.length == 1 && flushed.first.length == 2);
  }

  // ---- flush failure requeues (nothing lost) ----
  {
    var attempts = 0;
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 5,
      maxDelay: const Duration(seconds: 30),
      flush: (_) async {
        attempts++;
        throw StateError('offline');
      },
      persist: (_) async {},
      restore: () async => [],
    ));
    await b.init();
    b.enqueueTelemetry({'hr': 70}, urgent: true);
    await _tick();
    _chk('flush failure requeues item', attempts == 1 && b.pending == 1);
  }

  // ---- disk restore on init (offline-first survives app kill) ----
  {
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 5,
      maxDelay: const Duration(seconds: 30),
      flush: (_) async {},
      persist: (_) async {},
      restore: () async => [const QueuedItem('telemetry', {'hr': 66})],
    ));
    await b.init();
    _chk('init restores buffered items from disk', b.pending == 1);
  }

  // ---- reconnect flushes the buffer ----
  {
    final flushed = <List<QueuedItem>>[];
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 50,
      maxDelay: const Duration(seconds: 30),
      flush: (items) async => flushed.add(items),
      persist: (_) async {},
      restore: () async => [],
    ));
    await b.init();
    b.enqueueTelemetry({'hr': 72}, urgent: false); // buffered, timer far off
    await _tick();
    _chk('buffered before reconnect', flushed.isEmpty && b.pending == 1);
    b.onConnectivityRestored();
    await _tick();
    _chk('reconnect flushes buffer', flushed.length == 1 && b.pending == 0);
  }

  // ---- A long spell offline must still sync afterwards ----
  // The server rejects a batch over 500 items. The whole queue used to be sent
  // in one request, so once a backlog passed that, every flush came back 400,
  // requeued and retried forever: sync never recovered and the radio kept
  // waking for nothing.
  {
    const serverCap = 500;
    var accepted = 0, attempts = 0, oversized = 0;
    var offline = true;
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 50,
      maxDelay: const Duration(milliseconds: 5),
      flush: (items) async {
        attempts++;
        if (items.length > serverCap) {
          oversized++;
          throw StateError('server rejects a batch this large');
        }
        if (offline) throw StateError('offline');
        accepted += items.length;
      },
      persist: (_) async {},
      restore: () async => [],
    ));
    await b.init();
    for (var i = 0; i < 600; i++) {
      b.enqueueTelemetry({'i': i});
    }
    await _tick();
    _chk('a long offline stretch keeps everything queued', b.pending == 600);

    offline = false;
    b.onConnectivityRestored();
    for (var i = 0; i < 12 && b.pending > 0; i++) {
      await _tick();
    }
    _chk('a 600-item backlog drains once back online', b.pending == 0);
    _chk('every queued reading is delivered', accepted == 600);
    _chk('no request ever exceeds the server limit', oversized == 0);
    _chk('the backlog goes in several requests, not one', attempts >= 3);
  }

  // ---- Items enqueued DURING a flush are not stranded ----
  // _scheduleFlush bails while a flush is running and _flushNow returned early,
  // so anything arriving mid-flush sat with no timer armed — waiting on the
  // next enqueue to move it. An urgent reading could be delayed indefinitely.
  {
    final release = Completer<void>();
    var flushes = 0;
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 1000, // never trip the size trigger; only the flush matters
      maxDelay: const Duration(milliseconds: 10),
      flush: (items) async {
        flushes++;
        if (flushes == 1) await release.future; // hold the first one open
      },
      persist: (_) async {},
      restore: () async => [],
    ));
    await b.init();
    b.enqueueTelemetry({'a': 1}, urgent: true); // starts a flush that hangs
    await _tick();
    b.enqueueTelemetry({'b': 2}); // arrives mid-flush
    b.enqueueTelemetry({'c': 3}, urgent: true); // an emergency mid-flush
    release.complete();
    for (var i = 0; i < 8 && b.pending > 0; i++) {
      await _tick();
    }
    _chk('items enqueued during a flush are still sent', b.pending == 0);
    _chk('a second flush runs to carry them', flushes >= 2);
  }

  // ---- The queue cannot grow without limit ----
  // Offline indefinitely would otherwise grow both the queue and its disk
  // mirror forever. Urgent items survive the trim; ordinary ones age out.
  {
    var offline = true;
    final delivered = <QueuedItem>[];
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 100000,
      maxDelay: const Duration(milliseconds: 5),
      flush: (items) async {
        if (offline) throw StateError('offline');
        delivered.addAll(items);
      },
      persist: (_) async {},
      restore: () async => [],
      maxQueue: 100,
    ));
    await b.init();
    b.enqueueTelemetry({'sos': true}, urgent: true); // the OLDEST item
    for (var i = 0; i < 500; i++) {
      b.enqueueTelemetry({'i': i});
    }
    _chk('the queue is capped', b.pending == 100);

    offline = false;
    b.onConnectivityRestored();
    for (var i = 0; i < 10 && b.pending > 0; i++) {
      await _tick();
    }
    // The urgent record is the oldest of all, so plain age-based trimming would
    // have dropped it first — exactly the wrong one to lose.
    _chk('the urgent record survives the trim',
        delivered.any((q) => q.urgent && q.payload['sos'] == true));
    _chk('ordinary records are what gave way',
        delivered.length == 100 && delivered.where((q) => !q.urgent).length == 99);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
