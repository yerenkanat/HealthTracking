-- Frame 03 «Карточка заказа» — the order's own history.
--
-- Until now an order carried exactly two facts about time: when it was created,
-- and what status it happens to be in right now. Everything between them was
-- lost. «Когда его собрали?», «кто отменил заказ Айгуль и во сколько?» and
-- «сколько он простоял в „новый"» had no answer anywhere in the product —
-- audit_log records THAT the status was changed, by whom, but never to what,
-- so it cannot reconstruct a timeline either.
--
-- One row per transition, written inside the same statement that moves the
-- status. Nothing here is ever updated or deleted: a wrong step is corrected by
-- taking the next one, exactly like shop_stock_moves, so what somebody believed
-- survives beside what was true.
--
-- Rows only exist from this migration onward. The card SAYS so when an order is
-- past «новый» and has no events — an empty timeline on a delivered order would
-- otherwise read as "nothing ever happened to it", which is a lie the schema
-- cannot back out of on its own.
CREATE TABLE IF NOT EXISTS shop_order_events (
  id          BIGSERIAL PRIMARY KEY,
  order_id    UUID NOT NULL REFERENCES shop_orders(id) ON DELETE CASCADE,
  -- NULL for the first recorded transition of an order that predates this
  -- table, and for any row written where the previous status is not known.
  from_status TEXT,
  to_status   TEXT NOT NULL CHECK (to_status IN ('new','confirmed','shipped','delivered','cancelled')),
  -- TEXT, matching audit_log.staff_id: entries written by an account since
  -- removed must stay readable, so no foreign key.
  staff_id    TEXT,
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS shop_order_events_order ON shop_order_events (order_id, at);
