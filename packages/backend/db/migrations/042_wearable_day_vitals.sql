-- The vitals a DAY of watch history carries, which had nowhere to go.
--
-- Migration 040 gave the watch's activity and wellbeing a per-day home: steps,
-- calories, distance, sleep, stress, breathing rate, MET. It was built around
-- the live snapshot, which is the only thing the app could read at the time.
--
-- The watch also stores about a week of per-minute samples on the device
-- itself, and the vendor documents a command per metric to read them back
-- (UniappSDKDocumentation.md §5.44–5.53, §5.58). Those days carry heart rate,
-- SpO2, blood pressure, temperature and blood sugar as well — and of those five,
-- not one had a column here. A backfill could restore how much she walked last
-- Tuesday and had to throw away what her heart was doing while she did it.
--
-- Averages, plus the extremes that a mean cannot express. A day whose mean
-- heart rate is 78 and whose maximum is 165 is not the same day as one that
-- never left 80, and «среднее 78» alone cannot tell a clinician which she had.
-- The minimum matters on the other side: an SpO2 that averaged 97 and touched
-- 88 is the reading worth a phone call.
--
-- NULL = not measured, exactly as in 040. The device writes 0xFF into a slot it
-- did not measure; the app turns that into "no reading" and it must arrive here
-- as NULL, because a stored 0 reads back as a heart that stopped.
ALTER TABLE wearable_days
  ADD COLUMN IF NOT EXISTS hr_avg            SMALLINT,
  ADD COLUMN IF NOT EXISTS hr_min            SMALLINT,
  ADD COLUMN IF NOT EXISTS hr_max            SMALLINT,
  ADD COLUMN IF NOT EXISTS spo2_avg          SMALLINT,
  ADD COLUMN IF NOT EXISTS spo2_min          SMALLINT,
  ADD COLUMN IF NOT EXISTS systolic_avg      SMALLINT,
  ADD COLUMN IF NOT EXISTS diastolic_avg     SMALLINT,
  -- Tenths of a degree Celsius (365 = 36.5 °C), the device's own unit, so
  -- nothing rounds twice between the wrist and the clinician's screen.
  ADD COLUMN IF NOT EXISTS temp_avg_tenths   SMALLINT,
  -- Tenths of a mmol/L. A watch-optical estimate, never a diagnosis.
  ADD COLUMN IF NOT EXISTS blood_sugar_tenths SMALLINT;

-- Ranges wide enough for a real emergency and narrow enough to reject a
-- decoding bug. These are the same shape as 040's sane_* constraints: the point
-- is that a byte read at the wrong offset lands outside human physiology and is
-- refused at the door, rather than being drawn on a chart as a fact.
ALTER TABLE wearable_days
  DROP CONSTRAINT IF EXISTS sane_hr,
  DROP CONSTRAINT IF EXISTS sane_spo2,
  DROP CONSTRAINT IF EXISTS sane_bp,
  DROP CONSTRAINT IF EXISTS sane_temp_day,
  DROP CONSTRAINT IF EXISTS sane_sugar_day;

ALTER TABLE wearable_days
  ADD CONSTRAINT sane_hr CHECK (
    (hr_avg IS NULL OR hr_avg BETWEEN 20 AND 250) AND
    (hr_min IS NULL OR hr_min BETWEEN 20 AND 250) AND
    (hr_max IS NULL OR hr_max BETWEEN 20 AND 250)),
  ADD CONSTRAINT sane_spo2 CHECK (
    (spo2_avg IS NULL OR spo2_avg BETWEEN 50 AND 100) AND
    (spo2_min IS NULL OR spo2_min BETWEEN 50 AND 100)),
  ADD CONSTRAINT sane_bp CHECK (
    (systolic_avg  IS NULL OR systolic_avg  BETWEEN 50 AND 260) AND
    (diastolic_avg IS NULL OR diastolic_avg BETWEEN 30 AND 200)),
  -- 30.0 – 45.0 °C. Anything outside is a parse error, not a fever.
  ADD CONSTRAINT sane_temp_day CHECK (
    temp_avg_tenths IS NULL OR temp_avg_tenths BETWEEN 300 AND 450),
  -- 1.0 – 30.0 mmol/L.
  ADD CONSTRAINT sane_sugar_day CHECK (
    blood_sugar_tenths IS NULL OR blood_sugar_tenths BETWEEN 10 AND 300);
