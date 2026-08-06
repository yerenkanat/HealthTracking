-- How far she has got through the Ма!Ма! course.
--
-- Thirty lessons and no memory of any of them: she closed the app in the middle
-- of lesson 7 and came back to an undifferentiated list, with nothing marking
-- what she had seen and no way back to where she stopped. That is the single
-- most common reason a bought course is never finished, and this course is the
-- 9 200 ₸ difference between the комплект and two devices.
--
-- Keyed by PHONE, the same key as user_entitlements, and for the same reason:
-- the account and the purchase are joined by the number. A reinstall, a new
-- phone, a second device — she signs in with the same eleven digits and her
-- progress is still there. Keying on a user id would lose it exactly when
-- somebody has just spent money on a new device.

CREATE TABLE IF NOT EXISTS course_progress (
  phone            TEXT NOT NULL,
  lesson_id        UUID NOT NULL REFERENCES course_lessons(id) ON DELETE CASCADE,
  -- Where the player was. Seconds, because that is what the player reports and
  -- what it can be seeked back to.
  position_seconds INTEGER NOT NULL DEFAULT 0,
  -- How long the video is, as the player measured it. Nullable: the length is
  -- YouTube's, not ours, and it is unknown until a player has loaded the video
  -- at least once.
  duration_seconds INTEGER,
  -- Set once and never unset. "Watched" is a fact about the past; rewatching
  -- the first minute of a finished lesson must not un-finish it.
  completed        BOOLEAN NOT NULL DEFAULT FALSE,
  first_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (phone, lesson_id)
);

-- "Who is working through the course, and when were they last at it" — the
-- back-office read, which sorts by recency across all phones.
CREATE INDEX IF NOT EXISTS course_progress_recent
  ON course_progress (updated_at DESC);
