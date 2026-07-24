-- =============================================================================
-- 003 — Medication adherence (doses taken)
--
-- Brings an existing database up to schema.sql for the per-day dose log a
-- clinician reads against each medication's perDay target. Idempotent.
--
--   psql "$DATABASE_URL" -f db/migrations/003_med_doses.sql
-- =============================================================================

CREATE TABLE IF NOT EXISTS med_doses (
  med_id    TEXT NOT NULL REFERENCES medications(id) ON DELETE CASCADE,
  user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  log_date  DATE NOT NULL,
  count     SMALLINT NOT NULL CHECK (count >= 0),
  PRIMARY KEY (med_id, log_date)
);

-- The per-user feed reads doses across all her medications, newest day first;
-- the PK leads with med_id and can't serve it.
CREATE INDEX IF NOT EXISTS idx_med_doses_user ON med_doses (user_id, log_date DESC);
