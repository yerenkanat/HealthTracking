# Backlog / Roadmap

Legend: `[ ]` todo · `[~]` partial · `[x]` done · 🟢 doable now (no external deps) ·
🔑 needs credentials/keys · 📱 needs real device/hardware · 🐳 needs Docker ·
⚖️ needs human/legal/clinical sign-off.

Status today: app runs on the Android emulator; 11 Dart verify suites + 40 Flutter
tests + 40 Node vitest tests green. Everything below is what remains.

---

## 1. Accounts & Auth 🔑
- [ ] Firebase project + `google-services.json` / `GoogleService-Info.plist`
- [ ] Phone-OTP sign-in (we already collect phone + country code)
- [ ] Backend auth middleware (verify Firebase ID token) on every route
- [ ] Attach `userId` to the app session; send it on `/ingest`, `/ai/chat`, `/calibration/bp`
- [ ] Sync persisted config (profile/children/devices) to the backend account
- [ ] Sign-out (clear session, keep or wipe local data)

## 2. Live band + BLE 📱
- [ ] Wire `BleDeviceManager` live in `main.dart` `bootstrapRuntime` (currently TODO)
- [ ] Feed the onboarding **pair-band** step from a real BLE scan (currently a stub)
- [ ] Runtime permission priming (BLE scan/connect, location) with rationale screens
- [ ] Confirm the OEM band frame spec — `BandCmd` ids + byte offsets vs the real SDK
      (parsers use the common DaFit envelope; dispatch/scaling/checksum are done)
- [ ] Real beacon advertisement scan → child location fixes
- [ ] Native background execution: iOS region monitoring / Android `GeofencingClient`
      (replaces JS/Dart polling — see docs/BATTERY_OPTIMIZATION.md)
- [ ] POST `/calibration/bp` from the app once `userId` exists (offsets already computed locally)

## 3. Maps & location 🔑📱
- [ ] Provide a real `GOOGLE_MAPS_API_KEY`; build with `--dart-define=MAPS_ENABLED=true`
- [ ] Live GPS via `geolocator` feeding `controller.onChildLocation`
- [ ] Capture onboarding Home/School zones from the **current** GPS location (now hardcoded Almaty)
- [ ] Geofence editor: draw/adjust circle/polygon zones + radius on a map
- [ ] Wi-Fi SSID / LBS (cell) positioning fallback (spec) for indoor/low-power
- [ ] Child location-history trail view

## 4. Notifications 🔑
- [ ] FCM setup + push-token registration → `push_tokens`
- [ ] Re-enable `flutter_local_notifications` (removed for the smoke build) for geofence/emergency
- [ ] Notification settings/toggles in Settings
- [ ] Nudge-Master copy review (behavioral-science tone) ⚖️

## 5. AI advisor — depth 🔑🟢
- [x] Rule-based, data-grounded advisories (on-device)
- [ ] LLM-narrated advisory via the backend guardrail, grounded in the rule findings + data 🔑
- [ ] Advisor request language follows the in-app locale at runtime (set at startup today) 🟢
- [ ] More rules: sleep quality, hydration nudges, multi-day/week trends 🟢
- [ ] RAG knowledge base: replace the stubbed `retrieveRagPassages` with vetted content + pgvector 🔑⚖️

## 6. Backend productionization 🐳🔑
- [ ] Run docker-compose (Timescale+PostGIS, Redis), apply schema, run `infra/integration_smoke.mjs`
- [ ] Envelope-encrypt health + location columns; key management/rotation ⚖️
- [ ] Rate limiting, request-size caps, structured error responses
- [ ] Env/secret config (`.env`, secret store), 12-factor cleanup
- [ ] Deploy: container image, hosting, CI/CD to cloud
- [ ] Observability: logging, metrics, error tracking, health/readiness probes
- [ ] Confirm Timescale retention (90d location) + compression policies on a live DB

## 7. Features / screens still missing 🟢
- [ ] Detail screen: day / week / month range toggle + longer history
- [ ] Sleep tracking view (deep/light/REM — spec) — needs band sleep data
- [ ] Emergency contacts management (doctor number) in Profile/Settings
- [ ] Weekly health summary / report
- [ ] Growth: share a safety/health milestone, referral loop (spec)
- [ ] Consistent loading / empty / error states across all screens

## 8. Quality, testing, polish 🟢
- [ ] Widget tests: settings, profile, calibration sheet, child tab, add-child/device sheets
- [ ] Golden/screenshot tests for key screens (light theme)
- [ ] Accessibility audit: contrast, screen-reader labels, 44dp targets, dynamic type
- [ ] iOS platform folder (`flutter create --platforms=ios`) + build (only `android/` exists)
- [ ] App icon, splash screen, store branding
- [ ] End-to-end offline behavior test (batcher replay, restore)
- [ ] Re-enable deferred plugins once configured: `firebase_messaging`, `mmkv`, `flutter_local_notifications`

## 9. Localization ⚖️🟢
- [x] Trilingual ru (default) / kk / en, coverage-enforced
- [ ] Native RU/KK review of **all** copy
- [ ] Clinical + native review of Kazakh/Russian **medical** strings (triage + advisor) ⚖️

## 10. Compliance / medical / regulatory ⚖️
- [ ] OB-GYN clinical sign-off on triage thresholds + advisory copy
- [ ] PPG blood-pressure validation stance; SaMD / medical-device determination per market
- [ ] HIPAA / GDPR review; data-processing agreement
- [ ] Privacy policy + Terms screens + consent capture in onboarding
- [ ] Security pen-test of ingest + AI endpoints (injection tests seeded)

## 11. Public / client API surface 🟢🔑
Current: Fastify with `/ingest/batch`, `/ai/chat`, `/calibration/bp`,
`/children/:id/location`, `/health`. Missing for a real product:
- [ ] Auth endpoints (session from Firebase token, refresh, sign-out)
- [ ] Users: `GET/PATCH /me`, profile + emergency contacts
- [ ] Children CRUD: `GET/POST/PATCH/DELETE /children`
- [ ] Devices CRUD: `GET/POST/DELETE /devices` (band + tags)
- [ ] Geofences CRUD: `GET/POST/PATCH/DELETE /geofences` (circle + polygon)
- [ ] Health history query: `GET /metrics?from&to&metric` (Timescale aggregates)
- [ ] Geofence-event history: `GET /children/:id/events`
- [ ] Calibration history: `GET/POST /calibration/bp`
- [ ] Chat/advisor history: `GET /ai/history`
- [ ] Real-time: WebSocket/SSE for live child location + emergency events
- [ ] Cross-cutting: pagination, filtering, sorting, API versioning (`/v1`)
- [ ] OpenAPI/Swagger spec + generated client types
- [ ] Zod schemas for every request/response (partly done on ingest/chat)
- [ ] Rate limiting, idempotency keys on ingest, request tracing

## 12. Admin panel & back-office (web dashboard) 🟢🔑
A separate web app (e.g. Next.js/React) for staff/clinicians — none exists yet.
- [ ] Staff auth + roles (admin / clinician / support) with RBAC
- [ ] **Ops dashboard**: KPIs — active users, devices online, alerts today, ingest rate
- [ ] **Live emergency feed**: real-time stream of `emergency` triage events, ack/assign,
      call/notify the mother, resolution status
- [ ] **User management**: search mothers, view profile + pregnancy context, children, devices
- [ ] **Patient health view** (clinician): timeseries charts (HR/SpO2/BP/temp), triage history,
      BP calibration history — read-only, audit-logged
- [ ] **Geofence event log**: per-child enter/exit history on a map/timeline
- [ ] **Device fleet**: paired bands/tags, firmware, last-seen, battery, disconnect alerts
- [ ] **RAG content CMS**: author/curate/approve the assistant knowledge base (with review workflow) ⚖️
- [ ] **Triage-threshold console**: view (and, with clinical sign-off, propose) threshold changes
      that flow through the shared contract → app + server
- [ ] **Notifications console**: send/schedule broadcast or targeted nudges; template management
- [ ] **Support tools**: impersonate (audited), resend push, reset a user, export their data (GDPR)
- [ ] **Audit log**: every staff action on PHI/location recorded and queryable
- [ ] **Analytics**: retention/DAU/WAU, funnel (onboarding→paired→active), advisory engagement
- [ ] Admin API: server endpoints backing all of the above (separate `/admin` namespace + RBAC)
- [ ] Data-privacy controls: least-privilege access, field-level masking, access reviews ⚖️

## 13. Analytics, growth & data 🟢🔑
- [ ] Product analytics (events, funnels) — privacy-safe, no PHI in analytics
- [ ] Growth loops: share a safety/health milestone, referral program (spec)
- [ ] Data warehouse / BI for cohort + clinical outcome analysis (de-identified) ⚖️
- [ ] A/B testing framework for nudges/onboarding

---

## Suggested next sprint (all 🟢 — no external deps)
1. Emergency contacts in Profile (doctor number) + wire into the emergency screen call button.
2. Detail-screen range toggle (24h / 7d) + longer history.
3. Advisor: runtime locale + 2–3 more rules (sleep/hydration/multi-day trend).
4. Widget tests for settings/profile/calibration + an offline batcher test.
5. iOS scaffold so the app builds for both platforms.
