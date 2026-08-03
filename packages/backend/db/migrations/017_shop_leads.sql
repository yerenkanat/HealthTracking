-- Callback requests from the Ana-Bala landing page ("оставьте номер — перезвоним").
--
-- The landing offers two ways to buy: WhatsApp (leaves no trace here) and this
-- short form — name, phone, which bundle. It is NOT an order: there is no
-- address, no variant and no stock to reserve, so it cannot go through
-- shop_orders. Staff call the number back and place the real order themselves.
--
-- Status mirrors the shop_orders vocabulary in spirit but is deliberately its
-- own small set: a lead is either untouched, already called, converted into an
-- order, or dead.
CREATE TABLE IF NOT EXISTS shop_leads (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  customer_name TEXT NOT NULL,
  phone         TEXT NOT NULL,
  -- The bundle the visitor picked, as the label shown on the page ("Комплект
  -- «Мама и ребёнок» — 25 900 ₸"). Free text on purpose: the landing's packages
  -- are marketing copy, not shop_products rows, and the label is what the
  -- person actually saw.
  package       TEXT NOT NULL DEFAULT '',
  -- Which language the landing was in when they submitted — staff should call
  -- back in that language.
  locale        TEXT NOT NULL DEFAULT 'ru' CHECK (locale IN ('ru','kz')),
  status        TEXT NOT NULL DEFAULT 'new' CHECK (status IN ('new','called','ordered','dropped')),
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_shop_leads_created ON shop_leads (created_at DESC);
