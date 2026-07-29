-- =============================================================================
-- 015 — Women's-health day-log note
--
-- Brings an existing database up to schema.sql for the free-text note a user
-- types on a calendar day. The app already sends it (DayLog.toJson) and reads
-- it back (fromJson), but cycle_day_logs had no column, so a typed note was
-- dropped on backup and lost on a new device — a hand-entered value with
-- nothing to re-supply it. Idempotent.
--
--   psql "$DATABASE_URL" -f db/migrations/015_daylog_note.sql
-- =============================================================================

ALTER TABLE cycle_day_logs ADD COLUMN IF NOT EXISTS note TEXT;
