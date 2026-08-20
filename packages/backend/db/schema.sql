-- =============================================================================
-- FemTech & Child Safety Consortium — Relational schema
-- Target: PostgreSQL 15+ (plain — runs on any managed Postgres or a local install).
-- Specialists: Senior Backend Engineer, OB-GYN (metric columns/constraints),
--              Geofencing Specialist, Data Privacy Officer (encryption notes).
--
-- Portability note: this was TimescaleDB + PostGIS, but the app never used either
-- at QUERY time — geofence math is done in TypeScript (haversine), and the
-- hypertables/continuous-aggregate were storage optimisation nothing read. So they
-- were a hard dependency the app didn't leverage, and one that forced a special
-- host. Geometry is now plain lat/lng (+ GeoJSON) columns; the timeseries tables
-- are ordinary tables. If write-scale ever needs it, TimescaleDB can be re-added
-- as an opt-in migration (SELECT create_hypertable + compression) — the row shape
-- is unchanged.
--
-- Privacy: health + child-location data are special-category (GDPR Art.9) / PHI (HIPAA).
--
-- Read this before assuming anything below is encrypted, because until 2026-08-20
-- this block said the opposite. It claimed the bp_calibration offsets and any
-- free text were held as ciphertext by an application-layer crypto module, and
-- it named a directory under the backend source for that module. No such
-- directory has ever existed: no cipher call, no pgcrypto, no key material
-- anywhere in packages/backend/src. The claim's only effect was to stop the next
-- reviewer looking. It is quoted in full, once, in docs/SECURITY_FOLLOWUP.md §8;
-- it is not repeated here, because pgSchema.test.ts reads this file literally and
-- cannot tell a quotation from a claim — which is precisely the property that
-- keeps the claim from coming back.
--
--   * NOT encrypted at rest, at any layer. bp_calibration.systolic_offset /
--     diastolic_offset, every column of pregnancy_health_metrics (triage_severity
--     included), location_history.lat/lng, children, and child_emergency
--     (blood_type, allergies, conditions, doctor_phone) are PLAINTEXT columns.
--     Anyone holding a copy of this database — a stolen disk, a mishandled dump,
--     a support query — reads them by name. pgSchema.test.ts now fails if this
--     file ever again names a crypto module that is not on disk.
--   * What IS cryptographic, and this is the whole list: staff passwords
--     (staff_accounts.password_hash — salted scrypt) and staff session cookies
--     (staff_sessions.token_hash — sha256). See src/http/staffAuth.ts.
--   * What protects health and location instead: access control plus audit — a
--     capability check (src/auth/capabilities.ts) and an audit_log row carrying a
--     non-empty stated reason on every protected read. That is a control on the
--     RUNNING SERVER. It does nothing for a copy of the data.
--   * At-rest, host level: the Docker volume sits on an unencrypted disk. The
--     nightly dump is the one copy that IS encrypted — age, to a public key on
--     the box whose private half only the owner holds (deploy/backup.sh).
--   * Encrypting the columns themselves is an OWNER decision, not a TODO, and the
--     reason is key management: the app and the database share one host, so a key
--     the app can read unattended is a key an attacker with that host can read
--     too. docs/SECURITY_FOLLOWUP.md §8 states the question plainly and lists what
--     ciphertext would break: the sane_hr / sane_spo2 / sane_bp CHECKs, the four
--     triage_severity filters and idx_phm_emergency with them, and ORDER BY
--     children.name. Answer the key question before touching these columns.
--   * Retention: prune location_history older than ROUTE_RETENTION_DAYS
--     (src/privacy/retention.ts — 90 days, the same constant the app shows the
--     mother). A cron DELETE; was a Timescale policy.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- substring search on the admin user list
CREATE EXTENSION IF NOT EXISTS citext;     -- case-insensitive email uniqueness

-- -----------------------------------------------------------------------------
-- Identity
-- -----------------------------------------------------------------------------
CREATE TABLE users (                       -- Mothers / primary caregivers
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- Nullable: a mother who signs up with her phone has no email to give, and
  -- inventing one to satisfy a constraint would put fake addresses in the
  -- column somebody later tries to send mail to (migration 020).
  email          CITEXT UNIQUE,
  phone_e164     TEXT,
  display_name   TEXT NOT NULL,
  locale         TEXT NOT NULL DEFAULT 'ru-KZ',   -- Localization Specialist: CIS default
  timezone       TEXT NOT NULL DEFAULT 'Asia/Almaty',
  -- Pregnancy context lets the OB-GYN rules adapt (trimester-aware baselines).
  due_date       DATE,
  -- Collected in-app with a stated reason (see the profile sheet): age-relevant
  -- guidance, and products that can actually be delivered where she lives.
  -- Both OPTIONAL — the app works without them and must keep working.
  birth_date     DATE,
  city           TEXT,
  -- Where an ambulance is sent (app screen 37 «Экстренная помощь», migration
  -- 043). Free text and optional — a real address here is «мкр. Самал-2, д. 33,
  -- кв. 12, домофон 12К», and declining is a supported answer: the screen then
  -- shows her city with «Добавьте адрес» rather than inventing one.
  --
  -- NOT shop_orders.address, which is a delivery address attached to one order
  -- and may be a workplace or a relative's flat. Dictating that to a 103
  -- dispatcher sends the ambulance to the wrong door.
  address        TEXT,
  -- Her own emergency contact (a doctor/clinic number), free text. Optional.
  doctor_phone   TEXT,
  -- Women's-health baselines she can set until two cycles are logged; they drive
  -- the period/fertility predictions. NULL = fall back to the 28/5 defaults.
  avg_cycle_length  SMALLINT CHECK (avg_cycle_length IS NULL OR avg_cycle_length BETWEEN 15 AND 60),
  avg_period_length SMALLINT CHECK (avg_period_length IS NULL OR avg_period_length BETWEEN 1 AND 14),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- The admin user list searches with `ILIKE '%term%'`. A leading wildcard makes
-- the btree on email useless and display_name has none at all, so every search
-- keystroke was a full scan of users plus a per-row pattern match. Trigram GIN
-- indexes are the one index type that can serve an unanchored ILIKE.
CREATE INDEX idx_users_name_trgm  ON users USING GIN (display_name gin_trgm_ops);
CREATE INDEX idx_users_email_trgm ON users USING GIN ((email::TEXT) gin_trgm_ops);

CREATE TABLE devices (                     -- Smart bands + child tracker tags
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id        UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ble_mac        TEXT NOT NULL,
  model          TEXT,                     -- OEM model for protocol selection
  firmware       TEXT,
  kind           TEXT NOT NULL DEFAULT 'band' CHECK (kind IN ('band','tag')),
  name           TEXT,
  -- tracker tag → child. The FK is added AFTER `children` is created (below):
  -- `children` is defined after this table, so an inline REFERENCES here was a
  -- forward reference that failed on any freshly-built database.
  child_id       UUID,
  paired_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Fleet telemetry. Both were already SELECTed by adminDevices() and neither
  -- was ever declared here, so the fleet view worked only against databases
  -- that had drifted ahead of this file and failed outright on one built from
  -- it. NULL means never reported, which is distinct from "reported nothing".
  battery_pct    INT CHECK (battery_pct BETWEEN 0 AND 100),
  last_seen      TIMESTAMPTZ,
  -- «Пометить браком» (frame 11). A support note on THIS mother's paired
  -- device, not a warehouse decision: device_registry.status = 'blocked' stops
  -- a serial pairing with any account and lives on the Склад screen. Marking a
  -- device faulty here changes nothing about how it works — it records that
  -- somebody found it faulty, with who and when, and it is reversible because
  -- the commonest reason to mark something is a mistake.
  defect_at      TIMESTAMPTZ,
  defect_by      TEXT,
  defect_note    TEXT,
  UNIQUE (user_id, ble_mac)
);
CREATE INDEX idx_devices_last_seen ON devices (last_seen DESC NULLS LAST);

CREATE TABLE children (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  guardian_id    UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name           TEXT NOT NULL,            -- e.g. "Sultan"
  gender         TEXT CHECK (gender IN ('boy','girl')),  -- null = not provided
  date_of_birth  DATE,                     -- null = not provided; drives age stats
  -- Beacon identity: iBeacon triple, or a Tuya/LBS tag id for non-iBeacon tags.
  beacon_uuid    TEXT,
  beacon_major   INT,
  beacon_minor   INT,
  tag_serial     TEXT,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
  -- No "must have a beacon/tag" CHECK: a child is added first (name/DOB) and a
  -- tracker is paired later, so requiring a beacon identity at creation rejected
  -- every child the app creates. Beacon fields are optional until a tag is paired.
);
CREATE INDEX idx_children_guardian ON children(guardian_id);
CREATE INDEX idx_children_beacon    ON children(beacon_uuid, beacon_major, beacon_minor);

-- devices.child_id → children(id), added now that `children` exists (see the note
-- on devices.child_id above). SET NULL: unpairing a tag must not delete the band.
ALTER TABLE devices
  ADD CONSTRAINT devices_child_fk FOREIGN KEY (child_id) REFERENCES children(id) ON DELETE SET NULL;

-- Appointments / reminders (prenatal visits, ultrasounds, lab work). The id is
-- CLIENT-supplied so an appointment created offline keeps its identity when it
-- syncs; upsert on that id makes re-syncing idempotent.
CREATE TABLE appointments (
  id        TEXT PRIMARY KEY,
  user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title     TEXT NOT NULL,
  at        TIMESTAMPTZ NOT NULL,
  note      TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_appointments_user ON appointments(user_id, at);

-- Medications / supplements the mother is taking (client keeps the id).
CREATE TABLE medications (
  id        TEXT PRIMARY KEY,
  user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name      TEXT NOT NULL,
  dose      TEXT NOT NULL DEFAULT '',
  per_day   INTEGER NOT NULL DEFAULT 1
);
CREATE INDEX idx_medications_user ON medications(user_id);

-- Medication adherence: doses of a medication actually taken on a day. One row
-- per (medication, day); count is capped app-side at the med's perDay target.
-- The clinician reads this against the perDay to see if she is keeping to, say,
-- her aspirin or iron. med_id is globally unique (medications PK), so it keys
-- the row; user_id carries the owner for the per-user list + cascade.
CREATE TABLE med_doses (
  med_id    TEXT NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
  user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  log_date  DATE NOT NULL,
  count     SMALLINT NOT NULL CHECK (count >= 0),
  PRIMARY KEY (med_id, log_date)
);
CREATE INDEX idx_med_doses_user ON med_doses (user_id, log_date DESC);

-- -----------------------------------------------------------------------------
-- Pregnancy health metrics — TIMESERIES (TimescaleDB hypertable)
-- -----------------------------------------------------------------------------
CREATE TABLE pregnancy_health_metrics (
  -- NULL = a manual (hand-typed cuff) reading: it has no device. Requiring a
  -- device_id here rejected the app's most trustworthy readings outright, so a
  -- mother's typed cuff numbers never reached her clinician on a real database.
  device_id      UUID REFERENCES devices(id) ON DELETE CASCADE,
  user_id        UUID NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  recorded_at    TIMESTAMPTZ NOT NULL,
  core_temp_c    REAL,
  skin_temp_c    REAL,
  -- A temperature a DEVICE reported with no stated measurement site and no
  -- stated accuracy (the Starmax watch's `当前体温`), in °C, unconverted.
  --
  -- Its own column on purpose: it is NOT a core temperature and must never be
  -- written to, read as, or merged with core_temp_c — with no site there is no
  -- defensible conversion, and every reader of core_temp_c treats that column
  -- as an estimate of her core. It is NOT a triage input either: assessTelemetry
  -- ignores it, and no device path may raise a temperature emergency. Carried
  -- and stored, never graded — the glucose_mmol precedent below. A thermometer
  -- reading she TYPES IN is the escalating path, and is untouched by this.
  -- See migration 048 and docs/CLINICAL-REVIEW-WATCH.md.
  device_temp_c  REAL,
  heart_rate_bpm SMALLINT,
  spo2_pct       SMALLINT,
  systolic_mmhg  SMALLINT,      -- PPG screening estimate (calibrated)
  diastolic_mmhg SMALLINT,      -- PPG screening estimate (calibrated)
  glucose_mmol   REAL,          -- blood glucose (typed glucometer or band estimate); wellness, not triaged
  during_sleep   BOOLEAN NOT NULL DEFAULT FALSE,
  -- Highest triage severity computed at ingest, for fast dashboard filtering.
  triage_severity TEXT NOT NULL DEFAULT 'ok'
    CHECK (triage_severity IN ('ok','info','warning','emergency')),
  CONSTRAINT sane_hr   CHECK (heart_rate_bpm IS NULL OR heart_rate_bpm BETWEEN 20 AND 250),
  CONSTRAINT sane_spo2 CHECK (spo2_pct IS NULL OR spo2_pct BETWEEN 50 AND 100),
  CONSTRAINT sane_bp   CHECK (systolic_mmhg IS NULL OR systolic_mmhg BETWEEN 60 AND 260),
  -- A credibility window, not a clinical one: it keeps every temperature a
  -- person can have and rejects only a mis-decoded frame (the raw field is a
  -- u16 — a corrupt 4000 becomes 400 °C). 20–45 repeats the wire bound in
  -- server.ts EXACTLY, because the telemetry path has no plausible() filter
  -- between the schema and this INSERT; a CHECK narrower than the wire would
  -- fail the write and make the client resend that reading for ever.
  CONSTRAINT sane_device_temp CHECK (device_temp_c IS NULL OR device_temp_c BETWEEN 20 AND 45),
  -- Idempotent ingest: the batcher re-sends a whole batch when a flush's RESPONSE
  -- is lost even though the row was stored, so the same reading can arrive twice.
  -- One reading per (user, device, instant) makes the resend a no-op instead of a
  -- duplicate history row and a second emergency push. NULLS NOT DISTINCT so that
  -- manual readings (device_id NULL) dedup too — otherwise every NULL counts as
  -- distinct and a resent hand-typed reading would slip through.
  CONSTRAINT phm_unique_reading UNIQUE NULLS NOT DISTINCT (user_id, device_id, recorded_at)
);
-- (Was a TimescaleDB hypertable partitioned on recorded_at. A plain table with the
-- same indexes is functionally identical; re-add create_hypertable in a migration
-- if write volume ever calls for it.)
CREATE INDEX idx_phm_user_time ON pregnancy_health_metrics (user_id, recorded_at DESC);
-- The admin emergency feed reads the newest emergencies across ALL users.
-- idx_phm_user_time leads with user_id and so cannot serve it: the feed fell
-- back to scanning every chunk of the largest table in the database. PARTIAL,
-- because emergencies are a tiny fraction of rows — the index stays small and
-- only pays maintenance cost on the rare row that qualifies.
CREATE INDEX idx_phm_emergency ON pregnancy_health_metrics (recorded_at DESC)
  WHERE triage_severity = 'emergency';

-- Emergency acknowledgements — a back-office overlay on the (derived) emergency
-- feed. The emergency itself stays a health-metric row on the safety path; this
-- only records that a staff member has seen and acted on it. The id is the
-- composite "<user_id>|<recorded_at ISO>" the API computes for each emergency.
CREATE TABLE emergency_acks (
  emergency_id    TEXT PRIMARY KEY,
  staff_id        TEXT NOT NULL,
  acknowledged_at TIMESTAMPTZ NOT NULL
);

-- (Was Timescale columnar compression + a `phm_hourly` continuous aggregate for
-- hourly chart rollups. Nothing in the app ever read the aggregate, so it was
-- dropped rather than ported; charts read the raw rows through idx_phm_user_time.)

-- Weekly manual tonometer calibration inputs (drives the PPG BP offset).
CREATE TABLE bp_calibration (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  measured_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  cuff_systolic     SMALLINT NOT NULL,
  cuff_diastolic    SMALLINT NOT NULL,
  ppg_systolic      SMALLINT NOT NULL,   -- band's raw reading at calibration time
  ppg_diastolic     SMALLINT NOT NULL,
  -- REAL, in the clear. These two are the columns the old privacy note at the
  -- top of this file named as ciphertext; they never were. Anyone reading the
  -- table reads her cuff-versus-band blood-pressure offsets.
  systolic_offset   REAL NOT NULL,       -- cuff - ppg, applied to future readings
  diastolic_offset  REAL NOT NULL
);
CREATE INDEX idx_bpcal_user_time ON bp_calibration (user_id, measured_at DESC);

-- -----------------------------------------------------------------------------
-- Geofences + child location history (PostGIS)
-- -----------------------------------------------------------------------------
CREATE TABLE geofences (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  guardian_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  child_id     UUID REFERENCES children(id) ON DELETE CASCADE,
  name         TEXT NOT NULL,                     -- "Home", "School"
  shape        TEXT NOT NULL CHECK (shape IN ('circle','polygon')),
  -- Circles: center_lat/lng + radius. Polygons: area_geojson (a GeoJSON Polygon,
  -- ring closed). Exactly one shape is populated. Plain columns rather than PostGIS
  -- geography: containment/distance is computed in TS (haversine), never in SQL.
  center_lat   DOUBLE PRECISION,
  center_lng   DOUBLE PRECISION,
  radius_m     REAL,
  area_geojson JSONB,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ( (shape = 'circle'  AND center_lat IS NOT NULL AND center_lng IS NOT NULL AND radius_m IS NOT NULL)
       OR (shape = 'polygon' AND area_geojson IS NOT NULL) )
);
-- Zones are read BY CHILD constantly: the map, the new-device restore, the
-- per-child zone count in the admin drawer, and the inside-any-zone check
-- documented at the foot of this file. Only the two shape indexes existed, and
-- neither can serve `WHERE child_id = $1` — every one of those reads was a
-- sequential scan over every family's zones.
CREATE INDEX idx_geofences_child ON geofences(child_id);

CREATE TABLE location_history (                    -- child location timeseries
  child_id     UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  observed_at  TIMESTAMPTZ NOT NULL,
  lat          DOUBLE PRECISION NOT NULL,
  lng          DOUBLE PRECISION NOT NULL,
  source       TEXT NOT NULL CHECK (source IN ('gps','wifi','lbs','ble')),
  accuracy_m   REAL
);
-- (Was a Timescale hypertable on observed_at; a plain table with the same index
-- is equivalent. Prune > 90d with a scheduled DELETE rather than a drop policy.)
CREATE INDEX idx_loc_child_time ON location_history (child_id, observed_at DESC);
-- Privacy retention: location trails older than 90 days are deleted, which is
-- what the app's privacy policy promises every user.
--
-- This was a Timescale retention policy. When that went, the DELETE was left
-- here as a COMMENT with a note to run it "as a scheduled job (pg_cron, or an
-- app cron)" — and neither was ever set up, so every child's trail accumulated
-- from the first fix. A note is not a job.
--
-- It now runs in the backend: src/privacy/retention.ts, started by buildServer
-- and swept every six hours. Nothing needs to be scheduled by hand. If you ever
-- want to run it manually, this is the same statement:
--   DELETE FROM location_history WHERE observed_at < now() - INTERVAL '90 days';

-- Debounced geofence crossing log (written only on real state transitions).
CREATE TABLE geofence_events (
  id           UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  child_id     UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  geofence_id  UUID NOT NULL REFERENCES geofences(id) ON DELETE CASCADE,
  transition   TEXT NOT NULL CHECK (transition IN ('enter','exit')),
  source       TEXT NOT NULL,
  occurred_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_gfevents_child_time ON geofence_events (child_id, occurred_at DESC);
-- Privacy retention: 90 days, the same window as the trail that produced them.
-- A crossing says a named child left a named place at a named minute, which is
-- a coarse movement history under another name; keeping it longer than the
-- route it came from was never a decision, only an omission.
-- Swept by src/privacy/retention.ts. Manually, it is:
--   DELETE FROM geofence_events WHERE occurred_at < now() - INTERVAL '90 days';

-- Staff audit log (every back-office access to PHI/location is recorded).
CREATE TABLE audit_log (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  staff_id    TEXT NOT NULL,
  action      TEXT NOT NULL,
  target      TEXT,
  -- Why the record was opened. Nullable: most actions (listing orders, editing
  -- a lesson) explain themselves, and rows written before migration 029 have
  -- no reason and never will. The routes that serve health and location refuse
  -- to answer without one, so those rows are never blank.
  reason      TEXT,
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_at ON audit_log (at DESC);
-- Frame 22 counts protected reads over a window of up to a year:
-- WHERE action = ANY(...) AND at >= ... ORDER BY at DESC. See migration 050.
CREATE INDEX idx_audit_action_at ON audit_log (action, at DESC);
-- Retention: 3 years. The panel printed this period for months while nothing
-- deleted a row (b8aac0c took the number off the screen rather than leave the
-- fiction beside the real 90-day route sweep). The owner has since set it, so
-- the claim is true: src/privacy/retention.ts sweeps this table on the same
-- constant the screen prints. Manually:
--   DELETE FROM audit_log WHERE at < now() - INTERVAL '1095 days';

-- Nightly sleep summaries from the band (one row per wake-day per user).
-- Baby cry-analysis results (parent-recorded). Newest-first history, pushed so
-- it survives a reinstall and restores on a new device.
CREATE TABLE cry_results (
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  at          TIMESTAMPTZ NOT NULL,
  reason      TEXT NOT NULL,          -- wire code, e.g. hungry | tired | discomfort
  confidence  REAL NOT NULL,          -- 0..1
  -- Was the answer right? Migration 046. The mother's own verdict, and the only
  -- ground truth this product will ever have: nothing here reads a clinic and
  -- the clip itself is never stored. NULL is «не спрашивали», a third state —
  -- never «wrong» — and every accuracy figure is computed over rated rows only.
  verdict       TEXT,
  actual_reason TEXT,
  PRIMARY KEY (user_id, at),
  CONSTRAINT cry_results_verdict_check
    CHECK (verdict IS NULL OR verdict IN ('correct','wrong'))
);

-- The one number the cry detector has that a release used to be needed to
-- change: below it the app names NO reason and says «не уверены» instead
-- (migration 046). Single-row, like vaccination_settings — one detector, one
-- threshold. Deliberately NOT seeded: an absent row means the shipped default
-- in src/cry/settings.ts, which is the truthful state before anybody decided.
CREATE TABLE cry_settings (
  id             BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
  min_confidence REAL NOT NULL CHECK (min_confidence >= 0 AND min_confidence <= 0.95),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by     TEXT
);

CREATE TABLE sleep_nights (
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  night       DATE NOT NULL,
  deep_min    INTEGER NOT NULL DEFAULT 0,
  rem_min     INTEGER NOT NULL DEFAULT 0,
  light_min   INTEGER NOT NULL DEFAULT 0,
  awake_min   INTEGER NOT NULL DEFAULT 0,
  -- Provenance. NULL source = a device-measured ('band') night, the historical
  -- default. A hand-entered night is 'manual' and carries the typed asleep total
  -- in manual_asleep_min, which the app can't infer a stage split for.
  source            TEXT,
  manual_asleep_min INTEGER,
  PRIMARY KEY (user_id, night)
);

-- What the watch measured beyond the four triage vitals, one row per wearer's
-- day per device: what she did (steps / distance / calories), how her body was
-- between measurements (stress, breathing rate, MET), and the state of the
-- device itself (battery, charging, on-wrist).
--
-- None of it is triaged — it cannot raise an emergency — which is exactly why
-- it does not belong in pregnancy_health_metrics. It had no home at all before:
-- the app rendered it on one panel and it existed nowhere else, so a clinician
-- reading her chart saw the vitals and nothing about how she had been living.
--
-- Upserted rather than appended because steps/kcal/meters are the watch's own
-- running daily totals; a poll every thirty seconds would otherwise write 2 880
-- rows a day that each restate the same day a little later. `day` is the
-- WEARER's local date: her watch rolls its totals over at her midnight, and
-- filing an Almaty evening under the next UTC day would misreport every day.
CREATE TABLE IF NOT EXISTS wearable_days (
  user_id         UUID NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  day             DATE NOT NULL,
  recorded_at     TIMESTAMPTZ NOT NULL,   -- the snapshot this row last folded in
  steps           INTEGER NOT NULL DEFAULT 0,
  kcal            INTEGER NOT NULL DEFAULT 0,
  meters          INTEGER NOT NULL DEFAULT 0,
  sleep_min       INTEGER NOT NULL DEFAULT 0,
  deep_sleep_min  INTEGER NOT NULL DEFAULT 0,
  light_sleep_min INTEGER NOT NULL DEFAULT 0,
  -- NULL = the watch has not measured this. NOT 0: a stress of 0 read back is a
  -- measurement of perfect calm, which is the opposite of "no reading".
  stress          SMALLINT,
  breath_rate     SMALLINT,
  met             SMALLINT,
  battery_pct     SMALLINT,
  charging        BOOLEAN NOT NULL DEFAULT FALSE,
  worn            BOOLEAN NOT NULL DEFAULT FALSE,
  -- The vitals a DAY of the watch's own stored history carries (migration 042).
  -- Averages plus the extremes a mean cannot express: a day averaging 78 bpm
  -- that touched 165 is not the day that never left 80, and a clinician needs
  -- to be able to tell them apart. NULL = not measured, same rule as above.
  hr_avg             SMALLINT,
  hr_min             SMALLINT,
  hr_max             SMALLINT,
  spo2_avg           SMALLINT,
  spo2_min           SMALLINT,
  systolic_avg       SMALLINT,
  diastolic_avg      SMALLINT,
  temp_avg_tenths    SMALLINT,  -- 365 = 36.5 °C, the device's own unit
  blood_sugar_tenths SMALLINT,  -- tenths of a mmol/L; an estimate, not a test
  CONSTRAINT sane_stress  CHECK (stress      IS NULL OR stress      BETWEEN 0 AND 100),
  CONSTRAINT sane_breath  CHECK (breath_rate IS NULL OR breath_rate BETWEEN 1 AND 80),
  CONSTRAINT sane_battery CHECK (battery_pct IS NULL OR battery_pct BETWEEN 0 AND 100),
  -- A byte read at the wrong offset lands outside human physiology; refuse it
  -- at the door rather than draw it on a chart as a fact.
  CONSTRAINT sane_hr CHECK (
    (hr_avg IS NULL OR hr_avg BETWEEN 20 AND 250) AND
    (hr_min IS NULL OR hr_min BETWEEN 20 AND 250) AND
    (hr_max IS NULL OR hr_max BETWEEN 20 AND 250)),
  CONSTRAINT sane_spo2 CHECK (
    (spo2_avg IS NULL OR spo2_avg BETWEEN 50 AND 100) AND
    (spo2_min IS NULL OR spo2_min BETWEEN 50 AND 100)),
  CONSTRAINT sane_bp CHECK (
    (systolic_avg  IS NULL OR systolic_avg  BETWEEN 50 AND 260) AND
    (diastolic_avg IS NULL OR diastolic_avg BETWEEN 30 AND 200)),
  CONSTRAINT sane_temp_day CHECK (
    temp_avg_tenths IS NULL OR temp_avg_tenths BETWEEN 300 AND 450),
  CONSTRAINT sane_sugar_day CHECK (
    blood_sugar_tenths IS NULL OR blood_sugar_tenths BETWEEN 10 AND 300),
  PRIMARY KEY (user_id, device_id, day)
);
CREATE INDEX IF NOT EXISTS idx_wearable_days_user ON wearable_days (user_id, day DESC);

-- Newborn care log — feeds, nappy changes, sleeps. One row per event, per
-- child, keyed by (child, instant, kind). Gives a clinician the feeding /
-- hydration pattern of the first weeks.
CREATE TABLE newborn_events (
  child_id     UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  at           TIMESTAMPTZ NOT NULL,
  kind         TEXT NOT NULL CHECK (kind IN ('feed','diaper','sleep')),
  detail       TEXT,
  duration_min INTEGER,
  PRIMARY KEY (child_id, at, kind)
);

-- Child vaccination record (parent-marked). One row per (child, vaccine key)
-- that the parent has ticked done — presence IS "done", absence is "not yet".
-- The clinician reads which shots are recorded; a child with none is a flag.
CREATE TABLE child_vaccines (
  child_id     UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  vaccine_key  TEXT NOT NULL,   -- app's "<id>/<dose>", e.g. "bcg/1"
  PRIMARY KEY (child_id, vaccine_key)
);

-- Child growth measurements (weight / height), one row per child per day — the
-- pediatric growth curve a clinician reads for faltering. Mirrors the mother's
-- weight_entries; keyed by (child, day) so a same-day correction replaces.
CREATE TABLE child_growth (
  child_id   UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  at         DATE NOT NULL,
  weight_kg  NUMERIC(5,2),   -- typo-filter bounds enforced app + route side
  height_cm  NUMERIC(5,1),
  PRIMARY KEY (child_id, at),
  CHECK (weight_kg IS NOT NULL OR height_cm IS NOT NULL)
);

-- Completed fetal-movement (kick) counting sessions. One row per session,
-- keyed by when it ended. Reduced movement is a safety signal, so a clinician
-- seeing the trend matters.
CREATE TABLE kick_sessions (
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ended_at     TIMESTAMPTZ NOT NULL,
  count        INTEGER NOT NULL,
  duration_sec INTEGER NOT NULL,
  PRIMARY KEY (user_id, ended_at)
);

-- Completed labour-timing (contraction) sessions — the 5-1-1 signal.
CREATE TABLE contraction_sessions (
  user_id          UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  ended_at         TIMESTAMPTZ NOT NULL,
  count            INTEGER NOT NULL,
  avg_duration_sec INTEGER NOT NULL,
  avg_interval_sec INTEGER NOT NULL,
  PRIMARY KEY (user_id, ended_at)
);

-- A child's emergency medical-ID (what a parent hands a paramedic). One row per
-- child; all free text, all optional.
CREATE TABLE child_emergency (
  child_id      UUID PRIMARY KEY REFERENCES children(id) ON DELETE CASCADE,
  blood_type    TEXT NOT NULL DEFAULT '',
  allergies     TEXT NOT NULL DEFAULT '',
  conditions    TEXT NOT NULL DEFAULT '',
  medications   TEXT NOT NULL DEFAULT '',
  doctor_name   TEXT NOT NULL DEFAULT '',
  doctor_phone  TEXT NOT NULL DEFAULT '',
  contact_name  TEXT NOT NULL DEFAULT '',
  contact_phone TEXT NOT NULL DEFAULT '',
  notes         TEXT NOT NULL DEFAULT ''
);

-- Maternal weight log (one row per day per user).
CREATE TABLE weight_entries (
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  log_date    DATE NOT NULL,
  kg          NUMERIC(5,2) NOT NULL,
  PRIMARY KEY (user_id, log_date)
);

-- Women's-health day logs (mood / symptoms / fetal kicks / menstrual flow).
CREATE TABLE cycle_day_logs (
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  log_date    DATE NOT NULL,
  mood        TEXT,                              -- happy | calm | anxious | tired | sad
  symptoms    TEXT[] NOT NULL DEFAULT '{}',      -- allGood | cramps | spotting | ...
  kicks       INTEGER NOT NULL DEFAULT 0,
  flow        TEXT,                              -- light | medium | heavy | NULL
  note        TEXT,                              -- free-text note the user typed for the day
  PRIMARY KEY (user_id, log_date)
);

-- Postpartum screening results (EPDS) — the SCORE, the BAND and the DATE.
--
-- There is no column for the ten answers and there must never be one: item 10
-- asks about thoughts of self-harm, and that answer is not something a back
-- office needs in order to do anything. See db/migrations/049_epds.sql for the
-- full reasoning, and app/lib/domain/epds.dart for the scoring the numbers
-- come from. Not a diagnosis; nothing downstream may present it as one.
--
-- Per-person only: read through the audited /admin/users/:id/wellness route and
-- never listed, filtered or segmented by (there is no index by score or band,
-- on purpose).
CREATE TABLE epds_results (
  user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  id        UUID NOT NULL,                    -- client-supplied, so a re-push upserts
  taken_at  TIMESTAMPTZ NOT NULL,
  score     INTEGER NOT NULL CHECK (score BETWEEN 0 AND 30),
  band      TEXT NOT NULL CHECK (band IN ('low', 'possible', 'high')),
  PRIMARY KEY (user_id, id)
);

-- Child safety alerts (geofence enter/exit history).
CREATE TABLE safety_alerts (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  child_id    UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  -- The five the app's AlertKind sends. It was ('entered','left') while the
  -- app already sent checkIn/sos/lowBattery, so those were refused on insert
  -- while an index and two counters read rows the table would not accept.
  -- See migration 030.
  kind        TEXT NOT NULL CHECK (kind IN ('entered','left','checkIn','sos','lowBattery')),
  zone_name   TEXT NOT NULL,
  at          TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Frame 48 «Чем закончилось» — what the parent marked an SOS as, afterwards.
  -- NULL means nobody has closed it yet, which is a different thing from
  -- 'unknown' («не удалось выяснить»): a default would erase that difference.
  -- See migration 032.
  outcome     TEXT CHECK (outcome IS NULL OR outcome IN ('false_press','scared','needed_help','unknown'))
);
CREATE INDEX idx_safety_alerts_user_at ON safety_alerts (user_id, at DESC);
-- The outcome write is keyed on (user, child, at): the alert feed carries no id,
-- so that triple is all the client can send. Partial — only an SOS is closed.
CREATE INDEX idx_safety_alerts_sos_at ON safety_alerts (user_id, child_id, at) WHERE kind = 'sos';
-- The admin alert feed and the 7-day / SOS dashboard counters read across ALL
-- users; the index above leads with user_id and cannot serve them.
CREATE INDEX idx_safety_alerts_at  ON safety_alerts (at DESC);
CREATE INDEX idx_safety_alerts_sos ON safety_alerts (at DESC) WHERE kind = 'sos';
-- The feed and the day's history are read per child and per day; the indexes
-- above lead with user_id or with `at` alone. Migration 030 created this one on
-- every live server and it was never copied back here, so a database built from
-- this file was missing an index every migrated one had.
CREATE INDEX idx_safety_alerts_child_at ON safety_alerts (child_id, at DESC);
-- Privacy retention: 12 months, SOS rows included. Long enough that a parent can
-- look back over a school year, short enough that this is not a permanent
-- movement history of a child — what is kept is the record of the event.
-- Swept by src/privacy/retention.ts. Manually:
--   DELETE FROM safety_alerts WHERE at < now() - INTERVAL '365 days';

-- Push tokens for FCM/APNS delivery.
CREATE TABLE push_tokens (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  platform    TEXT NOT NULL CHECK (platform IN ('ios','android')),
  token       TEXT NOT NULL,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (user_id, token)
);
-- FCM/APNS reports a dead token and the push layer deletes it BY TOKEN alone.
-- UNIQUE(user_id, token) leads with user_id, so that delete scanned the whole
-- table — on the push path, for every unregistered device.
CREATE INDEX idx_push_tokens_token ON push_tokens(token);

-- =============================================================================
-- Example geospatial queries (Geofencing Specialist)
-- =============================================================================
-- Is the child currently inside any of their geofences? (single round-trip)
--   SELECT g.id, g.name, g.shape
--   FROM geofences g
--   WHERE g.child_id = $1
--     AND (
--       (g.shape = 'circle'  AND ST_DWithin(g.center, ST_MakePoint($3,$2)::geography, g.radius_m))
--       OR (g.shape = 'polygon' AND ST_Covers(g.area, ST_MakePoint($3,$2)::geography))
--     );
-- ($2 = lat, $3 = lng). ST_DWithin on geography uses meters and hits the GIST index.

-- ---------------------------------------------------------------------------
-- Timeline content (the CMS behind /admin/content)
--
-- One row per stage: 'w1'..'w40' for pregnancy weeks, 'm0'..'m60' for child
-- months. The items are stored as JSONB because they are authored content
-- rather than something queried by field — the app reads a whole stage at
-- once, and the shape evolves with the catalogue rather than the schema.
CREATE TABLE IF NOT EXISTS timeline_content (
  stage_key   text PRIMARY KEY,
  payload     jsonb NOT NULL,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

-- ---- Shop: device store (see migrations/009_shop.sql for seed data) ---------
-- Products (watch/tracker), per-colour variants with stock managed from the admin
-- panel, and cash-on-delivery orders carrying a delivery address. An order
-- decrements the variant's stock atomically (see pgRepository.placeShopOrder).
-- Categories as a table rather than free text on the product (migration 033):
-- frame 08b edits them as their own list with an order the storefront follows,
-- and free text gives «Часы», «часы» and «Чacы» inside a month. Declared before
-- shop_products because that table references it.
CREATE TABLE IF NOT EXISTS shop_categories (
  id       TEXT PRIMARY KEY,
  name_ru  TEXT NOT NULL,
  name_kk  TEXT,
  sort     INTEGER NOT NULL DEFAULT 0
);
INSERT INTO shop_categories (id, name_ru, name_kk, sort) VALUES
  ('watch',   'Смарт-часы',      'Смарт-сағат',     10),
  ('tracker', 'Детские трекеры', 'Балалар трекері', 20),
  ('bundle',  'Комплекты',       'Жинақтар',        30),
  ('other',   'Прочее',          'Басқа',           90)
ON CONFLICT (id) DO NOTHING;

CREATE TABLE IF NOT EXISTS shop_products (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  price_minor INTEGER NOT NULL CHECK (price_minor >= 0),
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  sort        INTEGER NOT NULL DEFAULT 0,
  -- Inventory (migration 021). What goes on a box and an invoice; what we pay
  -- for it; whether it is stocked in its own right or assembled from others.
  sku         TEXT,
  cost_minor  INTEGER CHECK (cost_minor IS NULL OR cost_minor >= 0),
  kind        TEXT NOT NULL DEFAULT 'simple' CHECK (kind IN ('simple','bundle')),
  low_stock_threshold INTEGER NOT NULL DEFAULT 3 CHECK (low_stock_threshold >= 0),
  -- What fulfilling an order for this product unlocks in the app (migration
  -- 025), e.g. 'mama_course' on the комплект. On the product rather than
  -- hardcoded against the id: a second bundle carrying a second course should
  -- be a row, not a branch in the code.
  grants_feature TEXT,
  -- Catalogue (migration 033), for frames 08 / 08a. All nullable: a product
  -- that predates this is uncategorised rather than mis-categorised, which the
  -- panel shows as «не указан» so the work left is visible.
  category    TEXT REFERENCES shop_categories(id) ON DELETE SET NULL,
  -- Which stage of motherhood this is FOR. shop_stage.dart derived this from
  -- her pregnancy flag and her children's ages because the column did not
  -- exist; with it, «Для вашего этапа» is data an operator owns.
  stage       TEXT CHECK (stage IS NULL OR stage IN ('planning','pregnancy','newborn','infant','toddler','any')),
  name_kk        TEXT,
  description_ru TEXT,
  description_kk TEXT,
  -- Персонализация: the child age band this suits, in months. Independent —
  -- «от 0» and «до 36» are each meaningful alone.
  age_min_months INTEGER CHECK (age_min_months IS NULL OR (age_min_months >= 0 AND age_min_months <= 216)),
  age_max_months INTEGER CHECK (age_max_months IS NULL OR (age_max_months >= 0 AND age_max_months <= 216)),
  CONSTRAINT shop_products_age_band_check
    CHECK (age_min_months IS NULL OR age_max_months IS NULL OR age_min_months <= age_max_months),
  photo_url       TEXT,
  seo_slug        TEXT,
  seo_title       TEXT,
  seo_description TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS shop_products_sku_unique
  ON shop_products (sku) WHERE sku IS NOT NULL;
-- Two products answering the same URL is a bug that only shows up in production.
CREATE UNIQUE INDEX IF NOT EXISTS shop_products_seo_slug_unique
  ON shop_products (seo_slug) WHERE seo_slug IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_shop_products_category ON shop_products (category);
CREATE INDEX IF NOT EXISTS idx_shop_products_stage    ON shop_products (stage);
CREATE TABLE IF NOT EXISTS shop_variants (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id TEXT NOT NULL REFERENCES shop_products(id) ON DELETE CASCADE,
  color      TEXT NOT NULL,
  color_hex  TEXT NOT NULL,
  stock      INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
  sort       INTEGER NOT NULL DEFAULT 0,
  UNIQUE (product_id, color)
);
CREATE TABLE IF NOT EXISTS shop_orders (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_name TEXT NOT NULL,
  phone         TEXT NOT NULL,
  city          TEXT NOT NULL,
  address       TEXT NOT NULL,
  note          TEXT,
  total_minor   INTEGER NOT NULL CHECK (total_minor >= 0),
  discount_minor INTEGER NOT NULL DEFAULT 0 CHECK (discount_minor >= 0),
  status        TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new','confirmed','shipped','delivered','cancelled')),
  -- Digits only, 77xxxxxxxxx — how an order is matched to an app account.
  phone_normalized TEXT,
  -- Sold as this set (migration 025). The line items are still the PARTS —
  -- that is what leaves the warehouse — and this says which bundle priced them
  -- and whose entitlement the sale carries.
  bundle_id     TEXT REFERENCES shop_products(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_shop_orders_created ON shop_orders (created_at DESC);
CREATE INDEX IF NOT EXISTS shop_orders_bundle ON shop_orders (bundle_id);
-- Entitlement is granted by matching a fulfilled order to a phone number, so
-- this lookup runs on every fulfilment. Added by migration 023 and missing
-- here until 2026-08-19, which meant every migrated server had it and every
-- fresh install silently did not.
CREATE INDEX IF NOT EXISTS shop_orders_phone_normalized
  ON shop_orders (phone_normalized);
CREATE TABLE IF NOT EXISTS shop_order_items (
  order_id         UUID NOT NULL REFERENCES shop_orders(id) ON DELETE CASCADE,
  variant_id       UUID NOT NULL REFERENCES shop_variants(id),
  product_name     TEXT NOT NULL,
  color            TEXT NOT NULL,
  qty              INTEGER NOT NULL CHECK (qty > 0),
  unit_price_minor INTEGER NOT NULL CHECK (unit_price_minor >= 0)
);
CREATE INDEX IF NOT EXISTS idx_shop_items_order ON shop_order_items (order_id);

-- The order's own history (migration 039). One row per status transition,
-- written inside the statement that moves it. Frame 03 draws the timeline from
-- here; without it an order knew only when it was created and where it is now,
-- and «кто отменил и во сколько» had no answer — audit_log records that the
-- status changed, never to what.
--
-- Never updated, never deleted: a wrong step is corrected by taking the next
-- one, like shop_stock_moves.
CREATE TABLE IF NOT EXISTS shop_order_events (
  id          BIGSERIAL PRIMARY KEY,
  order_id    UUID NOT NULL REFERENCES shop_orders(id) ON DELETE CASCADE,
  from_status TEXT,
  to_status   TEXT NOT NULL CHECK (to_status IN ('new','confirmed','shipped','delivered','cancelled')),
  -- TEXT, matching audit_log.staff_id: an entry written by an account since
  -- removed must stay readable, so no foreign key.
  staff_id    TEXT,
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS shop_order_events_order ON shop_order_events (order_id, at);

-- A bundle holds no stock of its own: it is worth as many sets as its scarcest
-- part allows. Storing a count here would drift from the parts within a week.
CREATE TABLE IF NOT EXISTS shop_bundle_items (
  bundle_id TEXT NOT NULL REFERENCES shop_products(id) ON DELETE CASCADE,
  part_id   TEXT NOT NULL REFERENCES shop_products(id) ON DELETE RESTRICT,
  qty       INTEGER NOT NULL DEFAULT 1 CHECK (qty > 0),
  PRIMARY KEY (bundle_id, part_id),
  CHECK (bundle_id <> part_id)
);

-- The stock ledger. shop_variants.stock is the running total; this says WHY it
-- changed. Rows are never updated or deleted — a miscount is corrected by
-- another row, so what somebody believed survives beside what was true.
CREATE TABLE IF NOT EXISTS shop_stock_moves (
  id         BIGSERIAL PRIMARY KEY,
  variant_id UUID NOT NULL REFERENCES shop_variants(id) ON DELETE CASCADE,
  delta      INTEGER NOT NULL CHECK (delta <> 0),
  reason     TEXT NOT NULL CHECK (reason IN ('receipt','sale','return','writeoff','correction')),
  note       TEXT,
  staff_id   TEXT,
  order_id   UUID REFERENCES shop_orders(id) ON DELETE SET NULL,
  at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS shop_stock_moves_variant_at ON shop_stock_moves (variant_id, at DESC);
CREATE INDEX IF NOT EXISTS shop_stock_moves_at ON shop_stock_moves (at DESC);
CREATE INDEX IF NOT EXISTS shop_stock_moves_order ON shop_stock_moves (order_id);

-- Daily audio for the pregnancy + child-development calendars (see migration 012).
CREATE TABLE IF NOT EXISTS daily_audio (
  track      TEXT NOT NULL CHECK (track IN ('pregnancy','child')),
  day        INTEGER NOT NULL CHECK (day >= 1 AND day <= 400),
  locale     TEXT NOT NULL DEFAULT 'ru' CHECK (locale IN ('ru','kk')),
  title      TEXT,
  mime       TEXT NOT NULL,
  bytes      BYTEA NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (track, day, locale)
);

-- A photo an operator UPLOADS, rather than a link she is asked to find.
-- See migration 044 for why the bytes live here and why `color` is in the key.
CREATE TABLE IF NOT EXISTS shop_product_photos (
  product_id  TEXT NOT NULL REFERENCES shop_products(id) ON DELETE CASCADE,
  color       TEXT NOT NULL DEFAULT '',
  mime        TEXT NOT NULL CHECK (mime IN ('image/jpeg','image/png','image/webp')),
  bytes       BYTEA NOT NULL,
  CONSTRAINT photo_not_empty CHECK (octet_length(bytes) > 0),
  CONSTRAINT photo_not_huge  CHECK (octet_length(bytes) <= 3 * 1024 * 1024),
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- The FOREIGN KEY to staff_accounts is added further down, once that table
  -- exists. schema.sql runs top to bottom and declares the shop before the back
  -- office; migration 044 could write the reference inline because on a LIVE
  -- server migration 019 had created staff_accounts long before. Written inline
  -- HERE it made schema.sql abort with «relation "staff_accounts" does not
  -- exist», so no fresh database could be built at all. See the ALTER under
  -- staff_accounts.
  uploaded_by UUID,
  PRIMARY KEY (product_id, color)
);
CREATE INDEX IF NOT EXISTS idx_product_photos_product ON shop_product_photos(product_id);

-- Store settings (WhatsApp number, Kaspi link, …) edited in the admin panel.
CREATE TABLE IF NOT EXISTS shop_settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Callback requests from the landing page — a name and a phone number, not an
-- order (no address, no variant, no stock held). See migration 017.
CREATE TABLE IF NOT EXISTS shop_leads (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_name TEXT NOT NULL,
  phone         TEXT NOT NULL,
  package       TEXT NOT NULL DEFAULT '',
  locale        TEXT NOT NULL DEFAULT 'ru' CHECK (locale IN ('ru','kz')),
  status        TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new','called','ordered','dropped')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_shop_leads_created ON shop_leads (created_at DESC);
-- Retention: 12 months. A name and a phone number typed into the landing form.
-- If nobody has acted on it in a year, holding it is not a business need.
-- Swept by src/privacy/retention.ts; the index above serves the DELETE.
--   DELETE FROM shop_leads WHERE created_at < now() - INTERVAL '365 days';

-- Staff accounts for the back office: phone number + password, the same two
-- fields the app asks a mother for. See migration 019 — this block and that one
-- must stay identical, because schema.sql builds a fresh database and the
-- migration upgrades an existing one.
CREATE TABLE IF NOT EXISTS staff_accounts (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone         TEXT NOT NULL UNIQUE,          -- digits only, e.g. 77073452244
  password_hash TEXT NOT NULL,                 -- scrypt, salted
  role          TEXT NOT NULL DEFAULT 'admin', -- any of STAFF_ROLES in src/auth/capabilities.ts
  display_name  TEXT NOT NULL DEFAULT '',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at TIMESTAMPTZ,
  disabled_at   TIMESTAMPTZ
);

-- shop_product_photos.uploaded_by points here, and could not say so where the
-- column is declared: that block runs some forty tables earlier. The name is
-- the one Postgres derives from an inline REFERENCES, so a server migrated
-- through 044 and a database built from this file end up with the SAME
-- constraint under the SAME name. IF NOT EXISTS is not available for ADD
-- CONSTRAINT; schema.sql is applied exactly once per database (apply.mjs
-- records it in schema_migrations), inside a transaction, so this runs once.
ALTER TABLE shop_product_photos
  ADD CONSTRAINT shop_product_photos_uploaded_by_fkey
  FOREIGN KEY (uploaded_by) REFERENCES staff_accounts(id) ON DELETE SET NULL;

CREATE TABLE IF NOT EXISTS staff_sessions (
  token_hash  TEXT PRIMARY KEY,               -- sha256 of the cookie value
  staff_id    UUID NOT NULL REFERENCES staff_accounts(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL,
  user_agent  TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS staff_sessions_expiry ON staff_sessions (expires_at);

CREATE TABLE IF NOT EXISTS staff_login_attempts (
  id         BIGSERIAL PRIMARY KEY,
  phone      TEXT NOT NULL,
  at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  succeeded  BOOLEAN NOT NULL DEFAULT false
);
CREATE INDEX IF NOT EXISTS staff_login_attempts_phone_at
  ON staff_login_attempts (phone, at DESC);
-- Retention: 90 days, the same as user_login_attempts below — one decision over
-- two tables. Rate-limiting reads minutes and intrusion review reads weeks;
-- neither reads years, and phone + timestamp is personal data.
--   DELETE FROM staff_login_attempts WHERE at < now() - INTERVAL '90 days';

-- ---------------------------------------------------------------------------
-- App sign-in with a phone number (migration 020).
--
-- The number IS the identity: `users.email` is nullable and the unique index
-- below is what stops two accounts sharing a number. No SMS — a number is
-- claimed, not verified — so this is also the only place a code check would
-- later go.
-- ---------------------------------------------------------------------------
CREATE UNIQUE INDEX IF NOT EXISTS users_phone_e164_unique
  ON users (phone_e164) WHERE phone_e164 IS NOT NULL;

CREATE TABLE IF NOT EXISTS user_sessions (
  token_hash  TEXT PRIMARY KEY,               -- sha256 of the bearer token
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL,           -- 90 days; a phone is personal
  user_agent  TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS user_sessions_expiry ON user_sessions (expires_at);
CREATE INDEX IF NOT EXISTS user_sessions_user ON user_sessions (user_id);

CREATE TABLE IF NOT EXISTS user_login_attempts (
  id     BIGSERIAL PRIMARY KEY,
  phone  TEXT NOT NULL,
  at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS user_login_attempts_phone_at
  ON user_login_attempts (phone, at DESC);
-- Retention: 90 days. See staff_login_attempts above; swept together, by
-- src/privacy/retention.ts.
--   DELETE FROM user_login_attempts WHERE at < now() - INTERVAL '90 days';

-- The one-time sign-in code (migration 027).
--
-- Signing in used to be `POST /auth/phone` with a number and nothing else: the
-- number WAS the credential. A customer's number is on every parcel, every
-- WhatsApp order and every delivery manifest, so anyone holding one could read
-- her pregnancy, her children and their live locations.
--
-- Hashed, like a password: this row is readable by anything that can read the
-- database, and a six-digit code in plaintext beside a phone number is a key.
CREATE TABLE IF NOT EXISTS phone_codes (
  phone       TEXT PRIMARY KEY,        -- one live code per number
  code_hash   TEXT NOT NULL,
  expires_at  TIMESTAMPTZ NOT NULL,
  attempts    INTEGER NOT NULL DEFAULT 0,  -- five wrong guesses and it is dead
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS phone_codes_expiry ON phone_codes (expires_at);
-- Retention: 30 days, on CREATED_AT and not on expires_at. A used code is
-- deleted the moment it is used; an ABANDONED one — a number that asked for a
-- code and never came back — lived here for ever, a phone number beside a hash.
-- This index implied a sweep that nobody had written. Now written, in
-- src/privacy/retention.ts. A live code expires in minutes, so thirty days can
-- never take one that still works.
--   DELETE FROM phone_codes WHERE created_at < now() - INTERVAL '30 days';

-- ---------------------------------------------------------------------------
-- What a purchase unlocks in the app (migration 023).
--
-- The combo is two devices plus the Ма!Ма! course, so buying it is what opens
-- the lessons. An order and an account are joined by the PHONE — the order
-- captures it at checkout, the app signs in with it — because a customer does
-- not know she has an account id, and there is nothing for her to do.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_entitlements (
  phone      TEXT NOT NULL,          -- normalised: 77xxxxxxxxx
  feature    TEXT NOT NULL,          -- 'mama_course'
  order_id   UUID REFERENCES shop_orders(id) ON DELETE SET NULL,
  granted_by TEXT,                   -- staff id, or null when an order granted it
  note       TEXT,
  at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (phone, feature)
);
CREATE INDEX IF NOT EXISTS user_entitlements_feature ON user_entitlements (feature);

-- ---------------------------------------------------------------------------
-- The Ма!Ма! course (migration 024). A standalone ordered series, not timeline
-- content: it does not move with a due date, so it is not filed under a week.
-- Videos are on YouTube and play through YouTube's own embedded IFrame player,
-- which is what their terms require: their player, their branding.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS course_lessons (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  course      TEXT NOT NULL DEFAULT 'mama',
  title_ru    TEXT NOT NULL,
  title_kk    TEXT,                     -- optional: Russian first, app falls back
  youtube_url TEXT NOT NULL,
  summary_ru  TEXT,
  summary_kk  TEXT,
  sort        INTEGER NOT NULL DEFAULT 0,   -- sparse, so one can be inserted between
  published   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS course_lessons_order ON course_lessons (course, sort, created_at);

-- How far she got (migration 026). Keyed by PHONE, like user_entitlements and
-- for the same reason: the account and the purchase are joined by the number,
-- so a reinstall or a new phone finds her place again.
CREATE TABLE IF NOT EXISTS course_progress (
  phone            TEXT NOT NULL,
  lesson_id        UUID NOT NULL REFERENCES course_lessons(id) ON DELETE CASCADE,
  position_seconds INTEGER NOT NULL DEFAULT 0,
  duration_seconds INTEGER,                    -- YouTube's; unknown until a player loads
  completed        BOOLEAN NOT NULL DEFAULT FALSE,  -- set once, never unset
  first_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (phone, lesson_id)
);
CREATE INDEX IF NOT EXISTS course_progress_recent ON course_progress (updated_at DESC);

-- -------------------------------------------------------------------------
-- Which devices are ours (migration 028).
-- -------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS device_registry (
  -- Normalised: uppercase, separators stripped. A MAC is written six different
  -- ways depending on who printed the label, and a registry that misses a unit
  -- because it was typed with dashes is worse than no registry — it refuses a
  -- real customer.
  serial       TEXT PRIMARY KEY,

  -- stock   — ours, received, not yet paired
  -- sold    — paired to an account (activated_by_phone says which)
  -- blocked — stolen, returned, or replaced under warranty. Never pairs again.
  status       TEXT NOT NULL DEFAULT 'stock'
               CHECK (status IN ('stock', 'sold', 'blocked')),

  -- What kind, so the panel can tell a watch from a tag without pairing it.
  kind         TEXT CHECK (kind IN ('band', 'tag')),

  -- The code printed on the box, for units whose serial nobody captured and
  -- for warranty replacements. The FALLBACK path, deliberately: a code can be
  -- photographed and posted in a group chat, a MAC cannot be guessed.
  --
  -- Stored in plain text, unlike a password: it is printed on the outside of a
  -- box that customers hold, so it is not a secret to us — and support has to
  -- be able to read it back to somebody on the phone. What protects it is being
  -- single-use and bound to the first account that redeems it.
  activation_code TEXT,

  -- Provenance, for the warranty conversation nobody can currently have.
  order_id     UUID,
  received_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  activated_by_phone TEXT,
  activated_at TIMESTAMPTZ,
  note         TEXT,
  added_by     TEXT
);

CREATE INDEX IF NOT EXISTS device_registry_status ON device_registry (status, received_at DESC);
CREATE INDEX IF NOT EXISTS device_registry_phone ON device_registry (activated_by_phone)
  WHERE activated_by_phone IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS device_registry_code ON device_registry (activation_code)
  WHERE activation_code IS NOT NULL;

-- ---------------------------------------------------------------------------
-- Family access (screen 40 · «Семейный доступ»). See migration 031.
--
-- A father, a grandmother and an aunt all want to know the child got to
-- school. Note what is NOT here: neither table names anything of the MOTHER's.
-- A grant is over her children, and the app's green banner — «здоровье и цикл
-- не видит никто» — is kept by there being no column here that could say
-- otherwise. The levels and the shareable subjects live in
-- src/family/access.ts.
-- ---------------------------------------------------------------------------

CREATE TABLE family_access (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- Whose children. Not "which child": a relative invited into a family sees
  -- the family, and per-child grants would mean re-inviting the grandmother
  -- every time a baby is born.
  owner_user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  member_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  level          TEXT NOT NULL CHECK (level IN ('viewer', 'guardian')),
  -- The owner's label for them — «Папа», «Бабушка». Hers, not their profile
  -- name, because the list is read by her.
  label          TEXT NOT NULL DEFAULT '',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- One grant per pair, so a second acceptance re-levels rather than granting
  -- twice and one revoke really revokes.
  UNIQUE (owner_user_id, member_user_id),
  CHECK (owner_user_id <> member_user_id)
);
CREATE INDEX idx_family_access_member ON family_access (member_user_id);

-- Outstanding invitations. «24 ч, одноразовая».
CREATE TABLE family_invites (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- The HASH. The token lives in the link and is never stored, so a copy of
  -- this table is not a set of working invitations.
  token_hash     TEXT NOT NULL UNIQUE,
  level          TEXT NOT NULL CHECK (level IN ('viewer', 'guardian')),
  label          TEXT NOT NULL DEFAULT '',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at     TIMESTAMPTZ NOT NULL,
  -- Spent, not deleted: "somebody already joined with this link" is a
  -- different message from "this link never existed".
  used_at        TIMESTAMPTZ,
  used_by        UUID REFERENCES users(id) ON DELETE SET NULL,
  revoked_at     TIMESTAMPTZ
);
CREATE INDEX idx_family_invites_owner ON family_invites (owner_user_id, created_at DESC);

-- ---- Support (frame 12), mirroring migrations/034 -------------------------
--
-- There was nowhere to record that a customer asked for help. Support happened
-- on WhatsApp and lived in one operator's phone: nobody else could see what had
-- been asked, whether it was answered, or how long somebody had been waiting.
-- The queue board counts orders and leads and could not count this at all.
--
-- ON THE AUTHOR. Either a user_id or a bare phone, and NOT NULL on neither:
-- a person can write before they have an account, and refusing those is
-- refusing the customers most likely to need help. The phone is kept
-- normalised alongside so a ticket can be matched to an account that appears
-- later.
--
-- NOTHING IS DELETED. A closed ticket is a status, not a disappearance — the
-- journal rule applies here as everywhere: «ничего не удаляется».

CREATE TABLE IF NOT EXISTS support_tickets (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- Null when the writer has no account. ON DELETE SET NULL rather than
  -- CASCADE: deleting an account must not erase the record that somebody was
  -- helped, and the ticket text is the operator's, not the customer's.
  user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
  phone       TEXT,
  customer_name TEXT,
  channel     TEXT NOT NULL DEFAULT 'whatsapp'
              CHECK (channel IN ('whatsapp','phone','panel','app')),
  subject     TEXT NOT NULL,
  body        TEXT NOT NULL DEFAULT '',
  -- new: nobody has looked. open: an operator has it. waiting: we answered and
  -- are waiting on HER, which must not count against our response time.
  status      TEXT NOT NULL DEFAULT 'new'
              CHECK (status IN ('new','open','waiting','closed')),
  assignee_id UUID REFERENCES staff_accounts(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- When WE last replied. The SLA is measured from the customer's last message
  -- to this, so a ticket waiting on her does not read as us being slow.
  answered_at TIMESTAMPTZ,
  closed_at   TIMESTAMPTZ,
  -- What the app knew when she wrote: version, device, whether she was offline.
  -- Free text on purpose — support_context.dart composes it, and pinning a
  -- shape here would mean a migration every time the app learns a new fact.
  app_context TEXT,
  -- When SHE last opened the thread (migration 035). The «Есть ответ
  -- поддержки» badge is lit by an answer NEWER than this instant, so reading
  -- one takes it down and the next answer lights it again. Not the status: the
  -- queue state is the operator's, and her glancing at the screen must not move
  -- her ticket out of the board the desk works from.
  customer_read_at TIMESTAMPTZ,
  CONSTRAINT support_tickets_has_author
    CHECK (user_id IS NOT NULL OR (phone IS NOT NULL AND phone <> ''))
);

-- The queue: oldest unanswered first. Partial, because a closed ticket is
-- never in it and the table will be mostly closed tickets within a year.
CREATE INDEX IF NOT EXISTS idx_support_open
  ON support_tickets (created_at) WHERE status <> 'closed';
CREATE INDEX IF NOT EXISTS idx_support_user  ON support_tickets (user_id);
CREATE INDEX IF NOT EXISTS idx_support_phone ON support_tickets (phone);

-- The thread. Kept separate from the ticket rather than as an appended blob so
-- «кто ответил» has an answer per message.
CREATE TABLE IF NOT EXISTS support_replies (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ticket_id  UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  -- Who spoke. 'customer' has no staff id; 'staff' always does.
  author     TEXT NOT NULL CHECK (author IN ('customer','staff')),
  staff_id   UUID REFERENCES staff_accounts(id) ON DELETE SET NULL,
  body       TEXT NOT NULL,
  at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_support_replies_ticket
  ON support_replies (ticket_id, at);
-- Retention: 3 years for support_tickets, matching audit_log — a dispute about
-- an order can surface long after the order. Measured from the LAST activity on
-- the thread (updated_at, plus a NOT EXISTS over newer replies), never from
-- created_at: a conversation that ran for two years must not lose its beginning
-- while its end is still live. support_replies goes with the ticket through the
-- CASCADE above. Swept by src/privacy/retention.ts.
--
-- shop_orders next door has NO sweep, deliberately: it is an accounting record,
-- and the exact term RK requires is a question for a lawyer, not a number an
-- engineer may put behind a DELETE.

-- Canned answers. «Шаблоны» in the spec: the same six questions arrive every
-- day and retyping them is how an answer drifts.
CREATE TABLE IF NOT EXISTS support_templates (
  id      TEXT PRIMARY KEY,
  title   TEXT NOT NULL,
  body_ru TEXT NOT NULL,
  -- Bilingual like everything else a customer reads. Nullable so a template
  -- can be drafted in one language, but the panel marks those as incomplete
  -- rather than sending Russian to a Kazakh speaker.
  body_kk TEXT,
  sort    INTEGER NOT NULL DEFAULT 0
);

INSERT INTO support_templates (id, title, body_ru, body_kk, sort) VALUES
  ('where_order', 'Где мой заказ',
   'Здравствуйте! Проверила ваш заказ — он {status}. Ожидаемая доставка: {eta}.',
   'Сәлеметсіз бе! Тапсырысыңызды тексердім — ол {status}. Күтілетін жеткізу: {eta}.', 10),
  ('pair_device', 'Не подключается трекер',
   'Давайте попробуем заново: выключите трекер, зажмите кнопку 5 секунд и откройте «Устройства» в приложении.',
   'Қайтадан көрейік: трекерді өшіріп, түймені 5 секунд басып тұрыңыз да, қосымшадағы «Құрылғылар» бөлімін ашыңыз.', 20),
  ('course_access', 'Не открывается курс',
   'Курс открывается после доставки комплекта. Проверила — доступ {access}.',
   'Курс жинақ жеткізілгеннен кейін ашылады. Тексердім — қолжетімділік {access}.', 30)
ON CONFLICT (id) DO NOTHING;


-- ---------------------------------------------------------------------------
-- Frame 14a / 14b — the editable pregnancy calendar.
--
-- OVERRIDES over packages/contract/pregnancy_weeks.json, never a replacement:
-- the contract stays the offline baseline the app bundles, and only the weeks
-- somebody actually edited live here. See migrations/036 for why.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS pregnancy_week_overrides (
  week       INTEGER PRIMARY KEY CHECK (week BETWEEN 1 AND 42),
  -- Free text: the contract stores "0,02", "25–156" and "—". Ranges and dashes
  -- written by a clinician, not measurements.
  length_cm  TEXT,
  hcg        TEXT,
  -- {baby, you, recommend} per language. Both NOT NULL — the route refuses a
  -- save without Kazakh, and a nullable column re-opens the hole that closes.
  ru         JSONB NOT NULL,
  kk         JSONB NOT NULL,
  -- Stored but not served: a drafted week still reads as the contract text.
  draft      BOOLEAN NOT NULL DEFAULT FALSE,
  -- {by, at, fingerprint} — see content/medicalReview.ts.
  review     JSONB,
  -- Bumped on every save; the served calendar's version is
  -- `contract version + SUM(rev)`, so it moves whenever this table moves.
  rev        INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by TEXT
);


-- ---------------------------------------------------------------------------
-- Frame 06 «Маркетинг» — рассылки.
--
-- One message to a named group of mothers, and a ledger of who received it.
-- See migrations/037 for why the ledger is the half that matters.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS broadcasts (
  id           TEXT PRIMARY KEY,
  -- RU required, KK not: a draft may be half-written, but PUBLISHING without
  -- the Kazakh half is refused by the route (content/bilingual.ts). A NOT NULL
  -- here would force placeholder Kazakh into drafts, which is how untranslated
  -- text reaches a phone.
  title_ru     TEXT NOT NULL,
  body_ru      TEXT NOT NULL,
  title_kk     TEXT,
  body_kk      TEXT,
  -- {audience, locale} only — src/admin/broadcasts.ts validates it. Never a
  -- health field: those are collected to warn a woman about her own pregnancy,
  -- not to choose who gets an advertisement.
  segment      JSONB NOT NULL DEFAULT '{}'::jsonb,
  -- One way. There is no unpublish — the message is already on a phone.
  status       TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),
  created_by   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  published_at TIMESTAMPTZ
);

-- «Не чаще раза в неделю», made real. The cap is ACROSS broadcasts: publishing
-- skips anybody written to in the last seven days, and the panel reports how
-- many were skipped rather than claiming to have delivered more than it did.
CREATE TABLE IF NOT EXISTS broadcast_deliveries (
  broadcast_id TEXT NOT NULL REFERENCES broadcasts(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (broadcast_id, user_id)
);
CREATE INDEX IF NOT EXISTS idx_broadcast_deliveries_user
  ON broadcast_deliveries (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_broadcasts_published
  ON broadcasts (published_at DESC NULLS LAST);


-- ---------------------------------------------------------------------------
-- Frame 25 «Уведомления» — the switches the SERVER obeys, and what happened to
-- every push it tried to send. See migrations/047.
--
-- Until this existed, the app's notification screen was a promise the server
-- had never heard of: the switches lived in SharedPrefs on one phone and gated
-- only what that phone raised for itself.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS notification_prefs (
  user_id     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  -- All TRUE by default, and a MISSING ROW means the same: an install that
  -- predates the table must not lose alerts it was already receiving.
  zone_events BOOLEAN NOT NULL DEFAULT TRUE,
  check_in    BOOLEAN NOT NULL DEFAULT TRUE,
  low_battery BOOLEAN NOT NULL DEFAULT TRUE,
  -- Рассылки and support answers — a FOURTH category, never a reuse of
  -- check_in: muting advertisements must not mute «ребёнок на месте».
  updates     BOOLEAN NOT NULL DEFAULT TRUE,
  -- Minutes since midnight IN HER timezone (users.timezone), not the server's.
  -- Both NULL = off; start > end is a legitimate overnight window.
  quiet_start SMALLINT CHECK (quiet_start BETWEEN 0 AND 1439),
  quiet_end   SMALLINT CHECK (quiet_end   BETWEEN 0 AND 1439),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- SOS and medical emergency have no column here on purpose: they are not
-- switchable, and a column for them is a column somebody sets to false.

-- One row per ATTEMPT, held ones included — «почему ей не пришло» is the
-- question this table exists for. It records no open rate: FCM accepting a
-- message is not a woman reading it, and there is no such number in this
-- product to print.
CREATE TABLE IF NOT EXISTS push_deliveries (
  id          BIGSERIAL PRIMARY KEY,
  user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
  kind        TEXT NOT NULL,
  sent        INTEGER NOT NULL DEFAULT 0,
  failed      INTEGER NOT NULL DEFAULT 0,
  dead        INTEGER NOT NULL DEFAULT 0,
  held_reason TEXT CHECK (held_reason IN ('muted', 'quiet_hours')),
  error       TEXT,
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_push_deliveries_at ON push_deliveries (at DESC);
CREATE INDEX IF NOT EXISTS idx_push_deliveries_kind ON push_deliveries (kind, at DESC);
CREATE INDEX IF NOT EXISTS idx_push_deliveries_user ON push_deliveries (user_id, at DESC);


-- ---------------------------------------------------------------------------
-- Frames 15 / 15a / 15b — the editable immunisation calendar.
--
-- OVERRIDES over packages/contract/vaccination_schedule.json, never a
-- replacement: the contract stays the offline baseline the app bundles, and
-- only the vaccines somebody edited or added live here. See migrations/038.
-- ---------------------------------------------------------------------------

-- Keyed exactly as a mother's tick is keyed — `<id>/<dose>`, matching
-- vaccineKey() in the app and child_vaccines.vaccine_key. Not by `id` (three
-- pentavalent rows share one), not by (id, dose, at_month) (the age is the
-- field most likely to be edited, and re-keying would orphan every tick).
CREATE TABLE IF NOT EXISTS vaccination_overrides (
  key        TEXT PRIMARY KEY,
  vaccine_id TEXT    NOT NULL,
  dose       INTEGER,
  at_month   INTEGER NOT NULL CHECK (at_month BETWEEN 0 AND 216),
  -- {name, note} per language. Both NOT NULL — the route refuses a save
  -- without Kazakh, and a nullable column re-opens the hole that closes.
  ru         JSONB   NOT NULL,
  kk         JSONB   NOT NULL,
  -- Not in the contract (frame 15a): appended by the merge rather than
  -- patching a shipped entry.
  added      BOOLEAN NOT NULL DEFAULT FALSE,
  -- Stored but not served. Drafting an edit shows the contract through again;
  -- drafting an added vaccine retires it. Rows are never deleted.
  draft      BOOLEAN NOT NULL DEFAULT FALSE,
  -- {by, at, fingerprint} — see content/medicalReview.ts. The age is inside
  -- the fingerprint, so moving a dose drops the sign-off.
  review     JSONB,
  -- Bumped on every save; the served version is
  -- `contract version + SUM(rev) + settings rev`.
  rev        INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by TEXT
);

-- The catch-up window, the one reminder setting this product can honestly
-- offer: nothing here sends a vaccination push, so there is no toggle for one.
-- Single row; absent means «the contract's value».
CREATE TABLE IF NOT EXISTS vaccination_settings (
  id                BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
  due_window_months INTEGER NOT NULL CHECK (due_window_months BETWEEN 1 AND 12),
  rev               INTEGER NOT NULL DEFAULT 1,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by        TEXT
);

-- Frame 15b: append-only before/after, so the version list is a real diff and
-- not a guess reconstructed from the current row. `before` is NULL on a
-- vaccine's first edit — there was no row, and the baseline is the contract.
CREATE TABLE IF NOT EXISTS vaccination_schedule_log (
  id     BIGSERIAL PRIMARY KEY,
  key    TEXT NOT NULL,
  before JSONB,
  after  JSONB NOT NULL,
  actor  TEXT,
  at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_vaccination_log_at
  ON vaccination_schedule_log (at DESC);

-- ---------------------------------------------------------------------------
-- Frame 16b «Экстренная помощь» / app screen 37 — the editable first-aid list.
--
-- OVERRIDES over packages/contract/emergency_help.json, never a replacement:
-- the contract stays the offline baseline the app bundles, and only the
-- scenarios somebody edited live here. See migrations/043.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS emergency_help_overrides (
  -- The contract's scenario id ('breathing', 'bleeding', …) — what joins this
  -- row to the entry it patches.
  id         TEXT PRIMARY KEY,
  -- 'red' = звоните 103 сейчас, 'amber' = звоните врачу сегодня. Decides the
  -- border-left colour, and therefore whether somebody dials or waits.
  severity   TEXT NOT NULL CHECK (severity IN ('red', 'amber')),
  -- Reading order: triage order is a clinical decision, so it is editable.
  sort       INTEGER NOT NULL DEFAULT 0,
  -- {title, what, do} per language. Both NOT NULL — the route refuses a save
  -- without Kazakh, and a nullable column re-opens the hole that closes.
  ru         JSONB NOT NULL,
  kk         JSONB NOT NULL,
  -- Stored but not served: drafting a scenario shows the contract through
  -- again. Rows are never deleted, so `rev` — and the served version — only
  -- ever grows.
  draft      BOOLEAN NOT NULL DEFAULT FALSE,
  -- {by, at, fingerprint} — see content/medicalReview.ts. The severity is
  -- inside the fingerprint, so downgrading red to amber drops the sign-off.
  review     JSONB,
  rev        INTEGER NOT NULL DEFAULT 1,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by TEXT
);

-- ---------------------------------------------------------------------------
-- Поставки и поставщики — кадры 07a «Поставки», 07g «Поставщики», и полоса
-- «поставки в пути» кадра 07. См. migrations/045_supply.sql.
--
-- `lead_time_days` — срок, ЗАЯВЛЕННЫЙ поставщиком, а не выведенный из истории:
-- пары «разместили → приняли» в базе ещё нет, и среднее считать не из чего.
-- `unit_cost_minor` NULLABLE — закупочную цену этот проект узнаёт только из
-- приёмки с `batchCostMinor`; панель печатает «—», а не догадку.
--
-- Ничто отсюда не прибавляется к `shop_variants.stock`: коробка на таможне —
-- не полка, и прогноз, считающий её, обещает товар, который нельзя отгрузить.
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS suppliers (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name           TEXT NOT NULL,
  -- Телефон, ватсап, имя менеджера — одной строкой.
  contact        TEXT,
  lead_time_days INTEGER CHECK (lead_time_days IS NULL OR (lead_time_days >= 0 AND lead_time_days <= 365)),
  -- Не удаляем: у поставщика есть история заказов. Архивируем.
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE UNIQUE INDEX IF NOT EXISTS suppliers_name_unique ON suppliers (lower(name));

CREATE TABLE IF NOT EXISTS purchase_orders (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
  -- draft не едет, cancelled не едет; в пути считается только placed.
  status      TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','placed','received','cancelled')),
  placed_at   TIMESTAMPTZ,
  -- Дата, а не отметка времени: никто не обещает груз к 14:20.
  expected_at DATE,
  note        TEXT,
  -- TEXT, как shop_stock_moves.staff_id.
  created_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_open ON purchase_orders (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier ON purchase_orders (supplier_id);

CREATE TABLE IF NOT EXISTS purchase_order_items (
  po_id           UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  -- Цвет, а не товар: заказывают «часы чёрные 40», а не «часы 40».
  variant_id      UUID NOT NULL REFERENCES shop_variants(id) ON DELETE CASCADE,
  qty_ordered     INTEGER NOT NULL CHECK (qty_ordered > 0),
  unit_cost_minor INTEGER CHECK (unit_cost_minor IS NULL OR unit_cost_minor >= 0),
  -- Факт, который приносит приёмка. Пока received_at пуст — эти qty_ordered
  -- штук считаются «в пути».
  qty_received    INTEGER NOT NULL DEFAULT 0 CHECK (qty_received >= 0),
  received_at     TIMESTAMPTZ,
  PRIMARY KEY (po_id, variant_id)
);
CREATE INDEX IF NOT EXISTS idx_po_items_variant ON purchase_order_items (variant_id);
