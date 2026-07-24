-- =============================================================================
-- FemTech & Child Safety Consortium — Relational + Timeseries + Geospatial schema
-- Target: PostgreSQL 15+ with TimescaleDB and PostGIS extensions.
-- Specialists: Senior Backend Engineer, OB-GYN (metric columns/constraints),
--              Geofencing Specialist (PostGIS), Data Privacy Officer (encryption notes).
--
-- Privacy: health + child-location data are special-category (GDPR Art.9) / PHI (HIPAA).
--   * Column-level: `bp_calibration.*_offset` and any free-text are stored under
--     application-layer envelope encryption (see backend/src/crypto). DB stores ciphertext.
--   * At-rest: enable cluster-level TDE / encrypted EBS volumes.
--   * Retention: location_history is auto-dropped after 90d via a Timescale policy.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS timescaledb;
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- substring search on the admin user list

-- -----------------------------------------------------------------------------
-- Identity
-- -----------------------------------------------------------------------------
CREATE TABLE users (                       -- Mothers / primary caregivers
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  email          CITEXT UNIQUE NOT NULL,
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
  child_id       UUID REFERENCES children(id) ON DELETE SET NULL,  -- tracker tag → child
  paired_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Fleet telemetry. Both were already SELECTed by adminDevices() and neither
  -- was ever declared here, so the fleet view worked only against databases
  -- that had drifted ahead of this file and failed outright on one built from
  -- it. NULL means never reported, which is distinct from "reported nothing".
  battery_pct    INT CHECK (battery_pct BETWEEN 0 AND 100),
  last_seen      TIMESTAMPTZ,
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
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (beacon_uuid IS NOT NULL OR tag_serial IS NOT NULL)
);
CREATE INDEX idx_children_guardian ON children(guardian_id);
CREATE INDEX idx_children_beacon    ON children(beacon_uuid, beacon_major, beacon_minor);

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
  device_id      UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  user_id        UUID NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  recorded_at    TIMESTAMPTZ NOT NULL,
  core_temp_c    REAL,
  skin_temp_c    REAL,
  heart_rate_bpm SMALLINT,
  spo2_pct       SMALLINT,
  systolic_mmhg  SMALLINT,      -- PPG screening estimate (calibrated)
  diastolic_mmhg SMALLINT,      -- PPG screening estimate (calibrated)
  during_sleep   BOOLEAN NOT NULL DEFAULT FALSE,
  -- Highest triage severity computed at ingest, for fast dashboard filtering.
  triage_severity TEXT NOT NULL DEFAULT 'ok'
    CHECK (triage_severity IN ('ok','info','warning','emergency')),
  CONSTRAINT sane_hr   CHECK (heart_rate_bpm IS NULL OR heart_rate_bpm BETWEEN 20 AND 250),
  CONSTRAINT sane_spo2 CHECK (spo2_pct IS NULL OR spo2_pct BETWEEN 50 AND 100),
  CONSTRAINT sane_bp   CHECK (systolic_mmhg IS NULL OR systolic_mmhg BETWEEN 60 AND 260)
);
SELECT create_hypertable('pregnancy_health_metrics', 'recorded_at',
                         chunk_time_interval => INTERVAL '7 days');
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

-- Compress chunks older than 14 days (Timescale native columnar compression).
ALTER TABLE pregnancy_health_metrics SET (
  timescaledb.compress,
  timescaledb.compress_segmentby = 'user_id',
  timescaledb.compress_orderby   = 'recorded_at DESC'
);
SELECT add_compression_policy('pregnancy_health_metrics', INTERVAL '14 days');

-- Continuous aggregate: hourly rollups powering charts without scanning raw rows.
CREATE MATERIALIZED VIEW phm_hourly
  WITH (timescaledb.continuous) AS
SELECT
  user_id,
  time_bucket('1 hour', recorded_at) AS bucket,
  avg(heart_rate_bpm)::REAL AS avg_hr,
  min(spo2_pct)             AS min_spo2,
  max(systolic_mmhg)        AS max_systolic,
  max(diastolic_mmhg)       AS max_diastolic,
  max(core_temp_c)          AS max_temp
FROM pregnancy_health_metrics
GROUP BY user_id, bucket
WITH NO DATA;
SELECT add_continuous_aggregate_policy('phm_hourly',
  start_offset => INTERVAL '3 days',
  end_offset   => INTERVAL '1 hour',
  schedule_interval => INTERVAL '1 hour');

-- Weekly manual tonometer calibration inputs (drives the PPG BP offset).
CREATE TABLE bp_calibration (
  id                UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id           UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  measured_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  cuff_systolic     SMALLINT NOT NULL,
  cuff_diastolic    SMALLINT NOT NULL,
  ppg_systolic      SMALLINT NOT NULL,   -- band's raw reading at calibration time
  ppg_diastolic     SMALLINT NOT NULL,
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
  -- Circles: center + radius. Polygons: `area`. Exactly one is populated.
  center       GEOGRAPHY(POINT, 4326),
  radius_m     REAL,
  area         GEOGRAPHY(POLYGON, 4326),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK ( (shape = 'circle'  AND center IS NOT NULL AND radius_m IS NOT NULL)
       OR (shape = 'polygon' AND area  IS NOT NULL) )
);
CREATE INDEX idx_geofences_center ON geofences USING GIST (center);
CREATE INDEX idx_geofences_area   ON geofences USING GIST (area);
-- Zones are read BY CHILD constantly: the map, the new-device restore, the
-- per-child zone count in the admin drawer, and the inside-any-zone check
-- documented at the foot of this file. Only the two shape indexes existed, and
-- neither can serve `WHERE child_id = $1` — every one of those reads was a
-- sequential scan over every family's zones.
CREATE INDEX idx_geofences_child ON geofences(child_id);

CREATE TABLE location_history (                    -- TIMESERIES hypertable
  child_id     UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  observed_at  TIMESTAMPTZ NOT NULL,
  geog         GEOGRAPHY(POINT, 4326) NOT NULL,
  source       TEXT NOT NULL CHECK (source IN ('gps','wifi','lbs','ble')),
  accuracy_m   REAL
);
SELECT create_hypertable('location_history', 'observed_at',
                         chunk_time_interval => INTERVAL '7 days');
CREATE INDEX idx_loc_child_time ON location_history (child_id, observed_at DESC);
CREATE INDEX idx_loc_geog       ON location_history USING GIST (geog);
-- Privacy retention: drop location trails older than 90 days automatically.
SELECT add_retention_policy('location_history', INTERVAL '90 days');

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

-- Staff audit log (every back-office access to PHI/location is recorded).
CREATE TABLE audit_log (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  staff_id    TEXT NOT NULL,
  action      TEXT NOT NULL,
  target      TEXT,
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_audit_at ON audit_log (at DESC);

-- Nightly sleep summaries from the band (one row per wake-day per user).
CREATE TABLE sleep_nights (
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  night       DATE NOT NULL,
  deep_min    INTEGER NOT NULL DEFAULT 0,
  rem_min     INTEGER NOT NULL DEFAULT 0,
  light_min   INTEGER NOT NULL DEFAULT 0,
  awake_min   INTEGER NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, night)
);

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
  PRIMARY KEY (user_id, log_date)
);

-- Child safety alerts (geofence enter/exit history).
CREATE TABLE safety_alerts (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  child_id    UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  kind        TEXT NOT NULL CHECK (kind IN ('entered','left')),
  zone_name   TEXT NOT NULL,
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_safety_alerts_user_at ON safety_alerts (user_id, at DESC);
-- The admin alert feed and the 7-day / SOS dashboard counters read across ALL
-- users; the index above leads with user_id and cannot serve them.
CREATE INDEX idx_safety_alerts_at  ON safety_alerts (at DESC);
CREATE INDEX idx_safety_alerts_sos ON safety_alerts (at DESC) WHERE kind = 'sos';

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
