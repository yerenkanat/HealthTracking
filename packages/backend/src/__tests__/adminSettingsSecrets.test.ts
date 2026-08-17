/**
 * The secret never leaves the server, and the mask never becomes the key.
 *
 * GET /admin/settings used to return `anthropicApiKey` in full. The panel put
 * it straight into an `<input>`, so the key was in the DOM of a screen anybody
 * with a back-office login could open, in the network tab of any browser, and
 * in any HAR exported while reporting an unrelated bug.
 *
 * Masking it is only half a fix, and the missing half is the dangerous one. A
 * form pre-filled with `••••7f2a` posts that string back on the next save — an
 * edit to the Telegram chat id, say — and a server that stores what it is sent
 * writes eight bullet characters over a live API key, answers 200, and lets the
 * panel draw a tick. The key is gone, completely, and nothing anywhere says so
 * until the assistant stops answering. Both halves are asserted here.
 *
 * Real HTTP against a real memory repository, and every "it was kept" is read
 * back out of storage rather than off the response — the response redacts, so
 * it could not tell the difference between a stored key and a wiped one.
 */
import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';

let repo: ReturnType<typeof createMemoryRepository>;
let app: FastifyInstance;

function makeApp(role: 'admin' | 'support' = 'admin') {
  repo = createMemoryRepository();
  return buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        resolveTransition: async () => null,
        sendEmergencyPush: async () => {},
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => ({ staffId: 's1', role }),
    },
    { logger: false },
  );
}

const REAL_KEY = 'sk-ant-api03-LONGREALKEY7f2a';
const REAL_TOKEN = '123456:AAHrealbottoken9999';

const get = async () => (await app.inject({ method: 'GET', url: '/admin/settings' })).json();
const put = (payload: Record<string, string>) =>
  app.inject({ method: 'PUT', url: '/admin/settings', payload });

const envBefore = process.env.ANTHROPIC_API_KEY;

beforeEach(async () => {
  delete process.env.ANTHROPIC_API_KEY;
  app = makeApp();
  await put({ anthropicApiKey: REAL_KEY, telegramBotToken: REAL_TOKEN, telegramChatId: '-100777' });
});
afterEach(() => {
  if (envBefore === undefined) delete process.env.ANTHROPIC_API_KEY;
  else process.env.ANTHROPIC_API_KEY = envBefore;
});

describe('GET /admin/settings never carries a secret', () => {
  it('answers with the mask, not the key', async () => {
    const res = await app.inject({ method: 'GET', url: '/admin/settings' });
    // On the RAW body: a key leaked under an unexpected property name would
    // still pass a field-by-field check.
    expect(res.body, 'the Anthropic key reached the browser').not.toContain(REAL_KEY);
    expect(res.body, 'the Telegram bot token reached the browser').not.toContain('AAHrealbottoken');

    const body = res.json();
    expect(body.settings.anthropicApiKey).toBeUndefined();
    expect(body.settings.telegramBotToken).toBeUndefined();
    expect(body.secrets.anthropicApiKey).toEqual(
      expect.objectContaining({ stored: true, mask: '••••7f2a', source: 'panel' }),
    );
    expect(body.secrets.telegramBotToken).toEqual(
      expect.objectContaining({ stored: true, mask: '••••9999' }),
    );
  });

  it('says «nothing stored» as an entry, not as a missing property', async () => {
    // A form has to tell «ключ сохранён» from «ключа нет». An absent property
    // reads as «нет», which is how somebody retypes a key that was fine.
    app = makeApp();
    const body = await get();
    expect(body.secrets.anthropicApiKey).toEqual(
      expect.objectContaining({ stored: false, mask: null, source: null }),
    );
  });

  it('still hands over the chat id in full, because it is not a secret', async () => {
    // It is printed in the frame 24b diagnostics and in the integrations table,
    // and an operator has to be able to correct it.
    expect((await get()).settings.telegramChatId).toBe('-100777');
  });

  it('names the environment key as the one in force, and marks the stored one inert', async () => {
    // index.ts copies a stored key across only when the environment has none,
    // so with both set the environment wins.
    process.env.ANTHROPIC_API_KEY = 'sk-ant-fromenv-abcd';
    const s = (await get()).secrets.anthropicApiKey;
    expect(s.source).toBe('env');
    expect(s.envMask).toBe('••••abcd');
    // The stored one is still reported — somebody pasted it expecting effect.
    expect(s.stored).toBe(true);
    expect(s.mask).toBe('••••7f2a');
  });

  it('redacts on the PUT response too', async () => {
    // The save answers with the settings as well. Echoing the key back there
    // would put it in the browser by the other door.
    const res = await put({ whatsapp: '77070000000' });
    expect(res.body).not.toContain(REAL_KEY);
    expect(res.json().secrets.anthropicApiKey.mask).toBe('••••7f2a');
  });
});

describe('a mask sent back is never written over the key', () => {
  it('keeps the stored key when the mask is posted with an unrelated edit', async () => {
    // The exact failure: somebody opens the form to change the chat id, the
    // client sends every box including the masked one, and a naive server
    // stores `••••7f2a`. Silent and total.
    const res = await put({
      anthropicApiKey: '••••7f2a',
      telegramBotToken: '••••9999',
      telegramChatId: '-100888',
    });
    expect(res.statusCode).toBe(200);

    const stored = await repo.getShopSettings();
    expect(stored.anthropicApiKey, 'the API key was overwritten with bullets').toBe(REAL_KEY);
    expect(stored.telegramBotToken, 'the bot token was overwritten with bullets').toBe(REAL_TOKEN);
    // The edit that WAS meant still went through.
    expect(stored.telegramChatId).toBe('-100888');
  });

  it('says which keys it left alone, rather than implying it rewrote them', async () => {
    const body = (await put({ anthropicApiKey: '••••7f2a', whatsapp: '77070000000' })).json();
    expect(body.keptUnchanged).toContain('anthropicApiKey');
    expect(body.written).toContain('whatsapp');
    expect(body.written).not.toContain('anthropicApiKey');
  });

  it('does not let a bullet anywhere in the value through', async () => {
    // Any bullet at all, not just the exact mask. U+2022 cannot occur in an
    // Anthropic key or a BotFather token — both ASCII — so a value carrying one
    // was assembled by a client, never typed by a person.
    await put({ anthropicApiKey: 'sk-ant-••••7f2a' });
    expect((await repo.getShopSettings()).anthropicApiKey).toBe(REAL_KEY);
  });

  it('still lets a real new key replace the old one', async () => {
    // The guard must not become a wall: replacing a leaked key is the whole
    // reason this screen exists.
    await put({ anthropicApiKey: 'sk-ant-api03-BRANDNEW1234' });
    expect((await repo.getShopSettings()).anthropicApiKey).toBe('sk-ant-api03-BRANDNEW1234');
    expect((await get()).secrets.anthropicApiKey.mask).toBe('••••1234');
  });

  it('still lets an empty string clear a key on purpose', async () => {
    // Deliberate removal stays possible — an empty string is not a mask. The
    // panel confirms before sending it; the server does not second-guess it.
    await put({ anthropicApiKey: '' });
    expect((await repo.getShopSettings()).anthropicApiKey).toBe('');
    expect((await get()).secrets.anthropicApiKey.stored).toBe(false);
  });
});

describe('the two fields that did nothing are gone from the write', () => {
  it('ignores a rating and a review count without failing the save', async () => {
    const res = await put({ whatsapp: '77070000001', rating: '4.9', reviewCount: '1240' });
    expect(res.statusCode).toBe(200);
    const stored = await repo.getShopSettings();
    expect(stored.whatsapp).toBe('77070000001');
    expect(stored.rating, 'an invented rating was stored again').toBeUndefined();
    expect(stored.reviewCount).toBeUndefined();
  });

  it('leaves a value stored before the withdrawal exactly where it was', async () => {
    // Nothing is destroyed. The panel reads it back and says on screen that it
    // is inert, which is the only honest answer to "where did my 4.9 go".
    await repo.setShopSettings({ rating: '4.9' });
    await put({ whatsapp: '77070000002' });
    expect((await repo.getShopSettings()).rating).toBe('4.9');
    expect((await get()).settings.rating).toBe('4.9');
  });
});

describe('the route a non-staff role must not reach', () => {
  it('refuses a support operator', async () => {
    app = makeApp('support');
    expect((await app.inject({ method: 'GET', url: '/admin/settings' })).statusCode).toBe(403);
  });
});
