-- =============================================================================
-- 002 — Child growth measurements
--
-- Brings an existing database up to schema.sql for the pediatric growth curve
-- (weight/height per child per day). Idempotent — safe to run repeatedly.
--
--   psql "$DATABASE_URL" -f db/migrations/002_child_growth.sql
-- =============================================================================

CREATE TABLE IF NOT EXISTS child_growth (
  child_id   UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  at         DATE NOT NULL,
  weight_kg  NUMERIC(5,2),
  height_cm  NUMERIC(5,1),
  PRIMARY KEY (child_id, at),
  CHECK (weight_kg IS NOT NULL OR height_cm IS NOT NULL)
);

-- The PRIMARY KEY (child_id, at) already indexes the per-child lookup the app
-- and admin do; no extra index is needed. See 001's footnote for the rule.
