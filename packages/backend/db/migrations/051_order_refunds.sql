-- 051 · Кадр 05a «Возвраты и брак» — the write side.
--
-- An operator who takes a delivered комплект back from a mother had nowhere to
-- record it. The only writer of a reason='return' stock move was order
-- CANCELLATION (setShopOrderStatus), so staff either wrote the unit off —
-- destroying stock and inflating «Списано на сумму» — or did nothing, and the
-- refunded money stayed in earnedMinor for ever.
--
-- WHAT THIS TABLE DOES NOT RECORD, deliberately:
--
--  · WHERE the money went back to (Kaspi / наличные). shop_orders has never
--    stored a payment method, so a destination column here could only ever be
--    filled in by guessing. The panel says the destination is not stored.
--  · Anything about refunds that predate this migration. There are none: no
--    refund could be recorded before this table existed. Return moves older
--    than this are cancellations, and they keep refund_id NULL rather than
--    being backfilled with an invented reason.
CREATE TABLE IF NOT EXISTS shop_order_refunds (
  id           BIGSERIAL PRIMARY KEY,
  order_id     UUID NOT NULL REFERENCES shop_orders(id) ON DELETE CASCADE,
  -- Minor units, and strictly positive: a refund of nothing is not an event,
  -- and a negative one is a sale wearing the wrong word.
  amount_minor INTEGER NOT NULL CHECK (amount_minor > 0),
  reason       TEXT NOT NULL CHECK (reason IN ('defect','not_suitable','changed_mind','not_delivered','other')),
  note         TEXT,
  -- TEXT, as shop_order_events.staff_id and audit_log.staff_id: a refund booked
  -- by an account since removed must stay readable, so no foreign key.
  staff_id     TEXT,
  at           TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- The order card reads one order's refunds, newest first.
CREATE INDEX IF NOT EXISTS shop_order_refunds_order ON shop_order_refunds (order_id, at DESC);
-- Frame 05 reads a period.
CREATE INDEX IF NOT EXISTS shop_order_refunds_at ON shop_order_refunds (at DESC);

-- Which return moves are a REFUND, and which are a cancellation putting goods
-- back on the shelf.
--
-- Both are reason='return' with an order_id, and «Возвратов, шт» / «Доля
-- возвратов, %» counted them together — over orders that were never in revenue
-- in the first place. That is the number frame 05 printed wrongly. NULL means
-- "not part of a refund", which is true of every row written before today.
ALTER TABLE shop_stock_moves
  ADD COLUMN IF NOT EXISTS refund_id BIGINT REFERENCES shop_order_refunds(id) ON DELETE SET NULL;
CREATE INDEX IF NOT EXISTS shop_stock_moves_refund ON shop_stock_moves (refund_id);
