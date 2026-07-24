-- Bundle discount on shop orders.
--
-- Buying a watch and a tracker together saves 2 900 ₸ per matched pair. The
-- discount is recomputed server-side at order time and stored here, so the
-- admin sees exactly what the customer was charged (total_minor is already the
-- discounted total; this column records how much came off, for the receipt).
ALTER TABLE shop_orders
  ADD COLUMN IF NOT EXISTS discount_minor INTEGER NOT NULL DEFAULT 0 CHECK (discount_minor >= 0);
