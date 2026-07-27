-- Reprice the smart watch to 29 000 ₸ (the mom-focused S5 model). The child
-- tracker stays 9 900 ₸, so the family bundle is now 29 000 + 9 900 − 2 900 =
-- 36 000 ₸. Orders already placed keep their snapshotted unit price.
UPDATE shop_products SET price_minor = 2900000 WHERE id = 'watch';
