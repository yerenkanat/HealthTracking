-- Proving she owns the number before handing over the account.
--
-- Until now `POST /auth/phone` took a phone number and answered with a session:
-- typing eleven digits WAS the sign-in. Anyone who knew a customer's number —
-- which is on every parcel, every WhatsApp order and every delivery manifest —
-- could open her account and read her pregnancy, her children and their live
-- locations. The file said so plainly and waited for an SMS gateway.
--
-- The code is stored HASHED, for the same reason a password is: this table is
-- readable by anything that can read the database, and a six-digit code in
-- plaintext beside a phone number is a working key.
CREATE TABLE IF NOT EXISTS phone_codes (
  phone       TEXT PRIMARY KEY,
  code_hash   TEXT NOT NULL,
  expires_at  TIMESTAMPTZ NOT NULL,
  -- Wrong guesses so far. Six digits is a million combinations, but a bot does
  -- not need a million tries — it needs enough, so it gets five.
  attempts    INTEGER NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- One live code per number: requesting a second replaces the first, so a code
-- read over somebody's shoulder stops working the moment she asks for another.
CREATE INDEX IF NOT EXISTS phone_codes_expiry ON phone_codes (expires_at);
