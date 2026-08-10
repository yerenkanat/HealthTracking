-- Frame 48 — «Чем закончилось».
--
-- A mother opens the alarm the next morning to close it: to say what it was, so
-- the next one means something. The four chips have existed in the app and the
-- four keys in SOS_OUTCOMES since they were written, and there was nowhere to
-- put the answer — the screen could not offer the section at all.
--
-- Nullable with no default: null means "nobody has closed this yet", which is a
-- different thing from 'unknown' ("we tried to find out and could not"). A
-- default would erase that distinction on every historical row.
ALTER TABLE safety_alerts ADD COLUMN IF NOT EXISTS outcome text;

-- The same four keys the app sends and the API validates. Stated here too so a
-- direct write cannot put a fifth value in a column the app switches on.
ALTER TABLE safety_alerts DROP CONSTRAINT IF EXISTS safety_alerts_outcome_check;
ALTER TABLE safety_alerts ADD CONSTRAINT safety_alerts_outcome_check
  CHECK (outcome IS NULL OR outcome IN ('false_press', 'scared', 'needed_help', 'unknown'));

-- The write is keyed on (user, child, at) because that triple is what the client
-- has: the alert feed carries no id. Partial, because only an SOS is ever
-- closed — a zone crossing has no outcome to record.
CREATE INDEX IF NOT EXISTS idx_safety_alerts_sos_at
  ON safety_alerts (user_id, child_id, at) WHERE kind = 'sos';
