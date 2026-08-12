# What is wired to the backend, and what is not

Written because a sweep for dead code found none — it found the opposite. The
backend implements a full CRUD and sync API that the app does not call. None of
it is unused by accident; all of it is waiting on the same thing.

Keep this current. The alternative is rediscovering it, which has already cost
one investigation: `ApiClient.lastLocation` existed, was called from nowhere,
and the child tracking map therefore had no source of position at all outside a
demo build. It looked like it was waiting for a fix that was never coming.

## Update — 2026-07-29: audited against source — items below are STALE

A wiring audit re-checked this file against the code. Much of what it still
describes as open or broken has shipped — grep the code before acting on any
entry below. Confirmed fixed since this was written:

- **Emergency "Acknowledge"** — described as removed for want of storage; it is
  wired end to end (`server.ts` route → `repo.acknowledgeEmergency` → admin
  button + `acknowledgedBy` render).
- **Telemetry disk mirror** — described as a `(_) async {}` no-op; it persists to
  `prefs_telemetry_queue` (`main.dart` `persist`/`restore`).
- **`submitBpCalibration`** — described as never called; it is (`main.dart`).
- **`getProfile`** — the "NOT CALLED YET" comment in `api_client.dart` is stale;
  the restore path calls it.
- **New this session:** sleep provenance (source + typed asleep total),
  women's-health day-log notes, and **baby cry-analysis history** now all
  round-trip through the backup + restore (migrations 014–016). The in-memory
  admin drilldown no longer drops the doctor phone / cycle baselines / child
  DOB, and the base-wide SOS KPI renders. Cry analysis is now a discoverable
  Care card, not a buried icon.

The genuine remaining blockers are external: real Firebase auth, the cry
classifier model (`packages/cry-classifier` needs a trained `model.pkl`), a Maps
key, and band hardware. See `docs/DEPLOY.md`.

## Update — 2026-07-22: sign-in and first sync landed

The "one blocker" below has been substantially addressed with a **provider-agnostic
phone-OTP sign-in** (`domain/phone_auth.dart`), running today against a
deterministic stub (test code `123456`) and swapping to Firebase by replacing one
class. The app now has a server identity:

- A `SignInScreen` (Settings ▸ Account), `AppController.authSession` (persisted),
  and `HttpApiTransport.getToken` now returns the **session token** — the app
  sends the signed-in caller on every request (was a hard-null).
- **Appointments now sync** app↔backend (`GET/POST/DELETE /appointments`,
  user-scoped, ownership-enforced, idempotent upsert). Local stays the source of
  truth; the server is a backup pulled on sign-in. The admin patient drawer shows
  a mother's upcoming visits.
- New **public reference endpoints**, each from a shared contract the app + admin
  also read: `GET /antenatal/protocol`, `GET /pregnancy/weeks[/:week]`,
  `GET /vaccination/schedule`. The admin panel gained tabs for all three.

Still open: replace the stub provider with real Firebase (needs a project +
credentials); add backend **token verification** (firebase-admin is already a
dependency); run **Postgres** so sync *persists* (it is per-session against the
default in-memory backend); and reconcile local vs server **child ids** (below).

## Update — 2026-07-24: sync + restore now cover most data types

The tables further down ("Implemented server-side, not called by the app" and
"all of a user's data lives on one device") are **out of date** — read them as
history, not current state. Since 2026-07-22 the local-first store gained a
push-on-change hook AND a pull-on-sign-in restore for nearly everything:

- **Push** (`AppController.attach*Sync`, all 16 wired in `main.dart`):
  profile, children, devices, geofences, sleep, cycle days, appointments,
  medications + doses, growth, weight, vaccines, newborn log, BP calibration,
  emergency medical-ID, contraction/kick sessions, auth session.
- **Restore** (`mergeRemote*`, driven by `_restore()` on sign-in, local-wins,
  order-independent, concurrent): the same set. A new phone now rehydrates from
  the backend instead of starting empty. Covered by `test/restore_test.dart`
  and the per-type `*_sync_test.dart` suites.

So `submitBpCalibration` (step 4 below) and the profile/children sync (step 3)
are **done**. What remains genuinely open: real token verification (auth stub),
Postgres so it *persists* across sessions, and the two defects below.

Two items in the tables below are still accurate and still matter:

1. **The `/ingest/batch` "disk mirror" is not real.** `main.dart` passes
   `persist: (_) async {}` / `restore: () async => []` to `TelemetryBatcher`
   (`// TODO: MMKV disk mirror`). The offline queue is memory-only, so telemetry
   queued while offline is **lost if the app is killed before it flushes**. The
   "Offline-first with a disk mirror" note below is aspirational — correct the
   claim or finish the mirror.
2. ~~**Ingest is still not idempotent**~~ — **fixed 2026-07-24.** See the section
   below, now marked resolved.

## The one blocker (historical — mostly resolved above)

**There was no sign-in.** `authUser` is still a dev stub that trusts an
`x-user-id` header (`--dart-define=DEV_USER_ID`) until the backend verifies the
real token, but the app now has a notion of server identity and sends a token.

A second, narrower blocker sits on top of it: **local and server children are
different things**. The app creates children during onboarding with ids like
`child-1`; the backend issues UUIDs and enforces ownership. Any route taking a
child id is refused until the two are reconciled.

## Wired and working

| Path | Notes |
|---|---|
| `GET /content` | Timeline catalogue. Falls back to cache → bundled asset → seed, so it works offline and before the backend exists. |
| `PUT /admin/content/:stage`, `PUT /admin/content` | Authoring from the back-office, including whole-catalogue import. Verified end to end. |
| `POST /ingest/batch` | Telemetry and location, via TelemetryBatcher. Offline-first with a disk mirror. |
| `POST /ai/chat` | Assistant, behind the guardrail and a per-user rate limit. |
| `GET /children/:id/location` | Polled every 45s. **Currently refused (403)** — see the child-id blocker above. Logs the reason once. |
| `GET /antenatal/protocol` | KZ 8-visit schedule, from `contract/antenatal_protocol.json`. App bundles the same domain; admin renders it. |
| `GET /pregnancy/weeks[/:week]` | Week-by-week calendar (ru+kk): `contract/pregnancy_weeks.json` **with the back-office's overrides merged on top** (frames 14a/14b). The app bundles the contract as an asset and layers this over it week by week, so an offline launch still shows the shipped week. Cached in prefs and refreshed at bootstrap, like `/content`. |
| `PUT /admin/pregnancy/weeks/:week`, `POST …/review` | Editing one calendar week from the panel: `content` to write, `health` to sign off, no Kazakh → no publication. Overrides only; the contract is never touched. |
| `GET /vaccination/schedule` | Childhood immunisations, from `contract/vaccination_schedule.json`. App + admin. |
| `GET/POST/DELETE /appointments` | **Now synced** when signed in: push on add/remove, pull on start. User-scoped, ownership-enforced, idempotent on the client id. |

## Implemented server-side, not called by the app

The app is local-first: everything below is stored on the device and persisted
through `PersistedConfig`. These endpoints exist for when sync arrives.

| Path | What the app does instead |
|---|---|
| `GET/PUT /profile` | Held locally in `UserProfile`. |
| `GET/POST /children`, `DELETE /children/:id` | Children live in the controller and the local config. |
| `GET/POST /devices`, `PATCH/DELETE /devices/:id` | Paired devices are local. |
| `GET/POST /children/:id/geofences`, `DELETE /geofences/:id` | Zones are local. |
| `GET /children/:id/events` | Zone history is derived from the local alert feed. |
| `GET/POST /sleep` | Nightly summaries are local. |
| `GET/PUT /cycle/days` | Day logs are local. |
| `GET/POST /alerts` | The safety feed is local and capped in memory. |
| `GET /metrics` | Charts read the in-memory `SampleStore`. |
| `POST /calibration/bp` | `ApiClient.submitBpCalibration` exists and is never called; the app computes and stores offsets locally. |

### The consequence worth knowing

Because none of the above syncs, **all of a user's data lives on one device**.
A reinstall or a new phone starts empty unless she exported a backup first —
which is exactly why the export/import flow and the backup-freshness nudge
exist, and why "erase all data" had to actually erase everything.

Blood-pressure calibration is the sharpest case: it is computed on the device
and stored only there, so a new phone has none until she re-calibrates. That is
handled correctly rather than silently — an absent calibration reports readings
as uncorrected and flags them stale — but it is a real step to redo.

## What to do when endpoints and keys arrive

1. Replace the `x-user-id` dev header with a real token (`HttpApiTransport`
   already prefers a token when one exists and refuses to send the dev header
   alongside it — asserted in `test/http_transport_test.dart`).
2. Reconcile children: adopt server ids, or map local ids to them. Until this
   lands, every child-scoped route stays refused.
3. Wire the sync endpoints above, starting with profile and children, since
   everything else is scoped by them.
4. Call `submitBpCalibration` from `AppController.calibrateBp` so a calibration
   survives a device change. The bounds are already enforced on both sides and
   pinned to `packages/contract/triage_thresholds.json`.

## Authentication: what is actually protecting this

**User auth is wired; staff/admin auth is not.** As of 2026-07-24:

- `authUser` — real. `initFirebaseAuth()` lazily loads `firebase-admin` and
  verifies a Firebase ID token → uid when `REAL_AUTH=1` (a service account is
  needed to activate it). In dev it also honours the app's stub session token and
  the `x-user-id` header. So the USER path is code-complete; it needs credentials,
  not code.
- `authAdmin` — **still a development stub.** It trusts `x-staff-id` plus
  `x-staff-role` outright; there is no real staff/RBAC verifier yet. **`REAL_AUTH`
  does NOT cover it.** So anyone who can reach the port can type
  `x-staff-role: admin` and read every family's record, every child's last known
  location, the audit log, and rewrite the timeline catalogue.

The ownership checks on top of this are real and worth keeping — they stop one
signed-in user reaching another's data, and eight IDOR holes were closed to make
that true. They assume the identity is honest.

### What now stops that becoming a production incident

1. **The server refuses to start** when `NODE_ENV=production` and *either* path is
   still a stub — decided by the pure `authPosture(env)` (tested in
   `authPosture.test.ts`). The earlier guard checked only `!REAL_AUTH`, so a
   `REAL_AUTH=1` deploy — enabling the now-real USER auth — would have shipped the
   back-office **still trusting a forged `x-staff-role`**, while the log claimed
   auth was real. Now `REAL_AUTH=1` alone is not enough: staff auth must be wired
   too (which flips `adminStub` in `authPosture.ts` — deliberately a code change,
   not an env flag, so a stub can never be waved through).
2. **It binds to `127.0.0.1` by default.** It bound to `0.0.0.0`, which put a
   server trusting a forgeable admin header on every network the machine had
   joined — a café's Wi-Fi was enough. `HOST` still widens it, so the exposure
   is at least a decision someone made rather than the default.
3. **It says so at boot**, on every development start, rather than looking like
   a working system.

The Android emulator reaches the host through `10.0.2.2`, which maps to
loopback, so the localhost bind does not affect emulator development — checked,
not assumed.

### What replacing it involves

`buildServer` takes `authUser` and `authAdmin` as injected functions, so the
change is confined to the composition root: verify a Firebase ID token (users)
and a staff session with role claims (back-office), return the same shapes, set
`REAL_AUTH=1`. Every route already goes through `requireCaller` / `requireAdmin`
and checks ownership, and those checks do not change.

## Telemetry ingest is idempotent — RESOLVED 2026-07-24

`TelemetryBatcher` requeues a whole batch whenever a flush fails — including the
case where the server processed it and the RESPONSE was lost on the way back.
The same readings then arrived a second time, producing duplicate rows in her
history **and a second emergency push for a single reading** — one critical-BP
reading, two "your blood pressure is critical" notifications.

### The fix (as shipped)

A unique constraint makes the duplicate impossible in the database, and the
insert reports back whether it stored anything so the caller can skip the push:

```sql
-- schema.sql + migrations/006_phm_idempotent.sql
ALTER TABLE pregnancy_health_metrics
  ADD CONSTRAINT phm_unique_reading UNIQUE (user_id, device_id, recorded_at);
```

- `insertHealthMetric` uses `INSERT ... ON CONFLICT (user_id, device_id,
  recorded_at) DO NOTHING` and returns `true` when the row was already there
  (`rowCount === 0`). The in-memory repo mirrors it with a seen-key set.
- `ingestTelemetry` skips the emergency push and the store count on a duplicate,
  and reports it in a new `duplicates` field of the ingest summary. **Fail-safe:**
  a repo that does not dedup returns `false`, so the worst case is the old
  behaviour (a repeated push), never a *suppressed* real emergency.
- Manual cuff readings carry `deviceId: ''` but distinct `recorded_at`, so they
  never false-collide; the constraint only ever rejects a true resend.

Locked by `ingestIdempotency.test.ts` (resend an emergency batch → one row, one
push, `duplicates: 1`). `keys.bandFrameDedup` in `cache/redis.ts` is now obsolete
— the DB constraint, not a TTL cache, provides the guarantee.

## Acknowledging an emergency has nowhere to be recorded

The back-office emergency feed carried an "Acknowledge" button. It had no click
handler, no route behind it, and no column anywhere to write to. Nothing in the
stack could record that an emergency had been dealt with, or by whom.

It has been removed rather than left in place. On most screens a dead control
is an annoyance; on this one a staff member presses it, watches it depress,
and moves on believing a woman's emergency is handled — a hand-off that never
happened, and the kind of failure nobody discovers until the case is reviewed.

### What restoring it needs

Somewhere to store the acknowledgement, which does not exist yet:

```sql
ALTER TABLE pregnancy_health_metrics
  ADD COLUMN acknowledged_by TEXT,
  ADD COLUMN acknowledged_at TIMESTAMPTZ;
```

Then a `POST /admin/emergencies/:id/ack` guarded by `requireStaff`, written to
the audit log like every other action that touches a family's data, and a
`recentEmergencies` that returns the acknowledgement so the feed can show who
took it and stop counting it in the sidebar badge.

The open question worth settling first is what acknowledgement MEANS: that a
human has seen it, or that the woman has been contacted. Those are different
promises, and the second one is the one a reviewer will assume was made.

## The growth chart has no percentile bands

`domain/child_growth.dart` plots what the parent measured and reports the change
since the previous visit. It does not draw WHO percentile curves, and that is a
decision rather than an unfinished edge.

Percentiles come from the WHO Child Growth Standards: an LMS table (lambda, mu,
sigma) per sex per day of age, from which a z-score and then a centile is
computed. The honest way to have them is to ship that published data file and
interpolate it. The dishonest way is to type approximate numbers from memory
into a medical chart, and a band that is 300 g off tells a mother her healthy
child is underweight.

### What adding them involves

1. The WHO tables for weight-for-age, length/height-for-age and
   weight-for-length, 0–5 years, both sexes, as an asset. They are published as
   text and are not large.
2. `zScore(value, l, m, s)` — the standard LMS formula — plus interpolation
   between the daily rows.
3. Sex on the child record. It is optional today, and a percentile without it
   is meaningless, so the chart must fall back to the plain trend when it is
   absent rather than guessing.
4. An editorial decision about what to SHOW. A centile number invites a parent
   to read it as a grade. Most clinical apps draw the bands and place the child
   on them without naming a number, which is the same information without the
   scoring.

Until then the chart shows her child against her child, which is a comparison
the app can stand behind.

## The Starmax / RunmeFit smartwatch (in progress)

The vendor shipped a uniapp (JavaScript) SDK — `docs/sdk-demo/`. Their code is
not ours to run: we are Flutter. So the wire protocol was reversed from it and
re-implemented in Dart under `app/lib/ble/starmax/`, as a PURE layer with no BLE
or I/O so it is fully testable offline (`tool/verify_starmax.dart`, 47 checks).

**Done — the protocol core.**
- `starmax_protocol.dart` — the frame (`[0xDA, cmd, len16LE, payload, crc16LE]`),
  CRC-16/ARC (pinned to the published `0xBB3D` check value), the command builders
  the app needs (pair, get-health-snapshot, set-time, set-user-info, start/stop a
  live measurement, history-by-day), and a frame parser. A reply's cmd is the
  request's + 0x80; a reply carries a status byte at index 4.
- `starmax_frames.dart` — typed decoders for the snapshot (frame 141: steps,
  kcal, distance, sleep totals, HR, SpO₂, stress, temperature, worn-flag,
  breath rate), the live-measurement result (194), battery (134) and version
  (135). "Current" fields of 0 mean *unknown*, surfaced as null/dash, never as a
  real zero.

**The transport is the Nordic UART Service.** Service `6E400001-…`, write char
`…0002`, notify char `…0003`. Scan filter: advertising data contains the bytes
`0x00 0x01` (device name usually includes `GTS`). MTU negotiated to 512, frames
chunked at 244 bytes.

**Done — the client and the transport.**
- `starmax_client.dart` — a transport-agnostic client (typed async calls,
  request↔reply matching, timeouts, error surfacing, live-measurement fan-out),
  fully tested over a fake transport (`test/starmax_client_test.dart`).
- `starmax_health_bridge.dart` — maps a snapshot to the app's `BandTelemetry`,
  with the safety-critical "0 = unknown → null" rule so an unmeasured metric
  never reaches triage as a false zero.
- `starmax_ble_transport.dart` — the concrete flutter_blue_plus transport
  (`flutter_blue_plus` was already a dependency) and `StarmaxBandManager`: scan
  for the NUS service / name / `0x00 0x01` marker, connect, discover, subscribe,
  run the pair+clock handshake, then poll `readHealth` on an interval and emit
  the same `(BandTelemetry, TriageResult)` records the OEM band does. Mirrors
  BleDeviceManager's lifecycle (single connect, capped-backoff reconnect, held
  subscriptions, link-state stream).

**Wiring.** `main.dart` starts the watch when `--dart-define=STARMAX_WATCH=true`
(opt-in so a user without one never pays a scan; `--dart-define=STARMAX_ID=<id>`
reconnects a known device instead of scanning). Telemetry flows to
`controller.onTelemetry` + `monitor.handle` — the existing dashboard/triage/
batching path, unchanged.

**The health decision was made:** the watch is the mother's health wearable, so
it feeds `HealthMonitor`. Its SOS/contacts commands exist in the protocol for a
future child-safety use but are not wired.

**Every parameter is surfaced, not only the four vitals.** HR/SpO₂/BP/temp go
through triage (`BandTelemetry`); everything else the snapshot carries — steps,
distance, calories, total/deep/light sleep, stress, breathing rate, blood sugar,
worn-state — flows as `WearableMetrics` on the manager's `onSnapshot` stream to
`AppController.latestWearable`, and the dashboard's "Activity & wellness" panel
renders each metric that has a value.

**Link state is wired.** `AppController.onBandLinkState` consumes the manager's
`onStatus`, and the dashboard shows a "not measuring" chip when a wired device
is not delivering — so a watch out of range since morning is explained, not
mistaken for a quiet one.

**Left for when a device is in hand.**
- Verify scan/connect/handshake against real hardware — the transport is the one
  layer no fake could exercise. The scan filter (service UUID / name / adv
  marker) in particular may need tuning to the exact model's advertising.
- Pairing UX (choosing the watch during onboarding) and persisting `STARMAX_ID`.
