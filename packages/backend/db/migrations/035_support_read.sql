-- Frame 43 — the «Есть ответ поддержки» badge had no way DOWN.
--
-- The count on «Помощь» is «tickets with status = 'waiting'», which is the
-- desk's own statement that it answered and is waiting on her. Nothing ever
-- took it down: reading the thread changed no state, so the mint badge stayed
-- lit for weeks — until an operator happened to close the ticket. A badge that
-- is permanently on is a badge she stops reading, and the next real answer
-- loses its only signal.
--
-- So: when SHE last opened the thread. Not a per-message read receipt — she is
-- shown every thread at once and there is no per-bubble surface to hang one on
-- — one instant per ticket, compared against the last thing staff said in it.
-- An answer newer than this instant is unread and lights the badge again; the
-- one she has already read does not.
--
-- Deliberately NOT the ticket status. 'waiting' is the operator's queue state
-- and hers to act on; letting the app flip it would move her ticket out of the
-- board the desk works from just because she glanced at the screen.
ALTER TABLE support_tickets
  ADD COLUMN IF NOT EXISTS customer_read_at TIMESTAMPTZ;
