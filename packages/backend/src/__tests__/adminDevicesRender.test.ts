/**
 * Кадр 11 «Устройства» in a browser, plus the watch stream on the mother card.
 *
 * "Verified structurally" is not verification: every one of these strings could
 * be present in the source and never painted, which is the failure this panel
 * produces most. So the real file is booted in jsdom, the tab is opened, and
 * the rendered text is read.
 *
 * What it is really about:
 *   * «на связи» is derived from a real timestamp against the threshold the
 *     SERVER states, not from a flag;
 *   * nothing unknown is printed as a dash — a device that has never reported
 *     says so in words, and a firmware nobody sent says «не сообщалась»;
 *   * «Пометить браком» asks first, names the consequence, and reports what
 *     the server actually answered rather than the fact that it was asked;
 *   * the wearable days that had no reader are on the mother's card.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';
import { answerReasonPromptIfShown } from './helpers/reasonPrompt.js';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const UID = '11111111-1111-1111-1111-111111111111';
const hoursAgo = (h: number) => new Date(Date.now() - h * 3600_000).toISOString();

/** Four rows, one per state the fleet view has to be able to describe. */
const DEVICES = {
  devices: [
    {
      id: 'AA:BB:CC:DD:EE:01', deviceId: 'row-1', name: 'GTS10', kind: 'band', userId: UID,
      displayName: 'Айгерим', childName: null, batteryPct: 78, lastSeen: hoursAgo(2),
      firmware: 'v1.4.2', defectAt: null, defectBy: null, defectNote: null,
    },
    {
      // Paired and never heard from. NOT a dash.
      id: 'AA:BB:CC:DD:EE:02', deviceId: 'row-2', name: 'Трекер', kind: 'tag', userId: UID,
      displayName: 'Айгерим', childName: 'Сұлтан', batteryPct: null, lastSeen: null,
      firmware: null, defectAt: null, defectBy: null, defectNote: null,
    },
    {
      // Silent for five days — past the stated staleness window.
      id: 'AA:BB:CC:DD:EE:03', deviceId: 'row-3', name: null, kind: 'band', userId: UID,
      displayName: 'Мадина', childName: null, batteryPct: 12, lastSeen: hoursAgo(24 * 5),
      firmware: 'v1.2.0', defectAt: null, defectBy: null, defectNote: null,
    },
    {
      id: 'AA:BB:CC:DD:EE:04', deviceId: 'row-4', name: 'GTS10', kind: 'band', userId: UID,
      displayName: 'Асем', childName: null, batteryPct: 90, lastSeen: hoursAgo(3),
      firmware: 'v1.4.2', defectAt: hoursAgo(48), defectBy: 'staff-dev', defectNote: 'экран треснул',
    },
  ],
  onlineWithinHours: 24,
  staleAfterDays: 3,
  limit: 100,
};

interface Sent { path: string; method: string; body: unknown }
interface Fleet {
  window: JSDOM['window'];
  /**
   * Resolves when the panel has stopped working, never after a fixed delay.
   *
   * Three fixed sleeps stood here — 200 after boot, 400 after the tab, 250 per
   * row action — each deciding its verdict on elapsed wall-clock rather than on
   * the work being finished. `text` is snapshotted at the end of the boot, so a
   * window that closed early froze a half-filled fleet view into every
   * assertion in this file at once. See helpers/panelSettle.ts.
   */
  quiet: (label?: string) => Promise<void>;
  text: string;
  sent: Sent[];
  prompts: string[];
  confirms: string[];
  errors: string[];
}

async function openFleet(opts: {
  failWrite?: number;
  promptAnswer?: string | null;
  failList?: boolean;
} = {}): Promise<Fleet> {
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
  const sent: Sent[] = [];
  const prompts: string[] = [];
  const confirms: string[] = [];
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
      // jsdom implements neither; unstubbed, prompt() returns undefined and
      // every "the operator cancelled" path would look confirmed.
      (window as unknown as { alert: (m: string) => void }).alert = () => {};
      (window as unknown as { confirm: (m: string) => boolean }).confirm = (m) => {
        confirms.push(m);
        return true;
      };
      (window as unknown as { prompt: (m: string) => string | null }).prompt = (m) => {
        prompts.push(m);
        return opts.promptAnswer === undefined ? 'не заряжается' : opts.promptAnswer;
      };
      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = path;
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        const method = init?.method ?? 'GET';
        if (method !== 'GET') {
          sent.push({ path: p, method, body: init?.body ? JSON.parse(String(init.body)) : null });
          if (opts.failWrite) {
            return { ok: false, status: opts.failWrite, json: async () => ({}), text: async () => '' };
          }
          return { ok: true, status: 200, json: async () => ({ ok: true }), text: async () => '{}' };
        }
        if (p.includes('/admin/devices')) {
          if (opts.failList) return { ok: false, status: 503, json: async () => ({}), text: async () => '' };
          return { ok: true, status: 200, json: async () => DEVICES, text: async () => JSON.stringify(DEVICES) };
        }
        const body = p.includes('/admin/stats')
          ? { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 }
          : {};
        return { ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) };
      });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  window.document.querySelector('[data-view="devices"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Устройства tab');
  const read = () =>
    (window.document.querySelector('section#devices')?.textContent ?? '').replace(/\s+/g, ' ').trim();
  return { window, quiet: settle.quiet, text: read(), sent, prompts, confirms, errors };
}

/** Click a row action and let the handler finish — actually finish. */
async function click(f: Fleet, selector: string) {
  const el = f.window.document.querySelector(selector) as HTMLElement | null;
  expect(el, `no ${selector} on the fleet view`).not.toBeNull();
  el!.dispatchEvent(new f.window.MouseEvent('click', { bubbles: true }));
  await f.quiet(`the click on ${selector}`);
}

describe('кадр 11 · метрики онлайн', () => {
  it('renders without throwing', async () => {
    const f = await openFleet();
    expect(f.errors).toEqual([]);
  });

  it('counts who is on air, and prints the threshold it counted with', async () => {
    // «3» means nothing on its own; «3 из 4 показанных · порог 24 ч» is an
    // answer somebody can argue with. And the threshold comes from the server,
    // so the panel cannot quietly hold a different opinion.
    const f = await openFleet();
    expect(f.text).toContain('На связи');
    expect(f.text).toContain('порог 24 ч');
    expect(f.text).toContain('из 4 показанных');
  });

  it('counts the ones that have never reported at all, separately from the silent ones', async () => {
    const f = await openFleet();
    expect(f.text).toContain('Ни разу не выходили на связь');
    expect(f.text).toContain('Молчат дольше 3 дн.');
    expect(f.text).toContain('привязаны, но данных от них не приходило никогда');
  });

  it('says how many devices the battery figure is even known for', async () => {
    const f = await openFleet();
    expect(f.text).toContain('Заряд ниже 20 %');
    expect(f.text).toMatch(/о заряде которых знаем/);
  });

  it('refuses to compute metrics when the list did not load', async () => {
    // «0 на связи» printed because the request failed is the worst thing this
    // screen can say: it reads as a fleet-wide outage.
    const f = await openFleet({ failList: true });
    expect(f.text).toContain('Не удалось загрузить парк устройств');
    expect(f.text).not.toContain('порог 24 ч');
    expect(f.text).toContain('Показывать «0 на связи» было бы враньём');
  });
});

describe('кадр 11 · таблица', () => {
  it('shows the firmware column, and admits when nobody reported one', async () => {
    const f = await openFleet();
    expect(f.text).toContain('Прошивка');
    expect(f.text).toContain('v1.4.2');
    // A dash here reads as "no firmware", which is a different claim.
    expect(f.text).toContain('не сообщалась');
  });

  it('says in words that a device has never been heard from', async () => {
    const f = await openFleet();
    expect(f.text).toContain('ни разу не выходило на связь');
    expect(f.text).toContain('не сообщался');   // its battery
  });

  it('tints the rows that need looking at, rather than recolouring their text', async () => {
    const f = await openFleet();
    const rows = [...f.window.document.querySelectorAll('#devicesBody tr')];
    expect(rows).toHaveLength(4);
    expect(rows.find((r) => r.className.includes('attn-crit')), 'the defect row is not flagged').toBeTruthy();
    expect(rows.filter((r) => r.className.includes('attn-warn')).length,
      'the silent and never-seen rows should be tinted').toBeGreaterThan(1);
  });

  it('states the rule its «последний сигнал» column obeys', async () => {
    const f = await openFleet();
    expect(f.text).toContain('когда данные от устройства дошли до сервера');
    expect(f.text).toContain('Показано 4');
  });

  it('shows an existing defect mark with its reason', async () => {
    const f = await openFleet();
    expect(f.text).toContain('экран треснул');
    expect(f.text).toContain('Снять пометку');
  });

  it('opens the owner\'s card from the row, asking why first', async () => {
    // The join between кадр 11 and кадр 09a. Without it an operator who has
    // just seen a silent watch has to leave for «Пользователи» and find the
    // mother again by the name in the next column — and her card is where the
    // watch's own daily data is. The reason prompt still guards it: reaching a
    // record sideways must not skip the question.
    const f = await openFleet();
    await click(f, '#devicesBody tr:first-child .devcard');
    const wrap = f.window.document.querySelector('#reasonWrap') as HTMLElement;
    expect(wrap.hidden, 'a health record opened from the fleet view without asking why').toBe(false);
  });
});

describe('«Пометить браком» asks before it happens', () => {
  it('names the device, the owner and what the mark does NOT do', async () => {
    const f = await openFleet();
    await click(f, '#devicesBody tr:first-child .devdefect');
    expect(f.prompts.length, 'a customer device was flagged without asking').toBe(1);
    expect(f.prompts[0]).toContain('AA:BB:CC:DD:EE:01');
    expect(f.prompts[0]).toContain('Айгерим');
    // The consequence, stated: this is not the warehouse block.
    expect(f.prompts[0]).toContain('продолжит работать');
    expect(f.prompts[0]).toContain('Склад');
  });

  it('sends the mark, with the note, addressed by the row id', async () => {
    const f = await openFleet();
    await click(f, '#devicesBody tr:first-child .devdefect');
    const write = f.sent.find((s) => s.path.includes('/defect'));
    expect(write, 'the button changed nothing').toBeTruthy();
    expect(write!.method).toBe('POST');
    expect(write!.path).toContain('row-1');
    expect(write!.body).toEqual({ defect: true, note: 'не заряжается' });
  });

  it('sends nothing when the operator backs out', async () => {
    const f = await openFleet({ promptAnswer: null });
    await click(f, '#devicesBody tr:first-child .devdefect');
    expect(f.sent.filter((s) => s.method === 'POST')).toEqual([]);
  });

  it('says the mark was NOT saved when the server refuses', async () => {
    // The defect this exists for: a tick over a write that never landed.
    const f = await openFleet({ failWrite: 500 });
    await click(f, '#devicesBody tr:first-child .devdefect');
    const msg = f.window.document.getElementById('devMsg')!.textContent ?? '';
    expect(msg).toContain('Не сохранено');
    expect(msg).not.toContain('✓');
  });

  it('explains a 404 as the device having gone, not as a server fault', async () => {
    const f = await openFleet({ failWrite: 404 });
    await click(f, '#devicesBody tr:first-child .devdefect');
    expect(f.window.document.getElementById('devMsg')!.textContent)
      .toContain('больше не числится за аккаунтом');
  });

  it('confirms — not merely prompts — before taking a mark back', async () => {
    const f = await openFleet();
    await click(f, '#devicesBody tr:last-child .devdefect');
    expect(f.confirms.length).toBe(1);
    expect(f.confirms[0]).toContain('Снять пометку брака');
    expect(f.sent.find((s) => s.path.includes('/defect'))!.body).toEqual({ defect: false, note: '' });
  });
});

// ---------------------------------------------------------------------------
// The mother card: what the watch has actually been sending.
// ---------------------------------------------------------------------------

const USERS = {
  total: 1,
  users: [{ id: UID, displayName: 'Айгерим', phone: '+77015551122', dueDate: null, lastMetricAt: null }],
};
const DETAIL = {
  id: UID, displayName: 'Айгерим', phone: '+77015551122', dueDate: null, locale: 'ru-KZ',
  birthDate: null, city: null, latest: {}, triage: [], children: [], devices: [], alerts: [],
  sleepNights: 0, loggedDays: 0, appointments: [],
};
const WELLNESS = {
  sleep: [], days: [], alerts: [], weight: [], medications: [], medicalIds: [],
  kickSessions: [], contractionSessions: [], newbornEvents: [], bpCalibration: null,
  growth: [], doses: [], vaccines: [],
};

async function openCard(wearable: unknown, ok = true): Promise<{ drawer: string; errors: string[] }> {
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
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
      settle.attach(window as never, async (path: string) => {
        const p = path;
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (p.includes('/wearable')) {
          if (!ok) return { ok: false, status: 503, json: async () => ({}), text: async () => '' };
          return { ok: true, status: 200, json: async () => wearable, text: async () => JSON.stringify(wearable) };
        }
        if (p.includes('/admin/bi') || p.includes('/admin/analytics')) {
          return { ok: false, status: 503, json: async () => ({}), text: async () => '' };
        }
        const body = p.includes('/wellness') ? WELLNESS
          : p.includes('/detail') ? DETAIL
          : p.includes('/admin/users') ? USERS
          : p.includes('/admin/stats') ? { activeUsers: 1, devicesOnline: 0, alertsToday: 0, ingestLastHour: 0 }
          : {};
        return { ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) };
      });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  window.document.querySelector('[data-view="users"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Пользователи tab');
  const row = window.document.querySelector(`#usersBody tr[data-user="${UID}"]`);
  if (!row) throw new Error('no user row rendered');
  row.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the row click');
  // The shared prompt helper had its own 250 ms sleep; handing it the panel's
  // completion signal is what removes it. See helpers/reasonPrompt.ts.
  await answerReasonPromptIfShown(window, undefined, { settled: settle.quiet });
  return {
    drawer: (window.document.querySelector('#drawer')?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    errors,
  };
}

const DAY = {
  deviceId: 'AA:BB:CC:DD:EE:01', day: '2026-07-21', recordedAt: '2026-07-21T14:00:00.000Z',
  steps: 6480, kcal: 320, meters: 4600,
  sleepMinutes: 445, deepSleepMinutes: 95, lightSleepMinutes: 280,
  stress: 42, breathRate: 16, met: 3, batteryPercent: 78, charging: false, worn: true,
};

describe('the mother card answers «часы вообще передают данные?»', () => {
  it('renders the days the watch sent', async () => {
    const { drawer, errors } = await openCard({ days: [DAY], window: 14 });
    expect(errors).toEqual([]);
    expect(drawer).toContain('Что передают часы');
    expect(drawer).toContain('6 480 шагов');
    expect(drawer).toContain('4.6 км');
    expect(drawer).toContain('320 ккал');
    expect(drawer).toContain('стресс 42');
    expect(drawer).toContain('на руке');
    expect(drawer).toContain('78%');
  });

  it('says an indicator was not measured rather than printing a zero', async () => {
    const { drawer } = await openCard({
      days: [{ ...DAY, stress: null, breathRate: null, met: null }], window: 14,
    });
    expect(drawer).toContain('стресс не измерялось');
    expect(drawer).not.toContain('стресс 0');
  });

  it('distinguishes «ничего не пришло за 14 дней» from «не загрузилось»', async () => {
    const empty = await openCard({ days: [], window: 14 });
    expect(empty.drawer).toContain('За последние 14 дн. от часов не пришло ни одного дня данных');

    const broken = await openCard({ days: [] }, false);
    expect(broken.drawer).toContain('Данные часов не загрузились');
    expect(broken.drawer).toContain('Это НЕ значит, что часы ничего не передают');
    expect(broken.drawer).not.toContain('не пришло ни одного дня данных');
  });

  it('shows that the watch was not worn, instead of a silent zero day', async () => {
    const { drawer } = await openCard({
      days: [{ ...DAY, steps: 0, meters: 0, kcal: 0, worn: false, charging: true }], window: 14,
    });
    expect(drawer).toContain('не носили');
    expect(drawer).toContain('на зарядке');
  });
});

/**
 * The vitals a day of watch HISTORY carries — and the three a clinical review
 * REFUSED.
 *
 * The backfill reads about a week of per-minute samples off the watch, the
 * server stores them (migration 042) and puts them on the wire. Five were
 * rendered. Review kept two and refused three, and the refusal is the part
 * that needs a test: a removal with no test comes back on the next person who
 * notices a field on the wire and nothing on the screen.
 *
 * The payload below deliberately still CARRIES all five. These cases are worth
 * nothing against a fixture that has nothing to leak.
 */
const VITALS = {
  ...DAY,
  heartRateAvg: 78, heartRateMin: 54, heartRateMax: 165,
  spo2Avg: 97, spo2Min: 88,
  // Refused. On the wire, and must not be on the screen.
  systolicAvg: 118, diastolicAvg: 76,
  tempAvgTenths: 365,
  bloodSugarTenths: 54,
};

describe('the vitals of a day reach the screen', () => {
  it('prints heart rate and SpO2', async () => {
    const { drawer, errors } = await openCard({ days: [VITALS], window: 14 });
    expect(errors).toEqual([]);
    expect(drawer).toContain('пульс 78 уд/мин');
    expect(drawer).toContain('кислород 97 %');
  });

  it('labels the daily extremes instead of leaving them to be read as alarms', async () => {
    // 54 is under our own bradycardia line and 165 is over the tachycardia
    // one. Both are an ordinary night's sleep and an ordinary flight of
    // stairs, and an unlabelled pair invites a phone call about neither.
    const { drawer } = await openCard({ days: [VITALS], window: 14 });
    expect(drawer).toContain('за сутки 54–165');
    expect(drawer).toContain('минимум обычно во сне, максимум при нагрузке');
  });

  it('states the SpO2 floor as a floor, not as half a range', async () => {
    // «кислород 97% (88–—)» read as a truncated range: a dash where a maximum
    // would go looks like data that failed to arrive.
    const { drawer } = await openCard({ days: [VITALS], window: 14 });
    expect(drawer).toContain('самое низкое за сутки 88 %');
    expect(drawer, 'the dash range is back').not.toContain('(88–—)');
  });

  it('marks every row as an estimate, not just the card', async () => {
    // The card-level qualifier scrolls off around day five of fourteen, and
    // after that every line reads as a measurement.
    const { drawer } = await openCard({
      days: [VITALS, { ...VITALS, day: '2026-07-30' }, { ...VITALS, day: '2026-07-29' }],
      window: 14,
    });
    expect((drawer.match(/оценка часов ·/g) || []).length,
      'the per-row marker is missing from some rows').toBe(3);
  });

  it('says nothing was measured rather than printing zeros', async () => {
    // A stored 0 heart rate reads as a heart that stopped. Absent must look
    // absent.
    const { drawer } = await openCard({ days: [DAY], window: 14 });
    expect(drawer).toContain('пульс и кислород за день не измерялись');
    expect(drawer).not.toContain('пульс 0');
  });
});

/**
 * The three the clinician refused. Each has its own reason and its own way of
 * being wrong, so each gets its own case rather than one loop.
 */
describe('the refused metrics are not on the screen', () => {
  it('does not print a day-average blood pressure', async () => {
    // There is no maximum column. A day that touched 158/104 and sat at
    // 105/68 renders «118/76» and reads as reassurance — and wrist PPG BP is
    // ±10–15 mmHg against a 140 threshold, with no calibration state on these
    // rows at all.
    const { drawer } = await openCard({ days: [VITALS], window: 14 });
    expect(drawer, 'the day-average BP is back').not.toContain('118/76');
    expect(drawer).not.toMatch(/давление \d/);
  });

  it('does not print a day-average temperature', async () => {
    // Four hours at 38.6 inside an otherwise-36.6 day averages to 36.9: the
    // statistic hides the thing it would be opened to find. And the OEM band
    // path runs skinToCoreTempC while the Starmax path does not, so the two
    // code paths do not agree on what the degrees mean.
    const { drawer } = await openCard({ days: [VITALS], window: 14 });
    expect(drawer, 'the day-average temperature is back').not.toContain('36.5 °C');
    expect(drawer).not.toMatch(/температура \d/);
  });

  it('does not print blood sugar, and never prints a unit the vendor does not state', async () => {
    // The band field is «血糖（0.1）» with no unit stated anywhere in the
    // vendor's 3 248 lines. We invented «ммоль/л» — on a diabetes number, to
    // pregnant women, against a 24–28-week OGTT window that closes.
    const { drawer } = await openCard({ days: [VITALS], window: 14 });
    expect(drawer, 'blood sugar is back').not.toContain('5.4');
    expect(drawer, 'a unit our source never claims').not.toContain('ммоль/л');
    // «сахар» as a VALUE. The qualifier above the rows names it deliberately —
    // «не называйте эти цифры маме как её … сахар» — so the word itself is not
    // the thing to forbid; a number after it is.
    expect(drawer, 'a blood sugar value is back').not.toMatch(/сахар[^.]{0,12}\d/i);
  });

  it('the qualifier is written for the owner, and forbids acting on the numbers', async () => {
    const { drawer } = await openCard({ days: [VITALS], window: 14 });
    expect(drawer).toContain('оценки оптического датчика на запястье');
    // The old text said «сверяйте с тонометром» — an instruction the reader
    // cannot carry out for a woman who is not in the room.
    expect(drawer, 'the un-actionable instruction is back').not.toMatch(/сверяйте с тонометром/i);
    expect(drawer).toContain('Не называйте эти цифры маме');
    // It has to qualify the STATISTIC, not only the sensor.
    expect(drawer).toContain('в среднем не виден');
  });
});
