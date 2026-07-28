-- Daily audio for the pregnancy and child-development calendars: one short clip
-- per day (like the "每日知识 / daily knowledge" audio in the reference app),
-- uploaded and edited from the admin panel, played by the app on the matching
-- day of the mother's/child's timeline.
--
-- The clip bytes live here (bytea) so the whole feature is self-contained with
-- the Postgres the rest of the stack already uses — no object store to wire.
-- Clips are short (tens of seconds), so this stays small.
CREATE TABLE IF NOT EXISTS daily_audio (
  track      TEXT NOT NULL CHECK (track IN ('pregnancy','child')),
  day        INTEGER NOT NULL CHECK (day >= 1 AND day <= 400),
  locale     TEXT NOT NULL DEFAULT 'ru' CHECK (locale IN ('ru','kk')),
  title      TEXT,
  mime       TEXT NOT NULL,
  bytes      BYTEA NOT NULL,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (track, day, locale)
);
