/**
 * Render кадр 25 «Уведомления» for real (jsdom).
 *
 * The routes and the gate are proved in notificationGate.test.ts. This is the
 * other half of the same defect: a tab that draws a table wired to nothing
 * looks exactly like a working one, and this screen's whole reason to exist is
 * being the place somebody looks when a mother says «мне не пришло».
 *
 * Nothing here is asserted structurally. Every expectation is on text a browser
 * painted into a cell, which is what «Hidden vs painted» in this suite's own
 * history is about: an assertion on `.hidden` passes over a tab a browser never
 * shows.
 *
 * The two rules the screen must not break, asserted rather than commented:
 *   * a kind nothing happened to is ABSENT, not a row of zeros;
 *   * there is no open rate — not in a column, not in the footer, not derived.
 */
import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

/** The shape GET /admin/notifications really answers with. */
const SUMMARY = {
  windowDays: 30,
  kinds: [
    {
      kind: 'geofence', attempts: 14, delivered: 9, failed: 1,
      noTokens: 2, held: 2, heldMuted: 1, heldQuiet: 1, errors: 0, dead: 1,
    },
    {
      kind: 'sos', attempts: 3, delivered: 3, failed: 0,
      noTokens: 0, held: 0, heldMuted: 0, heldQuiet: 0, errors: 0, dead: 0,
    },
  ],
  deadTokens: 1,
  muted: { zoneEvents: 3, checkIn: 0, lowBattery: 1, updates: 5, quietHours: 4, configured: 9 },
  lastAt: '2026-08-10T21:14:00.000Z',
  holdReasons: { muted: 'категория отключена', quiet_hours: 'тихие часы' },
  categories: ['zoneEvents', 'checkIn', 'lowBattery', 'updates'],
  alwaysDelivered: ['sos', 'emergency'],
};

interface Rendered {
  text(sel: string): string;
  count(sel: string): number;
  errors: string[];
  window: import('jsdom').DOMWindow;
}

interface BootOpts {
  role?: string;
  body?: unknown;
  status?: number;
  message?: string;
}

async function boot(opts: BootOpts = {}): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: 'http://localhost/admin/ui',
    virtualConsole: vc,
    beforeParse(window) {
      window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
        const noop = () => {};
        return new Proxy(
          { canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true },
        );
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      (window as unknown as { CSS: { escape: (s: string) => string } }).CSS = { escape: (s) => s };
      window.fetch = (async (path: string) => {
        const p = String(path);
        const ok = (body: unknown, status = 200) => ({
          ok: status >= 200 && status < 300, status,
          text: async () => JSON.stringify(body),
          json: async () => body,
        });
        if (p.includes('/admin/me')) return ok({ staffId: 's1', role: opts.role ?? 'admin' });
        if (p.includes('/admin/notifications')) {
          if (opts.status && opts.status >= 400) {
            return ok({ error: 'notifications_unavailable', message: opts.message ?? 'База не ответила.' }, opts.status);
          }
          return ok(opts.body ?? SUMMARY);
        }
        return ok({});
      }) as never;
    },
  });
  const { window } = dom;
  await new Promise((r) => setTimeout(r, 120));
  return {
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (sel) => window.document.querySelectorAll(sel).length,
    errors,
    window,
  };
}

async function click(page: Rendered, sel: string) {
  page.window.document.querySelector(sel)!.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 120));
}

/** «Hidden vs painted»: a display rule beats the hidden attribute. */
function painted(page: Rendered, sel: string): boolean {
  const el = page.window.document.querySelector(sel) as HTMLElement | null;
  if (!el) return false;
  for (let n: HTMLElement | null = el; n; n = n.parentElement) {
    if (n.hasAttribute('hidden')) return false;
    if (n.classList.contains('view') && !n.classList.contains('active')) return false;
  }
  return true;
}

async function open(opts: BootOpts = {}): Promise<Rendered> {
  const page = await boot(opts);
  await click(page, '[data-view="notifications"]');
  return page;
}

describe('the notifications tab draws', () => {
  it('boots, opens, and is the tab a browser would be showing', async () => {
    const page = await open();
    expect(page.errors).toEqual([]);
    // Not vacuous: on any other tab this table is not on screen.
    expect(painted(await boot(), '#ntBody')).toBe(false);
    expect(painted(page, '#ntBody')).toBe(true);
    expect(page.text('#pageTitle')).toBe('Уведомления');
  });

  it('prints one row per kind that actually happened, and no others', async () => {
    const page = await open();
    // Two rows because two kinds have rows in the ledger. `support`,
    // `broadcast` and `emergency` are absent — «broadcast 0 0 0» would read as
    // a broken sender when the truth is that nobody sent one.
    expect(page.count('#ntBody tr[data-ntkind]')).toBe(2);
    expect(page.text('#ntBody')).not.toContain('Рассылки');
    const geo = page.text('tr[data-ntkind="geofence"]');
    expect(geo).toContain('Зоны ребёнка');
    expect(geo).toContain('9');   // delivered
    expect(geo).toContain('2');   // held
  });

  it('says WHY each held push was held, in two separate numbers', async () => {
    // «Придержано 2» alone makes «тихие часы» and «она отключила категорию»
    // look like one thing. They need different answers from support.
    const geo = (await open()).text('tr[data-ntkind="geofence"]');
    expect(geo).toContain('категория отключена');
    expect(geo).toContain('тихие часы');
  });

  it('never prints an open rate, and says why', async () => {
    const page = await open();
    const rule = page.text('#ntRule').toLowerCase();
    expect(rule).toContain('доставлено на устройства');
    expect(rule).toContain('не «прочитано»');
    // The whole screen, not just the footer: no percentage anywhere. A rate is
    // the number this panel is most likely to grow, and FCM accepted ≠ read.
    const screen = page.text('#notifications');
    expect(screen, 'frame 25 grew a rate').not.toMatch(/\d+\s?%/);
    // …and the table header says what the column counts, so nobody reads the
    // number as opens.
    expect(page.text('#notifications thead')).toContain('Доставлено на устройства');
  });

  it('states the exemption the app promises on screen 39', async () => {
    // «Экстренные отключить нельзя» is a card in the app. If the back office
    // does not say the same thing, the two halves of one promise drift.
    const rule = (await open()).text('#ntRule');
    expect(rule).toContain('SOS');
    expect(rule).toContain('не придерживаются никогда');
  });

  it('reads the quiet hours in her timezone, and says so out loud', async () => {
    expect((await open()).text('#ntRule')).toContain('users.timezone');
  });

  it('counts who muted what, without naming anybody', async () => {
    const page = await open();
    expect(page.text('tr[data-ntcat="zoneEvents"]')).toContain('3');
    expect(page.text('tr[data-ntcat="updates"]')).toContain('5');
    expect(page.text('tr[data-ntcat="quietHours"]')).toContain('4');
    expect(page.text('#ntPrefsSub')).toContain('9');
    // The «updates» row exists at all, which is the trap this feature invites:
    // a рассылка hung off «Отметки» would silence «ребёнок на месте» with it.
    expect(page.text('tr[data-ntcat="updates"]')).toContain('Новости и ответы');
  });

  it('counts «не доставлено» in devices, never devices plus attempts', async () => {
    // One рассылка to a mother with three registered tokens; firebase-admin
    // threw on the whole send. sendPush answers `failed: tokens.length` AND
    // sets `error`, so the summary counts that one failure once per token in
    // `failed` and once more in `errors` — and the old `failed + errors` cell
    // printed «4» for a send that had three devices in it. A number larger than
    // any real quantity on the screen, traceable to no column.
    const page = await open({
      body: {
        ...SUMMARY,
        kinds: [{
          kind: 'broadcast', attempts: 1, delivered: 0, failed: 3,
          noTokens: 0, held: 0, heldMuted: 0, heldQuiet: 0, errors: 1, dead: 0,
        }],
      },
    });
    const row = page.text('tr[data-ntkind="broadcast"]');
    expect(row, 'devices were added to attempts again').not.toContain('4');
    expect(row).toContain('3');
    // The errored SEND is still visible — in its own unit, on its own line.
    expect(row).toContain('сорвались с ошибкой');
  });

  it('shows «нет устройства» for an SOS that reached nobody', async () => {
    // The row that used to be missing entirely: the fan-out skipped the
    // dispatcher when a recipient had no live token, so nothing was recorded —
    // and the footer below reads an absent row as «SOS за 30 дней не было».
    const page = await open({
      body: {
        ...SUMMARY,
        kinds: [{
          kind: 'sos', attempts: 2, delivered: 0, failed: 0,
          noTokens: 2, held: 0, heldMuted: 0, heldQuiet: 0, errors: 0, dead: 0,
        }],
      },
    });
    const row = page.text('tr[data-ntkind="sos"]');
    expect(row).toContain('SOS');
    expect(row).toContain('2');
  });

  it('an empty ledger says «ничего не отправлялось», not «0 доставлено»', async () => {
    const page = await open({
      body: { ...SUMMARY, kinds: [], deadTokens: 0, lastAt: null },
    });
    expect(page.text('#ntBody')).toContain('не отправляло ни одного уведомления');
    expect(page.text('#ntBody')).toContain('Это не ошибка панели');
  });

  it('a database that could not answer says so instead of showing zeros', async () => {
    // The distinction this panel has been burned by: «доставлено 0» and «мы не
    // смогли прочитать» call for opposite reactions.
    const page = await open({ status: 503, message: 'Журнал отправок недоступен.' });
    expect(page.text('#ntBody')).toContain('Журнал отправок недоступен.');
    expect(page.text('#ntBody')).not.toContain('не отправляло ни одного');
  });

  it('is not offered to a role the route would refuse', async () => {
    // GET /admin/notifications is requireCap(…, 'content'). A tab drawn for a
    // warehouse hand answers «403» about a server that is working — the exact
    // bug the «Финансы» item in this rail already carries a comment about.
    const page = await boot({ role: 'warehouse' });
    const item = page.window.document.querySelector('[data-view="notifications"]') as HTMLElement;
    expect(item.hidden, 'a role without `content` was offered frame 25').toBe(true);
  });
});
