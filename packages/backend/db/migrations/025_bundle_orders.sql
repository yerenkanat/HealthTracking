-- Selling the bundle, and letting the sale grant what it promises.
--
-- Until now a bundle could be priced and counted but not bought: order lines
-- reference a colour variant, and a bundle has no colours of its own. So the
-- combo existed in the back office and nowhere a customer could reach.
--
-- The shape that works: a combo order is still its PARTS as line items — she
-- picks a watch colour and a tracker colour, and stock comes off both — plus a
-- note on the order saying it was sold as a bundle. That keeps one truth about
-- what left the warehouse while letting the price and the entitlement follow
-- the bundle.
--
-- This distinction is the whole reason the bundle exists: two devices bought
-- separately cost 29 800 and are NOT the комплект. The комплект is 39 000 and
-- includes the Ма!Ма! course. If buying the parts unlocked the course, nobody
-- would ever buy the bundle.

ALTER TABLE shop_orders ADD COLUMN IF NOT EXISTS bundle_id TEXT
  REFERENCES shop_products(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS shop_orders_bundle ON shop_orders (bundle_id);

-- What a product unlocks in the app when its order is fulfilled.
--
-- On the product rather than hardcoded against the id 'combo': a second bundle
-- carrying a second course should be a row, not a branch in the code.
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS grants_feature TEXT;

UPDATE shop_products SET grants_feature = 'mama_course' WHERE id = 'combo';
