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

type Triage = Array<{ code: string; severity: string; at: string }>;

function detail(mother: unknown, triage: Triage = []) {
  return {
    id: UID, displayName: 'Айгерим', phone: '+77015551122', dueDate: null,
    locale: 'ru-KZ', birthDate: null, city: null,
    latest: { hr: 78, spo2: 98, systolic: 118, diastolic: 76, temp: 36.6 },
    triage, children: [], devices: [], alerts: [], sleepNights: 0, loggedDays: 0,
    appointments: [], mother,
  };
}

const WELLNESS = {
  sleep: [], days: [], alerts: [], weight: [], medications: [], medicalIds: [],
  kickSessions: [], contractionSessions: [], newbornEvents: [], bpCalibration: null,
  growth: [], doses: [], vaccines: [],
};

type Drawn = { drawer: string; errors: string[] };

/**
 * One boot per distinct fixture, not one per assertion.
 *
 * Booting the 417 KB panel in jsdom costs well over a second. This file used
 * to pay that ten times over, and the pool then starved the two other jsdom
 * suites past vitest's default timeout on a cold run — green in isolation, red
 * on CI. Six tests read the same CUSTOMER card, so they read the same render.
 */
const drawn = new Map<string, Promise<Drawn>>();

function openDrawer(mother: unknown, triage: Triage = [], measuredAt: string | null = null): Promise<Drawn> {
  // measuredAt is part of the key: two fixtures that differ only in HOW OLD
  // the reading is must not share a cached render, which is the whole point of
  // the freshness assertions below.
  const key = `${JSON.stringify(mother) ?? 'undefined'}|${JSON.stringify(triage)}|${measuredAt ?? '-'}`;
  let hit = drawn.get(key);
  if (!hit) {
    hit = renderDrawer(mother, triage, measuredAt);
    drawn.set(key, hit);
  }
  return hit;
}

async function renderDrawer(mother: unknown, triage: Triage, measuredAt: string | null = null): Promise<Drawn> {
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
            ? detail(mother, triage)
            : p.includes('/admin/users')
              ? { total: 1, users: [{ ...USERS.users[0], lastMetricAt: measuredAt }] }
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
    total: 2, open: 1, spentMinor: 3900000, pendingMinor: 0,
    lastAt: '2026-08-01T09:00:00.000Z', lastStatus: 'shipped',
    openLastAt: '2026-08-01T09:00:00.000Z', openLastStatus: 'shipped',
    unavailable: false, truncated: false, window: null,
    recent: [
      {
        id: 'o3', status: 'shipped', createdAt: '2026-08-01T09:00:00.000Z', totalMinor: 3900000,
        items: [{ productName: 'Умные часы', qty: 1 }, { productName: 'Трекер', qty: 1 }],
      },
      { id: 'o2', status: 'cancelled', createdAt: '2026-06-01T09:00:00.000Z', totalMinor: 2980000, items: [] },
    ],
  },
  course: { unlocked: true, started: 0, completed: 0, lastAt: null, neverStarted: true, unavailable: false },
};

/** One emergency in her history — the thing a clinician must read first. */
const EMERGENCY: Triage = [{ code: 'Severe BP', severity: 'emergency', at: '2m ago' }];

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

  it('shows what she PAID, and names the rule the number obeys', async () => {
    const { drawer } = await openDrawer(CUSTOMER);
    expect(drawer).toContain('39 000 ₸');
    // The qualifier is the actual rule — shipped and delivered — not the
    // half-rule «без отменённых», which reads as "everything else is in here".
    expect(drawer).toContain('отправленные и доставленные');
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

  it('puts the emergency above the order status in «Требует внимания»', async () => {
    // The block's own comment says a clinician should see what NEEDS attention
    // before scrolling. An info-severity order line above a red-dot emergency
    // is that promise broken.
    const { drawer } = await openDrawer(CUSTOMER, EMERGENCY);
    const emergency = drawer.indexOf('Экстренная тревога в истории триажа');
    const commercial = drawer.indexOf('Заказ в работе: 1');
    const course = drawer.indexOf('Курс оплачен, но ни разу не открыт');
    expect(emergency, 'the emergency flag is missing entirely').toBeGreaterThan(-1);
    expect(commercial).toBeGreaterThan(-1);
    expect(emergency, 'crit must lead').toBeLessThan(course);
    expect(course, 'warn before info').toBeLessThan(commercial);
  });

  it('names the status of the OPEN order, not of the newest one', async () => {
    // open = 1 (a June order still «Новый») while the newest overall is
    // already delivered. «в работе: 1 (последний — Доставлен)» sent staff
    // hunting a parcel that never went out.
    const { drawer } = await openDrawer({
      ...CUSTOMER,
      orders: {
        ...CUSTOMER.orders,
        total: 2, open: 1, spentMinor: 1000, pendingMinor: 3900000,
        lastAt: '2026-08-01T09:00:00.000Z', lastStatus: 'delivered',
        openLastAt: '2026-06-01T09:00:00.000Z', openLastStatus: 'new',
        recent: [],
      },
    });
    expect(drawer).toContain('Заказ в работе: 1 (самый свежий из них — Новый)');
    // Nothing on this card may call the open order delivered.
    expect(drawer).not.toContain('Доставлен');
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

  it('does not tell an operator she has no orders when the shop failed to load', async () => {
    // She is on the phone holding a Kaspi receipt. «Заказов на этот номер нет»
    // is a confident wrong answer; «не загрузились» is the true one.
    const { drawer, errors } = await openDrawer({
      ...CUSTOMER,
      orders: {
        total: 0, open: 0, spentMinor: 0, pendingMinor: 0, lastAt: null, lastStatus: null,
        openLastAt: null, openLastStatus: null, unavailable: true, truncated: false, window: null, recent: [],
      },
    });
    expect(errors).toEqual([]);
    expect(drawer).not.toContain('Заказов на этот номер нет');
    expect(drawer).toContain('Заказы не загрузились');
    expect(drawer).toContain('Это НЕ значит, что их нет');
    // And it is raised where staff actually look.
    expect(drawer).toContain('НЕИЗВЕСТНЫ');
  });

  it('does not say «комплект не покупали» when the course read failed', async () => {
    // She paid 39 000 ₸. Telling her she never bought it is the worst sentence
    // this card can produce.
    const { drawer, errors } = await openDrawer({
      ...CUSTOMER,
      course: { unlocked: false, started: 0, completed: 0, lastAt: null, neverStarted: false, unavailable: true },
    });
    expect(errors).toEqual([]);
    expect(drawer).not.toContain('комплект не покупали');
    expect(drawer).toContain('Доступ к курсу не проверился');
    expect(drawer).toContain('Это НЕ значит, что курса у неё нет');
  });

  it('shows an unpaid order as owed, not as money she spent', async () => {
    const { drawer } = await openDrawer({
      ...CUSTOMER,
      orders: {
        ...CUSTOMER.orders,
        total: 1, open: 1, spentMinor: 0, pendingMinor: 3900000,
        lastStatus: 'new', openLastStatus: 'new',
        recent: [{ id: 'o1', status: 'new', createdAt: '2026-08-01T09:00:00.000Z', totalMinor: 3900000, items: [] }],
      },
    });
    expect(drawer).toMatch(/Оплачено отправленные и доставленные\s*0 ₸/);
    expect(drawer).toMatch(/Ожидает оплаты[^₸]*39 000 ₸/);
  });

  it('admits on screen that the totals are only a window', async () => {
    // 23 orders behind a 100-window is fine; the point is that when the window
    // DOES bite, the operator is not quoting a partial spend as her history.
    const { drawer } = await openDrawer({
      ...CUSTOMER,
      orders: { ...CUSTOMER.orders, total: 100, truncated: true, window: 100 },
    });
    expect(drawer).toContain('Заказы · 100 (последние 100)');
    expect(drawer).toContain('более ранние в суммах НЕ учтены');
  });

  it('draws the rest of the card when an older server sends no mother block', async () => {
    const { drawer, errors } = await openDrawer(undefined);
    expect(errors).toEqual([]);
    expect(drawer).toContain('Профиль');
    expect(drawer).not.toContain('Заказов на этот номер нет');
    expect(drawer).not.toContain('Этап');
  });
});

/**
 * How old the reading is, and what the card is therefore allowed to claim.
 *
 * Four vitals were drawn with no timestamp anywhere near them, on the one card
 * a clinician opens to decide whether to ring somebody. 162/108 from three
 * weeks ago and 162/108 from four minutes ago were the same pixels.
 * `adminUserHealth` selects the newest row `ORDER BY recorded_at DESC` and
 * throws `recorded_at` away; `lastMetricAt` was on the list row that opened the
 * drawer the whole time.
 *
 * The thresholds are the app's own, not invented here: 6 h is
 * `latestTelemetryMaxAge`, past which the guardrail refuses to call a reading
 * "how she is now" — so the panel must not colour it as one either. Past 48 h
 * it is describing a different day and says so.
 */
describe('the age of a reading', () => {
  const hoursAgo = (h: number) => new Date(Date.now() - h * 36e5).toISOString();

  it('says when the measurement was taken', async () => {
    const { drawer, errors } = await openDrawer(undefined, [], hoursAgo(0.05));
    expect(errors).toEqual([]);
    expect(drawer).toContain('Последние измерения');
    expect(drawer).toMatch(/(мин|ч|дн) назад|только что/);
  });

  it('says outright when it does NOT know, rather than implying "now"', async () => {
    // The commonest state on a server that has not backfilled: no timestamp.
    // Silence here reads as freshness, which is the failure being prevented.
    const { drawer } = await openDrawer(undefined, [], null);
    expect(drawer).toContain('времени измерения нет');
    expect(drawer).toContain('справочными');
  });

  it('warns, in words, when the reading is from another day', async () => {
    const { drawer } = await openDrawer(undefined, [], hoursAgo(72));
    expect(drawer).toContain('описывают тот день, а не сегодняшний');
  });

  it('does not warn about a reading from an hour ago', async () => {
    const { drawer } = await openDrawer(undefined, [], hoursAgo(1));
    expect(drawer).not.toContain('описывают тот день');
  });
});

/**
 * A Russian panel, in Russian.
 *
 * «Heart rate», «Blood oxygen», «Systolic», «Diastolic», «Temperature»,
 * «Glucose», «bpm», «mmHg», «mmol/L» — all under a Russian heading, on the
 * clinical card. And «История триажа» printed `t.code`, which IS
 * `triage_severity`, so a patient's clinical history read «emergency».
 */
describe('the clinical card speaks Russian', () => {
  it('labels the vitals and their units', async () => {
    const { drawer } = await openDrawer(undefined, [], hoursAgoIso());
    for (const s of ['Пульс', 'уд/мин', 'Кислород в крови', 'Верхнее', 'Нижнее', 'мм рт. ст.', 'Температура']) {
      expect(drawer, `«${s}» is missing`).toContain(s);
    }
    for (const s of ['Heart rate', 'Blood oxygen', 'Systolic', 'Diastolic', 'bpm', 'mmHg']) {
      expect(drawer, `«${s}» is still in English`).not.toContain(s);
    }
  });

  it('names the triage severity instead of printing its key', async () => {
    const { drawer } = await openDrawer(undefined,
      [{ code: 'PREECLAMPSIA_BP', severity: 'emergency', at: '2026-08-12T09:41:03.221Z' }],
      hoursAgoIso());
    expect(drawer).toContain('Экстренно');
    expect(drawer, 'the raw severity key reached the screen').not.toContain('emergency');
    // And a readable time, not the ISO string the row used to print.
    expect(drawer).not.toContain('2026-08-12T09:41:03.221Z');
  });

  it('says the triage found nothing rather than drawing an empty list', async () => {
    const { drawer } = await openDrawer(undefined, [], hoursAgoIso());
    expect(drawer).toContain('Триаж ничего не отмечал');
  });
});

function hoursAgoIso(h = 0.5) {
  return new Date(Date.now() - h * 36e5).toISOString();
}
