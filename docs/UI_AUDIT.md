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

## Progress log — 2026-07-22 (this pass)

Worked the doable items one by one; full app suite **613 green** throughout.

- [x] **Assistant chat had no entry point** → surfaced from the advisor (app-bar
      action + "Ask Umay" card), shown only when the chat controller is attached.
- [x] **Privacy Policy + Terms screens** built and linked from Settings ▸ About,
      plus **onboarding consent** (accept before "Get started").
- [x] **Advisor reply language** now follows the in-app switch at runtime (was
      frozen at startup); added a **multi-night sleep-debt** trend rule.
- [x] **Accessibility**: labeled the consent checkbox and gave the home-safety
      rows 48dp targets; the new antenatal/privacy/terms screens pass clean.
- [x] **Tracking**: "pair a tracker" guidance when there's no location AND no
      device, instead of an indefinite "Waiting…".
- [x] **Tests**: BP calibration-sheet widget tests added.
- [x] Verified **already-done** (BACKLOG was stale): mother's emergency contact
      (doctorPhone in profile), metric day/week/all range toggle, weekly summary
      (digest card + "Your journey"), notification settings (toggle + reminders).

**Still open (doable, deferred for value/sequencing):**
- Shared `Pill`/`SectionHeader` primitives — like `StatTile`, the audit's counts
  are mostly *same-name, different-design* false positives; extract only the true
  dupes to avoid churn. Low value, do opportunistically.
- Backend `/appointments` CRUD, emergency-acknowledge route+column, and calling
  `GET /metrics` — all real, but the app cannot consume them until **sign-in**
  exists (they key on an authenticated user). Sequence these *after* auth.

Detailed remaining backlog below.

---

## A. NOT WORKING / BROKEN — fix first

- [x] **AI Assistant chat has no entry point (orphaned screen).** ✅ FIXED 2026-07-22 —
      surfaced from `AdvisorScreen` (app-bar forum action + an "Ask Umay" card), shown only
      when the chat controller is attached. `AssistantChatScreen` is now reachable.
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

Several of these turned out to **already exist** (BACKLOG.md was stale) — marked below.

- [x] **Privacy policy + Terms screens + consent capture.** ✅ FIXED 2026-07-22 — `LegalScreen`
      (both docs) linked from Settings ▸ About, plus a consent gate on the onboarding welcome step.
- [x] **Emergency contacts management** — ALREADY EXISTS: `UserProfile.doctorPhone`, set in the
      edit-profile sheet, dialed in the emergency flow (`app_controller.dart:1510`).
- [x] **History range toggle** — ALREADY EXISTS: `metric_detail_screen.dart` has a day/week/all
      `_RangeSelector`.
- [x] **Weekly health summary** — ALREADY EXISTS: dashboard `_WeeklyDigestCard` + the "Your journey"
      screen.
- [x] **Notification settings/toggles** — ALREADY EXISTS: Settings notifications toggle + the
      Reminders center (period/fertile/water/med). (Native `flutter_local_notifications` still to
      re-enable — needs config, see BLOCKED.)
- [ ] Consistent **loading / empty / error** states — audited: mostly fine; the `SizedBox.shrink()`
      uses are correct conditional hiding, and the sleep-card empty state is guaranteed by home_shell
      always passing `onLog`.
- [ ] **Location history trail** view + a **geofence editor** (draw/adjust zones on the map) — needs
      live location data (see BLOCKED: maps/GPS).
- [ ] **Lesson content**: `demo_content.dart` ships empty video URLs — needs a real catalogue.
- [ ] Platform/branding: **iOS folder** (only `android/` exists), **app icon + splash** (needs assets).

## C. DUPLICATED UI — consolidate into a shared component layer

There is no design-system layer, so nearly every screen re-declares its own private card / tile /
chip / header / row. This is the checklist's own top rule (`docs/UI_REVIEW_CHECKLIST.md`) and the
largest maintenance liability. **(Note: destructive-action confirms are NOT duplicated/unsafe — 18
gated sites, all correct. No work needed there.)**

- [x] **`StatTile`** — ✅ 2026-07-22: extracted `widgets/stat_tile.dart`; migrated the two true
      dupes (`profile`, `journey`). The dashboard and water-history ones share the *name* only
      (different design — a compact strip / a centred figure) and were deliberately left. The
      "4× duplicate" was 2 real + 2 false positives; expect the same for the chips/rows below.
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
