-- =============================================================================
-- 006 — Idempotent telemetry ingest (unique reading)
--
-- TelemetryBatcher re-sends a whole batch whenever a flush fails — including the
-- case where the server stored it and only the RESPONSE was lost on the way back.
-- The same reading then arrived twice: a duplicate row in her history AND a second
-- emergency push for one reading. `insertHealthMetric` now uses ON CONFLICT DO
-- NOTHING against this constraint, so a resend is a no-op and the caller learns
-- (rowCount 0) not to push the emergency again.
--
-- Includes recorded_at (the hypertable partition column), as Timescale requires of
-- any unique constraint on a hypertable. Idempotent — safe to run repeatedly.
--
--   psql "$DATABASE_URL" -f db/migrations/006_phm_idempotent.sql
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'phm_unique_reading'
  ) THEN
    ALTER TABLE pregnancy_health_metrics
      ADD CONSTRAINT phm_unique_reading UNIQUE (user_id, device_id, recorded_at);
  END IF;
END $$;
