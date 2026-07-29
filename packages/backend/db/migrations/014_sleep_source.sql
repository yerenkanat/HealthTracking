-- =============================================================================
-- 014 — Sleep provenance (hand-entered nights)
--
-- Brings an existing database up to schema.sql for the two fields a manually
-- logged night carries: `source` = 'manual' (vs a NULL/'band' device night) and
-- `manual_asleep_min`, the typed asleep total the app stores because a hand
-- entry has no measured deep/REM/light split to infer one from. Without these,
-- a hand-logged night round-trips through the backup as a band night and loses
-- the exact minutes the user typed. Idempotent.
--
--   psql "$DATABASE_URL" -f db/migrations/014_sleep_source.sql
-- =============================================================================

ALTER TABLE sleep_nights ADD COLUMN IF NOT EXISTS source            TEXT;
ALTER TABLE sleep_nights ADD COLUMN IF NOT EXISTS manual_asleep_min INTEGER;
