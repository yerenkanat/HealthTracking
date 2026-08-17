/**
 * Render frame 12 for real (jsdom): the queue, the banner that names a person,
 * and the ticket card.
 *
 * The payload is built by the REAL module, so a fixture cannot drift from what
 * the server sends and leave this testing a screen nobody will see.
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
import { buildSupportBoard, SUPPORT_SLA_HOURS, whatsappReplyLink } from '../admin/support';
import type { SupportTicketRow } from '../db/repository';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const NOW = '2026-08-11T12:00:00.000Z';
const hoursAgo = (h: number) => new Date(Date.parse(NOW) - h * 3_600_000).toISOString();

let n = 0;
const ticket = (t: Partial<SupportTicketRow> = {}): SupportTicketRow => ({
  id: `t${++n}`, userId: null, phone: '+7 707 345 22 44', customerName: 'Айгерім',
  channel: 'whatsapp', subject: 'Не приходит код', body: 'Жду 10 минут.',
  status: 'new', assigneeId: null,
  createdAt: hoursAgo(1), updatedAt: hoursAgo(1),
  answeredAt: null, closedAt: null, appContext: 'Приложение: 0.1.0',
  lastCustomerAt: null, customerReadAt: null,
  ...t,
});

const TICKETS = [
  ticket({ subject: 'Не приходит код', customerName: 'Айгерім', createdAt: hoursAgo(9) }),
  // Raised from the app — frame 43. The answer to this one goes back INTO the
  // app, so the operator must not go looking for it in WhatsApp.
  ticket({
    subject: 'Где мой заказ', customerName: 'Мадина', channel: 'app',
    createdAt: hoursAgo(2), phone: null,
  }),
  ticket({
    subject: 'Спасибо', customerName: 'Динара', status: 'waiting',
    createdAt: hoursAgo(300), answeredAt: hoursAgo(290),
  }),
];
const BOARD = buildSupportBoard(TICKETS, NOW);
const PAYLOAD = {
  ...BOARD,
  slaHours: SUPPORT_SLA_HOURS,
  templates: [
    { id: 'where_order', title: 'Где мой заказ', bodyRu: 'Заказ {status}.', bodyKk: 'Тапсырыс {status}.', sort: 10 },
  ],
  items: BOARD.items.map((t) => ({ ...t, whatsapp: whatsappReplyLink(t) })),
};
/** The single-ticket route, answered for whichever id was asked for. */
const one = (id: string) => {
  const t = TICKETS.find((x) => x.id === id) ?? TICKETS[0];
  return {
    ticket: t,
    replies: [{ id: 'r1', ticketId: t.id, author: 'staff', staffId: 's1', body: 'Проверяю.', at: hoursAgo(1) }],
    whatsapp: whatsappReplyLink(t),
  };
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
      window.confirm = () => true;
      settle.attach(window as never, async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        // The single-ticket route must be matched BEFORE the board route, or
        // /admin/support/<id> answers with the whole board.
        const single = /\/admin\/support\/([^/]+)$/.exec(p);
        if (single) {
          return { ok: true, status: 200, json: async () => one(decodeURIComponent(single[1])) };
        }
        const body = p.includes('/admin/support') ? PAYLOAD
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
  window.document.querySelector('[data-view="support"]')!
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

describe('frame 12 — the queue', () => {
  let page: Rendered;
  beforeAll(async () => { page = await boot(); });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('puts the longest wait at the TOP', async () => {
    // A queue, not a log. Newest-first keeps whoever has waited longest at the
    // bottom of the screen all day.
    const t = page.text('#supBody');
    expect(t.indexOf('Айгерім')).toBeLessThan(t.indexOf('Мадина'));
  });

  it('sinks a ticket waiting on the CUSTOMER below every one that is ours', () => {
    const t = page.text('#supBody');
    expect(t.indexOf('Динара')).toBeGreaterThan(t.indexOf('Мадина'));
  });

  it('names the PERSON in the banner, not the count', () => {
    // «3 просрочено» tells an operator nothing about who to open first.
    expect((page.el('#supAlert') as HTMLElement).hasAttribute('hidden')).toBe(false);
    expect(page.text('#supAlertTitle')).toContain('Айгерім');
    expect(page.text('#supAlertBody')).toContain('Не приходит код');
  });

  it('does not count the answered ticket as waiting', () => {
    // Динара was answered 290 hours ago and has not written back. Counting her
    // teaches an operator to ignore the colour on the screen.
    expect(page.text('#supKpis')).toContain('Ждут ответа');
    const badge = page.el('#supBadge') as HTMLElement;
    expect(badge.textContent).toBe('2');
  });

  it('states the counting rule under the table', () => {
    expect(page.text('#supRule')).toContain('ждём клиента');
  });

  it('names the app channel in Russian, not as «app»', () => {
    // The column printed the raw column value, so a ticket raised in the app
    // read «app» in a Russian table.
    const t = page.text('#supBody');
    expect(t).toContain('Приложение');
    expect(t).not.toMatch(/\bapp\b/);
  });
});

describe('frame 12 — the ticket card', () => {
  let page: Rendered;
  beforeAll(async () => { page = await boot(); });

  it('opens with the thread', async () => {
    await page.click('#supBody button[data-ticket]');
    expect((page.el('#supCard') as HTMLElement).hasAttribute('hidden')).toBe(false);
    const t = page.text('#scThread');
    expect(t).toContain('Жду 10 минут.');   // her message
    expect(t).toContain('Проверяю.');        // ours
  });

  it('shows what the app knew, so nobody asks «какая у вас версия»', () => {
    expect((page.el('#scCtx') as HTMLElement).hasAttribute('hidden')).toBe(false);
    expect(page.text('#scCtx')).toContain('0.1.0');
  });

  it('offers the WhatsApp link the SERVER composed', () => {
    const wa = page.el('#scWa') as HTMLAnchorElement;
    expect(wa.hasAttribute('hidden')).toBe(false);
    expect(wa.href).toContain('wa.me/77073452244');
  });

  it('says where the answer will land for a ticket raised in the app', async () => {
    // The operator's habit is WhatsApp. For an app ticket the answer goes back
    // into the app as a push, and Мадина has no number at all — writing to a
    // number she never gave us is the failure this line prevents.
    const app = TICKETS.find((t) => t.channel === 'app')!;
    await page.click(`#supBody button[data-ticket="${app.id}"]`);
    expect(page.text('#scSub')).toContain('Приложение');
    expect(page.text('#scNote')).toContain('приложении');
    expect((page.el('#scWa') as HTMLElement).hasAttribute('hidden')).toBe(true);
  });

  it('a template fills the reply box, placeholders intact', async () => {
    await page.click('#scTemplates button[data-tpl]');
    const box = page.el('#scReply') as HTMLTextAreaElement;
    // Left visible on purpose: «{status}» reaching a customer is embarrassing
    // and gets caught; a blank reads as finished and gets sent.
    expect(box.value).toContain('{status}');
  });
});
