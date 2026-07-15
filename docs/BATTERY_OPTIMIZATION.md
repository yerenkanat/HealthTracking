# Battery & Performance Checklist — Code Optimizer

The two continuous workloads (background BLE scanning + geofence/GPS) dominate
battery on an anxious mother's always-on phone. Concrete, code-level strategies,
each mapped to a file in this repo.

## 1. Adaptive scan duty cycling — *don't scan hard when nothing moves*
`packages/mobile/src/ble/AdaptiveScanController.ts`
- Accelerometer-gated state machine → `foreground|moving` scans at `LowLatency`,
  `background|stationary` drops to `LowPower` + 2-min GPS interval.
- Requires **60s of sustained stillness** before coasting down (debounce) so a
  child stopping at a crosswalk doesn't thrash the radio.
- **Impact:** background BLE at `LowPower` uses a fraction of `LowLatency`'s duty cycle.

## 2. Frame coalescing — *one telemetry record, not four*
`BLEDeviceManager.onBandFrame` / `flushFrame`
- HR, SpO2, temp, BP frames arriving within 400 ms are merged into ONE record and
  triaged once, cutting CPU wake-ups and downstream writes ~4×.

## 3. Network batching — *coalesce radio wake-ups*
`packages/mobile/src/net/TelemetryBatcher.ts`
- Buffer non-urgent samples; flush on size cap **or** `maxDelayMs` **or**
  connectivity-restored. The cellular radio's tail-energy means 1 batched POST ≪
  20 individual POSTs.
- **Emergencies bypass the batch** — safety beats battery.
- Disk-mirrored (MMKV/AsyncStorage) → offline-first, survives app kill.

## 4. RSSI/GPS smoothing at the edge — *compute once, alert never-falsely*
`beaconParser.DistanceSmoother` + `geofence.GeofenceTracker`
- Median-filter distance and apply hysteresis (buffer + N confirmations) BEFORE
  emitting. Fewer spurious events → fewer server round-trips and push sends.

## 5. Native background execution — *don't rely on JS timers*
- Use platform geofencing where possible: **iOS `CLLocationManager` region
  monitoring** and **Android `GeofencingClient`** wake the app on a real crossing
  instead of polling GPS. Reserve JS-side polling for foreground live-tracking.
- BLE: register the band's service UUID with the OS scanner so the OS (not your JS
  thread) filters advertisements while backgrounded.

## 6. Memory & GC discipline (continuous scanning)
- **Reuse buffers:** `toBytes` returns a right-sized `Uint8Array`; avoid per-frame
  intermediate strings on the hot path. Prefer `subarray` (view) over `slice` (copy).
- **Bounded structures:** `DistanceSmoother` uses a fixed ring (`window=5`);
  `GeofenceTracker` holds O(fences) state, not O(fixes). No unbounded growth.
- **Detach listeners:** every `on()` returns an unsubscribe; `BLEDeviceManager.destroy()`
  clears timers, stops scans, cancels the connection. Prevents leaks across screens.
- **Backoff, don't spin:** disconnect handling uses capped exponential backoff
  (max 30s) instead of a tight reconnect loop.

## 7. Server & infra (DevOps)
- Redis `enableAutoPipelining` + `sendEachForMulticast` batch fan-out.
- Timescale compression (14d) + continuous aggregates → charts read rollups, not
  raw rows. Retention policy auto-drops location trails at 90d (cost + privacy).

## Measurement gates (QA)
- Add an **Android Battery Historian** + **Xcode Energy Log** pass to CI-manual.
- Regression budget: background scanning session must stay under target mAh/hr on
  the reference device before release. Track wake-lock count per hour.
