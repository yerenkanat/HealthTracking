-- Поставки и поставщики — кадры 07a «Поставки» и 07g «Поставщики», плюс
-- полоса «поставки в пути» кадра 07.
--
-- ЧЕГО НЕ ХВАТАЛО. Склад умел отвечать на вопрос «что лежит на полке» и на
-- вопрос «на сколько дней хватит». Он не умел отвечать на третий, который и
-- решает, надо ли сегодня заказывать: «а что уже едет». Без него панель
-- писала «пора заказывать» рядом с товаром, который заказан две недели назад,
-- и закупщик либо заказывал второй раз, либо переставал верить плашке — оба
-- исхода стоят денег.
--
-- ЧТО ЗДЕСЬ ЕСТЬ И ЧЕГО НЕТ.
--
--   * `suppliers.lead_time_days` — СРОК, КОТОРЫЙ ЗАЯВИЛ ПОСТАВЩИК, а не срок,
--     посчитанный по истории. Ни одной пары «разместили → приняли» в базе ещё
--     нет, считать среднее не из чего, и число, выведенное из пустоты, было бы
--     хуже отсутствующего: закупщик планирует по нему деньги. Панель так его и
--     подписывает — «заявленный». Пусто → работает прежняя константа 14 дней
--     из routes/inventory.ts.
--
--   * `purchase_order_items.unit_cost_minor` NULLABLE. Себестоимость единицы
--     этот проект узнаёт ровно в один момент — когда приёмка принесла
--     `batchCostMinor` и её поделили на годные штуки. До этого закупочная цена
--     известна только если её вписали руками. Панель печатает «—», а не
--     вычисленную догадку.
--
--   * `qty_received` и `received_at` — факт, а не план. Строку закрывает
--     приёмка: сколько реально пришло и когда. Недостача не мешает закрыть
--     строку — она уже записана как претензия в истории движений, и держать
--     заказ открытым из-за двух недостающих штук значит вечно показывать их
--     «в пути».
--
-- ВАЖНО: ничто здесь не прибавляется к `shop_variants.stock`. Коробка на
-- таможне — это не полка. Запас считается по тому, что можно отгрузить
-- сегодня; прогноз, учитывающий груз в пути, обещает товар, которого нет.

-- ---------------------------------------------------------------------------
-- Кто нам возит (кадр 07g)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS suppliers (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  name           TEXT NOT NULL,
  -- Телефон, ватсап, имя менеджера — одной строкой. Отдельные колонки под
  -- каждый канал завели бы схему, в которой у половины поставщиков заполнена
  -- не та колонка.
  contact        TEXT,
  -- Заявленный срок поставки в днях. NULL = не заявлял, работаем по общей
  -- константе.
  lead_time_days INTEGER CHECK (lead_time_days IS NULL OR (lead_time_days >= 0 AND lead_time_days <= 365)),
  -- Не удаляем: у поставщика есть история заказов. Архивируем.
  active         BOOLEAN NOT NULL DEFAULT TRUE,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
-- Один поставщик — одна строка. Два «Shenzhen Ltd» с разным регистром это два
-- набора заказов, которые никто не сложит вместе.
CREATE UNIQUE INDEX IF NOT EXISTS suppliers_name_unique ON suppliers (lower(name));

-- ---------------------------------------------------------------------------
-- Заказ поставщику (кадры 07a, 07b)
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS purchase_orders (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- Поставщика могли архивировать после заказа — заказ от этого не исчезает.
  supplier_id UUID REFERENCES suppliers(id) ON DELETE SET NULL,
  -- draft     — набран, но никому не отправлен: в пути НЕ считается;
  -- placed    — размещён, едет;
  -- received  — все строки закрыты приёмкой;
  -- cancelled — отменён; в пути тоже не считается.
  status      TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','placed','received','cancelled')),
  -- Когда его разместили. NULL у черновика — и именно этой пары
  -- (placed_at, received_at строк) когда-нибудь хватит, чтобы посчитать
  -- настоящий срок поставки вместо заявленного.
  placed_at   TIMESTAMPTZ,
  -- Когда его ждут. Дата, а не отметка времени: никто не обещает груз к 14:20.
  expected_at DATE,
  note        TEXT,
  -- TEXT, как `shop_stock_moves.staff_id`: одна и та же величина в двух типах
  -- — это два способа её потерять.
  created_by  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_open ON purchase_orders (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier ON purchase_orders (supplier_id);

CREATE TABLE IF NOT EXISTS purchase_order_items (
  po_id           UUID NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  -- Цвет, а не товар: заказывают «часы чёрные 40», а не «часы 40».
  variant_id      UUID NOT NULL REFERENCES shop_variants(id) ON DELETE CASCADE,
  qty_ordered     INTEGER NOT NULL CHECK (qty_ordered > 0),
  -- NULL, пока цену никто не назвал. См. шапку файла.
  unit_cost_minor INTEGER CHECK (unit_cost_minor IS NULL OR unit_cost_minor >= 0),
  -- Сколько пришло по факту. Заполняет приёмка.
  qty_received    INTEGER NOT NULL DEFAULT 0 CHECK (qty_received >= 0),
  -- Строка закрыта приёмкой. Пока NULL — эти qty_ordered штук «в пути».
  received_at     TIMESTAMPTZ,
  PRIMARY KEY (po_id, variant_id)
);
-- «Сколько этого цвета уже едет» — вопрос, который задаёт каждый рендер склада.
CREATE INDEX IF NOT EXISTS idx_po_items_variant ON purchase_order_items (variant_id);
