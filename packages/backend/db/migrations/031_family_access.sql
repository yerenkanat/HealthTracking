-- Screen 40 — «Семейный доступ».
--
-- A father, a grandmother and an aunt all want to know the child got to
-- school. Until now there was no way to tell them: a child belongs to exactly
-- one user_id and every guard compares against it, so the only way to share was
-- to share the password.
--
-- Two tables, and one deliberate absence.
--
-- The absence: neither table names anything of the MOTHER's. A grant is over
-- her children, and the app's green banner — «здоровье и цикл не видит никто»
-- — is enforced by there being no column here that could express otherwise.
-- See src/family/access.ts.

-- Who may see this account's children.
CREATE TABLE IF NOT EXISTS family_access (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- Whose children. Not "which child": a relative invited into a family sees
  -- the family, and per-child grants would mean re-inviting the grandmother
  -- every time a baby is born.
  owner_user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  member_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  level          TEXT NOT NULL CHECK (level IN ('viewer', 'guardian')),
  -- What the member calls themselves to the mother — «Папа», «Бабушка». Her
  -- label for them, not their profile name, because the list is read by her.
  label          TEXT NOT NULL DEFAULT '',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- One grant per pair. A second invitation accepted by the same person
  -- updates the level rather than granting twice, so revoking removes access
  -- rather than removing one of two rows.
  UNIQUE (owner_user_id, member_user_id),
  -- Being your own relative would mean revoking it took away your own
  -- children.
  CHECK (owner_user_id <> member_user_id)
);
CREATE INDEX IF NOT EXISTS idx_family_access_member
  ON family_access (member_user_id);

-- Outstanding invitations. «24 ч, одноразовая».
CREATE TABLE IF NOT EXISTS family_invites (
  id             UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  owner_user_id  UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  -- The HASH. The token itself lives in the link and is never stored, so a
  -- copy of this table is not a set of working invitations.
  token_hash     TEXT NOT NULL UNIQUE,
  level          TEXT NOT NULL CHECK (level IN ('viewer', 'guardian')),
  label          TEXT NOT NULL DEFAULT '',
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at     TIMESTAMPTZ NOT NULL,
  -- Spent, not deleted: "somebody already joined with this link" is a
  -- different message from "this link never existed", and the mother is
  -- entitled to see who used it.
  used_at        TIMESTAMPTZ,
  used_by        UUID REFERENCES users(id) ON DELETE SET NULL,
  revoked_at     TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_family_invites_owner
  ON family_invites (owner_user_id, created_at DESC);
