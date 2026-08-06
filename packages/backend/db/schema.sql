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
--   * Column-level: `bp_calibration.*_offset` and any free-text are stored under
--     application-layer envelope encryption (see backend/src/crypto). DB stores ciphertext.
--   * At-rest: enable cluster-level TDE / encrypted EBS volumes.
--   * Retention: prune location_history > 90d (a cron DELETE; was a Timescale policy).
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
-- Privacy retention: prune location trails older than 90 days. This was a
-- Timescale retention policy; on plain Postgres run the equivalent as a scheduled
-- job (pg_cron, or an app cron):
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
-- Baby cry-analysis results (parent-recorded). Newest-first history, pushed so
-- it survives a reinstall and restores on a new device.
CREATE TABLE cry_results (
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  at          TIMESTAMPTZ NOT NULL,
  reason      TEXT NOT NULL,          -- wire code, e.g. hungry | tired | discomfort
  confidence  REAL NOT NULL,          -- 0..1
  PRIMARY KEY (user_id, at)
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

-- ---- Shop: device store (see migrations/009_shop.sql for seed data) ---------
-- Products (watch/tracker), per-colour variants with stock managed from the admin
-- panel, and cash-on-delivery orders carrying a delivery address. An order
-- decrements the variant's stock atomically (see pgRepository.placeShopOrder).
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
  grants_feature TEXT
);
CREATE UNIQUE INDEX IF NOT EXISTS shop_products_sku_unique
  ON shop_products (sku) WHERE sku IS NOT NULL;
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
CREATE TABLE IF NOT EXISTS shop_order_items (
  order_id         UUID NOT NULL REFERENCES shop_orders(id) ON DELETE CASCADE,
  variant_id       UUID NOT NULL REFERENCES shop_variants(id),
  product_name     TEXT NOT NULL,
  color            TEXT NOT NULL,
  qty              INTEGER NOT NULL CHECK (qty > 0),
  unit_price_minor INTEGER NOT NULL CHECK (unit_price_minor >= 0)
);
CREATE INDEX IF NOT EXISTS idx_shop_items_order ON shop_order_items (order_id);

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

-- Staff accounts for the back office: phone number + password, the same two
-- fields the app asks a mother for. See migration 019 — this block and that one
-- must stay identical, because schema.sql builds a fresh database and the
-- migration upgrades an existing one.
CREATE TABLE IF NOT EXISTS staff_accounts (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone         TEXT NOT NULL UNIQUE,          -- digits only, e.g. 77073452244
  password_hash TEXT NOT NULL,                 -- scrypt, salted
  role          TEXT NOT NULL DEFAULT 'admin', -- admin | clinician | support
  display_name  TEXT NOT NULL DEFAULT '',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at TIMESTAMPTZ,
  disabled_at   TIMESTAMPTZ
);

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
