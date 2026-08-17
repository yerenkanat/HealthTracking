/**
 * Frame 24a «Настроить» rendered for real (jsdom): the keys form on Настройки →
 * Интеграции, where the spec puts it and where it now lives.
 *
 * It used to be «Магазин → Настройки и ключи» — a storefront card holding
 * server credentials, with the Anthropic key arriving from the server in
 * plaintext and going straight into an `<input>`.
 *
 * THE THING THIS FILE EXISTS FOR is the second half of the fix. The mask is
 * easy; not letting the mask destroy the key is not. If the box were
 * pre-filled with `••••7f2a`, the next save — an edit to the chat id, say —
 * would post it back and overwrite a live API key with bullet characters,
 * report success, and say nothing. So the boxes start EMPTY, empty means «не
 * менять», and the save must send only what was actually typed. All of that is
 * asserted against a rendered screen, not read off the source.
 *
 * WAITING: quiet(), never a sleep. It returns when nothing is in flight and no
 * timer is outstanding, and throws rather than hand a half-drawn screen to an
 * assertion.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';
import { buildIntegrations, integrationSummary } from '../admin/integrations';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

/** Built from the real module, so a drifting fixture cannot green a broken screen. */
const INTEGRATIONS = (() => {
  const list = buildIntegrations({
    settings: { whatsapp: '+77000000000', telegramBotToken: '123:AAHsecret_7f2a', telegramChatId: '-100' },
    smsSenderIsReal: false,
    requirePhoneCode: true,
    pushWired: false,
    anthropicEnvKey: null,
  });
  return { integrations: list, summary: integrationSummary(list) };
})();

/** The shape GET /admin/settings answers with — redacted, plus masks. */
const STORED = {
  settings: { whatsapp: '77000000000', telegramChatId: '-1005550000', rating: '4.9' },
  secrets: {
    anthropicApiKey: { stored: true, mask: '••••7f2a', source: 'panel', envMask: null },
    telegramBotToken: { stored: true, mask: '••••9999' },
    googleMapsApiKey: { stored: false, mask: null },
  },
};

interface Sent { path: string; method: string; body: Record<string, unknown> | null }

interface Page {
  window: JSDOM['window'];
  sent: Sent[];
  confirms: string[];
  errors: string[];
  text(sel: string): string;
  el(sel: string): Element | null;
  click(sel: string): Promise<void>;
  quiet: (label?: string) => Promise<void>;
}

interface BootOpts {
  /** null = GET /admin/settings fails. */
  settings?: typeof STORED | null;
  confirmAnswer?: boolean;
  /** What the PUT answers with. */
  putBody?: Record<string, unknown>;
  /** Make the PUT fail with this status. */
  putFails?: number;
}

async function boot(opts: BootOpts = {}): Promise<Page> {
  const { settings = STORED, confirmAnswer = true, putFails } = opts;
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
  const errors: string[] = [];
  const sent: Sent[] = [];
  const confirms: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(html, {
    runScripts: 'dangerously', pretendToBeVisual: true,
    url: 'http://localhost/admin/ui', virtualConsole: vc,
    beforeParse(window) {
      window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
        const noop = () => {};
        return new Proxy(
          { canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true });
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      (window as unknown as { confirm: (m: string) => boolean }).confirm = (m) => {
        confirms.push(String(m));
        return confirmAnswer;
      };
      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = String(path);
        const method = init?.method ?? 'GET';
        sent.push({ path: p, method, body: init?.body ? JSON.parse(String(init.body)) : null });
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin', displayName: 'Диас' }) };
        }
        if (p.includes('/check')) {
          return { ok: true, status: 200, json: async () => ({ ok: true, steps: [] }) };
        }
        if (p.includes('/admin/settings')) {
          if (method === 'PUT') {
            if (putFails) return { ok: false, status: putFails, text: async () => 'nope', json: async () => ({}) };
            return {
              ok: true, status: 200,
              json: async () => opts.putBody ?? { ok: true, ...STORED, written: ['telegramChatId'], keptUnchanged: [] },
            };
          }
          if (!settings) return { ok: false, status: 503, text: async () => 'down', json: async () => ({}) };
          return { ok: true, status: 200, json: async () => settings };
        }
        if (p.includes('/admin/integrations')) {
          return { ok: true, status: 200, json: async () => INTEGRATIONS };
        }
        if (p.includes('/admin/stats')) {
          return { ok: true, status: 200, json: async () => ({ activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 }) };
        }
        return { ok: true, status: 200, json: async () => ({ leads: [], orders: [], products: [] }) };
      });
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  window.document.querySelector('[data-view="integrations"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Интеграции tab');

  return {
    window, sent, confirms, errors,
    text: (s) => (window.document.querySelector(s)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    el: (s) => window.document.querySelector(s),
    click: async (s) => {
      window.document.querySelector(s)!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
      await settle.quiet(`click ${s}`);
    },
    quiet: settle.quiet,
  };
}

const value = (page: Page, id: string) =>
  (page.window.document.getElementById(id) as HTMLInputElement | null)?.value;

describe('frame 24a — the keys live on Интеграции now', () => {
  let page: Page;
  beforeAll(async () => { page = await boot(); }, 30_000);

  it('renders without a script error', () => {
    expect(page.errors).toEqual([]);
  });

  it('draws the form on the Интеграции screen, inside the Настройки section', () => {
    const card = page.el('#intKeysCard')!;
    expect(card.closest('section')!.id).toBe('integrations');
    // The sidebar entry the spec names: Настройки → … → Интеграции.
    const nav = page.window.document.querySelector('#navsub-settings [data-view="integrations"]');
    expect(nav, 'Интеграции is not under Настройки in the menu').not.toBeNull();
    expect((page.el('#intKeysForm') as HTMLElement).hasAttribute('hidden')).toBe(false);
  });

  it('shows the mask and never a key', () => {
    const t = page.text('#intKeysState');
    expect(t).toContain('••••7f2a');
    expect(t).toContain('••••9999');
    expect(t).not.toContain('AAHsecret');
  });

  it('leaves the secret boxes EMPTY, because a filled one would post the mask back', () => {
    // The failure this prevents is silent and total: `••••7f2a` written over a
    // live key, 200 OK, a tick on screen, and nothing said until the assistant
    // stops answering.
    expect(value(page, 'intAnthropic')).toBe('');
    expect(value(page, 'intTgToken')).toBe('');
    // And the box says so, rather than looking like an unconfigured field.
    expect(page.el('#intAnthropic')!.getAttribute('placeholder')).toContain('не менять');
  });

  it('fills the chat id in full, because it is not a secret', () => {
    expect(value(page, 'intTgChat')).toBe('-1005550000');
  });

  it('sends only what was typed', async () => {
    (page.window.document.getElementById('intTgChat') as HTMLInputElement).value = '-100777';
    await page.click('#intKeysSave');
    const put = page.sent.filter((s) => s.method === 'PUT' && s.path.includes('/admin/settings'));
    expect(put).toHaveLength(1);
    const body = put[0].body!;
    expect(body.telegramChatId).toBe('-100777');
    // The untouched key boxes are absent from the payload entirely — not sent
    // as '' (which clears) and not sent as the mask (which the server refuses,
    // but which should never have been assembled here in the first place).
    expect(Object.keys(body)).not.toContain('anthropicApiKey');
    expect(Object.keys(body)).not.toContain('telegramBotToken');
    expect(page.text('#intKeysMsg')).toContain('Сохранено');
  });

  it('sends a NEW key when one is typed', async () => {
    (page.window.document.getElementById('intAnthropic') as HTMLInputElement).value = 'sk-ant-brandnew';
    await page.click('#intKeysSave');
    const put = page.sent.filter((s) => s.method === 'PUT' && s.path.includes('/admin/settings'));
    expect(put[put.length - 1].body!.anthropicApiKey).toBe('sk-ant-brandnew');
    expect(page.text('#intKeysMsg')).toContain('перезапуск');
  });
});

describe('frame 24a — deleting a key asks first, and says what breaks', () => {
  it('does nothing when the question is declined', async () => {
    const page = await boot({ confirmAnswer: false });
    await page.click('#intClearAnthropic');
    expect(page.confirms).toHaveLength(1);
    // The consequence, not «вы уверены?».
    expect(page.confirms[0]).toContain('Ассистент перестанет отвечать');
    expect(page.sent.filter((s) => s.method === 'PUT')).toHaveLength(0);
  }, 30_000);

  it('clears it when confirmed', async () => {
    const page = await boot({ confirmAnswer: true });
    await page.click('#intClearTgToken');
    expect(page.confirms[0]).toContain('заявке');
    const put = page.sent.filter((s) => s.method === 'PUT');
    expect(put).toHaveLength(1);
    expect(put[0].body!.telegramBotToken).toBe('');
  }, 30_000);
});

describe('frame 24a — a failed read is not an empty form', () => {
  let page: Page;
  beforeAll(async () => { page = await boot({ settings: null }); }, 30_000);

  it('names the failure instead of drawing boxes', () => {
    // An empty form here reads as «ничего не настроено» — which is how somebody
    // retypes a key that was fine, or saves over one from an unknown baseline.
    expect(page.text('#intKeysState')).toContain('Не удалось загрузить');
    expect((page.el('#intKeysForm') as HTMLElement).hasAttribute('hidden')).toBe(true);
  });

  it('still draws the integrations table, which loaded fine', () => {
    // Two requests, two fates. A settings outage must not blank the screen that
    // says what is broken.
    expect(page.text('#intBody')).toContain('SMS-шлюз');
  });
});

describe('frame 24a — a failed save says so', () => {
  it('reports the refusal rather than a tick', async () => {
    // «Отправлено» is not «сохранено». A panel that reports the fact a request
    // was made is how somebody believes a key is stored when it is not.
    const page = await boot({ putFails: 503 });
    (page.window.document.getElementById('intTgChat') as HTMLInputElement).value = '-100000';
    await page.click('#intKeysSave');
    const msg = page.text('#intKeysMsg');
    expect(msg).toContain('Не сохранено');
    expect(msg).toContain('503');
    expect(msg).toContain('прежними');
  }, 30_000);

  it('says a key was left alone when the server refused a masked value', async () => {
    const page = await boot({
      putBody: { ok: true, ...STORED, written: ['whatsapp'], keptUnchanged: ['anthropicApiKey'] },
    });
    await page.click('#intKeysSave');
    expect(page.text('#intKeysMsg')).toContain('оставлен прежним');
  }, 30_000);
});
