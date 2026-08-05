-- Correct the combo's price and name to what the landing actually sells.
--
-- Migration 021 created it at 27 900 ₸ under the name "Комплект: часы + брелок".
-- Both were invented. The landing sells «Комплект «Мама и ребёнок» — 39 000 ₸»,
-- and has since launch.
--
-- The difference is not a discount, and reading it as one is what produced the
-- wrong number: the combo is the two devices PLUS the Ма!Ма! course, which the
-- page presents as a 40 000 ₸ gift. So it costs MORE than the hardware sum
-- (24 900 + 4 900 = 29 800), not less — a bundle here is an upsell carrying
-- content, not a volume deal.
--
-- That is also why buying it unlocks the lessons in the app: the course IS what
-- the extra 9 200 ₸ buys.
UPDATE shop_products
   SET price_minor = 3900000,
       name        = 'Комплект «Мама и ребёнок»'
 WHERE id = 'combo';
