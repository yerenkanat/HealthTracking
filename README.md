# FemTech & Child Safety Consortium — MVP

A dual-purpose mobile app: **(1) a pregnancy health tracker** (BLE smart band →
proactive medical AI assistant) and **(2) a child safety tracker** (BLE/GPS/Wi-Fi/LBS
beacon → geofencing → instant parent alerts).

**Stack:** Flutter/Dart app · Node/TypeScript backend · PostgreSQL (TimescaleDB +
PostGIS) · Redis · Anthropic Claude for the guardrailed assistant.

> ⚕️ **Safety stance.** Decision-support software, **not a medical device and not a
> diagnosis.** PPG blood pressure and skin-temperature are *screening signals* that
> must be confirmed by a real cuff/thermometer. A genuine danger sign always routes
> to a human clinician / emergency services — the AI can never override that path.

## Layout

```
app/                         Flutter app (Dart)
  lib/core/triage.dart        OB-GYN thresholds — on-device, offline-capable
  lib/core/geofence.dart      circle+polygon geometry + hysteresis tracker
  lib/ble/parsers/*.dart      band GATT frames + iBeacon adverts (pure, tested)
  lib/ble/calibration.dart    skin→core temp, PPG-BP calibration, RSSI→distance
  lib/ble/ble_device_manager.dart  flutter_blue_plus orchestration (both devices)
  lib/perf/adaptive_scan_controller.dart  battery-aware duty cycling
  lib/net/telemetry_batcher.dart          offline-first batched sync
  test/                       flutter/dart test suites
  tool/verify_core.dart       dependency-free conformance runner
packages/
  contract/                  ★ language-neutral SOURCE OF TRUTH
    triage_thresholds.json    the OB-GYN numbers (shared by app + server)
    triage_vectors.json       golden input→verdict cases (shared by app + server)
  shared/    TS types + triage.ts (Node's copy of the safety core)
  backend/   Node + TypeScript
    db/schema.sql             Postgres + TimescaleDB + PostGIS
    src/index.ts              composition root (wires pg+redis+push+anthropic)
    src/server.ts             Fastify: /ingest/batch /ai/chat /calibration/bp /children/:id/location
    src/routes/ingestHandler.ts  pure batch handler (telemetry + location), injectable deps
    src/db/{repository,pgRepository}.ts  interface + Postgres impl
    src/cache/redis.ts        last-location / last-calibration / fence-state
    src/geofence/*            geometry + hysteresis + ingest→dedup→persist→push
    src/notifications/push.ts FCM/APNS + Nudge-Master copy
    src/ai/AIGuardrailProcessor.ts  deterministic triage override + INJECTED LLM (testable)
    src/ai/anthropicClient.ts       real Claude caller (claude-opus-4-8)
app/lib/domain/health_monitor.dart  BLE telemetry → sync + emergency navigation
app/lib/domain/health_series.dart   chart-ready series, stats, danger bands (verified)
app/lib/domain/child_tracker_state.dart  freshness, current zone, "x min ago" (verified)
app/lib/data/api_client.dart        typed backend client (injectable transport)
app/lib/ui/emergency/emergency_rescue_screen.dart  low-anxiety emergency UI
app/lib/ui/dashboard/                health dashboard (stat tiles + sparklines)
app/lib/ui/tracking/child_map_screen.dart  live map + geofence zones + status card
infra/                               docker-compose (timescale+postgis, redis) + smoke test
docs/BATTERY_OPTIMIZATION.md  Code-Optimizer checklist
```

## HTTP surface (what the Flutter app calls)

| Endpoint | Purpose |
|----------|---------|
| `POST /ingest/batch` | TelemetryBatcher flushes batched telemetry + location here; server re-triages (never trusts the client), debounces geofences, pushes alerts |
| `POST /ai/chat` | Guardrailed assistant — triage/red-flag/injection checks run *before* the LLM |
| `POST /calibration/bp` | Weekly cuff reading → PPG offsets (persisted + cached) |
| `GET /children/:id/location` | Last known location from Redis |

The `AIGuardrailProcessor` takes the LLM caller as an **injected dependency**, so the
safety logic (emergency bypass, prompt-injection block, false-reassurance output
filter) is unit-tested with fakes — no network. **Verified:** 13/13 guardrail +
ingest assertions, including a regression that caught a real gap where "your blood
pressure is fine" slipped past the output filter (now fixed).

## The five deliverables → where they live

| Task | Deliverable | Files |
|------|-------------|-------|
| 1 | DB schema (timeseries + geospatial) + Redis keyspace | `backend/db/schema.sql`, `backend/src/cache/redis.ts` |
| 2 | BLE parser service (band + beacon) | `app/lib/ble/*` |
| 3 | Geofencing + maps + notifications | `app/lib/core/geofence.dart`, `backend/src/geofence/*`, `backend/src/notifications/push.ts` |
| 4 | AI guardrails + emergency triage middleware | `backend/src/ai/*`, `app/lib/core/triage.dart` + `packages/contract/` |
| 5 | Battery/performance | `app/lib/perf/*`, `app/lib/net/*`, `docs/BATTERY_OPTIMIZATION.md` |

## ★ The single-source-of-truth safety invariant

The medical triage runs in **two places** — on-device in Dart (instant, works
offline) and on the server in TypeScript (so the LLM is bypassed before it ever
sees critical telemetry). To guarantee the two never disagree:

1. The thresholds live in **one JSON file** (`packages/contract/triage_thresholds.json`).
   Both languages assert their constants match it.
2. A set of **golden vectors** (`packages/contract/triage_vectors.json`) maps input
   telemetry → expected verdict. **Both** the Dart app and the Node server run the
   *same* file and must produce *identical* results.

If a threshold or branch ever drifts between app and server, one language's
conformance suite goes red. **Verified passing:** Dart 36/36, Node 20/20 over the
shared vectors (see "Verify" below).

Emergency flow:
```
band frame → parse → calibrate → assessTelemetry()
   └─ severity == emergency ──▶ mobile: EmergencyRescueScreen + call button (offline OK)
                                server: guardrails return SHOW_EMERGENCY_SCREEN, LLM skipped
```

## Verify

```bash
# Pure-Dart logic (no Flutter SDK needed) — verified on every change:
cd app
dart run tool/verify_core.dart        # 36/36: thresholds, golden vectors, geofence, parsers
dart run tool/verify_datalayer.dart   # 16/16: API parsing, HealthMonitor routing, chat escalation
dart run tool/verify_features.dart    # 24/24: dashboard series/stats/bands, tracking derivation

# Full Dart + widget suites (needs Flutter SDK):
flutter test                          # + emergency / dashboard / map widget tests

# Node backend (needs npm install):
cd .. && npm test                     # vitest: triage + geofence + cross-language contract

# End-to-end wiring (needs Docker): see infra/README.md
docker compose -f infra/docker-compose.yml up -d && node infra/integration_smoke.mjs
```

### Verification status (this machine, pure logic)
| Layer | Result |
|-------|--------|
| Dart core (safety) | 36/36 ✅ |
| Dart data/orchestration | 16/16 ✅ |
| Dart dashboard + tracking | 24/24 ✅ |
| Node guardrail + ingest | 11/11 ✅ |
| Node cross-language contract | 20/20 ✅ |

Flutter **widgets** (emergency/dashboard/map) and the **HTTP/DB integration** are
written with tests but need a Flutter SDK / Docker to execute — the logic feeding
them is verified above.

## Before production — honest gaps
1. **Confirm the OEM BLE frame spec.** `band_parser.dart` uses the common DaFit-style
   envelope; the `BandCmd` ids + byte offsets must be verified against your band's SDK.
   Dispatch, scaling, validation, checksum are real and tested.
2. **Clinical validation & regulatory review.** PPG BP is not a validated diagnostic.
   OB-GYN sign-off on thresholds/copy; assess SaMD/medical-device obligations per market.
3. **Security:** envelope-encrypt health + location columns, rotate keys, pen-test the
   ingest and AI endpoints (injection tests included as a starting point).
4. **Native background geofencing** (iOS region monitoring / Android GeofencingClient)
   to replace JS/Dart polling in the background — see the battery doc.
5. **UI screens** not yet built — the Emergency Rescue screen and low-anxiety FemTech
   dashboards are the next slice (the `ui-ux-pro-max` skill drives that design).
```
