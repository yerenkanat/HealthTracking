-- A real stock ledger, a bundle product, and the numbers a warehouse needs.
--
-- What existed: shop_products (name, price) and shop_variants (colour, stock).
-- Stock was a bare integer. Nothing recorded WHY it changed — a delivery of
-- fifty watches, a sale, a breakage and a typo were all the same event, which
-- is "the number is different now". You could not answer "we counted forty and
-- the system says thirty-seven, what happened", which is the question stock
-- control exists to answer.
--
-- Three gaps, in the order they cost money:
--
--  1. No ledger. Corrections were invisible and unattributable.
--  2. No bundle. The landing sells часы+брелок as one item at its own price,
--     and the back office had no such product — so a combo could not be priced,
--     counted, or stopped from overselling either half.
--  3. No reorder signal. Running out is discovered by a customer.

-- ---------------------------------------------------------------------------
-- Products: the things a warehouse actually tracks
-- ---------------------------------------------------------------------------

-- What goes on a box, an invoice and a courier's manifest. Nullable because the
-- two existing products have never had one and inventing codes for them here
-- would put guesses in a column people will read as authoritative.
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS sku TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS shop_products_sku_unique
  ON shop_products (sku) WHERE sku IS NOT NULL;

-- What we pay. Margin is unknowable without it, and "are we making money on the
-- combo" is exactly the question a bundle price raises.
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS cost_minor INTEGER
  CHECK (cost_minor IS NULL OR cost_minor >= 0);

-- 'simple' is stocked in its own right; 'bundle' has no stock of its own and
-- derives it from its parts (see shop_bundle_items). A bundle that carried its
-- own count would drift from the parts it is made of within a week.
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS kind TEXT NOT NULL DEFAULT 'simple'
  CHECK (kind IN ('simple', 'bundle'));

-- Below this, the panel says so. Per product rather than global: one tracker
-- left is a different problem from one watch left.
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS low_stock_threshold INTEGER NOT NULL DEFAULT 3
  CHECK (low_stock_threshold >= 0);

-- ---------------------------------------------------------------------------
-- Bundles: what a combo is made of
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS shop_bundle_items (
  bundle_id  TEXT NOT NULL REFERENCES shop_products(id) ON DELETE CASCADE,
  part_id    TEXT NOT NULL REFERENCES shop_products(id) ON DELETE RESTRICT,
  qty        INTEGER NOT NULL DEFAULT 1 CHECK (qty > 0),
  PRIMARY KEY (bundle_id, part_id),
  -- A bundle containing itself would make its available stock unanswerable.
  CHECK (bundle_id <> part_id)
);

-- ---------------------------------------------------------------------------
-- The ledger
-- ---------------------------------------------------------------------------
--
-- Every change to a variant's stock, with its reason and its author. The
-- variant's `stock` column stays as the running total — reading it is on every
-- storefront request and summing a ledger there would be wasteful — but it is
-- now a cache of this table rather than the only record.
--
-- Rows are never updated or deleted. A miscount is corrected by another row, so
-- the history of what somebody believed is preserved alongside what was true.
CREATE TABLE IF NOT EXISTS shop_stock_moves (
  id          BIGSERIAL PRIMARY KEY,
  variant_id  UUID NOT NULL REFERENCES shop_variants(id) ON DELETE CASCADE,
  -- Signed: +50 received, -1 sold, -2 written off, +2 a correction upward.
  -- Signed rather than a quantity plus a direction, so the ledger sums to the
  -- stock level with no case analysis and no chance of the two disagreeing.
  delta       INTEGER NOT NULL CHECK (delta <> 0),
  reason      TEXT NOT NULL CHECK (reason IN (
                'receipt',      -- a delivery arrived
                'sale',         -- an order took it
                'return',       -- a customer sent it back
                'writeoff',     -- damaged, lost, given away
                'correction'    -- a stocktake disagreed with the system
              )),
  -- Free text: the invoice number, the courier, what broke. Optional, because
  -- forcing a note produces "." rather than information.
  note        TEXT,
  -- Who did it. Null for automatic moves (an order decrementing stock).
  staff_id    TEXT,
  -- The order this belongs to, when it is a sale or a return.
  order_id    UUID REFERENCES shop_orders(id) ON DELETE SET NULL,
  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS shop_stock_moves_variant_at
  ON shop_stock_moves (variant_id, at DESC);
CREATE INDEX IF NOT EXISTS shop_stock_moves_at ON shop_stock_moves (at DESC);
CREATE INDEX IF NOT EXISTS shop_stock_moves_order ON shop_stock_moves (order_id);

-- ---------------------------------------------------------------------------
-- The combo the landing already sells
-- ---------------------------------------------------------------------------
--
-- The price the landing shows. NOT a discount: this is the two devices plus
-- the Ма!Ма! course, presented on the page as a 40 000 ₸ gift, so it costs more
-- than the hardware sum (24 900 + 4 900). Corrected in 022 after 021 shipped an
-- invented 27 900.
INSERT INTO shop_products (id, name, price_minor, kind, active, sort)
VALUES ('combo', 'Комплект «Мама и ребёнок»', 3900000, 'bundle', TRUE, 3)
ON CONFLICT (id) DO NOTHING;

INSERT INTO shop_bundle_items (bundle_id, part_id, qty) VALUES
  ('combo', 'watch', 1),
  ('combo', 'tracker', 1)
ON CONFLICT DO NOTHING;

-- ---------------------------------------------------------------------------
-- Opening balances
-- ---------------------------------------------------------------------------
--
-- Whatever each variant currently says becomes an explicit 'correction' row, so
-- the ledger sums to the same number the storefront shows from day one. Without
-- this the two would disagree by exactly the stock on hand at migration time,
-- and the first person to compare them would rightly stop trusting both.
INSERT INTO shop_stock_moves (variant_id, delta, reason, note)
SELECT id, stock, 'correction', 'opening balance at migration 021'
FROM shop_variants
WHERE stock <> 0;
