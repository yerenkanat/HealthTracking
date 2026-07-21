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

  // ---- A disk that will not take the mirror must not stop the uploads ----
  //
  // _flushing is a latch. It was cleared on each exit path by hand, which holds
  // only while nothing unexpected throws — and cfg.persist writes to a disk,
  // which can be full or have its permission revoked. One failed write left the
  // latch stuck true and NOTHING was ever uploaded again for the rest of the
  // process. Urgent readings included, which is the emergency path.
  //
  // Measured before the fix: one of three urgent readings delivered.
  {
    var delivered = 0;
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 2,
      maxDelay: const Duration(milliseconds: 10),
      maxQueue: 100,
      flush: (items) async => delivered += items.length,
      persist: (_) async => throw StateError('disk full'),
      restore: () async => [],
    ));
    await b.init();
    for (final hr in [70, 80, 90]) {
      b.enqueueTelemetry({'hr': hr}, urgent: true);
      await Future<void>.delayed(const Duration(milliseconds: 40));
    }
    _chk('a failing disk mirror does not stop the network path', delivered == 3);
    _chk('and nothing is left stranded in the queue', b.pending == 0);
  }

  // The same, on the RETRY path: persist is also called from the catch block,
  // where an escape would strand the latch just as surely.
  {
    var attempts = 0;
    var delivered = 0;
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 1,
      maxDelay: const Duration(milliseconds: 10),
      maxQueue: 100,
      flush: (items) async {
        attempts++;
        if (attempts == 1) throw StateError('offline');
        delivered += items.length;
      },
      persist: (_) async => throw StateError('disk full'),
      restore: () async => [],
    ));
    await b.init();
    b.enqueueTelemetry({'hr': 70});
    await Future<void>.delayed(const Duration(milliseconds: 200));
    _chk('a send that fails while the disk fails too still retries', attempts >= 2);
    _chk('and the reading is eventually delivered', delivered == 1);
  }

  // Ordering survives a failure: the batch goes back to the FRONT, so readings
  // reach the server in the order they were taken. Out-of-order vitals would
  // make a trend chart lie.
  {
    var attempts = 0;
    final seen = <int>[];
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 10,
      maxDelay: const Duration(milliseconds: 10),
      maxQueue: 100,
      maxFlushItems: 2,
      flush: (items) async {
        attempts++;
        if (attempts == 1) throw StateError('offline');
        for (final i in items) {
          seen.add(i.payload['n'] as int);
        }
      },
      persist: (_) async {},
      restore: () async => [],
    ));
    await b.init();
    for (var n = 1; n <= 6; n++) {
      b.enqueueTelemetry({'n': n});
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _chk('every reading arrives after a failed attempt', seen.length == 6);
    _chk('and they arrive in the order they were taken',
        seen.join(',') == '1,2,3,4,5,6');
  }

  // ---- An emergency reading does not queue behind the backlog ----
  //
  // `urgent` triggered a flush immediately and protected the item from being
  // trimmed, but the batch was still taken oldest-first. After a spell offline
  // an emergency reading sat behind thousands of routine ones and needed many
  // round trips to reach the server — and the server's emergency push fires on
  // ingest, so the guardian's alert waited with it. "Urgent bypasses the batch"
  // was only ever true of the timer.
  {
    final sent = <List<QueuedItem>>[];
    var allow = false;
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 100000, // never flush on size; we drive it explicitly
      maxDelay: const Duration(seconds: 30),
      maxFlushItems: 10,
      flush: (items) async {
        if (!allow) throw StateError('offline');
        sent.add(items);
      },
      persist: (_) async {},
      restore: () async => [],
    ));
    await b.init();

    // A long stretch offline: 50 routine readings, then the emergency.
    for (var n = 0; n < 50; n++) {
      b.enqueueTelemetry({'n': n});
    }
    b.enqueueTelemetry({'n': 'EMERGENCY'}, urgent: true);
    await Future<void>.delayed(const Duration(milliseconds: 50));

    allow = true;
    b.onConnectivityRestored();
    await Future<void>.delayed(const Duration(milliseconds: 200));

    _chk('the connection coming back sends everything', b.pending == 0);
    _chk('the emergency is in the FIRST batch, not the sixth',
        sent.first.any((i) => i.payload['n'] == 'EMERGENCY'));
    _chk('and it leads that batch', sent.first.first.payload['n'] == 'EMERGENCY');
    // Routine readings keep their own order behind it — the queue is a record
    // of when things were measured, and shuffling it would misreport a trend.
    final routine = [
      for (final batch in sent)
        for (final i in batch)
          if (i.payload['n'] != 'EMERGENCY') i.payload['n'] as int
    ];
    _chk('routine readings stay in the order they were taken',
        routine.join(',') == List.generate(50, (i) => i).join(','));
    _chk('nothing is lost or duplicated', routine.length == 50);
  }

  // Several urgent readings keep their order relative to each other.
  {
    final sent = <List<QueuedItem>>[];
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 100000,
      maxDelay: const Duration(seconds: 30),
      maxFlushItems: 5,
      flush: (items) async => sent.add(items),
      persist: (_) async {},
      restore: () async => [],
    ));
    await b.init();
    for (var n = 0; n < 8; n++) {
      b.enqueueTelemetry({'n': n});
    }
    b.enqueueTelemetry({'n': 'e1'}, urgent: true);
    b.enqueueTelemetry({'n': 'e2'}, urgent: true);
    b.onConnectivityRestored();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final urgentOrder = [
      for (final batch in sent)
        for (final i in batch)
          if (i.urgent) i.payload['n'] as String
    ];
    _chk('urgent readings keep their order among themselves',
        urgentOrder.join(',') == 'e1,e2');
  }

  // ---- Urgency survives a restart ----
  // The disk mirror is what lets a backlog resume after the app is killed. If
  // the urgent flag did not round-trip, an emergency reading queued before a
  // crash would come back as ordinary — losing both its place at the front of
  // the batch and its protection from being trimmed away.
  {
    final wire = const QueuedItem('telemetry', {'systolicMmHg': 175}, urgent: true).toJson();
    final back = QueuedItem.fromJson(wire);
    _chk('urgency round-trips through the disk mirror', back.urgent);
    _chk('so does the payload', back.payload['systolicMmHg'] == 175);
    _chk('and the kind', back.type == 'telemetry');

    final sent = <List<QueuedItem>>[];
    final b = TelemetryBatcher(BatcherConfig(
      maxBatch: 100000,
      maxDelay: const Duration(seconds: 30),
      maxFlushItems: 3,
      flush: (items) async => sent.add(items),
      persist: (_) async {},
      // A backlog from before the restart: routine readings, then an emergency.
      restore: () async => [
        const QueuedItem('telemetry', {'n': 0}),
        const QueuedItem('telemetry', {'n': 1}),
        const QueuedItem('telemetry', {'n': 2}),
        const QueuedItem('telemetry', {'n': 3}),
        const QueuedItem('telemetry', {'n': 'EMERGENCY'}, urgent: true),
      ],
    ));
    await b.init();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    // A restored EMERGENCY goes at once. An ordinary backlog waits for the
    // normal window — but this one has been undelivered since before the app
    // died, and waiting the full window again would add that delay on top of
    // however long the app was closed.
    _chk('a restored backlog with an emergency is sent at once', b.pending == 0);
    _chk('and the emergency leads', sent.first.first.payload['n'] == 'EMERGENCY');

    // An ordinary backlog still waits, so a cold start does not spend radio
    // the moment it opens.
    final quiet = <List<QueuedItem>>[];
    final ordinary = TelemetryBatcher(BatcherConfig(
      maxBatch: 100000,
      maxDelay: const Duration(seconds: 30),
      flush: (items) async => quiet.add(items),
      persist: (_) async {},
      restore: () async => [const QueuedItem('telemetry', {'n': 1})],
    ));
    await ordinary.init();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    _chk('an ordinary backlog still waits for the window',
        quiet.isEmpty && ordinary.pending == 1);
  }

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
