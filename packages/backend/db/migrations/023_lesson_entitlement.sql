-- Who is entitled to the Ма!Ма! course.
--
-- The landing sells «Комплект «Мама и ребёнок»» at 39 000 ₸: two devices plus
-- the course, which the page values at 40 000 ₸ as a gift. The course is what
-- the 9 200 ₸ above the hardware price buys, so buying the combo is what
-- unlocks the lessons in the app.
--
-- The link between an order and an account is the PHONE. An order captures it
-- at checkout and the app now signs in with it (migration 020), so the same
-- eleven digits identify the same person on both sides. No new identifier and
-- nothing for the customer to do — she does not know she has an account id.
--
-- Stored as a column rather than derived on every request because a phone can
-- be edited on an order, and an entitlement that silently disappears when
-- somebody fixes a typo is worse than one that has to be re-granted on purpose.

-- Normalised at write time, matching http/staffAuth.ts normalizePhone: digits
-- only, 8xxxxxxxxxx and 7xxxxxxxxxx both becoming 77xxxxxxxxx. An order taken
-- over the phone gets typed however the person typing feels, and "+7 707…" must
-- match "8707…" or the entitlement is a lottery.
ALTER TABLE shop_orders ADD COLUMN IF NOT EXISTS phone_normalized TEXT;
CREATE INDEX IF NOT EXISTS shop_orders_phone_normalized
  ON shop_orders (phone_normalized);

-- Backfill: digits only, then the same 8→7 and 10→11 rules.
UPDATE shop_orders
   SET phone_normalized = CASE
     WHEN length(regexp_replace(phone, '\D', '', 'g')) = 11
          AND left(regexp_replace(phone, '\D', '', 'g'), 1) = '8'
       THEN '7' || substr(regexp_replace(phone, '\D', '', 'g'), 2)
     WHEN length(regexp_replace(phone, '\D', '', 'g')) = 10
       THEN '7' || regexp_replace(phone, '\D', '', 'g')
     ELSE regexp_replace(phone, '\D', '', 'g')
   END
 WHERE phone_normalized IS NULL;

-- What a person is entitled to, and why.
--
-- A row here is granted by a paid order and can also be granted by hand — a
-- refund, a promise made on the phone, a course sold on its own later. The
-- source is recorded so an unexplained entitlement can be traced rather than
-- guessed at.
CREATE TABLE IF NOT EXISTS user_entitlements (
  phone      TEXT NOT NULL,          -- normalised; the account may not exist yet
  feature    TEXT NOT NULL,          -- 'mama_course' today
  order_id   UUID REFERENCES shop_orders(id) ON DELETE SET NULL,
  granted_by TEXT,                   -- staff id, or null when an order granted it
  note       TEXT,
  at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (phone, feature)
);

CREATE INDEX IF NOT EXISTS user_entitlements_feature ON user_entitlements (feature);

-- Entitlements for combos already delivered.
--
-- 'delivered' and 'shipped' only: a 'new' order is a promise, and unlocking a
-- 40 000 ₸ course on the strength of an unpaid cash-on-delivery order that may
-- never be collected would be giving it away.
INSERT INTO user_entitlements (phone, feature, order_id, note)
SELECT DISTINCT ON (o.phone_normalized)
       o.phone_normalized, 'mama_course', o.id, 'backfill at migration 023'
  FROM shop_orders o
  JOIN shop_order_items i ON i.order_id = o.id
 WHERE o.status IN ('shipped', 'delivered')
   AND o.phone_normalized IS NOT NULL
   AND i.product_name ILIKE '%комплект%'
 ORDER BY o.phone_normalized, o.created_at
ON CONFLICT (phone, feature) DO NOTHING;
