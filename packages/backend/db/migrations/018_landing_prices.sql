-- Bring the shop data in line with the Ana-Bala landing page, which is now the
-- site root and the only place prices are advertised.
--
-- The landing sells: часы 24 900 ₸ · брелок 4 900 ₸ · комплект 39 000 ₸.
-- shop_products still carried the previous generation's numbers (29 000 / 9 900),
-- so the same watch had two prices on one domain — the storefront API and the
-- admin order list disagreed with the page the customer actually read.
--
-- The комплект is deliberately NOT modelled here. On the landing it is
-- hardware plus the Ма!Ма! course (a 40 000 ₸ gift), not a hardware discount, and
-- there is no course product in this schema. Buying both devices through the
-- shop API therefore costs 24 900 + 4 900 = 29 800 ₸, exactly the landing's
-- à-la-carte sum — see BUNDLE_DISCOUNT_MINOR in src/db/repository.ts, now 0.
UPDATE shop_products SET price_minor = 2490000 WHERE id = 'watch';
UPDATE shop_products SET price_minor =  490000 WHERE id = 'tracker';
