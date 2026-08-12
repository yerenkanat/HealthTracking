-- Frame 14a / 14b — «40 недель» and the week editor.
--
-- packages/contract/pregnancy_weeks.json is the only content every pregnant
-- user of this app sees, and until now nobody could change a word of it without
-- a release: the file is compiled into the backend, bundled as an app asset, and
-- held identical by app/tool/verify_pregnancy_weeks_contract.dart. A typo in
-- week 22 was a build, a review and a store rollout.
--
-- So: OVERRIDES, never a replacement. The contract stays exactly where it is and
-- remains the offline baseline — a phone in a village with no signal still opens
-- week 22 and reads something. This table holds only the weeks somebody has
-- actually edited, and the served calendar is contract-with-overrides-on-top.
-- Delete every row here and the product is back to the shipped calendar, which
-- is the property that makes editing clinical text survivable.
--
-- One row per week, not per (week, field): a week is edited and reviewed as a
-- whole. A clinician approving «week 22» has read the baby text, the mother
-- text and the recommendation together — they are one piece of advice, and
-- letting them carry separate approvals would mean a reviewed page assembled
-- from three unreviewed halves.
CREATE TABLE IF NOT EXISTS pregnancy_week_overrides (
  -- The gestational week. 1..42 rather than 1..40: the contract runs past 40
  -- because babies are late, and an overdue mother is exactly the one who most
  -- wants the page to say something.
  week       INTEGER PRIMARY KEY CHECK (week BETWEEN 1 AND 42),

  -- Free text, both of them, and nullable. The contract stores "0,02" and
  -- "25–156" and "—"; these are ranges and dashes written by a clinician, not
  -- measurements, and typing them into a numeric column would force whoever
  -- edits them to pick a single false number.
  length_cm  TEXT,
  hcg        TEXT,

  -- {baby, you, recommend} per language. Both NOT NULL: the route refuses a
  -- save without Kazakh (content/bilingual.ts), and a nullable kk column would
  -- quietly re-open the hole that rule exists to close.
  ru         JSONB NOT NULL,
  kk         JSONB NOT NULL,

  -- Work in progress. A draft is stored but NOT served: GET /pregnancy/weeks
  -- keeps returning the contract text for a drafted week. This is what makes
  -- the medical-review rule workable rather than a wall — half-written advice
  -- has somewhere to live that is not a Word document.
  draft      BOOLEAN NOT NULL DEFAULT FALSE,

  -- {by, at, fingerprint} — a clinician's sign-off on the exact text they read.
  -- See content/medicalReview.ts: editing reviewed text drops this, so
  -- approve-then-rewrite cannot publish unreviewed advice by accident.
  review     JSONB,

  -- Bumped on every save. GET /pregnancy/weeks reports
  -- `contract version + SUM(rev)`, so the version a phone sees moves whenever
  -- anything here moves — including a week being pulled back into draft. Rows
  -- are never deleted (see below), so the sum only ever grows.
  rev        INTEGER NOT NULL DEFAULT 1,

  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Which staff account. Nullable because the column outlives accounts: a row
  -- whose author has left still says when it changed, and inventing a name for
  -- it would make the audit trail look answered when it is not.
  updated_by TEXT
);

-- Going back to the shipped text is `draft = TRUE`, not DELETE. A drafted week
-- is not served, so the contract shows through again — and the row, its author
-- and its `rev` survive, which keeps the served version number monotonic. A
-- DELETE would drop `rev` and let that number go backwards, which is the one
-- thing a client caching by version cannot survive.
