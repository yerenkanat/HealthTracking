-- =============================================================================
-- 007 — Manual (hand-typed) readings can be stored
--
-- pregnancy_health_metrics.device_id was UUID NOT NULL REFERENCES devices. But a
-- manual cuff reading — the app's MOST trustworthy health data — has no device
-- (deviceId ''), so insertHealthMetric failed the uuid cast and the reading never
-- reached the clinician's view. device_id is now nullable (NULL = manual), and the
-- idempotency constraint uses NULLS NOT DISTINCT so a resent manual reading still
-- dedups (otherwise every NULL device counts as distinct). Idempotent.
--
--   psql "$DATABASE_URL" -f db/migrations/007_manual_readings.sql
-- =============================================================================

ALTER TABLE pregnancy_health_metrics ALTER COLUMN device_id DROP NOT NULL;

-- Swap the unique constraint to NULLS NOT DISTINCT (Postgres 15+). Drop the old
-- one (added inline / by migration 006) and re-add, so existing databases get the
-- manual-reading dedup behaviour too.
ALTER TABLE pregnancy_health_metrics DROP CONSTRAINT IF EXISTS phm_unique_reading;
ALTER TABLE pregnancy_health_metrics
  ADD CONSTRAINT phm_unique_reading UNIQUE NULLS NOT DISTINCT (user_id, device_id, recorded_at);
