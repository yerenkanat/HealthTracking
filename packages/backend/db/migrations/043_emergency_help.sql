-- Frame 16b «Экстренная помощь» / app screen 37.
--
-- The scenarios on screen 37 are the text a frightened person reads at 3am
-- while deciding whether to call 103. They shipped as a compiled-in JSON file
-- (packages/contract/emergency_help.json), bundled into the app and read by the
-- backend, so correcting «держите ожог под водой 20 минут» to whatever the
-- protocol actually says was a backend release AND a store rollout.
--
-- Same shape as migration 036, deliberately: OVERRIDES, never a replacement.
-- The contract stays exactly where it is and remains the offline baseline — a
-- phone with no signal still opens this screen and reads nine scenarios. This
-- table holds only the ones somebody has actually edited, and what is served is
-- contract-with-overrides-on-top. Delete every row and the product is back to
-- the shipped text, which is the property that makes editing clinical
-- instructions survivable.
CREATE TABLE IF NOT EXISTS emergency_help_overrides (
  -- The scenario id from the contract ('breathing', 'bleeding', …). TEXT rather
  -- than a serial: the id is what joins a row to the contract entry it patches,
  -- and a surrogate key would let two rows claim the same scenario.
  id         TEXT PRIMARY KEY,

  -- 'red' — звоните 103 сейчас; 'amber' — звоните врачу сегодня. This is the
  -- one field that is not prose: it decides the border-left colour on the card
  -- and therefore whether somebody dials or waits. Constrained so a typo cannot
  -- render a scenario with no border at all.
  severity   TEXT NOT NULL CHECK (severity IN ('red', 'amber')),

  -- Reading order. Editable because triage order is a clinical decision — if
  -- the protocol says a silent baby outranks bleeding, that is a change to make
  -- in an afternoon, not in a release.
  sort       INTEGER NOT NULL DEFAULT 0,

  -- {title, what, do} per language. Both NOT NULL: the route refuses a save
  -- without Kazakh (content/bilingual.ts), and a nullable kk column would
  -- quietly re-open the hole that rule exists to close. A Kazakh-speaking
  -- mother reading Russian instructions about a child who cannot breathe is
  -- the exact failure this product cannot afford.
  ru         JSONB NOT NULL,
  kk         JSONB NOT NULL,

  -- Work in progress. A draft is stored but NOT served: GET /emergency-help
  -- keeps returning the contract text for a drafted scenario. This is what
  -- makes the medical-review rule workable rather than a wall — half-written
  -- first aid has somewhere to live that is not a Word document.
  draft      BOOLEAN NOT NULL DEFAULT FALSE,

  -- {by, at, fingerprint} — a clinician's sign-off on the exact text they read.
  -- See content/medicalReview.ts: editing reviewed text drops this, so
  -- approve-then-rewrite cannot publish unreviewed first aid by accident.
  review     JSONB,

  -- Bumped on every save. GET /emergency-help reports
  -- `contract version + SUM(rev)`, so the version a phone caches by moves
  -- whenever anything here moves — including a scenario being pulled back into
  -- draft. Rows are never deleted (see below), so the sum only ever grows.
  rev        INTEGER NOT NULL DEFAULT 1,

  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- Which staff account. Nullable because the column outlives accounts: a row
  -- whose author has left still says when it changed, and inventing a name for
  -- it would make the audit trail look answered when it is not.
  updated_by TEXT
);

-- Going back to the shipped text is `draft = TRUE`, not DELETE. A drafted
-- scenario is not served, so the contract shows through again — and the row,
-- its author and its `rev` survive, which keeps the served version monotonic. A
-- DELETE would drop `rev` and let that number go backwards, which is the one
-- thing a client caching by version cannot survive.

-- ---------------------------------------------------------------------------
-- «Карточка адреса для диспетчера» (screen 37).
--
-- The 103 dispatcher's first question is where to send the ambulance, and this
-- product had nowhere to keep the answer. `users.city` is a city, not an
-- address; `shop_orders.address` is a DELIVERY address attached to one order,
-- typed for a courier and possibly a workplace or a relative's flat — reusing
-- it would put a stranger's doorway on the screen of somebody dictating it to
-- an ambulance service.
--
-- So: a column of her own, on her own row. Free text and nullable, because a
-- real address in Kazakhstan is «мкр. Самал-2, д. 33, кв. 12, домофон 12К» and
-- because declining is a supported answer — the screen then shows her city and
-- «Добавьте адрес» rather than inventing one.
ALTER TABLE users ADD COLUMN IF NOT EXISTS address TEXT;
