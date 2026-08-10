-- Frame 12 — «Поддержка».
--
-- There was nowhere to record that a customer asked for help. Support happened
-- on WhatsApp and lived in one operator's phone: nobody else could see what had
-- been asked, whether it was answered, or how long somebody had been waiting.
-- The queue board counts orders and leads and could not count this at all.
--
-- ON THE AUTHOR. Either a user_id or a bare phone, and NOT NULL on neither:
-- a person can write before they have an account, and refusing those is
-- refusing the customers most likely to need help. The phone is kept
-- normalised alongside so a ticket can be matched to an account that appears
-- later.
--
-- NOTHING IS DELETED. A closed ticket is a status, not a disappearance — the
-- journal rule applies here as everywhere: «ничего не удаляется».

CREATE TABLE IF NOT EXISTS support_tickets (
  id          UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  -- Null when the writer has no account. ON DELETE SET NULL rather than
  -- CASCADE: deleting an account must not erase the record that somebody was
  -- helped, and the ticket text is the operator's, not the customer's.
  user_id     UUID REFERENCES users(id) ON DELETE SET NULL,
  phone       TEXT,
  customer_name TEXT,
  channel     TEXT NOT NULL DEFAULT 'whatsapp'
              CHECK (channel IN ('whatsapp','phone','panel','app')),
  subject     TEXT NOT NULL,
  body        TEXT NOT NULL DEFAULT '',
  -- new: nobody has looked. open: an operator has it. waiting: we answered and
  -- are waiting on HER, which must not count against our response time.
  status      TEXT NOT NULL DEFAULT 'new'
              CHECK (status IN ('new','open','waiting','closed')),
  assignee_id UUID REFERENCES staff_accounts(id) ON DELETE SET NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  -- When WE last replied. The SLA is measured from the customer's last message
  -- to this, so a ticket waiting on her does not read as us being slow.
  answered_at TIMESTAMPTZ,
  closed_at   TIMESTAMPTZ,
  -- What the app knew when she wrote: version, device, whether she was offline.
  -- Free text on purpose — support_context.dart composes it, and pinning a
  -- shape here would mean a migration every time the app learns a new fact.
  app_context TEXT,
  CONSTRAINT support_tickets_has_author
    CHECK (user_id IS NOT NULL OR (phone IS NOT NULL AND phone <> ''))
);

-- The queue: oldest unanswered first. Partial, because a closed ticket is
-- never in it and the table will be mostly closed tickets within a year.
CREATE INDEX IF NOT EXISTS idx_support_open
  ON support_tickets (created_at) WHERE status <> 'closed';
CREATE INDEX IF NOT EXISTS idx_support_user  ON support_tickets (user_id);
CREATE INDEX IF NOT EXISTS idx_support_phone ON support_tickets (phone);

-- The thread. Kept separate from the ticket rather than as an appended blob so
-- «кто ответил» has an answer per message.
CREATE TABLE IF NOT EXISTS support_replies (
  id         UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  ticket_id  UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  -- Who spoke. 'customer' has no staff id; 'staff' always does.
  author     TEXT NOT NULL CHECK (author IN ('customer','staff')),
  staff_id   UUID REFERENCES staff_accounts(id) ON DELETE SET NULL,
  body       TEXT NOT NULL,
  at         TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_support_replies_ticket
  ON support_replies (ticket_id, at);

-- Canned answers. «Шаблоны» in the spec: the same six questions arrive every
-- day and retyping them is how an answer drifts.
CREATE TABLE IF NOT EXISTS support_templates (
  id      TEXT PRIMARY KEY,
  title   TEXT NOT NULL,
  body_ru TEXT NOT NULL,
  -- Bilingual like everything else a customer reads. Nullable so a template
  -- can be drafted in one language, but the panel marks those as incomplete
  -- rather than sending Russian to a Kazakh speaker.
  body_kk TEXT,
  sort    INTEGER NOT NULL DEFAULT 0
);

INSERT INTO support_templates (id, title, body_ru, body_kk, sort) VALUES
  ('where_order', 'Где мой заказ',
   'Здравствуйте! Проверила ваш заказ — он {status}. Ожидаемая доставка: {eta}.',
   'Сәлеметсіз бе! Тапсырысыңызды тексердім — ол {status}. Күтілетін жеткізу: {eta}.', 10),
  ('pair_device', 'Не подключается трекер',
   'Давайте попробуем заново: выключите трекер, зажмите кнопку 5 секунд и откройте «Устройства» в приложении.',
   'Қайтадан көрейік: трекерді өшіріп, түймені 5 секунд басып тұрыңыз да, қосымшадағы «Құрылғылар» бөлімін ашыңыз.', 20),
  ('course_access', 'Не открывается курс',
   'Курс открывается после доставки комплекта. Проверила — доступ {access}.',
   'Курс жинақ жеткізілгеннен кейін ашылады. Тексердім — қолжетімділік {access}.', 30)
ON CONFLICT (id) DO NOTHING;
