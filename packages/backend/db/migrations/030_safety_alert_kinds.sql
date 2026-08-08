-- The alert kinds the app actually sends.
--
-- safety_alerts.kind was CHECK IN ('entered','left') while the app's AlertKind
-- has five: entered, left, checkIn, sos, lowBattery. So an SOS press, a
-- check-in and a low-battery warning were all refused by the constraint the
-- moment recordAlert tried to store one — and the alerts screen filters by
-- exactly those kinds.
--
-- The same table carries a partial index `idx_safety_alerts_sos ... WHERE kind
-- = 'sos'`, and both the dashboard's `sosAllTime` and the admin safety feed
-- count `kind = 'sos'`. An index and two queries over rows the table would not
-- accept: every SOS counter in this system has been structurally zero, which
-- reads as "no child has ever pressed the button".
--
-- Widened rather than dropped. The constraint is what stops a typo becoming a
-- sixth kind that no screen filters for and nobody ever sees.

ALTER TABLE safety_alerts DROP CONSTRAINT IF EXISTS safety_alerts_kind_check;

ALTER TABLE safety_alerts
  ADD CONSTRAINT safety_alerts_kind_check
  CHECK (kind IN ('entered', 'left', 'checkIn', 'sos', 'lowBattery'));

-- The feed and the day's history are read per child and per day; the existing
-- indexes lead with user_id or with `at` alone.
CREATE INDEX IF NOT EXISTS idx_safety_alerts_child_at
  ON safety_alerts (child_id, at DESC);
