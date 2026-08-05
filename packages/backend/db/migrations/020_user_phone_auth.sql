-- Sign in to the app with a phone number.
--
-- The app has always had the two screens — enter a number, enter a code — but
-- behind them sat StubPhoneAuthProvider, which accepts 123456 on the handset and
-- never speaks to a server. So every account lived only on the phone it was
-- created on: reinstall the app and the pregnancy is gone.
--
-- This is the server side of a real account. No SMS: a number is claimed, not
-- verified. That is a deliberate, reversible decision — the sign-in endpoint is
-- the only place a code check would go, so adding a gateway later changes one
-- handler and nothing in the app.

-- `email` was NOT NULL because every account used to be created by hand with
-- one. A mother signing up with her phone has no email to give, and inventing
-- `77071234567@placeholder.invalid` to satisfy a constraint would put fake
-- addresses in the one column somebody will later try to send mail to.
ALTER TABLE users ALTER COLUMN email DROP NOT NULL;

-- The number IS the identity now, so two accounts cannot share one. Partial,
-- because the rows that predate phone sign-in have no number at all and would
-- otherwise collide with each other on NULL.
CREATE UNIQUE INDEX IF NOT EXISTS users_phone_e164_unique
  ON users (phone_e164) WHERE phone_e164 IS NOT NULL;

-- Sessions. Same shape as staff_sessions and for the same reasons: the token
-- itself is never stored, only its sha256, so a leaked dump is not a set of
-- live keys.
--
-- Ninety days rather than the back office's twelve hours. A phone is a personal
-- device and the app is opened in the night, one-handed, by someone who has not
-- slept — being signed out is a real cost there in a way it is not at a desk.
CREATE TABLE IF NOT EXISTS user_sessions (
  token_hash  TEXT PRIMARY KEY,
  user_id     UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  expires_at  TIMESTAMPTZ NOT NULL,
  user_agent  TEXT NOT NULL DEFAULT ''
);

CREATE INDEX IF NOT EXISTS user_sessions_expiry ON user_sessions (expires_at);
CREATE INDEX IF NOT EXISTS user_sessions_user ON user_sessions (user_id);

-- Attempts, for rate limiting. A phone number is guessable in a way an email is
-- not — Kazakh mobiles are eleven digits with a fixed prefix — and without a
-- code to get wrong, the thing to limit is how fast one source can claim
-- numbers.
CREATE TABLE IF NOT EXISTS user_login_attempts (
  id     BIGSERIAL PRIMARY KEY,
  phone  TEXT NOT NULL,
  at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS user_login_attempts_phone_at
  ON user_login_attempts (phone, at DESC);
