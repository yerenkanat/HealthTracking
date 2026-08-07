/**
 * The queue board on screen.
 *
 * queues.test.ts proves the route. This proves an operator can see it, and
 * that the two dashboards really are two: the owner's block — revenue, margin,
 * stock value — must not be on her screen, and her board must not be the only
 * thing on his.
 *
 * The detail worth a test rather than a glance: the big number on a queue card
 * is the AGE, not the count. A board reading "3" and a board reading "4 дн."
 * lead to different mornings, and the count belongs underneath as the
 * explaining line the spec requires of every metric.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const hoursAgo = (h: number) => new Date(Date.now() - h * 3_600_000).toISOString();

const OPERATOR_QUEUES = {
  available: ['leads', 'orders', 'emergencies'],
  slaHours: { emergencies: 1, leads: 4, orders: 48 },
  overdue: ['emergencies', 'leads'],
  queues: {
    leads: {
      waiting: 3, oldestHours: 30,
      next: [
        { id: 'l1', who: 'Мадина', detail: 'Комплект', since: hoursAgo(30) },
        { id: 'l2', who: 'Айгерім', detail: 'Часы', since: hoursAgo(5) },
      ],
    },
    orders: { waiting: 0, oldestHours: null, next: [] },
    emergencies: {
      waiting: 1, oldestHours: 3,
      next: [{ id: 'e1', who: 'Гүлнұр', detail: 'sos · critical', since: hoursAgo(3) }],
    },
  },
};

const SELLER_QUEUES = {
  available: ['leads', 'orders'],
  slaHours: { emergencies: 1, leads: 4, orders: 48 },
  overdue: [],
  queues: {
    leads: { waiting: 0, oldestHours: null, next: [] },
    orders: { waiting: 0, oldestHours: null, next: [] },
  },
};

const NO_QUEUES = { available: [], queues: null };

async function open(role: string, queues: unknown) {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: 'http://localhost/admin',
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
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      (window as unknown as { alert: (m: string) => void }).alert = () => {};

      window.fetch = (async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role, displayName: 'Ерен' }) };
        }
        if (p.includes('/admin/queues')) {
          return { ok: true, status: 200, text: async () => '', json: async () => queues };
        }
        // The owner's dashboard is the finance capability; a non-owner is
        // refused it, exactly as the real server does.
        if (p.includes('/admin/dashboard') && role !== 'owner') {
          return { ok: false, status: 403, text: async () => '', json: async () => ({ error: 'forbidden' }) };
        }
        return { ok: true, status: 200, text: async () => '', json: async () => ({}) };
      }) as never;
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 400));
  const $ = (sel: string) => window.document.querySelector(sel) as HTMLElement;
  return { window, errors, $ };
}

describe('the operator sees her queues', () => {
  it('the board is on screen with a card per queue', async () => {
    const { $, window, errors } = await open('operator', OPERATOR_QUEUES);
    expect(errors, errors.join('\n')).toEqual([]);
    expect($('#queueBoard').hidden).toBe(false);
    expect(window.document.querySelectorAll('#queueKpis [data-queue]').length).toBe(3);
  });

  it('the big number is the wait, and the count explains it', async () => {
    const { $ } = await open('operator', OPERATOR_QUEUES);
    const card = $('#queueKpis [data-queue="leads"]');
    // Hours up to a day and a half, because in that band the precision is
    // worth reading: «30 ч» and «1 дн.» send somebody to a different task.
    expect(card.querySelector('.val')!.textContent).toBe('30 ч');
    expect(card.querySelector('.delta')!.textContent).toContain('3 заявк');
    expect(card.querySelector('.delta')!.textContent).toContain('норма 4 ч');
  });

  it('a wait long enough to count in days is said in days', async () => {
    // «97 ч» is a number somebody has to divide before it means anything.
    const { $ } = await open('operator', {
      ...OPERATOR_QUEUES,
      queues: {
        ...OPERATOR_QUEUES.queues,
        leads: { waiting: 1, oldestHours: 97, next: [{ id: 'l1', who: 'Мадина', detail: 'Комплект', since: hoursAgo(97) }] },
      },
    });
    expect($('#queueKpis [data-queue="leads"]').querySelector('.val')!.textContent).toBe('4 дн.');
  });

  it('a wait under an hour is not rounded down to nothing', async () => {
    // Zero would read as "nothing is waiting" on a card that has something on
    // it, which is the one thing this board must never say.
    const { $ } = await open('operator', {
      ...OPERATOR_QUEUES,
      queues: {
        ...OPERATOR_QUEUES.queues,
        leads: { waiting: 1, oldestHours: 0, next: [{ id: 'l1', who: 'Мадина', detail: 'Комплект', since: hoursAgo(0) }] },
      },
    });
    expect($('#queueKpis [data-queue="leads"]').querySelector('.val')!.textContent).toBe('меньше часа');
  });

  it('an empty queue says so instead of showing a zero', async () => {
    const { $ } = await open('operator', OPERATOR_QUEUES);
    const card = $('#queueKpis [data-queue="orders"]');
    expect(card.querySelector('.val')!.textContent).toBe('—');
    expect(card.querySelector('.delta')!.textContent).toBe('очередь пуста');
  });

  it('lists the front of each queue, oldest first', async () => {
    const { $ } = await open('operator', OPERATOR_QUEUES);
    const text = $('#queueLists').textContent ?? '';
    expect(text).toContain('Мадина');
    expect(text).toContain('Гүлнұр');
    expect(text.indexOf('Мадина')).toBeLessThan(text.indexOf('Айгерім'));
    // An empty queue contributes no card — a board of "нет заявок" panels is
    // the same screen with more to read.
    expect(text).not.toContain('Заказы к отгрузке');
  });

  it('marks only what is actually late', async () => {
    // Crimson is for action and lateness. A board where everything is red says
    // nothing, so the orders queue — empty — must not be marked.
    const { $ } = await open('operator', OPERATOR_QUEUES);
    const val = (k: string) =>
      ($(`#queueKpis [data-queue="${k}"]`).querySelector('.val') as HTMLElement).style.color;
    expect(val('emergencies')).toContain('crit');
    expect(val('leads')).toContain('crit');
    expect(val('orders')).toBe('');
  });
});

describe('the two dashboards are two', () => {
  it('an operator is not shown revenue, margin or stock value', async () => {
    const { $ } = await open('operator', OPERATOR_QUEUES);
    // These read /admin/dashboard, which is the finance capability. Left on
    // screen they would show "Сводка недоступна" where the business used to
    // be — the wrong dashboard, blanked, which is worse than the wrong one.
    expect($('#dashKpis').hidden).toBe(true);
    expect($('#queueBoard').hidden).toBe(false);
  });

  it('an owner keeps the business block and gets the board too', async () => {
    // He runs the queues on a small team. "Не смешивать" is about not putting
    // the operator's questions in place of his, not about hiding the work.
    const { $ } = await open('owner', OPERATOR_QUEUES);
    expect($('#dashKpis').hidden).toBe(false);
    expect($('#queueBoard').hidden).toBe(false);
  });

  it('a seller sees her two queues and no alarms', async () => {
    const { window, $ } = await open('seller', SELLER_QUEUES);
    expect($('#queueBoard').hidden).toBe(false);
    const keys = [...window.document.querySelectorAll('#queueKpis [data-queue]')]
      .map((el) => (el as HTMLElement).dataset.queue);
    expect(keys.sort()).toEqual(['leads', 'orders']);
  });

  it('a warehouse hand gets no board at all, rather than an empty one', async () => {
    // Her work arrives as a shipment, not as a list of people waiting. A board
    // of three permanent zeroes is furniture.
    const { $ } = await open('warehouse', NO_QUEUES);
    expect($('#queueBoard').hidden).toBe(true);
  });
});
