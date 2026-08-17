/**
 * Render frames 24 / 24b for real (jsdom): the integrations table, the banner
 * naming what is broken, and the step-by-step check.
 */
/**
 * WAITING — the fixed sleeps that used to stand in for "the panel has finished"
 * are gone. quiet() returns when no request is in flight, none has been issued
 * for several consecutive turns and the page has no timer outstanding, and it
 * THROWS rather than hand a half-drawn screen to an assertion. A wall-clock
 * wait decides its verdict on how busy the machine is; this one decides it on
 * the work being done. See helpers/panelSettle.ts.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle } from './helpers/panelSettle';
import { buildIntegrations, integrationSummary } from '../admin/integrations';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

// Built from the REAL module, not hand-written JSON: a fixture that drifts
// from what the server sends would test a screen nobody will see.
function payloadFor(over: Record<string, unknown> = {}) {
  const list = buildIntegrations({
    settings: { whatsapp: '+77000000000', telegramBotToken: '123:AAHsecret_7f2a', telegramChatId: '-100' },
    smsSenderIsReal: false,
    requirePhoneCode: true,
    pushWired: false,
    anthropicEnvKey: null,
    ...over,
  } as never);
  return { integrations: list, summary: integrationSummary(list) };
}

// What boot() serves. Reassigned by the block below so the same panel can be
// rendered against a second, worse, runtime state.
let PAYLOAD = payloadFor();
const CHECK_OK = {
  ok: true,
  steps: [
    { step: 'Токен бота сохранён', ok: true, detail: '••••7f2a' },
    { step: 'Чат указан', ok: true, detail: '-100' },
    { step: 'Тестовое сообщение доставлено', ok: true, detail: 'Сообщение ушло в чат' },
  ],
};

interface Rendered {
  text(s: string): string;
  count(s: string): number;
  el(s: string): Element | null;
  click(s: string): Promise<void>;
  errors: string[];
}

async function boot(): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  const settle = panelSettle();

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
      settle.attach(window as never, async (path: string, opts?: { method?: string }) => {
        const p = String(path);
        if (p.includes('/check')) return { ok: true, status: 200, json: async () => CHECK_OK };
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        const body = p.includes('/admin/integrations') ? PAYLOAD
          : p.includes('/admin/stats')
            ? { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 }
            : null;
        if (body === null) return { ok: false, status: 500, json: async () => ({}) };
        return { ok: true, status: 200, json: async () => body };
      });
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
    },
  });
  const { window } = dom;
  await settle.quiet();
  window.document.querySelector('[data-view="integrations"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet();
  return {
    text: (s) => (window.document.querySelector(s)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (s) => window.document.querySelectorAll(s).length,
    el: (s) => window.document.querySelector(s),
    click: async (s) => {
      window.document.querySelector(s)!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
      await settle.quiet();
    },
    errors,
  };
}

describe('frame 24 — Интеграции', () => {
  let page: Rendered;
  beforeAll(async () => { page = await boot(); });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('lists every integration', () => {
    const t = page.text('#intBody');
    for (const name of ['WhatsApp', 'Kaspi', 'Telegram', 'SMS-шлюз', 'Google Maps']) {
      expect(t).toContain(name);
    }
  });

  it('names what is BROKEN in the banner, not how many rows are red', () => {
    expect((page.el('#intAlert') as HTMLElement).hasAttribute('hidden')).toBe(false);
    expect(page.text('#intAlertTitle')).toContain('SMS-шлюз');
    // The consequence, which is the point of the screen.
    expect(page.text('#intAlertBody')).toContain('не сможет войти');
  });

  it('badges the sidebar with the count that is actually broken', () => {
    const badge = page.el('#intBadge') as HTMLElement;
    expect(badge.hasAttribute('hidden')).toBe(false);
    expect(Number(badge.textContent)).toBeGreaterThan(0);
  });

  it('shows a key masked, and never the key', () => {
    const t = page.text('#intBody');
    expect(t).toContain('••••7f2a');
    expect(t).not.toContain('AAHsecret');
  });

  it('offers «Проверить» only where a live check exists', () => {
    // Telegram is fully configured here; SMS and push have no endpoint to call,
    // and a button that always fails teaches an operator to ignore the screen.
    expect(page.count('#intBody button[data-check]')).toBe(1);
    expect(page.text('#intBody')).toContain('не проверяется');
  });
});

describe('frame 24 — a REQUIRE_PHONE_CODE that is doing nothing', () => {
  // The server can be started with the code gate switched on and no gateway to
  // honour it, in which case the flag is silently ignored and sign-in still
  // verifies nothing. On the screen that used to look identical to "nobody
  // turned it on" — which is how the variable came to be written down in
  // docs/RELEASE.md as the fix for unverified sign-in.
  let page: Rendered;
  beforeAll(async () => {
    PAYLOAD = payloadFor({ requirePhoneCode: false, phoneCodeRequested: true });
    page = await boot();
    PAYLOAD = payloadFor();
  });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('names the variable and says it is not in force', () => {
    const t = page.text('#intBody');
    expect(t).toContain('REQUIRE_PHONE_CODE=1');
    expect(t).toContain('НЕ действует');
  });

  it('spells out what an operator actually loses by believing it', () => {
    expect(page.text('#intBody')).toContain('войдёт в её аккаунт');
  });

  it('tells them where the fix is — in the code, not in backend.env', () => {
    expect(page.text('#intBody')).toContain('src/index.ts');
  });

  it('still raises the banner, because this is a blocking state', () => {
    expect((page.el('#intAlert') as HTMLElement).hasAttribute('hidden')).toBe(false);
    expect(page.text('#intAlertTitle')).toContain('SMS-шлюз');
  });
});

describe('frame 24b — Проверить связь', () => {
  let page: Rendered;
  beforeAll(async () => { page = await boot(); });

  it('opens and reports every step', async () => {
    await page.click('#intBody button[data-check="telegram"]');
    expect((page.el('#intCheck') as HTMLElement).hasAttribute('hidden')).toBe(false);
    const t = page.text('#icSteps');
    expect(t).toContain('Токен бота сохранён');
    expect(t).toContain('Тестовое сообщение доставлено');
    expect(page.text('#icNote')).toContain('Связь есть');
  });

  it('closes again', async () => {
    await page.click('#icDone');
    expect((page.el('#intCheck') as HTMLElement).hasAttribute('hidden')).toBe(true);
  });
});
