-- Staff accounts for the back office: sign in with a phone number and a
-- password, the same two fields the app asks a mother for.
--
-- Until now the only thing standing between the internet and /admin was Caddy's
-- basic_auth, and the panel itself trusted the x-staff-role header outright — so
-- anyone past the browser dialog could name themselves an admin. The dialog also
-- cannot be branded, cannot say "phone number" instead of "username", cannot
-- expire, and re-sends the password on every single request.
--
-- The phone is stored as digits only. It is what staff type, and "+7 707…",
-- "8 707…" and "7707…" are the same person; normalising on the way in is the
-- only way the login can be forgiving about it.

CREATE TABLE IF NOT EXISTS staff_accounts (
  id            UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  phone         TEXT NOT NULL UNIQUE,          -- digits only, e.g. 77073452244
  password_hash TEXT NOT NULL,                 -- scrypt, salted, see http/staffAuth.ts
  role          TEXT NOT NULL DEFAULT 'admin', -- admin | clinician | support
  display_name  TEXT NOT NULL DEFAULT '',
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
  last_login_at TIMESTAMPTZ,
  -- Set when someone is locked out. Nothing deletes an account: an ex-employee's
  -- audit rows must keep pointing at a real staff row.
  disabled_at   TIMESTAMPTZ
);

-- Sessions, so a sign-in survives a page reload without the password being
-- replayed on every request. Rows are deleted on sign-out and swept on expiry.
CREATE TABLE IF NOT EXISTS staff_sessions (
  token_hash  TEXT PRIMARY KEY,               -- sha256 of the cookie value
  staff_id    UUID NOT NULL REFERENCES staff_accounts(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL,
  -- What signed in. Not for security decisions — for the audit log, so "who
  -- looked at this mother's data" has a device beside the name.
  user_agent  TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS staff_sessions_expiry ON staff_sessions (expires_at);

-- Failed attempts, for rate limiting. A back office reachable from the internet
-- with a phone number for a username is guessable in a way an email is not:
-- Kazakh mobile numbers are 11 digits with a fixed prefix.
CREATE TABLE IF NOT EXISTS staff_login_attempts (
  id         BIGSERIAL PRIMARY KEY,
  phone      TEXT NOT NULL,
  at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  succeeded  BOOLEAN NOT NULL DEFAULT false
);

CREATE INDEX IF NOT EXISTS staff_login_attempts_phone_at
  ON staff_login_attempts (phone, at DESC);
