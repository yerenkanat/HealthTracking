-- A photo an operator UPLOADS, rather than a link she is asked to find.
--
-- The product card has carried a «Ссылка на фото» field: paste a URL. That
-- asks a person selling watches to first host an image somewhere and then
-- know its address — and it puts the storefront's photos on somebody else's
-- server, where they rot, hotlink-block, or turn into something nobody
-- intended. Nothing in this product uploaded an image; the only pictures it
-- has ever shown are seven watch JPEGs committed to the repository by hand.
--
-- Bytes in Postgres, exactly like `daily_audio` two tables up. The same
-- reasoning applies: this is a handful of files measured in megabytes, one
-- database is one thing to back up, and an object store is a dependency this
-- deployment does not have.
--
-- `color` is nullable and part of the key. A product has one photo; a product
-- in Розовое золото has its own. Nullable rather than a second table because
-- the storefront already sells by colour (`shop_variants`) and the panel
-- already lists them — a schema that could not hold a per-colour photo would
-- have to be migrated again the first time somebody uploaded one.
CREATE TABLE IF NOT EXISTS shop_product_photos (
  product_id  TEXT NOT NULL REFERENCES shop_products(id) ON DELETE CASCADE,
  -- '' rather than NULL so it can sit in a primary key: Postgres treats NULLs
  -- as distinct, which would let the same product accumulate a photo per
  -- upload instead of replacing one.
  color       TEXT NOT NULL DEFAULT '',
  mime        TEXT NOT NULL CHECK (mime IN ('image/jpeg','image/png','image/webp')),
  bytes       BYTEA NOT NULL,
  -- Big enough for a real product photo, small enough that nobody uploads a
  -- 40 MP original and makes the storefront unusable on a Kazakh mobile
  -- connection. Enforced here as well as in the route, because a check in one
  -- place is a check somebody can route around.
  CONSTRAINT photo_not_empty CHECK (octet_length(bytes) > 0),
  CONSTRAINT photo_not_huge  CHECK (octet_length(bytes) <= 3 * 1024 * 1024),
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  uploaded_by UUID REFERENCES staff_accounts(id) ON DELETE SET NULL,
  PRIMARY KEY (product_id, color)
);

-- The storefront asks «which products have a photo» on every render, and the
-- panel asks the same to draw its thumbnails. Neither wants the bytes.
CREATE INDEX IF NOT EXISTS idx_product_photos_product ON shop_product_photos(product_id);
