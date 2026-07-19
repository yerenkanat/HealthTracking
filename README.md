# Umay — FemTech & Child Safety MVP

A dual-purpose mobile app: **(1) a pregnancy & cycle health tracker** (BLE smart band →
proactive medical AI assistant) and **(2) a child safety tracker** (BLE/GPS/Wi-Fi/LBS
beacon → geofencing → instant parent alerts). Premium light theme, fully localized in
**Russian / Kazakh / English**.

**Stack:** Flutter/Dart app · Node/TypeScript backend · PostgreSQL (TimescaleDB +
PostGIS) · Redis · Anthropic Claude for the guardrailed assistant.

> ⚕️ **Safety stance.** Decision-support software, **not a medical device and not a
> diagnosis.** PPG blood pressure and skin-temperature are *screening signals* that
> must be confirmed by a real cuff/thermometer. A genuine danger sign always routes
> to a human clinician / emergency services — the AI can never override that path.

## What the app does today

Four tabs, all built and running (demo mode: `--dart-define=DEMO=true`):

- **Health** — a reassuring dashboard: heart-rate / blood-oxygen / temperature /
  merged blood-pressure cards with sparklines + danger bands, a "peace of mind"
  status banner, last-night sleep (vs the week's average), a **daily water tracker**
  (ring + goal + weekly trend & streak, with past days correctable), the data-driven
  **advisor**, and a one-tap **share health summary**. No band? Readings can be
  **entered by hand** — and are triaged identically to measured ones.
- **Calendar (Women's health)** — auto-switches between **cycle mode** (predictions
  with a confidence chip, current **phase card**, fertile-window countdown, month
  grid, shareable forecast, and **insights**: regularity, cycle-length range, flow
  breakdown, mood trend, symptom-by-phase, logging streak, searchable notes) and
  **pregnancy mode** (gestation progress, weekly **baby-size** comparison, non-medical
  milestones, **weight tracking** with gain rate, a **timed kick session** with goal
  ring + history, and a **contraction timer** with the informational 5-1-1 pattern).
  Plus **vitamins & medicines**: track doses, tick them off, see adherence history.
- **Child** — a live map (Google Maps, gated behind a key) with geofence zone pills, a
  low-anxiety status card showing freshness, **tracker battery** (with history), zone
  **dwell time** and last check-in, **check-in / SOS** actions, and a safety-alert feed
  (per-child and per-category filters, today's activity, days-since-SOS). Each child
  also has a **detail screen**. Geofence enter/exit and **low-battery** events fire
  real OS notifications.
- **Profile / Settings** — the mother's profile, children (with gender + zones) and
  devices, language, BP calibration, a **Reminders centre** (period, fertile, water,
  medication — all scheduled as OS notifications), **"Your journey"** lifetime totals,
  and **JSON data export / import** with backup-freshness nudging.

State lives in a pure-Dart `AppController` (dart:async streams), persisted as JSON via
`shared_preferences`, so the whole feature surface is unit-testable without Flutter.

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
app/lib/app/app_controller.dart      single source of UI state (pure Dart streams)
app/lib/data/persisted_config.dart   durable JSON state (profile, logs, water, weights…)
app/lib/l10n/l10n.dart               ru/kk/en catalog (coverage-checked)
app/lib/domain/                      PURE, unit-tested feature logic:
  health_monitor.dart                 BLE telemetry → sync + emergency navigation
  health_series.dart                  chart-ready series, stats, danger bands
  health_advisor.dart                 data-grounded advisory cards (non-diagnostic)
  child_tracker_state.dart            freshness, current zone, "x min ago"
  geofence_alerts.dart                enter/left/checkIn/sos/lowBattery events
  cycle_predictions.dart              next period / fertile / ovulation
  cycle_log.dart / cycle_insights.dart  day logs (mood/symptom/flow) + history
  pregnancy_milestones.dart · kick_session.dart · contraction.dart · weight.dart
  hydration.dart · appointment.dart · battery.dart · sleep.dart · family.dart
  medication.dart · baby_size.dart · reminders.dart · setup_checklist.dart
  manual_vitals.dart (hand-entered readings, triaged like band telemetry)
  journey_stats.dart · weekly_digest.dart · backup_status.dart
app/lib/ui/                          screens (thin presentation over the domain):
  dashboard/                          health dashboard, water card + weekly history
  calendar/                           women's health: cycle + pregnancy, kick/contraction
  tracking/                           child map, zones, alerts feed, check-in/SOS
  appointments/ · profile/ · settings/ · advisor/ · emergency/ · onboarding/
app/lib/data/notification_service.dart  OS notifications (geofence, reminders, low battery)
app/tool/verify_*.dart               33 dependency-free conformance runners (860 assertions)
app/tool/verify_all.dart             runs them all, prints a combined total
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
# Pure-Dart logic (no Flutter SDK needed) — 33 runners, 860 assertions:
cd app
dart run tool/verify_all.dart         # every runner, with a combined total

# …or individually:
dart run tool/verify_cycle.dart       # 128: predictions, phases, insights, trends
dart run tool/verify_alerts.dart      #  61: geofence events, filters, dwell, visits
dart run tool/verify_persistence.dart #  59: full config JSON round-trip + restore
dart run tool/verify_alerts.dart      #  51: geofence events, filters, dwell, visits
dart run tool/verify_family.dart      #  40: phone, children, devices
dart run tool/verify_core.dart        #  36: thresholds, golden vectors, geofence, parsers
# …plus verify_{advisor,app,appointments,baby_size,backup,batcher,battery,calibration,
#   chat,contractions,cycle_summary,datalayer,features,journey,kicks,l10n,milestones,
#   onboarding,reminders,safety,setup,sleep,summary,water,weekly_digest,weight}.dart

# Full Dart + widget suites (needs Flutter SDK):
flutter test                          # 227 widget/unit tests
flutter analyze                       # clean

# Node backend (needs npm install):
cd .. && npm test                     # vitest: triage + geofence + cross-language contract

# End-to-end wiring (needs Docker): see infra/README.md
docker compose -f infra/docker-compose.yml up -d && node infra/integration_smoke.mjs
```

### Verification status (this machine)
| Layer | Result |
|-------|--------|
| Dart pure logic (33 `verify_*` runners) | **860 assertions ✅** |
| Flutter widget + unit tests | **227 ✅** |
| `flutter analyze` | clean ✅ |
| Node cross-language contract (Dart core ⇄ Node) | 36 ⇄ 20 ✅ |

CI (`.github/workflows/ci.yml`) runs every `verify_*` runner, `flutter analyze`,
`flutter test`, and the backend suite on each push. The app runs standalone against
in-process fakes today (`--dart-define=DEMO=true`, or the backend's `USE_MEMORY_DB`) —
real endpoints + API keys drop in without touching the verified logic.

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
5. **Live backend + real device data.** The full UI is built and verified against
   demo/fake data; wiring the typed `ApiClient` to the real endpoints (telemetry,
   location, `/ai/chat`) and pairing real bands/tags is the remaining integration.
```
