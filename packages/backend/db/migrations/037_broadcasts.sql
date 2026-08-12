-- Frame 06 «Маркетинг» — рассылки.
--
-- Until now the product could reach a woman's phone for exactly two reasons: a
-- medical emergency, and an operator answering her support ticket. There was no
-- way to tell every pregnant user that the second screening window opens this
-- month, and no way to tell anybody anything at all — the back office had no
-- surface for it and the app had nowhere for such a message to land.
--
-- Two tables, because the second is the one that makes the first safe.

CREATE TABLE IF NOT EXISTS broadcasts (
  -- Panel-supplied, so a draft keeps its identity across saves.
  id           TEXT PRIMARY KEY,

  -- RU is NOT NULL and KK is not. That asymmetry is the publication gate, not
  -- an oversight: a draft may legitimately exist in one language while it is
  -- being written, and the route refuses to PUBLISH one without the Kazakh
  -- half (see content/bilingual.ts, the same rule the week editor enforces).
  -- Making kk NOT NULL would force an editor to paste placeholder Kazakh to
  -- save a draft, which is how untranslated text reaches a phone.
  title_ru     TEXT NOT NULL,
  body_ru      TEXT NOT NULL,
  title_kk     TEXT,
  body_kk      TEXT,

  -- {audience, locale} and nothing else — see src/admin/broadcasts.ts. JSONB
  -- rather than columns because the vocabulary will grow (city, a course
  -- cohort) and because the whole rule is validated in one place on write.
  --
  -- What it may NEVER contain is a health field. The route refuses unknown
  -- keys rather than dropping them: a segment stored as {} after somebody
  -- typed a blood-pressure rule would go to everybody while the panel showed
  -- the rule they wrote.
  segment      JSONB NOT NULL DEFAULT '{}'::jsonb,

  -- draft → published, one way. There is no unpublish: the message is on a
  -- phone. Deleting the row would only delete our record of what we sent.
  status       TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft','published')),

  -- Which member of staff. Nullable because the column outlives accounts.
  created_by   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- NULL while it is a draft; set once, when it goes out.
  published_at TIMESTAMPTZ
);

-- Who actually received what, and when.
--
-- This is the frequency rule «не чаще раза в неделю» made real. The cap is
-- ACROSS broadcasts, not per broadcast: two campaigns published on the same
-- afternoon are exactly the case it exists for. Publishing consults this table
-- for anybody written to in the last seven days and skips them — so the same
-- message published twice by a nervous operator reaches a mother once, and the
-- panel can report how many were skipped instead of pretending it delivered
-- more than it did.
--
-- PRIMARY KEY (broadcast_id, user_id) makes a re-publish idempotent per person
-- at the storage layer as well, so a partial failure can be retried without
-- double-sending.
CREATE TABLE IF NOT EXISTS broadcast_deliveries (
  broadcast_id TEXT NOT NULL REFERENCES broadcasts(id) ON DELETE CASCADE,
  user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (broadcast_id, user_id)
);

-- The two reads this table serves. Both lead with user_id: «когда мы в
-- последний раз ей писали» runs once per candidate on every publish, and
-- «что мне пришло» runs on every launch of the notification centre.
CREATE INDEX IF NOT EXISTS idx_broadcast_deliveries_user
  ON broadcast_deliveries (user_id, created_at DESC);

-- «Что опубликовано», newest first — the panel's table.
CREATE INDEX IF NOT EXISTS idx_broadcasts_published
  ON broadcasts (published_at DESC NULLS LAST);
