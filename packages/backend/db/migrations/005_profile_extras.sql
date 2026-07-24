-- =============================================================================
-- 005 — Profile extras (emergency contact + cycle baselines)
--
-- Brings an existing database up to schema.sql for the user-level fields the
-- profile backup now carries, so they survive a device change: her own
-- emergency doctor phone, and the women's-health baselines that drive the
-- period/fertility predictions. Idempotent.
--
--   psql "$DATABASE_URL" -f db/migrations/005_profile_extras.sql
-- =============================================================================

ALTER TABLE users ADD COLUMN IF NOT EXISTS doctor_phone TEXT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS avg_cycle_length  SMALLINT;
ALTER TABLE users ADD COLUMN IF NOT EXISTS avg_period_length SMALLINT;

-- Match schema.sql's plausibility bounds (typo filter, not a medical judgement).
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_avg_cycle_length_check') THEN
    ALTER TABLE users ADD CONSTRAINT users_avg_cycle_length_check
      CHECK (avg_cycle_length IS NULL OR avg_cycle_length BETWEEN 15 AND 60);
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'users_avg_period_length_check') THEN
    ALTER TABLE users ADD CONSTRAINT users_avg_period_length_check
      CHECK (avg_period_length IS NULL OR avg_period_length BETWEEN 1 AND 14);
  END IF;
END $$;
