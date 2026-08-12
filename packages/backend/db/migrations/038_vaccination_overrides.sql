-- Frame 15 «Вакцинация» / 15a «Добавить прививку» / 15b «История версий».
--
-- packages/contract/vaccination_schedule.json is the national immunisation
-- calendar of Kazakhstan: sixteen entries that decide what every parent in this
-- app is told to do and when. It is compiled into the backend, mirrored by
-- app/lib/domain/vaccination.dart and held identical by
-- app/tool/verify_vaccination_contract.dart. When the ministry moved the second
-- pneumococcal dose, changing it meant a backend release AND a store rollout.
--
-- Same shape as migration 036, for the same reasons and with the same promise:
-- OVERRIDES, never a replacement. The contract stays the offline baseline — a
-- phone in a village with no signal still opens the vaccination screen and
-- reads the whole calendar. This table holds only the vaccines somebody has
-- actually edited, plus the ones somebody has added. Delete every row and the
-- served schedule is byte-for-byte the shipped one again.

-- One row per INJECTION, keyed exactly as the app keys a mother's tick:
-- `<id>/<dose>` — 'pcv/1', 'pcv/2', 'bcg/null'. See vaccineKey() in
-- app/lib/domain/vaccination.dart and child_vaccines.vaccine_key.
--
-- Not keyed by `id`: the contract has three pentavalent rows and four polio
-- rows, so `id` is not unique and a row per id could only ever edit one of
-- them. Not keyed by (id, dose, at_month) either — the age is the field most
-- likely to be EDITED, and putting it in the key would mean moving pcv/2 from
-- month 4 to month 5 created a second row and orphaned every tick recorded
-- against the first.
--
-- Which is also why `dose` is not editable once a row exists: it is half of the
-- identity a mother's tick is filed under. Changing a dose number is adding a
-- different injection and retiring the old one, and the panel says so.
CREATE TABLE IF NOT EXISTS vaccination_overrides (
  key        TEXT PRIMARY KEY,

  -- The two halves of the key, stored so a reader does not have to parse it and
  -- so `added` rows carry a real id for the app's l10n fallback.
  vaccine_id TEXT    NOT NULL,
  dose       INTEGER,

  -- Completed months at which it is due. 0 is the first days of life, in the
  -- maternity hospital; 72 is the pre-school booster. Editable — this is the
  -- field an order from the ministry actually changes.
  at_month   INTEGER NOT NULL CHECK (at_month BETWEEN 0 AND 216),

  -- {name, note} per language. `name` is what a parent reads on the row;
  -- `note` is the line under it («Против пневмонии и отита…»).
  --
  -- Both NOT NULL: the route refuses a save without Kazakh
  -- (content/bilingual.ts), and a nullable kk column would quietly re-open the
  -- hole that rule exists to close. The contract carries a Russian label only —
  -- the Kazakh and the notes live in the app's l10n table under `vac_<id>` —
  -- so an edited row is where the two languages first sit side by side, and an
  -- ADDED vaccine has nowhere else for them to come from at all.
  ru         JSONB   NOT NULL,
  kk         JSONB   NOT NULL,

  -- This vaccine is not in the contract: frame 15a. The distinction matters at
  -- merge time. An edited contract row PATCHES a shipped entry; an added row is
  -- APPENDED, and is the only kind of row whose disappearance removes an
  -- injection from a parent's screen.
  added      BOOLEAN NOT NULL DEFAULT FALSE,

  -- Work in progress, and the only way back. A draft row is invisible to the
  -- merge, so drafting an EDIT lets the shipped entry show through again, and
  -- drafting an ADDED vaccine retires it. Both are reversible and neither
  -- destroys the words somebody wrote — which is what makes the medical-review
  -- rule workable rather than a wall.
  draft      BOOLEAN NOT NULL DEFAULT FALSE,

  -- {by, at, fingerprint} — a clinician's sign-off on the exact row they read,
  -- age included. See content/medicalReview.ts: editing reviewed text drops
  -- this, so approve-then-move-the-age cannot publish an unreviewed schedule.
  review     JSONB,

  -- Bumped on every save. GET /vaccination/schedule reports
  -- `contract version + SUM(rev) + settings rev`, so the version a phone sees
  -- moves whenever anything here moves — including a vaccine being pulled back
  -- into draft. Rows are never deleted (see below), so the sum only ever grows.
  rev        INTEGER NOT NULL DEFAULT 1,

  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Which staff account. Nullable because the column outlives accounts.
  updated_by TEXT
);

-- Retiring a vaccine is `draft = TRUE`, never DELETE. A drafted row is not
-- served — so an added vaccine vanishes from the calendar and an edited one
-- falls back to the contract — while the row, its author, its clinician
-- sign-off and its `rev` survive. A DELETE would drop `rev` and let the served
-- version number go backwards, which is the one thing a client caching by
-- version cannot survive.

-- «Настройки напоминаний», as much of them as this product can honestly offer.
--
-- There is no server-side vaccination sender: nothing in this backend pushes a
-- «пора прививаться» notification, and a toggle for one would be a switch
-- wired to nothing. What DOES reach every phone is the catch-up window — how
-- long a vaccine reads as «пора» before it reads as «стоит наверстать» — which
-- the app applies to every row of the screen and which used to be a Dart
-- constant. One row, one number, and the panel says out loud what it does.
CREATE TABLE IF NOT EXISTS vaccination_settings (
  -- Single-row table: the schedule has one catch-up window, not one per anything.
  id                BOOLEAN PRIMARY KEY DEFAULT TRUE CHECK (id),
  due_window_months INTEGER NOT NULL CHECK (due_window_months BETWEEN 1 AND 12),
  -- Counts into the served version like an override's does: changing the window
  -- changes what every phone computes, so a caching client has to be told.
  rev               INTEGER NOT NULL DEFAULT 1,
  updated_at        TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by        TEXT
);
-- Deliberately NOT seeded. An absent row means «контрактное значение», which is
-- the truthful state before anybody has chosen anything — seeding it with 1
-- would make the panel report a decision nobody took.

-- Frame 15b «История версий»: append-only, so the diff is real.
--
-- The override row holds only the CURRENT text; a version list assembled from
-- it could show what changed but never what it changed FROM. This holds the
-- before/after snapshot of every write, including the settings change, so the
-- panel can render an actual diff and name who made it.
--
-- `before` is NULL on a vaccine's first edit, and that is the honest record:
-- there was no row, and the baseline the edit departed from is the contract,
-- which the panel already has and can show instead of inventing one here.
CREATE TABLE IF NOT EXISTS vaccination_schedule_log (
  id     BIGSERIAL PRIMARY KEY,
  -- The override key, or '@settings' for a change to the catch-up window.
  key    TEXT NOT NULL,
  before JSONB,
  after  JSONB NOT NULL,
  actor  TEXT,
  at     TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_vaccination_log_at
  ON vaccination_schedule_log (at DESC);
