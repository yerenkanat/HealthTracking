-- =============================================================================
-- 008 — Blood glucose on health metrics
--
-- Manual glucose logging: a mother can type a glucometer reading, and it syncs so
-- her clinician sees it. Glucose is a WELLNESS reading, stored alongside the
-- vitals but NOT run through triage (assessTelemetry ignores it) — a glucometer
-- estimate must never force the Emergency screen. Idempotent.
--
--   psql "$DATABASE_URL" -f db/migrations/008_glucose.sql
-- =============================================================================

ALTER TABLE pregnancy_health_metrics ADD COLUMN IF NOT EXISTS glucose_mmol REAL;
