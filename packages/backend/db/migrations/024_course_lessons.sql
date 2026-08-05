-- The Ма!Ма! course: lessons added one at a time, shown to whoever bought the
-- combo.
--
-- Deliberately NOT part of the timeline content CMS. That one files an item
-- under a pregnancy week or a child month (w20, m3) because it answers "what is
-- relevant to her this week". A course is an ordered series that does not move
-- with a due date, and forcing it into stage keys would mean either filing every
-- lesson under a week it has nothing to do with, or inventing a fake stage.
--
-- The videos are on YouTube, which is what the owner has. YouTube's terms
-- require their player and their branding, so the app opens them externally
-- rather than embedding — the same rule the timeline CMS already states for its
-- youtube items.

CREATE TABLE IF NOT EXISTS course_lessons (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- Which course. One today; naming it now costs nothing and avoids a second
  -- table when there is a second course.
  course      TEXT NOT NULL DEFAULT 'mama',
  title_ru    TEXT NOT NULL,
  -- Kazakh is optional: lessons will be added one by one, often in Russian
  -- first, and blocking a lesson until it is translated would mean nothing
  -- ships. The app falls back to the Russian title.
  title_kk    TEXT,
  -- What plays. Stored as given so the owner can paste a youtu.be short link,
  -- a watch URL, or one with a timestamp — normalising here would silently
  -- change a link that works into one that does not.
  youtube_url TEXT NOT NULL,
  -- Free text under the title: what this lesson covers, how long it is.
  summary_ru  TEXT,
  summary_kk  TEXT,
  -- Order in the series. Sparse (10, 20, 30) so a lesson can be inserted
  -- between two others without renumbering the rest.
  sort        INTEGER NOT NULL DEFAULT 0,
  -- Unpublished lessons are visible in the panel and invisible in the app, so
  -- one can be drafted without appearing half-finished to somebody who paid.
  published   BOOLEAN NOT NULL DEFAULT FALSE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS course_lessons_order
  ON course_lessons (course, sort, created_at);
