-- Which devices are OURS.
--
-- The same watches and tags are sold on other marketplaces. Until now pairing
-- asked one question — "is this device already registered to somebody else?" —
-- so any compatible unit from any seller worked with the app, the backend, the
-- tracking and the course. The hardware is generic; the service is the product,
-- and the service was being given away with somebody else's box.
--
-- The key is the BLE MAC the app already sends as the device id: burned into
-- the chip at the factory, unique per unit, and nothing the customer types.
--
-- WHAT THIS IS NOT: it is not DRM. A technical person can spoof a MAC and pair.
-- It stops the ordinary marketplace buyer, which is the case that costs sales,
-- and it is honest about stopping nothing else.

CREATE TABLE IF NOT EXISTS device_registry (
  -- Normalised: uppercase, separators stripped. A MAC is written six different
  -- ways depending on who printed the label, and a registry that misses a unit
  -- because it was typed with dashes is worse than no registry — it refuses a
  -- real customer.
  serial       TEXT PRIMARY KEY,

  -- stock   — ours, received, not yet paired
  -- sold    — paired to an account (activated_by_phone says which)
  -- blocked — stolen, returned, or replaced under warranty. Never pairs again.
  status       TEXT NOT NULL DEFAULT 'stock'
               CHECK (status IN ('stock', 'sold', 'blocked')),

  -- What kind, so the panel can tell a watch from a tag without pairing it.
  kind         TEXT CHECK (kind IN ('band', 'tag')),

  -- The code printed on the box, for units whose serial nobody captured and
  -- for warranty replacements. The FALLBACK path, deliberately: a code can be
  -- photographed and posted in a group chat, a MAC cannot be guessed.
  --
  -- Stored in plain text, unlike a password: it is printed on the outside of a
  -- box that customers hold, so it is not a secret to us — and support has to
  -- be able to read it back to somebody on the phone. What protects it is being
  -- single-use and bound to the first account that redeems it.
  activation_code TEXT,

  -- Provenance, for the warranty conversation nobody can currently have.
  order_id     UUID,
  received_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  activated_by_phone TEXT,
  activated_at TIMESTAMPTZ,
  note         TEXT,
  added_by     TEXT
);

-- "Which units have we never sold?" and "who has this one?" — the two questions
-- the warehouse and support actually ask.
CREATE INDEX IF NOT EXISTS device_registry_status ON device_registry (status, received_at DESC);
CREATE INDEX IF NOT EXISTS device_registry_phone ON device_registry (activated_by_phone)
  WHERE activated_by_phone IS NOT NULL;
-- A code is worth nothing if two boxes carry the same one.
CREATE UNIQUE INDEX IF NOT EXISTS device_registry_code ON device_registry (activation_code)
  WHERE activation_code IS NOT NULL;
