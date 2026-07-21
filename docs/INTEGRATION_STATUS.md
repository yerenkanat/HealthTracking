# What is wired to the backend, and what is not

Written because a sweep for dead code found none — it found the opposite. The
backend implements a full CRUD and sync API that the app does not call. None of
it is unused by accident; all of it is waiting on the same thing.

Keep this current. The alternative is rediscovering it, which has already cost
one investigation: `ApiClient.lastLocation` existed, was called from nowhere,
and the child tracking map therefore had no source of position at all outside a
demo build. It looked like it was waiting for a fix that was never coming.

## The one blocker

**There is no sign-in.** `authUser` is a dev stub that trusts an `x-user-id`
header (`--dart-define=DEV_USER_ID`), and the app has no notion of a server
identity. Everything below follows from that.

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

Nothing, yet. Both auth functions are development stubs in
`packages/backend/src/index.ts`:

- `authUser` trusts an `x-user-id` header.
- `authAdmin` trusts `x-staff-id` plus `x-staff-role`.

So **anyone who can reach the port can type `x-staff-role: admin`** and read
every family's record, every child's last known location, the audit log, and
rewrite the timeline catalogue that a hundred thousand phones will show. There
is no password anywhere in the system.

The ownership checks on top of this are real and worth keeping — they stop one
signed-in user reaching another's data, and eight IDOR holes were closed to make
that true. They assume the identity is honest. Right now it is whatever the
caller typed.

### What now stops that becoming a production incident

1. **The server refuses to start** when `NODE_ENV=production` and the stubs are
   still in use. It exits 1 with a message naming the problem. A TODO comment
   does not stop a deploy; this does. Set `REAL_AUTH=1` once token verification
   is wired.
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

## Telemetry ingest is not idempotent

`TelemetryBatcher` requeues a whole batch whenever a flush fails — including
the case where the server processed it and the RESPONSE was lost on the way
back. The same readings then arrive a second time. Nothing on the server
rejects them, so that produces duplicate rows in her history and a second
emergency push for a single reading.

`keys.bandFrameDedup` in `cache/redis.ts` was declared for exactly this and is
wired to nothing.

### Where the fix belongs

Not in Redis. A cache that expires cannot promise idempotency, and the window
that matters here (a retry minutes later, or after a restart) is longer than
any TTL worth keeping. The right place is a unique index:

```sql
ALTER TABLE pregnancy_health_metrics
  ADD CONSTRAINT phm_unique_reading UNIQUE (user_id, device_id, recorded_at);
```

with `INSERT ... ON CONFLICT DO NOTHING` in `insertHealthMetric`, so a repeat
is impossible rather than merely unlikely, and the count the client gets back
still reflects what was stored.

Deferred rather than done because it changes what `/ingest/batch` reports for a
duplicate (stored vs. rejected vs. silently accepted), and that answer should
be settled when the real client is syncing against a real database — not
guessed at now.

Manual readings carry `deviceId: ''`, so the constraint needs a device
placeholder or a partial index; worth deciding at the same time.

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
