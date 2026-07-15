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
| Dart health advisor (data → advice) | 9 | ✅ |
| **Flutter widget + unit tests (executed via `flutter test`)** | 38 | ✅ |
| Node backend guardrail + ingest | 11 | ✅ |
| Node cross-language contract (app vs server agree) | 20 | ✅ |
| **Total** | **248** | ✅ |

> **Executed, not just written:**
> - `flutter test` → 38/38, `flutter analyze` → 0 errors/warnings.
> - `npx vitest run` → 40/40 (triage, contract, geofence, **+ 8 in-process
>   integration tests** that boot the real Fastify server via `fastify.inject()`
>   — no Docker needed).
> - **The app runs on the Android emulator** (`flutter run`, API 35). Onboarding,
>   the assistant chat, and the health dashboard all render correctly in Russian.
>
> **Bugs found by executing** (that written-only code hid):
> - Missing `flutter/semantics.dart` import → emergency screen would crash (fixed).
> - `main.dart` wired `HealthMonitor.onEmergency` with swapped arg order → compile
>   error caught by the Gradle build (fixed).
> - AndroidManifest lacked INTERNET / location / BLE permissions, the `tel:` query
>   (emergency-call button would silently fail on Android 11+), and the Maps key
>   slot (added all).
>
> **Still needs config:** the child map tab is blank until a real `GOOGLE_MAPS_API_KEY`
> is set (env var → `android/app/build.gradle.kts`). Docker isn't installed here, so
> the docker-compose smoke (literal pg/Timescale/PostGIS + ioredis drivers) runs in
> CI; the in-process integration test covers the routing/validation/handler logic.

## What's built
- **Flutter app** (`app/`): **modern high-tech dark UI** (glassmorphism, aurora
  glow background, violet/pink/teal gradients, Outfit + JetBrains Mono type —
  grounded in the ui-ux-pro-max design system). First-run onboarding gating the
  app; home shell (Health + Advisor + Child tabs); health dashboard as a glass
  metric grid with glowing sparklines; a **data-driven Health Advisor** (reasons
  over band telemetry → advisory cards; NOT a chatbot); child tracking (graceful
  map placeholder without a Maps key); and an app-wide Emergency Rescue screen that
  overrides everything on a critical reading. One pure-Dart `AppController`.
  Verified on the Android emulator with `--dart-define=DEMO=true` seed data.
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
1. Provide a real `GOOGLE_MAPS_API_KEY` (child map) and re-enable the deferred,
   config-dependent plugins in `pubspec.yaml` (firebase_messaging, mmkv,
   flutter_local_notifications — currently commented out since they're unused in
   Dart and need native config to build).
2. Firebase Auth (onboarding, profile/child/zone capture, AND persistence via
   shared_preferences are done — a completed setup now survives restart. Remaining:
   sign-in identity + syncing the persisted config to the backend account).
3. Wire `BleDeviceManager` live in `bootstrapRuntime`, and feed the onboarding
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
