/**
 * Frame 09a in the browser: этап · заказы · курс, actually painted.
 *
 * The backend can return a perfect `mother` block and the operator still reads
 * nothing — that is this repo's most common failure, and the family sections
 * next door were exactly it for months. So this boots the real panel, opens a
 * real mother, and reads the drawer's text.
 *
 * The sentences asserted are the ones the spec asks for by name: the stage
 * with its reason, the last order's status, and «доступ есть, но ни разу не
 * открывала».
 */

import { describe, it, expect } from 'vitest';
import { answerReasonPromptIfShown } from './helpers/reasonPrompt.js';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const UID = '11111111-1111-1111-1111-111111111111';
const USERS = {
  total: 1,
  users: [{ id: UID, displayName: 'Айгерим', phone: '+77015551122', dueDate: null, lastMetricAt: null }],
};

function detail(mother: unknown) {
  return {
    id: UID, displayName: 'Айгерим', phone: '+77015551122', dueDate: null,
    locale: 'ru-KZ', birthDate: null, city: null,
    latest: { hr: 78, spo2: 98, systolic: 118, diastolic: 76, temp: 36.6 },
    triage: [], children: [], devices: [], alerts: [], sleepNights: 0, loggedDays: 0,
    appointments: [], mother,
  };
}

const WELLNESS = {
  sleep: [], days: [], alerts: [], weight: [], medications: [], medicalIds: [],
  kickSessions: [], contractionSessions: [], newbornEvents: [], bpCalibration: null,
  growth: [], doses: [], vaccines: [],
};

async function openDrawer(mother: unknown): Promise<{ drawer: string; errors: string[] }> {
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
      (window as unknown as { CSS: unknown }).CSS = { escape: (s: string) => String(s).replace(/["\\]/g, '\\$&') };
      window.fetch = (async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (p.includes('/admin/bi') || p.includes('/admin/analytics')) {
          return { ok: false, status: 503, json: async () => ({}), text: async () => '' };
        }
        const body = p.includes('/wellness')
          ? WELLNESS
          : p.includes('/detail')
            ? detail(mother)
            : p.includes('/admin/users')
              ? USERS
              : p.includes('/admin/stats')
                ? { activeUsers: 1, devicesOnline: 0, alertsToday: 0, ingestLastHour: 0 }
                : {};
        return { ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) };
      }) as never;
    },
  });

  const { window } = dom;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  await wait(200);
  window.document.querySelector('[data-view="users"]')!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(500);
  const row = window.document.querySelector(`#usersBody tr[data-user="${UID}"]`);
  if (!row) throw new Error('no user row rendered');
  row.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(200);
  await answerReasonPromptIfShown(window);

  return { drawer: (window.document.querySelector('#drawer')?.textContent ?? '').replace(/\s+/g, ' ').trim(), errors };
}

/** A mother mid-relationship: shipped комплект, course untouched. */
const CUSTOMER = {
  stage: 'pregnancy',
  stageReason: 'срок родов 2026-11-20',
  orders: {
    total: 2, open: 1, spentMinor: 3900000,
    lastAt: '2026-08-01T09:00:00.000Z', lastStatus: 'shipped',
    recent: [
      {
        id: 'o3', status: 'shipped', createdAt: '2026-08-01T09:00:00.000Z', totalMinor: 3900000,
        items: [{ productName: 'Умные часы', qty: 1 }, { productName: 'Трекер', qty: 1 }],
      },
      { id: 'o2', status: 'cancelled', createdAt: '2026-06-01T09:00:00.000Z', totalMinor: 2980000, items: [] },
    ],
  },
  course: { unlocked: true, started: 0, completed: 0, lastAt: null, neverStarted: true },
};

describe('the mother card in the drawer', () => {
  it('renders without throwing', async () => {
    const { errors } = await openDrawer(CUSTOMER);
    expect(errors).toEqual([]);
  });

  it('shows the stage in the product vocabulary, with the reason it was derived from', async () => {
    // A derived label with no working shown is something to argue with.
    const { drawer } = await openDrawer(CUSTOMER);
    expect(drawer).toContain('Этап');
    expect(drawer).toContain('Беременность');
    expect(drawer).toContain('срок родов 2026-11-20');
  });

  it('shows the orders with the last status, in Russian', async () => {
    const { drawer } = await openDrawer(CUSTOMER);
    expect(drawer).toContain('Заказы · 2');
    expect(drawer).toContain('Отправлен');   // the shipped one
    expect(drawer).toContain('Отменён');     // still listed — it is an answer
    expect(drawer).toContain('Умные часы');  // what was in the box
  });

  it('shows what she spent, and says the cancelled one is not in it', async () => {
    const { drawer } = await openDrawer(CUSTOMER);
    expect(drawer).toContain('39 000 ₸');
    expect(drawer).toContain('без отменённых');
    // 29 800 was cancelled; the total must not have grown to 68 800.
    expect(drawer).not.toContain('68 800');
  });

  it('says «доступ есть, но ни разу не открывала»', async () => {
    const { drawer } = await openDrawer(CUSTOMER);
    expect(drawer).toContain('Курс Ма!Ма!');
    expect(drawer).toContain('Доступ есть, но ни разу не открывала');
  });

  it('raises it in «Требует внимания» too, where staff actually look', async () => {
    const { drawer } = await openDrawer(CUSTOMER);
    expect(drawer).toContain('Курс оплачен, но ни разу не открыт');
    expect(drawer).toContain('Заказ в работе: 1');
  });

  it('does not accuse her of ignoring a course she never bought', async () => {
    const { drawer, errors } = await openDrawer({
      ...CUSTOMER,
      course: { unlocked: false, started: 0, completed: 0, lastAt: null, neverStarted: false },
    });
    expect(errors).toEqual([]);
    expect(drawer).not.toContain('ни разу не открывала');
    expect(drawer).toContain('комплект не покупали');
  });

  it('shows how far she got once she starts', async () => {
    const { drawer } = await openDrawer({
      ...CUSTOMER,
      course: { unlocked: true, started: 4, completed: 2, lastAt: '2026-08-05T09:00:00.000Z', neverStarted: false },
    });
    expect(drawer).toContain('Доступ открыт');
    expect(drawer).toContain('начато 4');
    expect(drawer).toContain('пройдено 2');
    expect(drawer).toContain('Последний раз открывала');
  });

  it('states plainly that she has never ordered, rather than hiding the block', async () => {
    // A missing block reads as "not loaded". The operator needs "she has none".
    const { drawer, errors } = await openDrawer({
      ...CUSTOMER,
      orders: { total: 0, open: 0, spentMinor: 0, lastAt: null, lastStatus: null, recent: [] },
    });
    expect(errors).toEqual([]);
    expect(drawer).toContain('Заказов на этот номер нет');
  });

  it('draws the rest of the card when an older server sends no mother block', async () => {
    const { drawer, errors } = await openDrawer(undefined);
    expect(errors).toEqual([]);
    expect(drawer).toContain('Профиль');
    expect(drawer).not.toContain('Заказов на этот номер нет');
    expect(drawer).not.toContain('Этап');
  });
});
