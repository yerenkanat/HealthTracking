-- Frame 25 «Уведомления» — the switches the server obeys, and what happened to
-- every push it tried to send.
--
-- Before this, the app's notification screen was a promise the server had never
-- heard of. Per-category switches and quiet hours were stored in SharedPrefs on
-- one phone and read by exactly one thing: the notifications that phone raised
-- for itself. Everything the server sends — a geofence crossing derived from a
-- tracker fix, an operator's answer, a рассылка — ignored them. A mother who
-- turned «Зоны» off and set 22:00–07:00 still got a zone alert at three in the
-- morning, and «Доставлено 40» on the marketing screen counted ledger rows,
-- because nothing anywhere recorded whether a notification reached a phone.
--
-- Two tables: what she asked for, and what we did.

-- ---------------------------------------------------------------------------
-- What she asked for.
-- ---------------------------------------------------------------------------
--
-- Note what is NOT a column: SOS and medical emergency. They are not stored
-- because they are not switchable — see src/notifications/gate.ts. A column for
-- them would be a column somebody eventually sets to false.
CREATE TABLE IF NOT EXISTS notification_prefs (
  user_id     UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,

  -- All four default TRUE, and the absence of a row means the same thing. An
  -- install that predates this table must not lose the alerts it was already
  -- receiving because nobody has opened the screen yet.
  zone_events BOOLEAN NOT NULL DEFAULT TRUE,
  check_in    BOOLEAN NOT NULL DEFAULT TRUE,
  low_battery BOOLEAN NOT NULL DEFAULT TRUE,

  -- Рассылки and support answers. A FOURTH category rather than a reuse of
  -- check_in: silencing advertisements must not silence «ребёнок на месте»,
  -- and a mother who did both with one switch would never learn which.
  updates     BOOLEAN NOT NULL DEFAULT TRUE,

  -- Minutes since midnight IN HER TIMEZONE — users.timezone, not the server's
  -- clock. Both NULL = off. Start > end is a legitimate overnight window.
  -- SMALLINT with a range check because 1440 is the commonest off-by-one here
  -- and a stored 1440 would be a window nobody could ever be inside.
  quiet_start SMALLINT CHECK (quiet_start BETWEEN 0 AND 1439),
  quiet_end   SMALLINT CHECK (quiet_end   BETWEEN 0 AND 1439),

  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- What we did.
-- ---------------------------------------------------------------------------
--
-- One row per attempt, INCLUDING the attempts that were held. A ledger of only
-- the sends would answer «сколько ушло» and leave «почему ей не пришло»
-- unanswerable, which is the question this table exists for.
--
-- What it deliberately does NOT record: whether anybody opened anything. FCM
-- accepting a message is not a phone showing it and is certainly not a woman
-- reading it. There is no open rate in this product and inventing one here is
-- how it would appear on a dashboard next week.
CREATE TABLE IF NOT EXISTS push_deliveries (
  id          BIGSERIAL PRIMARY KEY,

  -- Nullable: a batch send without a single recipient still deserves a row, and
  -- the column outlives the account (ON DELETE SET NULL keeps the counts honest
  -- after an erasure instead of rewriting history).
  user_id     UUID REFERENCES users(id) ON DELETE SET NULL,

  -- 'emergency' | 'geofence' | 'sos' | 'support' | 'broadcast' — the same
  -- strings afterPush() has always logged, so the ledger and the log agree.
  -- Not an enum: a new kind must not need a migration to be recorded.
  kind        TEXT NOT NULL,

  -- Per-token outcome, as FCM reported it. `dead` are tokens it told us to
  -- forget; they are deleted from push_tokens by the caller and counted here so
  -- «не доходит» can be answered with «у неё нет живого устройства».
  sent        INTEGER NOT NULL DEFAULT 0,
  failed      INTEGER NOT NULL DEFAULT 0,
  dead        INTEGER NOT NULL DEFAULT 0,

  -- NULL = it was sent. 'muted' | 'quiet_hours' = it was not, and why.
  held_reason TEXT CHECK (held_reason IN ('muted', 'quiet_hours')),

  -- Whole-send failure, verbatim. 'no_tokens' is the commonest and is not an
  -- error in the usual sense: it means she has never registered a device.
  error       TEXT,

  at          TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- The panel's table: last N days, grouped by kind.
CREATE INDEX IF NOT EXISTS idx_push_deliveries_at ON push_deliveries (at DESC);
CREATE INDEX IF NOT EXISTS idx_push_deliveries_kind ON push_deliveries (kind, at DESC);
-- «Что мы посылали ЕЙ» — the support answer to one woman's complaint.
CREATE INDEX IF NOT EXISTS idx_push_deliveries_user ON push_deliveries (user_id, at DESC);
