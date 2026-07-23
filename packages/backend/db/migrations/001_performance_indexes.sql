-- =============================================================================
-- 001 — Performance indexes
--
-- schema.sql builds a database from scratch; this file brings an EXISTING one
-- up to the same index set. Every statement is IF NOT EXISTS, so it is safe to
-- run repeatedly and safe to run against a database already built from the
-- current schema.sql (it will simply do nothing).
--
-- Each index below was chosen by matching a real query in
-- src/db/pgRepository.ts against what the schema actually indexed. Indexes that
-- would have been redundant are listed at the foot of this file with the reason,
-- so nobody re-adds them.
--
--   psql "$DATABASE_URL" -f db/migrations/001_performance_indexes.sql
--
-- ON A LIVE DATABASE: a plain CREATE INDEX takes an ACCESS EXCLUSIVE lock and
-- blocks writes to that table for the duration. Against a table with real data,
-- run each statement with CONCURRENTLY instead (add the keyword, and run each
-- one on its own connection outside a transaction block — CONCURRENTLY cannot
-- run inside BEGIN/COMMIT).
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- The admin user list searches with `ILIKE '%term%'`. A leading wildcard makes
-- the btree on email useless and display_name had no index at all, so every
-- search keystroke was a full scan of users plus a per-row pattern match.
CREATE INDEX IF NOT EXISTS idx_users_name_trgm
  ON users USING GIN (display_name gin_trgm_ops);
CREATE INDEX IF NOT EXISTS idx_users_email_trgm
  ON users USING GIN ((email::TEXT) gin_trgm_ops);

-- Zones are read BY CHILD constantly: the map, the new-device restore, the
-- per-child zone count in the admin drawer, and the inside-any-zone check.
-- Only the two GIST shape indexes existed, and neither serves `child_id = $1`.
CREATE INDEX IF NOT EXISTS idx_geofences_child ON geofences(child_id);

-- The admin emergency feed reads the newest emergencies across ALL users.
-- idx_phm_user_time leads with user_id and cannot serve it, so the feed scanned
-- every chunk of the largest table. Partial: emergencies are a tiny fraction of
-- rows, so the index stays small.
CREATE INDEX IF NOT EXISTS idx_phm_emergency
  ON pregnancy_health_metrics (recorded_at DESC)
  WHERE triage_severity = 'emergency';

-- The admin alert feed and the 7-day / SOS counters read across all users;
-- idx_safety_alerts_user_at leads with user_id and cannot serve them.
CREATE INDEX IF NOT EXISTS idx_safety_alerts_at
  ON safety_alerts (at DESC);
CREATE INDEX IF NOT EXISTS idx_safety_alerts_sos
  ON safety_alerts (at DESC) WHERE kind = 'sos';

-- FCM/APNS reports a dead token and the push layer deletes it BY TOKEN alone.
-- UNIQUE(user_id, token) leads with user_id, so that delete scanned the whole
-- table — on the push path, for every unregistered device.
CREATE INDEX IF NOT EXISTS idx_push_tokens_token ON push_tokens(token);

-- =============================================================================
-- Deliberately NOT added — each of these looks missing and is not:
--
--   devices(user_id)          — UNIQUE (user_id, ble_mac) is a btree whose
--                               leading column is user_id, so it already serves
--                               `WHERE user_id = $1`.
--   push_tokens(user_id)      — same, via UNIQUE (user_id, token).
--   sleep_nights(user_id, night), weight_entries(user_id, log_date),
--   cycle_day_logs(user_id, log_date), kick_sessions(user_id, ended_at),
--   contraction_sessions(user_id, ended_at)
--                             — the composite PRIMARY KEY of each already leads
--                               with user_id and carries the sort/range column
--                               second, which is exactly what every list query
--                               on them needs.
--   newborn_events(child_id, at)
--                             — covered by PRIMARY KEY (child_id, at, kind).
--   child_emergency(child_id) — it is the PRIMARY KEY.
--   emergency_acks(emergency_id) — it is the PRIMARY KEY.
--   children(guardian_id, created_at)
--                             — idx_children_guardian already selects the rows;
--                               widening it to sort would save a sort of the
--                               handful of children one guardian has.
--   location_history(observed_at)
--                             — a Timescale hypertable partitioned on
--                               observed_at; chunk exclusion already prunes
--                               time-range scans.
-- =============================================================================
