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
| Dart assistant chat controller | 11 | ✅ |
| Dart onboarding flow | 25 | ✅ |
| Dart persistence (round-trip + restore) | 19 | ✅ |
| **Flutter widget + unit tests (executed via `flutter test`)** | 38 | ✅ |
| Node backend guardrail + ingest | 11 | ✅ |
| Node cross-language contract (app vs server agree) | 20 | ✅ |
| **Total** | **248** | ✅ |

> The Flutter widget suite now **runs** (Flutter SDK found at `/c/src/flutter`):
> `flutter test` → 38/38, `flutter analyze` → 0 errors/warnings. Running it caught
> a real crash bug (a missing `flutter/semantics.dart` import in the emergency
> screen). Docker still isn't available locally, so the DB integration smoke runs
> in CI, not on this machine.

## What's built
- **Flutter app** (`app/`): first-run onboarding (welcome → language → profile →
  pair band → child + zones) gating the app, entry point, calm FemTech theme, home
  shell (Health + Assistant + Child tabs), health dashboard (sparklines + danger
  bands), child tracking map, a guardrailed AI assistant chat (with a persistent
  "not a diagnosis" disclaimer, and chat that escalates to the emergency screen),
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
1. Firebase Auth (onboarding, profile/child/zone capture, AND persistence via
   shared_preferences are done — a completed setup now survives restart. Remaining:
   sign-in identity + syncing the persisted config to the backend account).
2. Wire `BleDeviceManager` live in `bootstrapRuntime`, and feed the onboarding
   band-scan step from a real BLE scan (marked TODO in `main.dart`).
3. Run `flutter test` + the Docker integration smoke in CI on a real runner.
4. RAG knowledge base for the assistant (`retrieveRagPassages` is stubbed) — the
   chat UI + guardrails are done; it needs a vetted content source.
5. Assistant request language should follow the in-app language switch at runtime
   (currently set at startup).
6. Nudge-Master notification copy review; native RU/KK medical-copy review.

## How to verify locally
```bash
cd app && dart run tool/verify_core.dart && dart run tool/verify_datalayer.dart \
  && dart run tool/verify_features.dart && dart run tool/verify_app.dart
```
