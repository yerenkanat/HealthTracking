# Project Status — FemTech & Child Safety MVP

_Last updated: 2026-07-15_

## Where we are
The app has a **verified spine** from sensor bytes → medical triage → sync →
backend → alerts → screens → app shell. Every piece of business logic that can run
without a device or cloud is unit-tested and green on each change.

## Verification (pure logic, runs in CI without a device/Docker)
| Layer | Assertions | Status |
|-------|-----------:|:------:|
| Dart safety core (triage, geofence, BLE parsers, calibration) | 36 | ✅ |
| Dart data/orchestration (API client, HealthMonitor, chat routing) | 16 | ✅ |
| Dart dashboard + tracking derivation | 24 | ✅ |
| Dart app controller + sample store | 15 | ✅ |
| Dart localization (ru/kk/en + coverage) | 33 | ✅ |
| Node backend guardrail + ingest | 11 | ✅ |
| Node cross-language contract (app vs server agree) | 20 | ✅ |
| **Total** | **155** | ✅ |

## What's built
- **Flutter app** (`app/`): entry point, calm FemTech theme, home shell (Health +
  Child tabs), health dashboard (sparklines + danger bands), child tracking map,
  and an app-wide Emergency Rescue screen that overrides everything on a critical
  reading. State flows through one pure-Dart `AppController`.
- **Backend** (`packages/backend/`): Fastify HTTP surface, Postgres+Timescale+PostGIS
  schema, Redis caching/dedup, geofence pipeline, FCM/APNS push, and the AI guardrail
  with a deterministic triage override the LLM cannot bypass.
- **Shared safety contract** (`packages/contract/`): one JSON source of truth for
  medical thresholds + golden vectors; app and server proven to agree.
- **Localization**: Russian (default on install), Kazakh, English. Medical triage
  emits codes; the UI localizes them (no language baked into safety logic). A
  coverage test fails the build if any key is missing a translation. In-app
  language switcher on the dashboard.
- **Infra** (`infra/`): docker-compose integration stack + end-to-end smoke test.
- **CI** (`.github/workflows/ci.yml`): runs all the above on every push/PR.

## Top risks (owner → mitigation)
1. **PPG blood pressure is not a validated diagnostic** (OB-GYN). Mitigated by
   weekly cuff calibration + a hard triage escalation that always routes to a human.
   → Needs clinical sign-off before any medical claim.
2. **OEM BLE frame offsets unconfirmed** (Hardware). Parsers use the common
   DaFit-style envelope. → Confirm `BandCmd` ids/offsets against the real SDK.
2a. **RU/KK medical translations need native + clinical review** (L10n + OB-GYN).
    Current Russian/Kazakh triage copy is a first pass; verify wording before launch.
3. **Regulatory** (PM). Determine SaMD / medical-device obligations per market
   (KZ/CIS + any EU/US).
4. **Privacy** (Security). Envelope-encrypt health + location columns; key rotation;
   pen-test ingest + AI endpoints (injection tests already seeded).

## Next up (in priority order)
1. Onboarding + Firebase Auth; pair a band; load child profile/geofences.
2. Wire `BleDeviceManager` live in `bootstrapRuntime` (marked TODO in `main.dart`).
3. Run `flutter test` + the Docker integration smoke in CI on a real runner.
4. RAG knowledge base for the assistant (`retrieveRagPassages` is stubbed).
5. Localization pass (ru-KZ / kk-KZ), Nudge-Master notification copy review.

## How to verify locally
```bash
cd app && dart run tool/verify_core.dart && dart run tool/verify_datalayer.dart \
  && dart run tool/verify_features.dart && dart run tool/verify_app.dart
```
