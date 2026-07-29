-- =============================================================================
-- 016 — Baby cry-analysis history
--
-- Adds the store the app pushes its cry-analysis results to, so the history
-- survives a reinstall and restores on a new device. It was device-local only
-- (no backend store, no mergeRemoteCry), so a parent's cry log was lost on any
-- device change. Idempotent.
--
--   psql "$DATABASE_URL" -f db/migrations/016_cry_results.sql
-- =============================================================================

CREATE TABLE IF NOT EXISTS cry_results (
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  at          TIMESTAMPTZ NOT NULL,
  reason      TEXT NOT NULL,
  confidence  REAL NOT NULL,
  PRIMARY KEY (user_id, at)
);
