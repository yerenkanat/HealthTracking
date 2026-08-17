/**
 * Writes that failed and said nothing, and destructive edits that asked
 * nothing — docs/BACKLOG.md §4.
 *
 * All four had the same shape: `await fetch(…)` with the response never read.
 * fetch does not throw on 4xx or 5xx, so every one of them redrew an unchanged
 * list, which an operator reads as a stale render rather than as a refusal:
 *
 *   §4.1 revoking course access — the customer keeps a course she was meant to
 *        lose, and nothing on the screen disagrees;
 *   §4.2 BLOCKING A STOLEN TRACKER. The worst instance in the file: the thief
 *        keeps a working device and the warehouse believes it is dead;
 *   §4.3 reordering a lesson. The commonest refusal is the bilingual gate — a
 *        published lesson with no Kazakh title 400s on every PUT, including
 *        one that only moves it — so the operator clicks ↑ repeatedly and
 *        nothing moves, with no explanation anywhere;
 *   §4.4 deleting a content card, and publishing an emptied stage, both with
 *        no confirmation at all. `{items: []}` wipes a live week for every
 *        reader of the app.
 *
 * Rendered in jsdom with the real panel, because "the handler checks r.ok" and
 * "the person is told" are different claims, and only the second one matters.
 *
 * ---------------------------------------------------------------------------
 * WAITING
 *
 * Five fixed sleeps — 200 after boot, 300 after the tab, 250 per click —
 * decided their verdict on elapsed wall-clock rather than on the work being
 * finished. Everything asserted here is a message written AFTER a write comes
 * back, so a window that closed early read the screen mid-request and would
 * have reported the very silence this file exists to forbid.
 *
 * They are all quiet() now: no request in flight, none newly issued for several
 * consecutive turns, no page timer outstanding, and a throw rather than a
 * half-drawn screen. See helpers/panelSettle.ts.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

interface Sent { path: string; method: string; body: unknown }

/** How a stubbed route answers. */
interface Reply { ok?: boolean; status?: number; body?: unknown }

interface Opts {
  /** Which tab to open. */
  view: string;
  /** GET payloads, keyed by a substring of the path. First match wins. */
  get?: Array<[string, unknown]>;
  /** Non-GET answers, keyed by a substring of the path. First match wins. */
  write?: Array<[string, Reply]>;
  /** What window.confirm returns. Every question asked is recorded. */
  confirmAnswer?: boolean;
}

/** A booted panel that knows when it has finished working. */
interface Page {
  window: JSDOM['window'];
  quiet: (label?: string) => Promise<void>;
}

async function open(opts: Opts) {
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
  const sent: Sent[] = [];
  const confirms: string[] = [];
  const alerts: string[] = [];
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
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      (window as unknown as { alert: (m: string) => void }).alert = (m) => alerts.push(m);
      (window as unknown as { confirm: (m: string) => boolean }).confirm = (m) => {
        confirms.push(m);
        return opts.confirmAnswer ?? true;
      };

      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = path;
        const method = init?.method ?? 'GET';
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, text: async () => '', json: async () => ({ staffId: 's1', role: 'owner', displayName: 'Ерен' }) };
        }
        if (method !== 'GET') {
          sent.push({ path: p, method, body: init?.body ? JSON.parse(String(init.body)) : null });
          const hit = (opts.write ?? []).find(([m]) => p.includes(m));
          const r = hit ? hit[1] : { ok: true, status: 200, body: { ok: true } };
          return {
            ok: r.ok ?? true, status: r.status ?? 200,
            text: async () => '', json: async () => r.body ?? {},
          };
        }
        const hit = (opts.get ?? []).find(([m]) => p.includes(m));
        return { ok: true, status: 200, text: async () => '', json: async () => (hit ? hit[1] : {}) };
      });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  window.document.querySelector(`[data-view="${opts.view}"]`)!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet(`the ${opts.view} tab`);
  return { window, sent, confirms, alerts, errors, quiet: settle.quiet };
}

const click = async (page: Page, sel: string) => {
  const el = page.window.document.querySelector(sel);
  expect(el, `no ${sel} on the page`).not.toBeNull();
  el!.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));
  await page.quiet(`the click on ${sel}`);
  return el as HTMLElement;
};

const text = (window: JSDOM['window'], sel: string) =>
  window.document.querySelector(sel)?.textContent ?? '';

// ---------------------------------------------------------------------------
// §4.1 — revoking course access
// ---------------------------------------------------------------------------

const LESSONS = {
  lessons: [
    { id: 'l1', course: 'mama', titleRu: 'Первые 40 дней', titleKk: 'Алғашқы 40 күн', summaryRu: null, summaryKk: null, youtubeUrl: 'https://youtu.be/aaaaaaaaaaa', sort: 10, published: true },
    { id: 'l2', course: 'mama', titleRu: 'Сон малыша', titleKk: '', summaryRu: null, summaryKk: null, youtubeUrl: 'https://youtu.be/bbbbbbbbbbb', sort: 20, published: true },
  ],
};
const ENTITLEMENTS = {
  entitlements: [
    { phone: '77001112233', feature: 'mama_course', orderId: null, grantedBy: 's1', note: 'заказ', at: '2026-07-01T10:00:00.000Z' },
  ],
};
const courseGets: Array<[string, unknown]> = [
  ['/admin/course/lessons', LESSONS],
  ['/admin/course/progress', { progress: [] }],
  ['/admin/entitlements', ENTITLEMENTS],
];

describe('§4.1 — revoking course access', () => {
  it('says the access was NOT closed when the server refuses', async () => {
    const page = await open({
      view: 'course', get: courseGets,
      write: [['/admin/entitlements/', { ok: false, status: 500, body: {} }]],
    });
    const { window, sent } = page;

    await click(page, '#entBody .erev');

    expect(sent.some((s) => s.method === 'DELETE'), 'it did try').toBe(true);
    const msg = text(window, '#entMsg');
    expect(msg, 'a failed revoke said nothing at all').toMatch(/НЕ закрыт/);
    // The customer is named, because the operator is looking at a list of them.
    expect(msg).toContain('77001112233');
    // And the row is still there, which is now the truth rather than a stale
    // render: she still has the course.
    expect(text(window, '#entBody')).toContain('77001112233');
  });

  it('names the capability when the refusal is a 403', async () => {
    // «Не удалось» sends somebody to a developer; «нет права Заказы» sends
    // them to the owner, who can actually fix it.
    const page = await open({
      view: 'course', get: courseGets,
      write: [['/admin/entitlements/', { ok: false, status: 403, body: { error: 'forbidden' } }]],
    });
    const { window } = page;
    await click(page, '#entBody .erev');
    expect(text(window, '#entMsg')).toMatch(/нет права «Заказы»/i);
  });

  it('confirms it when the revoke actually lands', async () => {
    const page = await open({ view: 'course', get: courseGets });
    const { window, sent } = page;
    await click(page, '#entBody .erev');
    expect(sent.find((s) => s.method === 'DELETE')!.path).toContain('77001112233');
    expect(text(window, '#entMsg')).toMatch(/Доступ закрыт/);
  });

  it('still asks first, and sends nothing when the answer is no', async () => {
    const page = await open({
      view: 'course', get: courseGets, confirmAnswer: false,
    });
    const { sent, confirms } = page;
    await click(page, '#entBody .erev');
    expect(confirms.length).toBe(1);
    expect(sent.filter((s) => s.method === 'DELETE')).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// §4.3 — reordering a lesson
// ---------------------------------------------------------------------------

describe('§4.3 — reordering a lesson that the bilingual gate refuses', () => {
  /** What the server really answers for a published lesson with no titleKk. */
  const GATE = {
    ok: false, status: 400,
    body: {
      error: 'translation_required', field: 'titleKk',
      message: 'Нельзя опубликовать урок без казахского названия. Сохраните как черновик и вернитесь, когда перевод будет готов.',
    },
  };

  it('repeats the server\'s own reason instead of redrawing in silence', async () => {
    const page = await open({
      view: 'course', get: courseGets,
      write: [['/admin/course/lessons', GATE]],
    });
    const { window, sent } = page;

    // ↓ on the first lesson: swap it with «Сон малыша», which is published and
    // has no Kazakh title.
    await click(page, '#lessonList .ldn');

    expect(sent.filter((s) => s.method === 'PUT').length, 'nothing was sent').toBeGreaterThan(0);
    const msg = text(window, '#lessonMsg');
    expect(msg, 'the operator clicked ↑ and was told nothing').toMatch(/Порядок не изменён/);
    expect(msg, 'the reason the server gave was thrown away').toContain('казахского названия');
  });

  it('stops after the first refusal rather than half-applying the swap', async () => {
    const page = await open({
      view: 'course', get: courseGets,
      write: [['/admin/course/lessons', GATE]],
    });
    const { sent } = page;
    await click(page, '#lessonList .ldn');
    expect(sent.filter((s) => s.method === 'PUT').length,
      'the second write went out after the first was refused').toBe(1);
  });

  it('says half when only the second write fails, because half is a real state', async () => {
    // The first PUT has landed on the server by then. Reporting "не изменён"
    // would be as wrong as reporting success.
    let n = 0;
    const html = readFileSync(PANEL, 'utf8');
    const settle = panelSettle();
    const vc = new VirtualConsole();
    const dom = new JSDOM(html, {
      runScripts: 'dangerously', pretendToBeVisual: true,
      url: 'http://localhost/admin/ui', virtualConsole: vc,
      beforeParse(window) {
        window.HTMLCanvasElement.prototype.getContext = (() => null) as never;
        window.scrollTo = () => {};
        Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
        (window as unknown as { alert: () => void }).alert = () => {};
        (window as unknown as { confirm: () => boolean }).confirm = () => true;
        settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
          const p = path;
          if (p.includes('/admin/me')) {
            return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'owner' }) };
          }
          if ((init?.method ?? 'GET') === 'PUT' && p.includes('/admin/course/lessons')) {
            n += 1;
            return n === 1
              ? { ok: true, status: 200, json: async () => ({ ok: true }) }
              : { ok: false, status: 500, json: async () => ({}) };
          }
          const body = p.includes('/admin/course/lessons') ? LESSONS
            : p.includes('/admin/course/progress') ? { progress: [] }
            : p.includes('/admin/entitlements') ? ENTITLEMENTS : {};
          return { ok: true, status: 200, json: async () => body };
        });
      },
    });
    const w = dom.window;
    const page: Page = { window: w, quiet: settle.quiet };
    await settle.quiet('boot');
    w.document.querySelector('[data-view="course"]')!
      .dispatchEvent(new w.MouseEvent('click', { bubbles: true }));
    await settle.quiet('the Курс tab');
    await click(page, '#lessonList .ldn');

    expect(w.document.querySelector('#lessonMsg')!.textContent)
      .toMatch(/наполовину/i);
  });
});

// ---------------------------------------------------------------------------
// §4.2 — blocking a stolen tracker
// ---------------------------------------------------------------------------

const REGISTRY = {
  devices: [
    { serial: 'AA:BB:CC:DD:EE:01', kind: 'band', status: 'stock', activatedByPhone: null },
  ],
};
const stockGets: Array<[string, unknown]> = [
  ['/admin/device-registry', REGISTRY],
  ['/admin/inventory', { products: [], windowDays: 30, leadTimeDays: 14 }],
  ['/admin/stock/moves', { moves: [] }],
];

describe('§4.2 — blocking a stolen tracker', () => {
  it('says the device was NOT blocked, in the row, when the server refuses', async () => {
    const page = await open({
      view: 'stock', get: stockGets,
      write: [['/status', { ok: false, status: 500, body: {} }]],
    });
    const { sent } = page;

    const btn = await click(page, '#serialBody .sblk');

    expect(sent.some((s) => s.path.includes('/status')), 'it did try').toBe(true);
    // In the row, not only in the card header: the table can be twenty rows
    // long and a message above it is a message off-screen.
    const row = btn.closest('tr')!;
    expect(row.textContent, 'a refused block said nothing at all').toMatch(/НЕ заблокировано/);
    expect(row.textContent).toContain('по-прежнему привязывается');
    // The control goes back to being clickable, and to saying what it does.
    expect((btn as HTMLButtonElement).disabled).toBe(false);
    expect(btn.textContent).toBe('Заблокировать');
    // And the status pill still says «На складе», which is what the server has.
    expect(row.textContent).toContain('На складе');
  });

  it('names a 403 as a missing capability, not as a fault', async () => {
    const page = await open({
      view: 'stock', get: stockGets,
      write: [['/status', { ok: false, status: 403, body: { error: 'forbidden' } }]],
    });
    const btn = await click(page, '#serialBody .sblk');
    expect(btn.closest('tr')!.textContent).toMatch(/складского доступа/i);
  });

  it('confirms the block when it lands', async () => {
    const page = await open({ view: 'stock', get: stockGets });
    const { window, sent, confirms } = page;
    await click(page, '#serialBody .sblk');
    expect(confirms.length, 'blocking a device did not ask').toBe(1);
    expect(sent.find((s) => s.path.includes('/status'))!.body).toEqual({ status: 'blocked' });
    expect(text(window, '#serialMsg')).toMatch(/Заблокировано/);
  });

  it('sends nothing when the operator backs out', async () => {
    const page = await open({
      view: 'stock', get: stockGets, confirmAnswer: false,
    });
    const { sent } = page;
    await click(page, '#serialBody .sblk');
    expect(sent.filter((s) => s.path.includes('/status'))).toEqual([]);
  });
});
