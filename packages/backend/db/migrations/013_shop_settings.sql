-- Store settings edited from the admin panel: the WhatsApp order number, the
-- Kaspi checkout link, and any other keys the operator adds later. A flat
-- key→value store so new settings need no schema change. The public /shop/config
-- endpoint exposes only a whitelist (contact/links) — never secrets.
CREATE TABLE IF NOT EXISTS shop_settings (
  key        TEXT PRIMARY KEY,
  value      TEXT NOT NULL DEFAULT '',
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
