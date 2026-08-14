-- The postpartum screening result, and ONLY the result.
--
-- WHAT THIS TABLE IS: one row per completed EPDS (Edinburgh Postnatal
-- Depression Scale) questionnaire — when she took it, the total, and which
-- published band the total fell in. The app's screen 30 offers the
-- questionnaire when her own mood entries have run low for four weeks running.
--
-- WHAT IT DELIBERATELY DOES NOT HAVE, AND MUST NEVER GAIN: a column for the ten
-- answers.
--
-- Item 10 of the scale asks whether she has had thoughts of harming herself.
-- An answer to that question, stored against a named account in a back office
-- several staff can open, is a disclosure she did not consent to and cannot
-- take back — and there is no operational use for it that outweighs that. The
-- total already carries everything the product needs (a number, a date, a band)
-- and the app routes her outward on item 10 without telling anybody here that
-- it did. If a future feature "needs the answers", it needs a different
-- conversation, not an ALTER TABLE.
--
-- NOT A DIAGNOSIS, and nothing downstream may present it as one. The panel
-- names the instrument and prints the number; no verdict word appears beside
-- it. See packages/admin/index.html, «Скрининг ЭШПД».
--
-- RULE 5 (the one this repository keeps breaking): this is per-person clinical
-- context, read one card at a time behind the same audited /wellness route as
-- her sleep and her diary. It must never reach a LIST, a FILTER or a SEGMENT.
-- There is no index by score and no index by band, deliberately: the only query
-- shape this table supports is "this user's rows, newest first", which is what
-- the primary key already serves.
CREATE TABLE IF NOT EXISTS epds_results (
  user_id   UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- Client-supplied (the handset mints a v4 UUID), so a re-push of the same
  -- screening updates rather than duplicating it — the app pushes its whole
  -- history on every first sync.
  id        UUID NOT NULL,
  taken_at  TIMESTAMPTZ NOT NULL,
  -- 0–30 is the instrument's range: ten items scored 0–3. The CHECK repeats the
  -- zod bound in crud.ts exactly, in both directions; a wider column would let
  -- a mis-scored client write a number the panel would then print as fact.
  score     INTEGER NOT NULL CHECK (score BETWEEN 0 AND 30),
  -- low | possible | high — the published bands (9/10 and 12/13 thresholds).
  -- Stored rather than derived so a future change to the thresholds cannot
  -- silently re-label results she was already shown.
  band      TEXT NOT NULL CHECK (band IN ('low', 'possible', 'high')),
  PRIMARY KEY (user_id, id)
);
