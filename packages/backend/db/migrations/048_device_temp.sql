-- The watch's own temperature reading, stored for the first time.
--
-- WHAT THIS COLUMN IS: a temperature a wrist device reported — the Starmax
-- watch's `当前体温` — in degrees Celsius, exactly as the device gave it, with
-- no conversion applied.
--
-- WHAT IT IS NOT, and this is the whole reason it is a separate column:
--
--   * It is NOT a core temperature, and must never be written to, read as, or
--     merged with `core_temp_c`. The vendor names the quantity and states
--     neither a measurement site nor an accuracy (docs/UniappSDKDocumentation.md),
--     so there is no defensible conversion to a core estimate; applying the OEM
--     band's `skinToCoreTempC` to it would be inventing a calibration. Every
--     reader of `core_temp_c` — the clinician view, the charts, triage — treats
--     that column as an estimate of her core.
--   * It is NOT a triage input. `assessTelemetry` ignores it in both twins
--     (packages/shared/src/triage.ts, app/lib/core/triage.dart), and no device
--     path may raise `emergency` on a temperature: the dominant error terms are
--     the room, the bedding and the strap, none of which is an input to the
--     conversion. The precedent is `glucose_mmol` in this same table — carried
--     and shown, never triaged. See docs/CLINICAL-REVIEW-WATCH.md, "Device
--     temperature — closed 2026-08-13".
--   * It is NOT a fever verdict, and nothing may print one from it. A
--     thermometer reading she TYPES IN keeps full emergency weight; that path is
--     unchanged by this column and must stay that way.
--
-- Why now: `BandTelemetry.deviceTempC` has existed since ed2a0d0 and the app has
-- been sending it on every /ingest batch. Zod strips keys a schema does not
-- name, so the value reached her chart and her advisor on the handset and then
-- died at the edge of the server — stored nowhere, for anyone.
--
-- REAL, like core_temp_c and skin_temp_c beside it: one decimal is the device's
-- own resolution (it transmits tenths of a degree).
ALTER TABLE pregnancy_health_metrics ADD COLUMN IF NOT EXISTS device_temp_c REAL;

-- The bound is a CREDIBILITY window, not a clinical one — it keeps every
-- temperature a person can have, including the alarming ones, and rejects only
-- a mis-decoded frame (the raw field is a u16: a corrupt 4000 becomes 400 °C).
--
-- 20–45 is not invented here: it is the gate the app's own parser already
-- applies (`starmax_frames.dart` `tempCelsius` returns null outside it) and the
-- same window `coreTempC` carries in the wire schema. It repeats the zod bound
-- in server.ts EXACTLY, in both directions, because the telemetry path has no
-- `plausible()` filter between the wire and the INSERT — the schema is the
-- guard. A CHECK narrower than the wire would fail the INSERT, and the
-- batch-level catch would count the item `rejected`, which makes the client
-- resend the same reading for ever.
--
-- Guarded by a DO block so re-running on a database that already has it is a
-- no-op (ADD CONSTRAINT has no IF NOT EXISTS).
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint WHERE conname = 'sane_device_temp'
  ) THEN
    ALTER TABLE pregnancy_health_metrics
      ADD CONSTRAINT sane_device_temp
      CHECK (device_temp_c IS NULL OR device_temp_c BETWEEN 20 AND 45);
  END IF;
END $$;
