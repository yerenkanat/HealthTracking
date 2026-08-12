-- What the watch measures beyond the four triage vitals, given somewhere to go.
--
-- The smartwatch reports far more than heart rate, SpO2, blood pressure and
-- temperature: steps, distance, calories, sleep stages, a stress index, a
-- breathing rate, a MET estimate, whether it is on the wrist, and its own
-- battery. All of it was parsed by the app, folded into one in-memory object
-- and rendered on a single panel. None of it was ever sent anywhere. It died
-- with the process, so her clinician's view showed the vitals and nothing at
-- all about how she had been living, and the operator could not tell a watch
-- that had run flat from one that was simply never worn.
--
-- One row per wearer's day per device. Upsert, not append: steps/kcal/meters
-- are the device's own running daily totals, so the app's thirty-second poll
-- would otherwise write thousands of rows a day each restating the same day.
--
-- `day` is the WEARER's local date. The watch rolls its totals over at her
-- midnight; filing an Almaty evening (UTC+5) under the following UTC day would
-- misreport every day of every user in the country.
CREATE TABLE IF NOT EXISTS wearable_days (
  user_id         UUID NOT NULL REFERENCES users(id)   ON DELETE CASCADE,
  device_id       UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
  day             DATE NOT NULL,
  recorded_at     TIMESTAMPTZ NOT NULL,
  steps           INTEGER NOT NULL DEFAULT 0,
  kcal            INTEGER NOT NULL DEFAULT 0,
  meters          INTEGER NOT NULL DEFAULT 0,
  sleep_min       INTEGER NOT NULL DEFAULT 0,
  deep_sleep_min  INTEGER NOT NULL DEFAULT 0,
  light_sleep_min INTEGER NOT NULL DEFAULT 0,
  -- NULL = not measured. Never 0: the watch reports 0 for a wellness value it
  -- has not taken, and a 0 stored here would read back as a real measurement of
  -- perfect calm — the same "0 means unknown" rule the app applies at the BLE
  -- edge, kept intact all the way to the database.
  stress          SMALLINT,
  breath_rate     SMALLINT,
  met             SMALLINT,
  battery_pct     SMALLINT,
  charging        BOOLEAN NOT NULL DEFAULT FALSE,
  worn            BOOLEAN NOT NULL DEFAULT FALSE,
  CONSTRAINT sane_stress  CHECK (stress      IS NULL OR stress      BETWEEN 0 AND 100),
  CONSTRAINT sane_breath  CHECK (breath_rate IS NULL OR breath_rate BETWEEN 1 AND 80),
  CONSTRAINT sane_battery CHECK (battery_pct IS NULL OR battery_pct BETWEEN 0 AND 100),
  PRIMARY KEY (user_id, device_id, day)
);

CREATE INDEX IF NOT EXISTS idx_wearable_days_user ON wearable_days (user_id, day DESC);
