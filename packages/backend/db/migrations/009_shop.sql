-- =============================================================================
-- 009 — Shop: products, per-colour variants (with stock), and COD orders
--
-- The device store: smart watch (19 900 ₸) + child tracker (9 900 ₸), each in
-- several colours whose stock is managed from the admin panel. Customers order
-- with a delivery address (cash on delivery); an order decrements the variant's
-- stock atomically. Idempotent — safe to run repeatedly.
--
--   psql "$DATABASE_URL" -f db/migrations/009_shop.sql
-- =============================================================================

CREATE TABLE IF NOT EXISTS shop_products (
  id          TEXT PRIMARY KEY,               -- slug: 'watch', 'tracker'
  name        TEXT NOT NULL,
  price_minor INTEGER NOT NULL CHECK (price_minor >= 0),  -- ₸ ×100 (1990000 = 19 900 ₸)
  active      BOOLEAN NOT NULL DEFAULT TRUE,
  sort        INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS shop_variants (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  product_id TEXT NOT NULL REFERENCES shop_products(id) ON DELETE CASCADE,
  color      TEXT NOT NULL,
  color_hex  TEXT NOT NULL,                   -- '#1C1E2A' — for the swatch
  stock      INTEGER NOT NULL DEFAULT 0 CHECK (stock >= 0),
  sort       INTEGER NOT NULL DEFAULT 0,
  UNIQUE (product_id, color)
);

CREATE TABLE IF NOT EXISTS shop_orders (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_name TEXT NOT NULL,
  phone         TEXT NOT NULL,
  city          TEXT NOT NULL,
  address       TEXT NOT NULL,
  note          TEXT,
  total_minor   INTEGER NOT NULL CHECK (total_minor >= 0),
  status        TEXT NOT NULL DEFAULT 'new'
                CHECK (status IN ('new','confirmed','shipped','delivered','cancelled')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_shop_orders_created ON shop_orders (created_at DESC);

CREATE TABLE IF NOT EXISTS shop_order_items (
  order_id         UUID NOT NULL REFERENCES shop_orders(id) ON DELETE CASCADE,
  variant_id       UUID NOT NULL REFERENCES shop_variants(id),
  product_name     TEXT NOT NULL,             -- snapshot at purchase time
  color            TEXT NOT NULL,             -- snapshot
  qty              INTEGER NOT NULL CHECK (qty > 0),
  unit_price_minor INTEGER NOT NULL CHECK (unit_price_minor >= 0)
);
CREATE INDEX IF NOT EXISTS idx_shop_items_order ON shop_order_items (order_id);

-- Seed the two products + a starter set of colours (stock starts at 0; set real
-- counts in the admin panel). Idempotent.
INSERT INTO shop_products (id, name, price_minor, sort) VALUES
  ('watch',   'Смарт-часы Umay',     1990000, 1),
  ('tracker', 'Детский трекер Umay',  990000, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO shop_variants (product_id, color, color_hex, sort) VALUES
  ('watch',   'Чёрный',         '#1C1E2A', 1),
  ('watch',   'Розовое золото', '#E8B4A0', 2),
  ('watch',   'Сиреневый',      '#B9A8F0', 3),
  ('tracker', 'Бирюзовый',      '#12B3A6', 1),
  ('tracker', 'Синий',          '#3B82F6', 2),
  ('tracker', 'Розовый',        '#E85C8A', 3)
ON CONFLICT (product_id, color) DO NOTHING;
