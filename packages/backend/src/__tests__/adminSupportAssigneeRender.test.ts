/**
 * Three fields every support ticket carried and no pixel ever showed:
 * `assigneeId`, `customerReadAt`, `closedAt`.
 *
 * What they cost: two operators answer the same woman a minute apart and
 * neither can see the other did, and a third rings her to chase a reply she
 * read yesterday.
 *
 * The rules these pin down:
 *   - the assignee is a NAME, never the uuid (nobody recognises a colleague by
 *     uuid), and an id that resolves to no name says so rather than reading as
 *     "free to take";
 *   - `customerReadAt` is only meaningful for the app channel — a WhatsApp
 *     ticket is never «не прочитано», it is «этот канал не сообщает»;
 *   - «взять на себя» reports the RESULT of its request, not that one was sent.
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
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';
import { buildSupportBoard, SUPPORT_SLA_HOURS, whatsappReplyLink } from '../admin/support';
import type { SupportTicketRow } from '../db/repository';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const NOW = '2026-08-11T12:00:00.000Z';
const hoursAgo = (h: number) => new Date(Date.parse(NOW) - h * 3_600_000).toISOString();

const ME = '55555555-5555-4555-8555-555555555555';
const HER = '66666666-6666-4666-8666-666666666666';
const GHOST = '77777777-7777-4777-8777-777777777777';

let n = 0;
const ticket = (t: Partial<SupportTicketRow> = {}): SupportTicketRow => ({
  id: `t${++n}`, userId: null, phone: '+7 707 345 22 44', customerName: 'Айгерім',
  channel: 'whatsapp', subject: 'Не приходит код', body: 'Жду 10 минут.',
  status: 'new', assigneeId: null,
  createdAt: hoursAgo(1), updatedAt: hoursAgo(1),
  answeredAt: null, closedAt: null, appContext: null,
  lastCustomerAt: null, customerReadAt: null,
  ...t,
});

// Neutral subjects on purpose: a subject reading «ведёт Айгуль» would satisfy
// an assertion about the assignee column from the wrong cell, and the column
// could be deleted with the test still green. (It was, once — this comment is
// what the revert-check turned up.)
const FREE = ticket({ subject: 'Не приходит код', customerName: 'Айгерім' });
const HERS = ticket({ subject: 'Где мой заказ', customerName: 'Сәуле', assigneeId: HER });
const MINE = ticket({ subject: 'Вопрос по оплате', customerName: 'Мадина', assigneeId: ME });
const UNKNOWN = ticket({ subject: 'Ошибка в приложении', customerName: 'Динара', assigneeId: GHOST });
const READ = ticket({
  subject: 'Прочитала ответ', customerName: 'Айнұр', channel: 'app', phone: null,
  status: 'closed', answeredAt: hoursAgo(30), closedAt: hoursAgo(20),
  customerReadAt: '2026-08-10T09:05:00.000Z',
});
const UNREAD = ticket({
  subject: 'Ещё не открывала', customerName: 'Ұлжан', channel: 'app', phone: null,
  answeredAt: hoursAgo(2),
});

const TICKETS = [FREE, HERS, MINE, UNKNOWN, READ, UNREAD];
const NAMES: Record<string, string> = { [ME]: 'Разработка', [HER]: 'Айгуль' };

const BOARD = buildSupportBoard(TICKETS, NOW);
const PAYLOAD = {
  ...BOARD,
  slaHours: SUPPORT_SLA_HOURS,
  templates: [],
  items: BOARD.items.map((t) => ({
    ...t,
    whatsapp: whatsappReplyLink(t),
    assigneeName: t.assigneeId ? NAMES[t.assigneeId] ?? null : null,
  })),
};

const card = (id: string) => {
  const t = TICKETS.find((x) => x.id === id) ?? TICKETS[0];
  return {
    ticket: t,
    assigneeName: t.assigneeId ? NAMES[t.assigneeId] ?? null : null,
    replies: [],
    whatsapp: whatsappReplyLink(t),
  };
};

interface Rendered {
  text(s: string): string;
  el(s: string): Element | null;
  rowText(subject: string): string;
  /** The «Ведёт» cell of the row carrying [subject] — the 5th column. */
  assigneeCell(subject: string): string;
  open(id: string): Promise<void>;
  click(s: string): Promise<void>;
  writes: Array<{ url: string; body: unknown }>;
  errors: string[];
}

/** @param failPatch make PATCH answer 500, to prove the panel says so */
async function boot(failPatch = false): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const writes: Array<{ url: string; body: unknown }> = [];
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
      settle.attach(window as never, async (path: string, opts?: PanelRequestInit) => {
        const p = String(path);
        if (opts?.method === 'PATCH') {
          writes.push({ url: p, body: JSON.parse(opts.body ?? '{}') });
          return failPatch
            ? { ok: false, status: 500, text: async () => 'boom', json: async () => ({}) }
            : { ok: true, status: 200, json: async () => ({ ok: true }) };
        }
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: ME, role: 'admin', displayName: 'Разработка' }) };
        }
        const single = /\/admin\/support\/([^/]+)$/.exec(p);
        if (single) {
          return { ok: true, status: 200, json: async () => card(decodeURIComponent(single[1])) };
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
  const flat = (el: Element | null | undefined) =>
    (el?.textContent ?? '').replace(/\s+/g, ' ').trim();
  return {
    errors, writes,
    text: (s) => flat(window.document.querySelector(s)),
    el: (s) => window.document.querySelector(s),
    rowText: (subject) => flat([...window.document.querySelectorAll('#supBody tbody tr')]
      .find((tr) => flat(tr).includes(subject))),
    assigneeCell: (subject) => {
      const tr = [...window.document.querySelectorAll('#supBody tbody tr')]
        .find((row) => flat(row).includes(subject));
      const heads = [...window.document.querySelectorAll('#supBody thead th')].map(flat);
      const col = heads.indexOf('Ведёт');
      expect(col, 'the queue has no «Ведёт» column at all').toBeGreaterThan(-1);
      return flat(tr?.querySelectorAll('td')[col]);
    },
    open: async (id) => {
      window.document.querySelector(`#supBody button[data-ticket="${id}"]`)!
        .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
      await settle.quiet();
    },
    click: async (s) => {
      window.document.querySelector(s)!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
      await settle.quiet();
    },
  };
}

describe('the queue says who is on each ticket', () => {
  let page: Rendered;
  beforeAll(async () => { page = await boot(); });

  it('renders without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('names the colleague holding it, and marks your own', () => {
    // Read out of the «Ведёт» cell, not out of the row: a row-wide match would
    // be satisfied by the customer's name or the subject.
    expect(page.assigneeCell(HERS.subject)).toContain('Айгуль');
    expect(page.assigneeCell(MINE.subject)).toContain('вы');
  });

  it('says «никто» for an unheld ticket rather than leaving a blank cell', () => {
    expect(page.assigneeCell(FREE.subject)).toBe('никто');
  });

  it('does not print a staff uuid at anybody', () => {
    expect(page.text('#supBody')).not.toContain(HER);
    expect(page.text('#supBody')).not.toContain(GHOST);
    // An id that resolved to nothing is said in words — an empty cell would
    // read as "free", and the ticket would be answered twice.
    expect(page.assigneeCell(UNKNOWN.subject)).toContain('имя не найдено');
  });

  it('explains the column in the card footer', () => {
    expect(page.text('#supRule')).toContain('ведёт');
  });
});

describe('the ticket card', () => {
  let page: Rendered;
  beforeAll(async () => { page = await boot(); });

  it('leads with who has it', async () => {
    await page.open(HERS.id);
    expect(page.text('#scMeta')).toContain('Айгуль');
  });

  it('says when SHE last read it, for a ticket raised in the app', async () => {
    await page.open(READ.id);
    const meta = page.text('#scMeta');
    expect(meta).toContain('открывала переписку');
    expect(meta).toContain('10.08');
  });

  it('does not claim «не прочитано» on a channel that cannot know', async () => {
    await page.open(FREE.id);
    const meta = page.text('#scMeta');
    expect(meta).toContain('не сообщает');
    expect(meta).not.toContain('открывала переписку');
  });

  it('says outright that she has never opened an app thread we answered', async () => {
    await page.open(UNREAD.id);
    expect(page.text('#scMeta')).toContain('ни разу не открывала');
  });

  it('shows when it was closed, and only for a closed ticket', async () => {
    await page.open(READ.id);
    expect(page.text('#scMeta')).toContain('Закрыто');
    await page.open(FREE.id);
    expect(page.text('#scMeta')).not.toContain('Закрыто');
  });
});

describe('taking a ticket on yourself', () => {
  it('sends the assignment and re-reads the card', async () => {
    const page = await boot();
    await page.open(FREE.id);
    expect((page.el('#scTake') as HTMLButtonElement).hidden).toBe(false);
    await page.click('#scTake');

    expect(page.writes).toHaveLength(1);
    expect(page.writes[0].url).toContain(`/admin/support/${FREE.id}`);
    expect(page.writes[0].body).toEqual({ assigneeId: ME });
  });

  it('offers to give back one you already hold', async () => {
    const page = await boot();
    await page.open(MINE.id);
    const btn = page.el('#scTake') as HTMLButtonElement;
    expect(btn.hidden).toBe(false);
    expect(btn.textContent).toContain('Снять с себя');
    await page.click('#scTake');
    expect(page.writes[0].body).toEqual({ assigneeId: null });
  });

  it('hides the button on a ticket somebody else is holding', async () => {
    const page = await boot();
    await page.open(HERS.id);
    expect((page.el('#scTake') as HTMLButtonElement).hidden).toBe(true);
  });

  it('says the write FAILED instead of pretending it landed', async () => {
    const page = await boot(true);
    await page.open(FREE.id);
    await page.click('#scTake');
    expect(page.text('#scNote')).toContain('Не удалось изменить исполнителя');
  });
});
