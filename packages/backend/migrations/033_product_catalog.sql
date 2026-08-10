-- Frame 08 / 08a — «Товары» and «Карточка товара».
--
-- shop_products has carried id, name, price, sku, cost and stock rules since
-- the shop existed, and nothing else the catalogue screen asks for: no
-- category, no mother-stage, no Kazakh, no child age range, no photo, no SEO.
--
-- The stage column is the important one. app/lib/domain/shop_stage.dart says it
-- outright: «There is no stage field on a product and inventing one would be
-- fabrication, so the recommendation is DERIVED from what the app already
-- knows». So «Для вашего этапа» in the shop is a heuristic over her pregnancy
-- flag and her children's ages, and nobody can correct it without editing Dart.
-- This makes it data an operator owns.
--
-- Everything is nullable. A product that predates this migration is not
-- mis-categorised by it — it is uncategorised, which the panel shows as «не
-- указан» and can be filtered on, so the work left to do is visible instead of
-- being papered over by a default.

ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS category TEXT;

-- Which stage of motherhood the product is FOR. Deliberately coarse: these are
-- the states the app can already tell apart, and a vocabulary finer than that
-- would be unfillable. 'any' is a real answer, not a missing one.
ALTER TABLE shop_products DROP CONSTRAINT IF EXISTS shop_products_stage_check;
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS stage TEXT;
ALTER TABLE shop_products ADD CONSTRAINT shop_products_stage_check
  CHECK (stage IS NULL OR stage IN ('planning','pregnancy','newborn','infant','toddler','any'));

-- Bilingual. «Двуязычность блокирует публикацию» — the panel refuses to
-- activate a product without the Kazakh name, the same rule the content
-- editor already applies to lessons.
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS name_kk        TEXT;
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS description_ru TEXT;
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS description_kk TEXT;

-- Персонализация: the child age band this suits, in months. Both nullable and
-- independent — «от 0» and «до 36» are each meaningful alone.
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS age_min_months INTEGER
  CHECK (age_min_months IS NULL OR (age_min_months >= 0 AND age_min_months <= 216));
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS age_max_months INTEGER
  CHECK (age_max_months IS NULL OR (age_max_months >= 0 AND age_max_months <= 216));
-- A band that ends before it starts would silently match nobody.
ALTER TABLE shop_products DROP CONSTRAINT IF EXISTS shop_products_age_band_check;
ALTER TABLE shop_products ADD CONSTRAINT shop_products_age_band_check
  CHECK (age_min_months IS NULL OR age_max_months IS NULL OR age_min_months <= age_max_months);

ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS photo_url TEXT;

-- SEO. slug is unique where present, because two products answering the same
-- URL is a bug that only shows up in production.
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS seo_slug        TEXT;
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS seo_title       TEXT;
ALTER TABLE shop_products ADD COLUMN IF NOT EXISTS seo_description TEXT;
CREATE UNIQUE INDEX IF NOT EXISTS shop_products_seo_slug_unique
  ON shop_products (seo_slug) WHERE seo_slug IS NOT NULL;

-- The catalogue screen filters by category and by stage on every load.
CREATE INDEX IF NOT EXISTS idx_shop_products_category ON shop_products (category);
CREATE INDEX IF NOT EXISTS idx_shop_products_stage    ON shop_products (stage);

-- Categories as a table rather than free text on the product: frame 08b edits
-- them as their own list, with an order the storefront follows, and free text
-- gives «Часы», «часы» and «Чacы» inside a month.
CREATE TABLE IF NOT EXISTS shop_categories (
  id       TEXT PRIMARY KEY,
  name_ru  TEXT NOT NULL,
  name_kk  TEXT,
  sort     INTEGER NOT NULL DEFAULT 0
);

-- Seeded from what is actually being sold today, so the screen is not empty on
-- first open. ON CONFLICT DO NOTHING: re-running must not undo an operator's
-- renames.
INSERT INTO shop_categories (id, name_ru, name_kk, sort) VALUES
  ('watch',   'Смарт-часы',        'Смарт-сағат',      10),
  ('tracker', 'Детские трекеры',   'Балалар трекері',  20),
  ('bundle',  'Комплекты',         'Жинақтар',         30),
  ('other',   'Прочее',            'Басқа',            90)
ON CONFLICT (id) DO NOTHING;
