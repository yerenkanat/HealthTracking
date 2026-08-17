/**
 * Render the admin panel's vaccination tab, the vaccine CARD and the version
 * history for real (jsdom).
 *
 * Frames 15 «Национальный календарь», 15a «Добавить прививку», 15b «История
 * версий». The routes were finished, tested and had ZERO callers: the tab
 * painted a read-only table off `/admin/reference/vaccination`, which is the
 * shipped contract rather than what a phone receives. So this boots the real
 * panel, clicks the real tab, opens the real card, types a new month into the
 * real box and presses the real button, then reads what a browser would have
 * drawn.
 *
 * "Verified structurally" is not verification: every assertion below is on
 * painted text or on the request the panel actually sent.
 *
 * The sharp one is the coverage column. Those figures are self-reported by
 * mothers in the app — a row in `child_vaccines` exists because a parent tapped
 * a circle — so the tests assert that the panel prints the payload's OWN
 * `source`/`sourceNote`/`rule` and never the words «охват по РК».
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { vaccinationSchedule } from '../vaccination/schedule.js';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const keyOf = (id: string, dose: number | null | undefined) => `${id}/${dose ?? null}`;

interface Row {
  key: string; id: string; dose: number | null; atMonth: number;
  contractAtMonth: number | null; contractRu: string | null; inContract: boolean;
  added: boolean; ru: { name: string; note: string }; kk: { name: string; note: string };
  edited: boolean; draft: boolean; live: boolean; liveAtMonth: number | null;
  review: { by: string; at: string } | null; reviewCurrent: boolean;
  updatedAt: string | null; updatedBy: string | null;
}

/** What GET /admin/vaccination/schedule answers — the served calendar + edit state. */
function adminSchedule(
  over: Record<string, Partial<Row>> = {},
  meta: Record<string, unknown> = {},
) {
  return {
    version: vaccinationSchedule.version,
    contractVersion: vaccinationSchedule.version,
    editsKnown: true,
    settingsKnown: true,
    dueWindowMonths: vaccinationSchedule.dueWindowMonths,
    contractDueWindowMonths: vaccinationSchedule.dueWindowMonths,
    dueWindowEdited: false,
    dueWindowUpdatedAt: null,
    dueWindowUpdatedBy: null,
    ...meta,
    vaccines: vaccinationSchedule.vaccines.map((v): Row => {
      const key = keyOf(v.id, v.dose);
      return {
        key,
        id: v.id,
        dose: v.dose ?? null,
        atMonth: v.atMonth,
        contractAtMonth: v.atMonth,
        contractRu: v.ru,
        inContract: true,
        added: false,
        ru: { name: v.ru, note: '' },
        kk: { name: '', note: '' },
        edited: false,
        draft: false,
        live: true,
        liveAtMonth: v.atMonth,
        review: null,
        reviewCurrent: false,
        updatedAt: null,
        updatedBy: null,
        ...(over[key] ?? {}),
      };
    }),
  };
}

/**
 * What GET /admin/vaccination/coverage answers.
 *
 * The three prose fields are the ROUTE's own words, copied verbatim: the test
 * that they reach the screen is only worth anything if the panel is printing
 * the payload rather than a sentence of its own.
 */
function adminCoverage(
  over: Record<string, Partial<{ due: number; done: number; pct: number | null; notYet: number }>> = {},
) {
  return {
    children: 12,
    childrenWithoutDob: 2,
    dueWindowMonths: vaccinationSchedule.dueWindowMonths,
    version: vaccinationSchedule.version,
    source: 'self_reported',
    sourceNote: 'Отметки мам в приложении, а не данные поликлиник. '
      + 'Это доля родителей — пользователей приложения, которые отметили прививку сделанной.',
    rule: 'В знаменателе — дети, у которых возраст прививки и догоняющее окно (1 мес.) уже прошли; '
      + 'дети, у которых прививка ещё «пора», не считаются ни в одну сторону.',
    vaccines: vaccinationSchedule.vaccines.map((v) => {
      const key = keyOf(v.id, v.dose);
      return {
        key, id: v.id, atMonth: v.atMonth, dose: v.dose ?? null, ru: v.ru,
        due: 8, done: 5, pct: 63, notYet: 4,
        ...(over[key] ?? {}),
      };
    }),
  };
}

const LOG_MOVE = {
  id: 2,
  key: 'pcv/2',
  before: null,
  after: {
    key: 'pcv/2', id: 'pcv', atMonth: 9, dose: 2,
    ru: { name: 'Пневмококковая', note: 'Против пневмонии и отита' },
    kk: { name: 'Пневмококк', note: 'Пневмония мен отитке қарсы' },
    added: false, draft: false, review: null,
  },
  actor: 'content-1',
  at: '2026-08-10T09:00:00Z',
};
const LOG_SETTINGS = {
  id: 1,
  key: '@settings',
  before: null,
  after: { dueWindowMonths: 3 },
  actor: 'content-1',
  at: '2026-08-09T09:00:00Z',
};

interface Rendered {
  text(sel: string): string;
  count(sel: string): number;
  /**
   * Resolves when the panel has stopped working, never after a fixed delay.
   *
   * This file had the one wait in the directory that was genuinely LOAD-BEARING
   * rather than merely lazy: 260 ms after typing into the "impact" field,
   * because the panel debounces that keystroke by 180 ms before it fetches
   * (`vacImpTimer = setTimeout(vacLoadImpact, 180)`). Counting requests alone
   * would return in five turns, before the debounce had even fired, and read a
   * card that had not been asked to change. So the harness holds the page's own
   * timers and runs the outstanding one once the request channel is calm —
   * clearTimeout still cancels, so a debounce still debounces. See
   * helpers/panelSettle.ts.
   */
  quiet: (label?: string) => Promise<void>;
  errors: string[];
  /** Every write the panel sent: [method, path, parsed body]. */
  sent: Array<{ method: string; path: string; body: unknown }>;
  /** Every GET the panel sent, so «did it ask at all» is answerable. */
  got: string[];
  window: import('jsdom').DOMWindow;
}

interface BootOpts {
  role?: string;
  schedule?: unknown;
  coverage?: unknown;
  /** 401/403 from /coverage and /impact — a clinician-less role. */
  coverageStatus?: number;
  impact?: unknown;
  log?: unknown;
  logStatus?: number;
  scheduleStatus?: number;
  /** What a PUT /admin/vaccination/schedule/:id/:dose answers. */
  putReply?: { status: number; body: unknown };
  settingsReply?: { status: number; body: unknown };
  /** Replace the schedule payload after a successful PUT, so a reload shows it. */
  afterPut?: unknown;
}

async function boot(opts: BootOpts = {}): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const settle = panelSettle();
  const errors: string[] = [];
  const sent: Rendered['sent'] = [];
  const got: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  let schedule = opts.schedule ?? adminSchedule();
  const coverage = opts.coverage ?? adminCoverage();
  const log = opts.log ?? { entries: [LOG_MOVE, LOG_SETTINGS] };
  const impact = opts.impact ?? {
    key: 'pcv/2', atMonth: 4, total: 12, notYet: 4, passed: 6,
    reclassified: 3, proposedAtMonth: 9, isNew: false, ageLabel: '4 мес.',
  };

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
      // Deliberately fatal. Frame 15's confirmations are the spec modal, and a
      // window.confirm() creeping back in would hang a real browser tab.
      window.confirm = () => { throw new Error('window.confirm() is not the spec modal'); };
      (window as unknown as { CSS: { escape: (s: string) => string } }).CSS = { escape: (s) => s };
      const reply = (status: number, body: unknown) => ({
        ok: status >= 200 && status < 300,
        status,
        text: async () => JSON.stringify(body),
        json: async () => body,
      });
      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = path;
        const method = init?.method ?? 'GET';
        if (method === 'GET') got.push(p);
        else sent.push({ method, path: p, body: init?.body ? JSON.parse(init.body) : null });

        if (p.includes('/admin/me')) return reply(200, { staffId: 's1', role: opts.role ?? 'admin' });

        if (p.includes('/admin/vaccination/settings')) {
          const r = opts.settingsReply ?? { status: 200, body: { ok: true, dueWindowMonths: 3 } };
          return reply(r.status, r.body);
        }
        if (p.includes('/admin/vaccination/schedule') && method === 'PUT') {
          const r = opts.putReply ?? { status: 200, body: { ok: true, key: 'pcv/2', draft: false, added: false, reviewed: false } };
          if (r.status >= 200 && r.status < 300 && opts.afterPut) schedule = opts.afterPut;
          return reply(r.status, r.body);
        }
        if (p.includes('/admin/vaccination/schedule') && method === 'POST') {
          return reply(200, { ok: true, key: 'pcv/2', review: { by: 's1', at: '2026-08-11T00:00:00Z' }, draft: false });
        }
        if (p.includes('/admin/vaccination/coverage')) {
          if (opts.coverageStatus) return reply(opts.coverageStatus, { error: 'forbidden' });
          return reply(200, coverage);
        }
        if (p.includes('/admin/vaccination/impact')) {
          if (opts.coverageStatus) return reply(opts.coverageStatus, { error: 'forbidden' });
          return reply(200, impact);
        }
        if (p.includes('/admin/vaccination/log')) {
          if (opts.logStatus) return reply(opts.logStatus, { error: 'log_unavailable' });
          return reply(200, log);
        }
        if (p.includes('/admin/vaccination/schedule')) {
          if (opts.scheduleStatus) return reply(opts.scheduleStatus, { error: 'boom' });
          return reply(200, schedule);
        }
        return reply(500, {});
      });
    },
  });
  const { window } = dom;
  await settle.quiet('boot');
  return {
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (sel) => window.document.querySelectorAll(sel).length,
    quiet: settle.quiet,
    errors, sent, got, window,
  };
}

async function click(page: Rendered, sel: string) {
  const el = page.window.document.querySelector(sel);
  if (!el) throw new Error(`nothing to click at ${sel}`);
  el.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));
  await page.quiet(`the click on ${sel}`);
}
async function typeInto(page: Rendered, sel: string, value: string) {
  const el = page.window.document.querySelector(sel) as HTMLInputElement;
  if (!el) throw new Error(`no field at ${sel}`);
  el.value = value;
  el.dispatchEvent(new page.window.Event('input', { bubbles: true }));
  // The 180 ms debounce lives here. quiet() runs it rather than outsleeping it.
  await page.quiet(`the typing into ${sel}`);
}
async function submit(page: Rendered, sel: string) {
  page.window.document.querySelector(sel)!
    .dispatchEvent(new page.window.Event('submit', { bubbles: true, cancelable: true }));
  await page.quiet(`the submit of ${sel}`);
}

/**
 * Painted, not merely present. `applyCaps` hides what a role may not use with
 * the `hidden` attribute, and a `.view` that is not the current tab is
 * display:none — which jsdom's computed style does not report.
 */
function painted(page: Rendered, sel: string): boolean {
  const el = page.window.document.querySelector(sel) as HTMLElement | null;
  if (!el) return false;
  for (let n: HTMLElement | null = el; n; n = n.parentElement) {
    if (n.hasAttribute('hidden')) return false;
    if (n.classList.contains('view') && !n.classList.contains('active')) return false;
  }
  return true;
}

async function openTab(opts: BootOpts = {}): Promise<Rendered> {
  const page = await boot(opts);
  await click(page, '[data-view="vaccines"]');
  return page;
}

describe('frame 15 — the calendar as it is actually served', () => {
  let page: Rendered;
  beforeAll(async () => { page = await openTab(); });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('reads the SERVED schedule, not the shipped contract', () => {
    // /admin/reference/vaccination is the raw contract. Painting it here is how
    // the panel came to show something different from what a phone receives.
    expect(page.got.some((p) => p.includes('/admin/vaccination/schedule'))).toBe(true);
    expect(page.got.some((p) => p.includes('/admin/reference/vaccination'))).toBe(false);
  });

  it('draws one row per injection, with its key', () => {
    expect(page.count('#vacBody tbody tr')).toBe(vaccinationSchedule.vaccines.length);
    const t = page.text('#vaccines');
    expect(t).toContain('При рождении');
    expect(t).toContain('Гепатит B');
    expect(t).toContain('pcv/2');
    expect(t).toContain('bcg/null');
  });

  it('the control for [painted] is not vacuous', async () => {
    const other = await boot();
    expect(painted(other, '#vacBody')).toBe(false);
    await click(other, '[data-view="vaccines"]');
    expect(painted(other, '#vacBody')).toBe(true);
  });
});

describe('the coverage column says what it is', () => {
  it('prints the payload’s own source note and rule — never «охват по РК»', async () => {
    const page = await openTab();
    const rule = page.text('#vacRule');
    expect(rule).toContain('Отметки мам в приложении, а не данные поликлиник');
    expect(rule).toContain('В знаменателе — дети');
    expect(rule).toContain('self_reported');
    // The two claims this screen must never make.
    const all = page.text('#vaccines');
    expect(all).not.toContain('по РК');
    expect(all).not.toContain('76 %');
    // ...and the ones it must: children left out are said out loud.
    expect(rule).toContain('без даты рождения: 2');
  });

  it('shows a share per vaccine with its own numerator and denominator', async () => {
    const page = await openTab({ coverage: adminCoverage({ 'pcv/2': { due: 8, done: 2, pct: 25, notYet: 4 } }) });
    const row = page.text('#vacBody tr[data-vackey="pcv/2"]');
    expect(row).toContain('25 %');
    expect(row).toContain('2 из 8');
  });

  it('says «детей такого возраста нет» rather than 0 % when nobody has reached it', async () => {
    const page = await openTab({ coverage: adminCoverage({ 'mmr/2': { due: 0, done: 0, pct: null, notYet: 12 } }) });
    expect(page.text('#vacBody tr[data-vackey="mmr/2"]')).toContain('детей такого возраста нет');
    expect(page.text('#vacBody tr[data-vackey="mmr/2"]')).not.toContain('0 %');
  });

  it('a 403 on coverage is a REFUSAL, not «не загрузилось» — and the calendar stays', async () => {
    // Coverage and impact need `health`; edits need `content`. A content editor
    // must still get the whole calendar and be told why the column is empty.
    const page = await openTab({ coverageStatus: 403 });
    expect(page.count('#vacBody tbody tr')).toBe(vaccinationSchedule.vaccines.length);
    const rule = page.text('#vacRule');
    expect(rule).toContain('Это не сбой');
    expect(rule).toContain('health');
    expect(rule).not.toContain('не загрузилось');
  });

  it('a role without `health` is told the column needs a right, not shown zeroes', async () => {
    const page = await openTab({ role: 'content' });
    expect(page.text('#vacBody tr[data-vackey="pcv/2"]')).toContain('нужно право health');
    expect(page.text('#vacRule')).toContain('Это отказ, а не сбой');
  });
});

describe('frame 15 — the card, and «затронет N детей» BEFORE saving', () => {
  it('opens on the row that was clicked and shows «было / стало» for a moved dose', async () => {
    const page = await openTab({
      schedule: adminSchedule({
        'pcv/2': {
          atMonth: 9, edited: true, live: true, liveAtMonth: 9, reviewCurrent: true,
          ru: { name: 'Пневмококковая', note: 'Против пневмонии и отита' },
          kk: { name: 'Пневмококк', note: 'Пневмония мен отитке қарсы' },
          review: { by: 'clinician-1', at: '2026-08-01T10:00:00Z' },
          updatedAt: '2026-08-01T09:00:00Z', updatedBy: 'content-1',
        },
      }),
    });
    const row = page.text('#vacBody tr[data-vackey="pcv/2"]');
    expect(row).toContain('4 мес.');   // contract
    expect(row).toContain('9 мес.');   // as served
    expect(row).toContain('Опубликовано, проверено врачом');

    await click(page, '#vacBody tr[data-vackey="pcv/2"] button');
    expect(painted(page, '#vacCard')).toBe(true);
    expect(page.text('#vacCardT')).toBe('Пневмококковая');
    expect(page.text('#vacCardSub')).toContain('pcv/2');
    expect(page.text('#vacCardBody')).toContain('В контракте');
  });

  it('refuses to renumber the dose — it is the key a mother’s tick is filed under', async () => {
    const page = await openTab();
    await click(page, '#vacBody tr[data-vackey="pcv/2"] button');
    const dose = page.window.document.querySelector('#vacDose') as HTMLInputElement;
    expect(dose.disabled).toBe(true);
    expect(page.text('#vacCardBody')).toContain('Доза — сменить нельзя');
  });

  it('asks the server what a new month would do, and prints the count', async () => {
    const page = await openTab();
    await click(page, '#vacBody tr[data-vackey="pcv/2"] button');
    await typeInto(page, '#vacAt', '9');

    const asked = page.got.filter((p) => p.includes('/admin/vaccination/impact'));
    expect(asked.length, 'the panel never asked what the change would do').toBeGreaterThan(0);
    expect(asked[asked.length - 1]).toContain('atMonth=9');
    const impact = page.text('#vacImpact');
    expect(impact).toContain('Затронет 3 детей');
    expect(impact).toContain('9 мес.');
    expect(impact).toContain('Ещё не доросли: 4');
    expect(impact).toContain('всего детей с датой рождения: 12');
  });

  it('sends the typed month and both languages, then paints the saved row', async () => {
    const saved = adminSchedule({
      'pcv/2': {
        atMonth: 9, edited: true, live: true, liveAtMonth: 9, reviewCurrent: true,
        ru: { name: 'Пневмококковая', note: 'Против пневмонии и отита' },
        kk: { name: 'Пневмококк', note: 'Пневмония мен отитке қарсы' },
        review: { by: 'clinician-1', at: '2026-08-01T10:00:00Z' },
      },
    });
    const page = await openTab({ afterPut: saved });
    await click(page, '#vacBody tr[data-vackey="pcv/2"] button');
    await typeInto(page, '#vacAt', '9');
    await typeInto(page, '#vacRuName', 'Пневмококковая');
    await typeInto(page, '#vacKkName', 'Пневмококк');
    await typeInto(page, '#vacRuNote', 'Против пневмонии и отита');
    await typeInto(page, '#vacKkNote', 'Пневмония мен отитке қарсы');
    await click(page, '#vacSave');

    const put = page.sent.find((r) => r.method === 'PUT');
    expect(put, 'nothing was sent').toBeTruthy();
    expect(put!.path).toBe('/admin/vaccination/schedule/pcv/2');
    expect(put!.body).toMatchObject({
      atMonth: 9,
      ru: { name: 'Пневмококковая', note: 'Против пневмонии и отита' },
      kk: { name: 'Пневмококк', note: 'Пневмония мен отитке қарсы' },
      dose: 2,
      draft: false,
    });
    // ...and the table now shows the month that was saved, not the one typed.
    expect(page.text('#vacBody tr[data-vackey="pcv/2"]')).toContain('9 мес.');
    expect(page.text('#vacCardMsg')).toContain('Опубликовано');
  });

  it('a single-dose vaccine keeps its `null` segment in the path', async () => {
    const page = await openTab();
    await click(page, '#vacBody tr[data-vackey="bcg/null"] button');
    await typeInto(page, '#vacRuName', 'БЦЖ');
    await typeInto(page, '#vacKkName', 'БЦЖ');
    await click(page, '#vacSave');
    expect(page.sent.find((r) => r.method === 'PUT')!.path).toBe('/admin/vaccination/schedule/bcg/null');
    expect(page.sent.find((r) => r.method === 'PUT')!.body).toMatchObject({ dose: null });
  });
});

describe('the card reports what the SERVER said', () => {
  it('refuses to send at all when the Kazakh box is empty, and names it', async () => {
    const page = await openTab();
    await click(page, '#vacBody tr[data-vackey="pcv/2"] button');
    await typeInto(page, '#vacRuName', 'Пневмококковая');
    await typeInto(page, '#vacKkName', '');
    await click(page, '#vacSave');
    expect(page.sent.filter((r) => r.method === 'PUT')).toHaveLength(0);
    expect(page.text('#vacCardMsg')).toContain('казахского названия');
  });

  it('prints the server’s own sentence on 400 translation_required', async () => {
    const page = await openTab({
      putReply: {
        status: 400,
        body: {
          error: 'translation_required',
          message: '«Пневмококковая»: нет казахского перевода поля «note». Публикация без ҚАЗ невозможна.',
        },
      },
    });
    await click(page, '#vacBody tr[data-vackey="pcv/2"] button');
    await typeInto(page, '#vacRuName', 'Пневмококковая');
    await typeInto(page, '#vacKkName', 'Пневмококк');
    await click(page, '#vacSave');
    const msg = page.text('#vacCardMsg');
    expect(msg).toContain('нет казахского перевода');
    expect(msg).not.toBe('Ошибка 400');
  });

  it('prints the server’s own sentence on 409 review_required', async () => {
    // «409» on its own sends a content editor to ask a developer what a 409 is.
    const page = await openTab({
      putReply: {
        status: 409,
        body: {
          error: 'review_required',
          message: '«vaccine-pcv/2»: медицинский текст без проверки врачом. Отправьте на проверку врачу или сохраните как черновик.',
        },
      },
    });
    await click(page, '#vacBody tr[data-vackey="pcv/2"] button');
    await typeInto(page, '#vacRuName', 'Пневмококковая');
    await typeInto(page, '#vacKkName', 'Пневмококк');
    await click(page, '#vacSave');
    const msg = page.text('#vacCardMsg');
    expect(msg).toContain('без проверки врачом');
    expect(msg).toContain('черновик');
  });

  it('a draft save says the phones keep the contract', async () => {
    const page = await openTab({ putReply: { status: 200, body: { ok: true, key: 'pcv/2', draft: true, added: false, reviewed: false } } });
    await click(page, '#vacBody tr[data-vackey="pcv/2"] button');
    await typeInto(page, '#vacRuName', 'Пневмококковая');
    await typeInto(page, '#vacKkName', 'Пневмококк');
    await click(page, '#vacDraft');
    expect(page.sent.find((r) => r.method === 'PUT')!.body).toMatchObject({ draft: true });
    expect(page.text('#vacCardMsg')).toContain('контрактный срок');
  });
});

describe('when the server could not read the edit state', () => {
  // Deploying the panel before migration 038, or a database blip. The sixteen
  // rows are still the real served calendar; what is unknown is which of them
  // somebody has already edited.
  it('still draws the calendar and does not pretend the rows are untouched', async () => {
    const page = await openTab({ schedule: adminSchedule({}, { editsKnown: false }) });
    expect(page.count('#vacBody tbody tr')).toBe(vaccinationSchedule.vaccines.length);
    expect(page.text('#vacRule')).toContain('Состояние правок недоступно');
  });

  it('disables saving and says why, rather than overwriting an edit it cannot see', async () => {
    const page = await openTab({ schedule: adminSchedule({}, { editsKnown: false }) });
    await click(page, '#vacBody tr[data-vackey="pcv/2"] button');
    const save = page.window.document.querySelector('#vacSave') as HTMLButtonElement;
    const draft = page.window.document.querySelector('#vacDraft') as HTMLButtonElement;
    expect(save.disabled).toBe(true);
    expect(draft.disabled).toBe(true);
    expect((page.window.document.querySelector('#vacRuName') as HTMLInputElement).disabled).toBe(true);
    expect(page.text('#vacCardBody')).toContain('Сохранение закрыто');
    expect(page.text('#vacCardBody')).toContain('vaccination_overrides');
    // ...and pressing it anyway sends nothing.
    await click(page, '#vacSave');
    expect(page.sent.filter((r) => r.method === 'PUT')).toHaveLength(0);
  });

  it('a refused calendar read says the server said no, not that there is no server', async () => {
    const page = await openTab({ scheduleStatus: 403 });
    expect(page.text('#vacBody')).toContain('Нет доступа');
    expect(page.text('#vacBody')).toContain('Это не сбой');
  });
});

describe('frame 15a — «Добавить прививку»', () => {
  it('builds the key out of code and dose, and opens an empty card on it', async () => {
    const page = await openTab();
    (page.window.document.querySelector('#vacAddId') as HTMLInputElement).value = 'rota';
    (page.window.document.querySelector('#vacAddDose') as HTMLInputElement).value = '1';
    await submit(page, '#vacAddForm');
    expect(page.text('#vacAddMsg')).toContain('rota/1');
    expect(painted(page, '#vacCard')).toBe(true);
    expect(page.text('#vacCardSub')).toContain('в контракте её нет');
    // An added vaccine has no l10n fallback in the app, so all four boxes are
    // required — and the card says so.
    expect(page.text('#vacCardBody')).toContain('обязательны все четыре поля');
  });

  it('refuses a code the server would refuse, before the round trip', async () => {
    const page = await openTab();
    (page.window.document.querySelector('#vacAddId') as HTMLInputElement).value = 'Rota Virus';
    await submit(page, '#vacAddForm');
    expect(page.text('#vacAddMsg')).toContain('латиница');
    expect(painted(page, '#vacCard')).toBe(false);
  });

  it('saves a new vaccine under the key that was composed', async () => {
    const page = await openTab({ putReply: { status: 200, body: { ok: true, key: 'rota/1', draft: false, added: true, reviewed: false } } });
    (page.window.document.querySelector('#vacAddId') as HTMLInputElement).value = 'rota';
    (page.window.document.querySelector('#vacAddDose') as HTMLInputElement).value = '1';
    await submit(page, '#vacAddForm');
    await typeInto(page, '#vacAt', '2');
    await typeInto(page, '#vacRuName', 'Ротавирусная');
    await typeInto(page, '#vacKkName', 'Ротавирус');
    await typeInto(page, '#vacRuNote', 'Против тяжёлой кишечной инфекции');
    await typeInto(page, '#vacKkNote', 'Ауыр ішек инфекциясына қарсы');
    await click(page, '#vacSave');
    const put = page.sent.find((r) => r.method === 'PUT');
    expect(put!.path).toBe('/admin/vaccination/schedule/rota/1');
    expect(put!.body).toMatchObject({ atMonth: 2, dose: 1, draft: false });
  });

  it('asks the impact of a vaccine that does not exist yet with atMonth alone', async () => {
    const page = await openTab({
      impact: { key: '', atMonth: 2, total: 12, notYet: 4, passed: 6, reclassified: 8, proposedAtMonth: 2, isNew: true, ageLabel: '2 мес.' },
    });
    (page.window.document.querySelector('#vacAddId') as HTMLInputElement).value = 'rota';
    await submit(page, '#vacAddForm');
    await typeInto(page, '#vacAt', '2');
    const asked = page.got.filter((p) => p.includes('/admin/vaccination/impact'));
    expect(asked[asked.length - 1]).toContain('atMonth=2');
    expect(asked[asked.length - 1]).not.toContain('key=');
    expect(page.text('#vacImpact')).toContain('Затронет 8 детей');
  });
});

describe('«настройки напоминаний» — the one honest knob', () => {
  it('offers the catch-up window and no notification toggle, and says why', async () => {
    const page = await openTab();
    expect(painted(page, '#vacWin')).toBe(true);
    const card = page.text('#vacSetCard');
    expect(card).toContain('Рассылки прививок на сервере нет');
    expect(card).toContain('тумблера');
  });

  it('is filled from the served value and PUT to /admin/vaccination/settings', async () => {
    const page = await openTab();
    expect((page.window.document.querySelector('#vacWin') as HTMLInputElement).value)
      .toBe(String(vaccinationSchedule.dueWindowMonths));
    (page.window.document.querySelector('#vacWin') as HTMLInputElement).value = '3';
    await submit(page, '#vacSetForm');
    const put = page.sent.find((r) => r.path.includes('/admin/vaccination/settings'));
    expect(put).toBeTruthy();
    expect(put!.body).toMatchObject({ dueWindowMonths: 3 });
    expect(page.text('#vacSetMsg')).toContain('3 мес');
  });

  it('refuses a window the column’s CHECK would refuse, and says the range', async () => {
    const page = await openTab();
    (page.window.document.querySelector('#vacWin') as HTMLInputElement).value = '99';
    await submit(page, '#vacSetForm');
    expect(page.sent.filter((r) => r.path.includes('/admin/vaccination/settings'))).toHaveLength(0);
    expect(page.text('#vacSetMsg')).toContain('от 1 до 12');
  });

  it('states whether the window is a decision or the contract’s default', async () => {
    const untouched = await openTab();
    expect(untouched.text('#vacRule')).toContain('контрактное значение');
    const chosen = await openTab({
      schedule: adminSchedule({}, {
        dueWindowMonths: 3, dueWindowEdited: true,
        dueWindowUpdatedAt: '2026-08-09T09:00:00Z', dueWindowUpdatedBy: 'content-1',
      }),
    });
    expect(chosen.text('#vacRule')).toContain('выбрано в панели');
    expect(chosen.text('#vacRule')).toContain('content-1');
  });
});

describe('frame 15b — «История версий»', () => {
  it('shows what changed, from what, and who did it', async () => {
    const page = await openTab();
    const log = page.text('#vacLog');
    expect(log).toContain('pcv/2');
    // before === null: the baseline is the contract, and the panel shows it
    // rather than inventing one.
    expect(log).toContain('Возраст:');
    expect(log).toContain('4 мес.');
    expect(log).toContain('9 мес.');
    expect(log).toContain('до этого правок не было, базой был контракт');
    expect(log).toContain('content-1');
  });

  it('renders the text diff in both languages', async () => {
    const page = await openTab();
    const log = page.text('#vacLog');
    expect(log).toContain('Пояснение RU');
    expect(log).toContain('Против пневмонии и отита');
    expect(log).toContain('Атауы ҚАЗ');
  });

  it('shows a settings change as a settings change', async () => {
    const page = await openTab();
    const log = page.text('#vacLog');
    expect(log).toContain('Настройки напоминаний');
    expect(log).toContain('Догоняющее окно');
    expect(log).toContain('контрактное значение');
    expect(log).toContain('3 мес.');
  });

  it('an unreachable journal does not read as «правок не было»', async () => {
    const page = await openTab({ logStatus: 503 });
    const log = page.text('#vacLog');
    expect(log).toContain('Это не значит, что правок не было');
  });

  it('an empty journal says the calendar runs on the contract', async () => {
    const page = await openTab({ log: { entries: [] } });
    expect(page.text('#vacLog')).toContain('Правок ещё не было');
  });
});

describe('who may type', () => {
  it('hides the editing forms from a role without `content`', async () => {
    // A clinician opens this tab to READ and to approve, not to author.
    const page = await openTab({ role: 'clinician' });
    expect(page.count('#vacBody tbody tr')).toBe(vaccinationSchedule.vaccines.length);
    expect(painted(page, '#vacAddCard')).toBe(false);
    expect(painted(page, '#vacSetCard')).toBe(false);
    await click(page, '#vacBody tr[data-vackey="pcv/2"] button');
    expect(page.window.document.querySelector('#vacSave')).toBeNull();
  });

  it('offers «Отметить проверенным» only on an edited row, and only to `health`', async () => {
    const edited = adminSchedule({
      'pcv/2': { edited: true, atMonth: 9, ru: { name: 'Пневмококковая', note: 'x' }, kk: { name: 'Пневмококк', note: 'y' } },
    });
    const clinician = await openTab({ role: 'clinician', schedule: edited });
    await click(clinician, '#vacBody tr[data-vackey="pcv/2"] button');
    expect(painted(clinician, '#vacReview')).toBe(true);

    // An untouched contract row has nothing to approve: the shipped calendar
    // came through the ministry's own order and this product's release.
    const untouched = await openTab({ role: 'clinician' });
    await click(untouched, '#vacBody tr[data-vackey="pcv/2"] button');
    expect(untouched.window.document.querySelector('#vacReview')).toBeNull();

    // ...and a content editor cannot sign off her own text.
    const editor = await openTab({ role: 'content', schedule: edited });
    await click(editor, '#vacBody tr[data-vackey="pcv/2"] button');
    expect(editor.window.document.querySelector('#vacReview')).toBeNull();
  });

  it('approving asks first — in the card, not in a browser dialog', async () => {
    const edited = adminSchedule({
      'pcv/2': { edited: true, atMonth: 9, ru: { name: 'Пневмококковая', note: 'x' }, kk: { name: 'Пневмококк', note: 'y' } },
    });
    const page = await openTab({ schedule: edited });
    await click(page, '#vacBody tr[data-vackey="pcv/2"] button');
    await click(page, '#vacReview');
    // Nothing sent yet: the question is on screen, with a way out.
    expect(page.sent.filter((r) => r.method === 'POST')).toHaveLength(0);
    expect(page.text('#vacCardMsg')).toContain('Ваше имя попадёт в журнал');
    expect(painted(page, '#vacAskNo')).toBe(true);
    await click(page, '#vacAskYes');
    const post = page.sent.find((r) => r.method === 'POST');
    expect(post!.path).toBe('/admin/vaccination/schedule/pcv/2/review');
  });

  it('cancelling the question sends nothing', async () => {
    const edited = adminSchedule({
      'pcv/2': { edited: true, atMonth: 9, ru: { name: 'Пневмококковая', note: 'x' }, kk: { name: 'Пневмококк', note: 'y' } },
    });
    const page = await openTab({ schedule: edited });
    await click(page, '#vacBody tr[data-vackey="pcv/2"] button');
    await click(page, '#vacReview');
    await click(page, '#vacAskNo');
    expect(page.sent.filter((r) => r.method === 'POST')).toHaveLength(0);
    expect(page.errors).toEqual([]);   // and window.confirm was never reached
  });
});
