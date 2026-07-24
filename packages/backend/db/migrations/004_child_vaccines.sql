-- =============================================================================
-- 004 — Child vaccination record (parent-marked)
--
-- Brings an existing database up to schema.sql for the immunization record a
-- clinician reads. One row per (child, vaccine key) the parent has ticked done;
-- presence is "done". Idempotent.
--
--   psql "$DATABASE_URL" -f db/migrations/004_child_vaccines.sql
-- =============================================================================

CREATE TABLE IF NOT EXISTS child_vaccines (
  child_id     UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
  vaccine_key  TEXT NOT NULL,
  PRIMARY KEY (child_id, vaccine_key)
);

-- The PRIMARY KEY (child_id, vaccine_key) already indexes the per-child read;
-- no extra index is needed.
