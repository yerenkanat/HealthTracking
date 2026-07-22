# UI Audit & To-Do

_Audit date: 2026-07-22. Scope: `app/lib/ui/` (70 files), plus how the UI wires
to backend / API / DB / admin panel. Method: full-codebase sweep (three parallel
audits) cross-checked against `BACKLOG.md`, `STATUS.md`, `docs/INTEGRATION_STATUS.md`._

**Headline:** the app's screens are almost all reachable and the destructive-action
safety discipline is holding (every delete/reset confirms). The real gaps are in
three places: (1) a handful of **broken / dead-end wirings**, (2) heavy **UI
duplication** from having no shared component layer, and (3) the app is **local-only**
for almost everything — only *content* and *chat* actually round-trip to the backend,
and there is **no sign-in** at all.

---

## A. NOT WORKING / BROKEN — fix first

- [ ] **AI Assistant chat has no entry point (orphaned screen).** `AssistantChatScreen`
      (`app/lib/ui/chat/assistant_chat_screen.dart`) is a finished, unit-tested chat UI,
      and the data layer behind it is fully wired (`main.dart:382` `attachChat(ChatController(...))`
      → `POST /ai/chat`). But nothing ever navigates to it — the only reachable AI surface is
      the data-driven `AdvisorScreen`. A mother can never actually chat with the assistant.
      → Add a nav entry (advisor app-bar action, or a dedicated tab/button).
- [ ] **Child live-location never returns a fix (403 / id mismatch).** The 45s poll
      (`main.dart:459-483`) calls `api.lastLocation(controller.selectedChild.id)` with a
      **locally-generated** child id against a server that keys on owned UUIDs — and there
      is no `userId` (see auth below), so ownership fails. The code already logs the mismatch
      (`main.dart:483`). Blocked until auth + server-issued child ids exist.
- [ ] **No sign-in — auth token is hard-null (root blocker).** `main.dart:340`
      `getToken: () async => null` → every "authenticated" call falls back to the forgeable
      `x-user-id` dev header. Nothing is tied to a real account. This blocks A#2 and all of
      section D's sync work.
- [ ] **Telemetry disk mirror is a no-op.** `main.dart:357` `persist: (_) async {}` (MMKV TODO) —
      batched telemetry is not mirrored to disk, so a crash mid-batch loses it.
- [ ] **BP calibration never reaches the server.** `app_controller.dart:1275` TODO — offsets are
      computed and stored locally; `POST /calibration/bp` (and `ApiClient.submitBpCalibration`)
      are never called.

## B. MISSING UI / FEATURES

- [ ] Consistent **loading / empty / error** states across all screens (several screens shrink to
      nothing instead of showing an empty state — verify every `sleep_card.dart:48` caller passes
      a non-null `onLog`, or the "stuck in the empty state" regression returns).
- [ ] **History depth**: day / week / month range toggle + longer history on the metric detail screen.
- [ ] **Emergency contacts management** (doctor's number) in Profile/Settings — the app is a
      pregnancy+child-safety app with no place to store who to call.
- [ ] **Weekly health summary / report** screen.
- [ ] **Location history trail** view + a **geofence editor** (draw/adjust zones on the map).
- [ ] **Notification settings / toggles** in Settings (and re-enable `flutter_local_notifications`).
- [ ] **Privacy policy + Terms screens + consent capture** in onboarding (compliance-blocking).
- [ ] **Lesson content**: `demo_content.dart` ships empty video URLs — the lesson player has nothing
      to play until a real catalogue is supplied.
- [ ] Platform/branding: **iOS folder** (only `android/` exists), **app icon + splash**.

## C. DUPLICATED UI — consolidate into a shared component layer

There is no design-system layer, so nearly every screen re-declares its own private card / tile /
chip / header / row. This is the checklist's own top rule (`docs/UI_REVIEW_CHECKLIST.md`) and the
largest maintenance liability. **(Note: destructive-action confirms are NOT duplicated/unsafe — 18
gated sites, all correct. No work needed there.)**

- [ ] **`StatTile`** — 4 independent copies (`profile_screen.dart:206`, `journey_screen.dart:77`,
      `health_dashboard_screen.dart:723`, `water_history_screen.dart:244`).
- [ ] **`AppCard`** — generic `_Card` re-declared 3× (`child_emergency_screen.dart:112`,
      `pregnancy_weight_screen.dart:159`, `week_detail_screen.dart:198`) + ~30 bespoke `*Card`
      variants with identical padding/radius/border scaffolding.
- [ ] **`Pill` / `Chip`** — ~15 private variants of the same rounded-label token across
      dashboard/calendar/tracking.
- [ ] **`SectionHeader`** — ~8 private variants.
- [ ] **`ListRow`** (leading icon / title-subtitle / trailing) — ~25 near-identical `_*Row` classes;
      also `_NoteRow` ×3, `_CheckRow` ×2, `_ItemRow` ×2.

## D. BACKEND / API / DB / ADMIN — integration gap map

The backend (`packages/backend`, Fastify + Postgres/Timescale/PostGIS + Redis) defines **~40
endpoints**, but the app calls only **5**: `GET /content`, `POST /ingest/batch`, `POST /ai/chat`,
`GET /children/:id/location` (currently 403), `DELETE /account`. Backend also **defaults to
in-memory** when `DATABASE_URL` is unset, so "persistence" only happens against a real Postgres.

| Feature area | Status | To-do |
|---|---|---|
| Auth / sign-in | **NONE (stub)** | Firebase phone-OTP sign-in; attach `userId`; backend auth middleware verifying the token on every route |
| Content / lessons | **BACKED** | ✓ round-trips (incl. admin CMS). Supply real lesson media. |
| Chat / assistant | **BACKED (data)** | Pipeline works; **UI orphaned** (see A#1). Add RAG source (`retrieveRagPassages` stubbed). |
| Health vitals / wearable | **WRITE-ONLY** | `ingest/batch` uploads; history charts read local `SampleStore`. Call `GET /metrics`; add idempotency key on ingest. |
| Child location / geofence | **STUBBED (403)** | Fix A#2; call the geofence CRUD endpoints (they exist, app keeps zones local). |
| Alerts | **LOCAL-ONLY** | `GET/POST /alerts` exist, never called — wire them (feed is memory-capped today). |
| Pregnancy / cycle / sleep | **LOCAL-ONLY** | `GET/PUT /cycle/days`, `/sleep` exist, uncalled — sync from `PersistedConfig`. |
| Family / child / profile | **LOCAL-ONLY** | `/children`, `/devices`, `/profile` exist, uncalled (`putProfile` never called). Wire CRUD + get server child ids (unblocks A#2). |
| Appointments | **NO BACKEND** | No endpoint exists at all — add `/appointments` CRUD, then sync. |
| BP calibration | **LOCAL-ONLY** | See A#5 — call `POST /calibration/bp`. |
| Data export / backup | **LOCAL (by design)** | JSON export/import on-device; `DELETE /account` erases the server copy. Fine until account sync exists. |

### Admin panel (`packages/admin/`)
Single-file `index.html` (~1,900 lines), served by the backend at `GET /admin/ui`. It is a **real,
functional** dashboard (Overview KPIs, Emergencies feed, Users→patient-health drawer, Content CMS,
Devices, Safety, Analytics, Audit) with a live/mock dual mode. Gaps:

- [ ] **Staff auth + RBAC** — the page hardcodes `STAFF = {id:"s1", role:"admin"}`; serving `/admin/ui`
      currently *is* granting admin. Production boot is blocked while this stub is active.
- [ ] **Read-only except content** — "Acknowledge emergency" was removed because there is no route/column
      to record it. Add an ack/assign/resolve route + schema, restore the action.
- [ ] **Deploy as its own app** (currently only reachable through the backend process).
- [ ] **Run against real Postgres** (docker-compose) so admin views show live, not in-memory/mock, data.

---

_See `BACKLOG.md` for the broader (non-UI) roadmap — auth, maps key, FCM push, backend
productionization, compliance/clinical sign-off._
