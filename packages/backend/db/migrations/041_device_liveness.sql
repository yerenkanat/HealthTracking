-- Frame 11 «Устройства»: whether a watch is talking to us at all.
--
-- Two separate holes, both verified before this ran.
--
-- 1. adminDevices() has always SELECTed battery_pct and last_seen, and NOTHING
--    in the codebase ever wrote either one. There is no `UPDATE devices SET
--    last_seen` anywhere. So the fleet view printed a battery that never moved
--    and a «последний сигнал» that was NULL for every row ever created — an
--    operator supporting a mother whose watch is misbehaving could not tell a
--    flat battery from a device that has never once reported. The columns are
--    declared in db/schema.sql but were never in a migration, so a database
--    upgraded rather than rebuilt may not have them at all: hence IF NOT
--    EXISTS on all three, which is a no-op on a box that already drifted.
--
-- 2. `firmware` was declared and never SELECTed, so «прошивка» could not be
--    shown. It is stamped from the ingest payload when the device reports it,
--    and shown as «не сообщалась» when it does not — never as a dash, which
--    reads as "none".
--
-- last_seen is stamped at INGEST, not from the reading's own recordedAt: the
-- question the column answers is «когда данные от устройства дошли до нас»,
-- and a phone draining a three-day offline queue IS talking to us now. The
-- panel states that rule under the table.
ALTER TABLE devices ADD COLUMN IF NOT EXISTS battery_pct INT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS last_seen   TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS firmware    TEXT;

-- The fleet list orders by it and the online counters filter on it.
CREATE INDEX IF NOT EXISTS idx_devices_last_seen ON devices (last_seen DESC NULLS LAST);

-- «Пометить браком» — frame 11's own action.
--
-- Deliberately NOT device_registry.status. That table is about a unit in the
-- warehouse (received / activated / blocked, keyed by serial), and blocking a
-- serial stops it pairing with any account — a different decision with a
-- different consequence, which frame 07's «Заблокировать» already covers. This
-- is a support note on ONE mother's paired device: her watch is faulty. It
-- changes nothing about how the device works, which is exactly why it is
-- recorded here and said out loud in the UI.
--
-- Nullable and reversible: the commonest reason to mark something is a mistake.
ALTER TABLE devices ADD COLUMN IF NOT EXISTS defect_at   TIMESTAMPTZ;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS defect_by   TEXT;
ALTER TABLE devices ADD COLUMN IF NOT EXISTS defect_note TEXT;
