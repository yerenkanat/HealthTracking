/**
 * Render the admin panel's pregnancy-calendar tab, the week EDITOR and the
 * patient drawer for real (jsdom).
 *
 * Frames 14a «40 недель» and 14b «Редактор недели». The route can be perfect
 * and the editor still never appear — that is this repo's most common failure —
 * so this boots the real panel, clicks the real tab, types into the real boxes
 * and presses the real button, then reads what a browser would have drawn.
 *
 * "Verified structurally" is not verification: every assertion below is on
 * painted text or on the request the panel actually sent.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { pregnancyCalendar } from '../pregnancy/weeks.js';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

// A due date that puts her in week 28 TODAY, rather than a fixed calendar date
// that silently drifts a week every week. The drawer derives the gestational
// week from dueDate — it used to read `weeks` off the demo fixture instead,
// which is how a real drawer came to be showing demo data.
const DUE_WEEK_28 = new Date(Date.now() + 12 * 7 * 864e5).toISOString();

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

/** What GET /admin/pregnancy/weeks answers — the served calendar + edit state. */
function adminWeeks(over: Partial<Record<number, Record<string, unknown>>> = {}, meta: Record<string, unknown> = {}) {
  return {
    version: pregnancyCalendar.version,
    contractVersion: pregnancyCalendar.version,
    editsKnown: true,
    mothersKnown: true,
    mothersTotal: 3,
    ...meta,
    weeks: pregnancyCalendar.weeks.map((w) => ({
      week: w.week,
      lengthCm: w.lengthCm,
      hcg: w.hcg,
      ru: w.ru,
      kk: w.kk,
      edited: false,
      draft: false,
      live: false,
      review: null,
      reviewCurrent: false,
      updatedAt: null,
      updatedBy: null,
      // Three mothers standing in week 22, none anywhere else — so «затронет N»
      // can be asserted as a real count rather than a coincidence.
      mothers: w.week === 22 ? 3 : 0,
      ...(over[w.week] ?? {}),
    })),
  };
}

interface Rendered {
  text(sel: string): string;
  count(sel: string): number;
  errors: string[];
  /** Every write the panel sent: [method, path, parsed body]. */
  sent: Array<{ method: string; path: string; body: unknown }>;
  window: import('jsdom').DOMWindow;
  /** Resolves when the panel has stopped working, never after a fixed delay. */
  quiet: (label?: string) => Promise<void>;
}

interface BootOpts {
  role?: string;
  weeks?: unknown;
  /** What a PUT /admin/pregnancy/weeks/:week answers. */
  putReply?: { status: number; body: unknown };
  /** Make the staff calendar read itself fail, to see what the tab then says. */
  weeksStatus?: number;
  confirm?: boolean;
}

async function boot(opts: BootOpts = {}): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const sent: Rendered['sent'] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  const weeks = opts.weeks ?? adminWeeks();
  const settle = panelSettle();
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
      window.confirm = () => opts.confirm !== false;
      (window as unknown as { CSS: { escape: (s: string) => string } }).CSS = { escape: (s) => s };
      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = String(path);
        const method = init?.method ?? 'GET';
        if (method !== 'GET') {
          sent.push({ method, path: p, body: init?.body ? JSON.parse(init.body) : null });
        }
        // The panel now opens on a sign-in gate and asks who is signed in
        // before it renders anything. These tests are about the dashboard,
        // so they answer as a signed-in admin.
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: opts.role ?? 'admin' }) };
        }
        if (p.includes('/admin/pregnancy/weeks') && method === 'PUT') {
          const r = opts.putReply ?? { status: 200, body: { ok: true, week: 22, draft: false, reviewed: false } };
          return {
            ok: r.status >= 200 && r.status < 300, status: r.status,
            text: async () => JSON.stringify(r.body),
            json: async () => r.body,
          };
        }
        if (p.includes('/admin/pregnancy/weeks') && method === 'POST') {
          return { ok: true, status: 200, text: async () => '{"ok":true}', json: async () => ({ ok: true }) };
        }
        if (p.includes('/admin/pregnancy/weeks')) {
          if (opts.weeksStatus && opts.weeksStatus >= 400) {
            return { ok: false, status: opts.weeksStatus, text: async () => '{}', json: async () => ({}) };
          }
          return { ok: true, status: 200, json: async () => weeks };
        }
        if (p.includes('/admin/reference/pregnancy')) return { ok: true, status: 200, json: async () => pregnancyCalendar };
        if (p.includes('/admin/users')) {
          return { ok: true, status: 200, json: async () => ({ total: 1, users: [{ id: 'u1', displayName: 'Aigerim S.', phone: '+77073452244', dueDate: DUE_WEEK_28, lastMetricAt: new Date(Date.now() - 36e5).toISOString() }] }) };
        }
        return { ok: false, status: 500, text: async () => '{}', json: async () => ({}) };
      });
    },
  });
  const { window } = dom;
  await settle.quiet('boot');
  return {
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (sel) => window.document.querySelectorAll(sel).length,
    errors,
    sent,
    window,
    quiet: settle.quiet,
  };
}
async function click(page: Rendered, sel: string) {
  page.window.document.querySelector(sel)!.dispatchEvent(new page.window.MouseEvent('click', { bubbles: true }));
  await page.quiet(`the click on ${sel}`);
}
function type(page: Rendered, sel: string, value: string) {
  (page.window.document.querySelector(sel) as HTMLInputElement).value = value;
}

/**
 * Painted, not merely present.
 *
 * `applyCaps` hides what a role may not use by setting the `hidden` attribute,
 * and a `.view` that is not the current tab is display:none — which jsdom's
 * computed style does not report. So "visible" here means: the node exists, no
 * ancestor carries `hidden`, and the section it lives in is the active view.
 */
function painted(page: Rendered, sel: string): boolean {
  let el = page.window.document.querySelector(sel) as HTMLElement | null;
  if (!el) return false;
  for (let n: HTMLElement | null = el; n; n = n.parentElement) {
    if (n.hasAttribute('hidden')) return false;
    if (n.classList.contains('view') && !n.classList.contains('active')) return false;
  }
  el = null;
  return true;
}

describe('admin pregnancy-calendar tab', () => {
  let page: Rendered;
  beforeAll(async () => {
    page = await boot();
    await click(page, '[data-view="pregweeks"]');
  });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('shows a week chip per calendar week and the default week content', () => {
    expect(page.count('#pwWeeks .pw-wk')).toBe(pregnancyCalendar.weeks.length);
    expect(page.count('#pwBody .pw-card')).toBe(3); // baby / you / recommend
    expect(page.text('#pwBody')).toContain('Неделя 12');
  });

  it('switches to a chosen week', async () => {
    await click(page, '#pwWeeks .pw-wk[data-week="6"]');
    const week6 = pregnancyCalendar.weeks.find((w) => w.week === 6)!;
    expect(page.text('#pwBody')).toContain(week6.ru.baby.slice(0, 20));
  });

  it('switches language to Kazakh', async () => {
    await click(page, '.pw-l[data-lang="kk"]');
    expect(page.text('#pwBody')).toContain('Апта');
  });
});

describe('frame 14a — «кого затрагивает»', () => {
  it('states the head-count for the open week, in words, from due dates', async () => {
    const page = await boot();
    await click(page, '[data-view="pregweeks"]');
    await click(page, '#pwWeeks .pw-wk[data-week="22"]');
    // Not «312»: three mothers are on week 22 in the fixture, and three is what
    // it says. The plural is Russian, so «3 мамы» rather than «3 мам».
    expect(page.text('#pwBody')).toContain('3 мамы на этой неделе сейчас');
  });

  it('the footer states where the number comes from and what the dots mean', async () => {
    const page = await boot();
    await click(page, '[data-view="pregweeks"]');
    const rule = page.text('#pwRule');
    expect(rule).toContain('users.due_date');
    expect(rule).toContain('всего беременных: 3');
    expect(rule).toContain('ждёт проверки врача');
    expect(rule).toContain('черновик');
  });

  it('says nothing at all when the server could not count, rather than showing zeroes', async () => {
    // A column of zeroes reads as «nobody is pregnant», which is a different
    // claim from «we could not count».
    const page = await boot({ weeks: adminWeeks({}, { mothersKnown: false, mothersTotal: null }) });
    await click(page, '[data-view="pregweeks"]');
    await click(page, '#pwWeeks .pw-wk[data-week="22"]');
    expect(page.text('#pwBody')).not.toContain('на этой неделе сейчас');
    expect(page.text('#pwRule')).toContain('Счётчик мам недоступен');
  });

  it('marks an edited week on the strip and names its state', async () => {
    const page = await boot({
      weeks: adminWeeks({
        22: { edited: true, draft: false, live: true, reviewCurrent: true,
          review: { by: 'clinician-1', at: '2026-08-01T10:00:00Z' },
          updatedAt: '2026-08-01T09:00:00Z', updatedBy: 'content-1' },
        23: { edited: true, draft: true },
      }),
    });
    await click(page, '[data-view="pregweeks"]');
    expect(page.count('#pwWeeks .pw-wk[data-week="22"] .pw-dot.live')).toBe(1);
    expect(page.count('#pwWeeks .pw-wk[data-week="23"] .pw-dot.draft')).toBe(1);
    // ...and the untouched weeks carry no dot at all.
    expect(page.count('#pwWeeks .pw-dot')).toBe(2);
  });
});

describe('frame 14b — the week editor, painted', () => {
  let page: Rendered;
  beforeAll(async () => {
    page = await boot();
    await click(page, '[data-view="pregweeks"]');
    await click(page, '#pwWeeks .pw-wk[data-week="22"]');
  });

  it('the visibility check is not vacuous: nothing here is painted from another tab', async () => {
    // A control for [painted]. `.view{display:none}` is a stylesheet rule jsdom
    // does not compute, so without this the whole file could be asserting that
    // elements exist in a section no browser is drawing — which is exactly the
    // failure the check exists to catch.
    const other = await boot();
    expect(painted(other, '#pwEditCard')).toBe(false);
    await click(other, '[data-view="pregweeks"]');
    expect(painted(other, '#pwEditCard')).toBe(true);
  });

  it('draws six text boxes — RU and ҚАЗ for each of the three fields', () => {
    for (const id of ['#wkRuBaby', '#wkKkBaby', '#wkRuYou', '#wkKkYou', '#wkRuRec', '#wkKkRec']) {
      expect(painted(page, id), `${id} is not on screen`).toBe(true);
    }
    expect(painted(page, '#wkLen')).toBe(true);
    expect(painted(page, '#wkHcg')).toBe(true);
  });

  it('fills the boxes with the week that is open, not the default one', () => {
    const w22 = pregnancyCalendar.weeks.find((w) => w.week === 22)!;
    const val = (s: string) => (page.window.document.querySelector(s) as HTMLTextAreaElement).value;
    expect(val('#wkRuBaby')).toBe(w22.ru.baby);
    expect(val('#wkKkBaby')).toBe(w22.kk.baby);
    expect(page.text('#pwEditH')).toBe('Редактор недели 22');
  });

  it('offers publish, draft and — to a role with `health` — approve', () => {
    expect(painted(page, '#wkSave')).toBe(true);
    expect(painted(page, '#wkDraft')).toBe(true);
    // The fixture signs in as `admin`, which holds both caps.
    expect(painted(page, '#wkReview')).toBe(true);
  });

  it('says the week is unedited until somebody edits it', () => {
    expect(page.text('#pwEdit')).toContain('Базовый текст из контракта');
  });

  it('sends what was typed, in both languages, to PUT /admin/pregnancy/weeks/22', async () => {
    type(page, '#wkRuBaby', 'Малыш слышит ваш голос.');
    type(page, '#wkKkBaby', 'Нәресте дауысыңызды естиді.');
    type(page, '#wkLen', '27,8');
    await click(page, '#wkSave');

    const put = page.sent.find((r) => r.method === 'PUT');
    expect(put, 'nothing was sent').toBeTruthy();
    expect(put!.path).toBe('/admin/pregnancy/weeks/22');
    const body = put!.body as { ru: { baby: string }; kk: { baby: string }; lengthCm: string; draft: boolean };
    expect(body.ru.baby).toBe('Малыш слышит ваш голос.');
    expect(body.kk.baby).toBe('Нәресте дауысыңызды естиді.');
    expect(body.lengthCm).toBe('27,8');
    expect(body.draft).toBe(false);
  });
});

describe('the editor reports what the server said', () => {
  it('refuses to send at all when the Kazakh boxes are empty, and names them', async () => {
    const page = await boot();
    await click(page, '[data-view="pregweeks"]');
    await click(page, '#pwWeeks .pw-wk[data-week="22"]');
    for (const id of ['#wkKkBaby', '#wkKkYou', '#wkKkRec']) type(page, id, '');
    await click(page, '#wkSave');

    expect(page.sent.filter((r) => r.method === 'PUT')).toHaveLength(0);
    const msg = page.text('#wkMsg');
    expect(msg).toContain('казахского текста');
    expect(msg).toContain('о малыше');
  });

  it('paints the server\'s own sentence when a medical edit is refused', async () => {
    // «409» on its own sends a content editor to ask a developer what a 409 is.
    const page = await boot({
      putReply: {
        status: 409,
        body: { error: 'review_required', message: '«week-22»: медицинский текст без проверки врачом. Отправьте на проверку врачу или сохраните как черновик.' },
      },
    });
    await click(page, '[data-view="pregweeks"]');
    await click(page, '#pwWeeks .pw-wk[data-week="22"]');
    await click(page, '#wkSave');
    expect(page.text('#wkMsg')).toContain('без проверки врачом');
    expect(page.text('#wkMsg')).toContain('черновик');
  });

  it('a draft save says the reader still sees the base text', async () => {
    const page = await boot({ putReply: { status: 200, body: { ok: true, week: 22, draft: true, reviewed: false } } });
    await click(page, '[data-view="pregweeks"]');
    await click(page, '#pwWeeks .pw-wk[data-week="22"]');
    await click(page, '#wkDraft');
    expect(page.sent.find((r) => r.method === 'PUT')!.body).toMatchObject({ draft: true });
    expect(page.text('#wkMsg')).toContain('базовый текст');
  });
});

describe('when the server could not read the edit state', () => {
  // Deploying the panel before migration 036, or any database blip. The forty
  // weeks are still the real served text; what is unknown is which of them
  // somebody has already edited.
  it('still draws the calendar, and does not pretend the weeks are untouched', async () => {
    const page = await boot({ weeks: adminWeeks({}, { editsKnown: false }) });
    await click(page, '[data-view="pregweeks"]');
    expect(page.count('#pwWeeks .pw-wk')).toBe(pregnancyCalendar.weeks.length);
    expect(page.text('#pwBody')).toContain('Неделя 12');
    expect(page.text('#pwRule')).toContain('Состояние правок недоступно');
  });

  it('closes the editor rather than letting a save overwrite an edit it cannot see', async () => {
    const page = await boot({ weeks: adminWeeks({}, { editsKnown: false }) });
    await click(page, '[data-view="pregweeks"]');
    await click(page, '#pwWeeks .pw-wk[data-week="22"]');
    expect(painted(page, '#wkRuBaby')).toBe(false);
    expect(painted(page, '#wkSave')).toBe(false);
    // ...and says why, in the editor's own card.
    expect(page.text('#pwEdit')).toContain('Редактор недоступен');
    expect(page.text('#pwEdit')).toContain('проверку врача');
  });

  it('a refused load says the server said no, not that there is no server', async () => {
    const page = await boot({ weeksStatus: 500 });
    await click(page, '[data-view="pregweeks"]');
    expect(page.text('#pwBody')).toContain('Календарь не загрузился');
    expect(page.text('#pwBody')).toContain('500');
  });
});

describe('who may type', () => {
  it('hides the editor from a role without `content`', async () => {
    // A clinician opens this tab to READ and to approve, not to write.
    const page = await boot({ role: 'clinician' });
    await click(page, '[data-view="pregweeks"]');
    // The calendar is still there...
    expect(page.count('#pwWeeks .pw-wk')).toBe(pregnancyCalendar.weeks.length);
    // ...and the boxes are not.
    expect(painted(page, '#wkRuBaby')).toBe(false);
    expect(painted(page, '#wkSave')).toBe(false);
  });

  it('shows the boxes but not the approve button to a role with only `content`', async () => {
    const page = await boot({ role: 'content' });
    await click(page, '[data-view="pregweeks"]');
    await click(page, '#pwWeeks .pw-wk[data-week="22"]');
    expect(painted(page, '#wkRuBaby')).toBe(true);
    // Approving is `health`. That separation IS the two-person rule.
    expect(painted(page, '#wkReview')).toBe(false);
  });
});

describe('admin patient drawer — this week content', () => {
  it('shows this-week baby/you text for the mother’s gestational week', async () => {
    const page = await boot();
    await click(page, '[data-view="users"]');
    await click(page, '#usersBody tr[data-user="u1"]'); // MOCK u1 = 28 weeks
    const drawer = page.text('#drawer');
    expect(drawer).toContain('Эта неделя');
    const week28 = pregnancyCalendar.weeks.find((w) => w.week === 28)!;
    expect(drawer).toContain(week28.ru.baby.slice(0, 20));
  });
});
