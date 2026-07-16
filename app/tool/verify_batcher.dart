/// Pure-Dart verification of the offline-first TelemetryBatcher: buffering, urgent
/// bypass, size-cap flush, flush-failure requeue, disk restore, reconnect flush.
/// `dart run tool/verify_batcher.dart`
library;

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

  print('\n$_pass passed, $_fail failed');
  exit(_fail == 0 ? 0 : 1);
}
