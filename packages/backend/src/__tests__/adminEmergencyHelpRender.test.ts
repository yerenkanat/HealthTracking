/**
 * Render the admin panel's «Экстренная помощь» tab and its editor for real
 * (jsdom).
 *
 * Frame 16b. The route can be perfect and the editor still never appear — that
 * is this repo's most common failure — so this boots the real panel, clicks the
 * real tab, types into the real boxes and presses the real button, then reads
 * what a browser would have drawn.
 *
 * "Verified structurally" is not verification: every assertion below is on
 * painted text or on the request the panel actually sent.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { emergencyHelp } from '../emergency/help.js';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

/** What GET /admin/emergency-help answers — the served list + edit state. */
function adminScenarios(
  over: Partial<Record<string, Record<string, unknown>>> = {},
  meta: Record<string, unknown> = {},
) {
  return {
    version: emergencyHelp.version,
    contractVersion: emergencyHelp.version,
    tel: emergencyHelp.tel,
    editsKnown: true,
    ...meta,
    scenarios: emergencyHelp.scenarios.map((s) => ({
      id: s.id,
      severity: s.severity,
      sort: s.sort,
      ru: s.ru,
      kk: s.kk,
      edited: false,
      draft: false,
      live: false,
      review: null,
      reviewCurrent: false,
      updatedAt: null,
      updatedBy: null,
      ...(over[s.id] ?? {}),
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
  scenarios?: unknown;
  /** What a PUT /admin/emergency-help/:id answers. */
  putReply?: { status: number; body: unknown };
  /** Make the staff list read itself fail, to see what the tab then says. */
  listStatus?: number;
  confirm?: boolean;
}

async function boot(opts: BootOpts = {}): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const sent: Rendered['sent'] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  const list = opts.scenarios ?? adminScenarios();
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
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: opts.role ?? 'admin' }) };
        }
        if (p.includes('/admin/emergency-help') && method === 'PUT') {
          const r = opts.putReply ?? { status: 200, body: { ok: true, id: 'bleeding', draft: false, reviewed: false } };
          return {
            ok: r.status >= 200 && r.status < 300, status: r.status,
            text: async () => JSON.stringify(r.body),
            json: async () => r.body,
          };
        }
        if (p.includes('/admin/emergency-help') && method === 'POST') {
          return { ok: true, status: 200, text: async () => '{"ok":true}', json: async () => ({ ok: true }) };
        }
        if (p.includes('/admin/emergency-help')) {
          if (opts.listStatus && opts.listStatus >= 400) {
            return { ok: false, status: opts.listStatus, text: async () => '{}', json: async () => ({}) };
          }
          return { ok: true, status: 200, json: async () => list };
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
  const el = page.window.document.querySelector(sel) as HTMLElement | null;
  if (!el) return false;
  for (let n: HTMLElement | null = el; n; n = n.parentElement) {
    if (n.hasAttribute('hidden')) return false;
    if (n.classList.contains('view') && !n.classList.contains('active')) return false;
  }
  return true;
}

const RED = emergencyHelp.scenarios.filter((s) => s.severity === 'red').length;
const AMBER = emergencyHelp.scenarios.filter((s) => s.severity === 'amber').length;

describe('the «Экстренная помощь» tab', () => {
  let page: Rendered;
  beforeAll(async () => {
    page = await boot();
    await click(page, '[data-view="emergency-help"]');
  });

  it('boots without throwing', () => {
    expect(page.errors).toEqual([]);
  });

  it('draws one row per scenario, with the app\'s own red/amber stripe', () => {
    expect(page.count('#ehList .eh-row')).toBe(emergencyHelp.scenarios.length);
    // The border colour IS the message. A panel that drew them all the same
    // would let an editor turn «звоните 103» into «позвоните завтра» without
    // seeing it.
    expect(page.count('#ehList .eh-row.red')).toBe(RED);
    expect(page.count('#ehList .eh-row.amber')).toBe(AMBER);
    expect(RED).toBeGreaterThan(0);
    expect(AMBER).toBeGreaterThan(0);
  });

  it('prints the shipped text, not a placeholder', () => {
    const first = emergencyHelp.scenarios[0];
    expect(page.text('#ehList')).toContain(first.ru.title);
    expect(page.text('#ehList')).toContain(first.ru.do.slice(0, 24));
  });

  it('switches language to Kazakh', async () => {
    await click(page, '.eh-l[data-ehlang="kk"]');
    expect(page.text('#ehList')).toContain(emergencyHelp.scenarios[0].kk.title);
    await click(page, '.eh-l[data-ehlang="ru"]');
  });

  it('states the severities in words and refuses to invent a head-count', () => {
    const rule = page.text('#ehRule');
    expect(rule).toContain('звоните 103 сейчас');
    expect(rule).toContain('позвоните врачу сегодня');
    expect(rule).toContain('ждёт проверки врача');
    // «312 мам» is exactly the number this screen must never print: nothing
    // records who opened screen 37.
    expect(rule).toContain('неизвестно');
  });

  it('marks an edited scenario and leaves the untouched ones unmarked', async () => {
    const p = await boot({
      scenarios: adminScenarios({
        bleeding: {
          edited: true, draft: false, live: true, reviewCurrent: true,
          review: { by: 'clinician-1', at: '2026-08-01T10:00:00Z' },
          updatedAt: '2026-08-01T09:00:00Z', updatedBy: 'content-1',
        },
        breathing: { edited: true, draft: true },
      }),
    });
    await click(p, '[data-view="emergency-help"]');
    expect(p.count('#ehList .eh-row[data-ehid="bleeding"] .pw-dot.live')).toBe(1);
    expect(p.count('#ehList .eh-row[data-ehid="breathing"] .pw-dot.draft')).toBe(1);
    expect(p.count('#ehList .pw-dot')).toBe(2);
  });
});

describe('the editor, painted', () => {
  let page: Rendered;
  beforeAll(async () => {
    page = await boot();
    await click(page, '[data-view="emergency-help"]');
    await click(page, '#ehList .eh-row[data-ehid="bleeding"]');
  });

  it('the visibility check is not vacuous: nothing here is painted from another tab', async () => {
    // A control for [painted]. `.view{display:none}` is a stylesheet rule jsdom
    // does not compute, so without this the whole file could be asserting that
    // elements exist in a section no browser is drawing.
    const other = await boot();
    expect(painted(other, '#ehEditCard')).toBe(false);
    await click(other, '[data-view="emergency-help"]');
    expect(painted(other, '#ehEditCard')).toBe(true);
  });

  it('draws six text boxes — RU and ҚАЗ for each of the three fields', () => {
    for (const id of ['#ehRuTitle', '#ehKkTitle', '#ehRuWhat', '#ehKkWhat', '#ehRuDo', '#ehKkDo']) {
      expect(painted(page, id), `${id} is not on screen`).toBe(true);
    }
    expect(painted(page, '#ehSev')).toBe(true);
    expect(painted(page, '#ehSort')).toBe(true);
  });

  it('fills the boxes with the scenario that is open, not the first one', () => {
    const s = emergencyHelp.scenarios.find((x) => x.id === 'bleeding')!;
    const val = (sel: string) => (page.window.document.querySelector(sel) as HTMLTextAreaElement).value;
    expect(val('#ehRuTitle')).toBe(s.ru.title);
    expect(val('#ehKkDo')).toBe(s.kk.do);
    expect((page.window.document.querySelector('#ehSev') as HTMLSelectElement).value).toBe('red');
    expect(page.text('#ehEditH')).toContain(s.ru.title);
  });

  it('offers publish, draft and — to a role with `health` — approve', () => {
    expect(painted(page, '#ehSave')).toBe(true);
    expect(painted(page, '#ehDraft')).toBe(true);
    expect(painted(page, '#ehReview')).toBe(true);
  });

  it('says the scenario is unedited until somebody edits it', () => {
    expect(page.text('#ehEdit')).toContain('Базовый текст из справочника');
  });

  it('sends what was typed, in both languages, to PUT /admin/emergency-help/bleeding', async () => {
    type(page, '#ehRuDo', 'Звоните 103 и лягте на бок.');
    type(page, '#ehKkDo', '103-ке қоңырау шалып, бүйіріңізге жатыңыз.');
    type(page, '#ehSort', '5');
    await click(page, '#ehSave');

    const put = page.sent.find((r) => r.method === 'PUT');
    expect(put, 'nothing was sent').toBeTruthy();
    expect(put!.path).toBe('/admin/emergency-help/bleeding');
    const body = put!.body as { ru: { do: string }; kk: { do: string }; sort: number; severity: string; draft: boolean };
    expect(body.ru.do).toBe('Звоните 103 и лягте на бок.');
    expect(body.kk.do).toBe('103-ке қоңырау шалып, бүйіріңізге жатыңыз.');
    expect(body.sort).toBe(5);
    expect(body.severity).toBe('red');
    expect(body.draft).toBe(false);
  });
});

describe('the editor reports what the server said', () => {
  it('refuses to send at all when the Kazakh boxes are empty, and names them', async () => {
    const page = await boot();
    await click(page, '[data-view="emergency-help"]');
    await click(page, '#ehList .eh-row[data-ehid="bleeding"]');
    for (const id of ['#ehKkTitle', '#ehKkWhat', '#ehKkDo']) type(page, id, '');
    await click(page, '#ehSave');

    expect(page.sent.filter((r) => r.method === 'PUT')).toHaveLength(0);
    const msg = page.text('#ehMsg');
    expect(msg).toContain('казахского текста');
    expect(msg).toContain('что делать');
  });

  it('paints the server\'s own sentence when a medical edit is refused', async () => {
    // «409» on its own sends a content editor to ask a developer what a 409 is.
    const page = await boot({
      putReply: {
        status: 409,
        body: { error: 'review_required', message: '«emergency-bleeding»: медицинский текст без проверки врачом. Отправьте на проверку врачу или сохраните как черновик.' },
      },
    });
    await click(page, '[data-view="emergency-help"]');
    await click(page, '#ehList .eh-row[data-ehid="bleeding"]');
    await click(page, '#ehSave');
    expect(page.text('#ehMsg')).toContain('без проверки врачом');
    expect(page.text('#ehMsg')).toContain('черновик');
  });

  it('a draft save says mothers still see the base text', async () => {
    const page = await boot({ putReply: { status: 200, body: { ok: true, id: 'bleeding', draft: true, reviewed: false } } });
    await click(page, '[data-view="emergency-help"]');
    await click(page, '#ehList .eh-row[data-ehid="bleeding"]');
    await click(page, '#ehDraft');
    expect(page.sent.find((r) => r.method === 'PUT')!.body).toMatchObject({ draft: true });
    expect(page.text('#ehMsg')).toContain('базовый текст');
  });

  it('«вернуть исходный текст» is a draft save, and confirms first', async () => {
    const page = await boot({
      scenarios: adminScenarios({ bleeding: { edited: true, draft: false, live: true } }),
      putReply: { status: 200, body: { ok: true, id: 'bleeding', draft: true, reviewed: false } },
    });
    await click(page, '[data-view="emergency-help"]');
    await click(page, '#ehList .eh-row[data-ehid="bleeding"]');
    expect(painted(page, '#ehRevert'), 'the revert button is not on screen').toBe(true);
    await click(page, '#ehRevert');
    // A draft, never a delete: the words somebody wrote are still there to come
    // back to, and the version stays monotonic.
    expect(page.sent.find((r) => r.method === 'PUT')!.body).toMatchObject({ draft: true });
  });

  it('...and a cancelled confirmation sends nothing', async () => {
    const page = await boot({
      scenarios: adminScenarios({ bleeding: { edited: true, draft: false, live: true } }),
      confirm: false,
    });
    await click(page, '[data-view="emergency-help"]');
    await click(page, '#ehList .eh-row[data-ehid="bleeding"]');
    await click(page, '#ehRevert');
    expect(page.sent.filter((r) => r.method === 'PUT')).toHaveLength(0);
  });
});

describe('when the server could not read the edit state', () => {
  it('still draws the list, and does not pretend the scenarios are untouched', async () => {
    const page = await boot({ scenarios: adminScenarios({}, { editsKnown: false }) });
    await click(page, '[data-view="emergency-help"]');
    expect(page.count('#ehList .eh-row')).toBe(emergencyHelp.scenarios.length);
    expect(page.text('#ehRule')).toContain('Состояние правок недоступно');
  });

  it('closes the editor rather than letting a save overwrite an edit it cannot see', async () => {
    const page = await boot({ scenarios: adminScenarios({}, { editsKnown: false }) });
    await click(page, '[data-view="emergency-help"]');
    await click(page, '#ehList .eh-row[data-ehid="bleeding"]');
    expect(painted(page, '#ehRuTitle')).toBe(false);
    expect(painted(page, '#ehSave')).toBe(false);
    expect(page.text('#ehEdit')).toContain('Редактор недоступен');
    expect(page.text('#ehEdit')).toContain('проверку врача');
  });

  it('a refused load says the server said no, not that there is no server', async () => {
    const page = await boot({ listStatus: 500 });
    await click(page, '[data-view="emergency-help"]');
    expect(page.text('#ehList')).toContain('Список не загрузился');
    expect(page.text('#ehList')).toContain('500');
  });
});

describe('who may type', () => {
  it('hides the editor from a role without `content`', async () => {
    // A clinician opens this tab to READ and to approve, not to write.
    const page = await boot({ role: 'clinician' });
    await click(page, '[data-view="emergency-help"]');
    // The list is still there...
    expect(page.count('#ehList .eh-row')).toBe(emergencyHelp.scenarios.length);
    // ...and the boxes are not.
    expect(painted(page, '#ehRuTitle')).toBe(false);
    expect(painted(page, '#ehSave')).toBe(false);
  });

  it('shows the boxes but not the approve button to a role with only `content`', async () => {
    const page = await boot({ role: 'content' });
    await click(page, '[data-view="emergency-help"]');
    await click(page, '#ehList .eh-row[data-ehid="bleeding"]');
    expect(painted(page, '#ehRuTitle')).toBe(true);
    // Approving is `health`. That separation IS the two-person rule.
    expect(painted(page, '#ehReview')).toBe(false);
  });
});
