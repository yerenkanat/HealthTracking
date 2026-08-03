/**
 * Telling staff a customer asked to be called back.
 *
 * The landing page has been live and collecting leads into shop_leads, where
 * nothing announced them — the only way to find one was for somebody to open
 * the admin panel and look. These cover the notification, and, more
 * importantly, that adding it cannot cost a customer the callback it exists to
 * deliver.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { createLeadNotifier, formatLeadMessage } from '../notifications/leadAlert';

let repo: Repository;
let sent: Array<{ url: string; body: Record<string, unknown> }>;

const LEAD = { customerName: 'Айгерім Тест', phone: '+7 707 345 22 44', package: 'Комплект «Мама и ребёнок» — 39 000 ₸', locale: 'kz' as const };

/** Records the call instead of reaching api.telegram.org. */
function spyFetch(status = 200, body = '{"ok":true}'): typeof fetch {
  return (async (url: string, opts: RequestInit) => {
    sent.push({ url: String(url), body: JSON.parse(String(opts.body)) });
    return new Response(body, { status });
  }) as unknown as typeof fetch;
}

function app(notify?: ReturnType<typeof createLeadNotifier>): FastifyInstance {
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      notifyLead: notify,
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => ({ staffId: 's1', role: 'admin' as const }),
    },
    { logger: false },
  );
}

const postLead = (a: FastifyInstance) =>
  a.inject({ method: 'POST', url: '/shop/leads', payload: LEAD });

beforeEach(() => {
  repo = createMemoryRepository();
  sent = [];
});

describe('a new lead reaches staff', () => {
  async function configured(fetchImpl: typeof fetch) {
    await repo.setShopSettings({ telegramBotToken: '123:ABC', telegramChatId: '-100777' });
    return createLeadNotifier({
      loadConfig: async () => {
        const s = await repo.getShopSettings();
        return { telegramBotToken: s.telegramBotToken, telegramChatId: s.telegramChatId };
      },
      fetchImpl,
      onError: () => {},
    });
  }

  it('sends the lead to the configured chat', async () => {
    const res = await postLead(app(await configured(spyFetch())));
    expect(res.statusCode).toBe(201);
    expect(sent).toHaveLength(1);
    expect(sent[0].url).toContain('/bot123:ABC/sendMessage');
    expect(sent[0].body.chat_id).toBe('-100777');
    const text = String(sent[0].body.text);
    // The three things staff need in order to act, without opening anything.
    expect(text).toContain('Айгерім Тест');
    expect(text).toContain('+7 707 345 22 44');
    expect(text).toContain('39 000');
  });

  it('picks up a token saved after the server started', async () => {
    // Staff paste it into the admin panel and expect the next lead to arrive.
    // Reading the config once at boot would have meant a restart, and nobody
    // would have known one was needed.
    const notify = createLeadNotifier({
      loadConfig: async () => {
        const s = await repo.getShopSettings();
        return { telegramBotToken: s.telegramBotToken, telegramChatId: s.telegramChatId };
      },
      fetchImpl: spyFetch(),
      onError: () => {},
    });
    const a = app(notify);

    await postLead(a);
    expect(sent, 'nothing configured yet').toHaveLength(0);

    await repo.setShopSettings({ telegramBotToken: '123:ABC', telegramChatId: '-100777' });
    await postLead(a);
    expect(sent).toHaveLength(1);
  });

  it('still records the lead when Telegram rejects the message', async () => {
    // The row is the commitment. A wrong chat ID must cost a notification, not
    // a customer.
    const res = await postLead(app(await configured(spyFetch(400, '{"description":"chat not found"}'))));
    expect(res.statusCode).toBe(201);
    expect(await repo.adminShopLeads(10)).toHaveLength(1);
  });

  it('still records the lead when the network throws', async () => {
    const explode = (async () => { throw new Error('ENOTFOUND api.telegram.org'); }) as unknown as typeof fetch;
    const res = await postLead(app(await configured(explode)));
    expect(res.statusCode).toBe(201);
    expect(await repo.adminShopLeads(10)).toHaveLength(1);
  });

  it('records the lead when no channel is configured at all', async () => {
    // The state the site is in today, and the one it must be safest in.
    const res = await postLead(app());
    expect(res.statusCode).toBe(201);
    expect(await repo.adminShopLeads(10)).toHaveLength(1);
    expect(sent).toHaveLength(0);
  });

  it('sends nothing when only half the settings are filled in', async () => {
    await repo.setShopSettings({ telegramBotToken: '123:ABC', telegramChatId: '   ' });
    const notify = createLeadNotifier({
      loadConfig: async () => {
        const s = await repo.getShopSettings();
        return { telegramBotToken: s.telegramBotToken, telegramChatId: s.telegramChatId };
      },
      fetchImpl: spyFetch(),
      onError: () => {},
    });
    await postLead(app(notify));
    expect(sent).toHaveLength(0);
  });
});

describe('the notifier never throws, whatever happens', () => {
  // ServerDeps documents this as the contract, and crud.ts relies on it: the
  // route awaits the notifier after the response has gone out, so a rejection
  // there is an unhandled error in the request lifecycle rather than anything
  // the customer sees. The route's send-first ordering already protects them —
  // this keeps the second line of defence honest rather than incidental.
  const notifier = (fetchImpl: typeof fetch) =>
    createLeadNotifier({
      loadConfig: async () => ({ telegramBotToken: '123:ABC', telegramChatId: '-100777' }),
      fetchImpl,
      onError: () => {},
    });

  it('resolves when the network throws', async () => {
    const explode = (async () => { throw new Error('ENOTFOUND'); }) as unknown as typeof fetch;
    await expect(notifier(explode)(LEAD)).resolves.toBeUndefined();
  });

  it('resolves when Telegram answers an error', async () => {
    await expect(notifier(spyFetch(401, 'Unauthorized'))(LEAD)).resolves.toBeUndefined();
  });

  it('resolves when reading the settings fails', async () => {
    // A database hiccup while loading the token must not take the lead with it.
    const n = createLeadNotifier({
      loadConfig: async () => { throw new Error('db down'); },
      fetchImpl: spyFetch(),
      onError: () => {},
    });
    await expect(n(LEAD)).resolves.toBeUndefined();
  });
});

describe('the message itself', () => {
  it('does not use markup a customer name could break', () => {
    // Telegram parses Markdown only when asked, and this asks for plain text —
    // so a name with an underscore or asterisk must travel as typed rather
    // than failing the send for the very lead worth reading.
    const text = formatLeadMessage(
      { customerName: 'Ай_гер*им', phone: '+7 700 000 00 00' },
      new Date('2026-08-03T14:30:00Z'),
    );
    expect(text).toContain('Ай_гер*им');
  });

  it('stamps the time in Almaty, not UTC', () => {
    // Staff read this on a phone set to local time; a UTC stamp would have them
    // working out whether a lead is ten minutes or five hours old.
    const text = formatLeadMessage(
      { customerName: 'X', phone: '+7 700 000 00 00' },
      new Date('2026-08-03T14:30:00Z'),
    );
    expect(text).toContain('19:30'); // 14:30Z is 19:30 in Almaty (UTC+5)
    expect(text).toContain('Алматы');
  });

  it('omits the package line when the visitor chose nothing', () => {
    const text = formatLeadMessage({ customerName: 'X', phone: '+7 700 000 00 00' }, new Date());
    expect(text).not.toContain('Пакет:');
  });
});

describe('the Telegram settings are secret', () => {
  it('never appear in the public /shop/config', async () => {
    await repo.setShopSettings({ telegramBotToken: 'SECRET-BOT-TOKEN', telegramChatId: '-100777' });
    const res = await app().inject({ method: 'GET', url: '/shop/config' });
    // The token lets anyone post as the bot, so it belongs with the API keys,
    // not with the WhatsApp number.
    expect(res.body).not.toContain('SECRET-BOT-TOKEN');
    expect(res.body).not.toContain('-100777');
  });
});
