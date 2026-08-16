/**
 * Patient 51 — docs/BACKLOG.md §5.2.
 *
 * GET /admin/users has always taken `offset` and always returned a real
 * count(*). The panel sent `?q=…&limit=50`, read `data.users`, and drew no
 * footer at all. On a base of more than fifty mothers the fifty-first did not
 * exist to a clinician: there was no way to reach her and, worse, nothing on
 * screen said there was anybody past the last row. A list that silently ends is
 * indistinguishable from a list that is complete.
 *
 * Two halves, because either alone would have passed while the feature stayed
 * broken:
 *   - the ROUTE, over HTTP against a real memory repository — page two holds
 *     the mothers page one did not, and `total` counts the table rather than
 *     the page;
 *   - the PANEL, executed in jsdom — the footer states «Показано 1–50 из 137»
 *     and the pager actually asks the server for the next fifty.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

// ---------------------------------------------------------------------------
// The route
// ---------------------------------------------------------------------------

let app: FastifyInstance;
let repo: Repository;

/** Enough mothers that one page cannot hold them: the case that was broken. */
const SEEDED = 55;

beforeEach(async () => {
  repo = createMemoryRepository();
  for (let i = 0; i < SEEDED; i += 1) {
    // The real door — a phone sign-in is the only way a user comes to exist.
    // Seeding through it keeps the fixture honest about these rows.
    await repo.createUserWithPhone({
      phone: `+7700000${String(i).padStart(4, '0')}`,
      displayName: `Мама ${String(i).padStart(2, '0')}`,
    });
  }
  app = buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => ({ staffId: 's1', role: 'owner' as const }),
    },
    { logger: false },
  );
});
afterEach(async () => { await app.close(); });

const page = async (qs: string) =>
  (await app.inject({ method: 'GET', url: `/admin/users${qs}` })).json();

describe('GET /admin/users pages the caseload', () => {
  it('counts the whole table, not the page it returned', async () => {
    const first = await page('?limit=50&offset=0');
    expect(first.users).toHaveLength(50);
    // The demo account exists alongside the seeded ones, so this asserts the
    // relationship rather than a hand-typed number: total is bigger than a page.
    expect(first.total).toBeGreaterThanOrEqual(SEEDED);
    expect(first.total).toBeGreaterThan(first.users.length);
  });

  it('hands over the mothers that did not fit on page one', async () => {
    const first = await page('?limit=50&offset=0');
    const second = await page('?limit=50&offset=50');
    expect(second.users.length).toBeGreaterThan(0);
    // Patient 51 herself: on page two, and on neither page one nor a duplicate.
    const firstIds = new Set(first.users.map((u: { id: string }) => u.id));
    for (const u of second.users) expect(firstIds.has(u.id)).toBe(false);
    expect(second.total).toBe(first.total);
  });

  it('the two pages together are the whole table', async () => {
    const all = new Set<string>();
    for (const off of [0, 50]) {
      for (const u of (await page(`?limit=50&offset=${off}`)).users) all.add(u.id);
    }
    expect(all.size).toBe((await page('?limit=50&offset=0')).total);
  });

  it('counts the SEARCH, not the base, when a query is on', async () => {
    // «из N» under a search must mean "found", or the footer promises rows the
    // pager can never reach.
    const found = await page('?q=Мама%2007&limit=50&offset=0');
    expect(found.users).toHaveLength(1);
    expect(found.total).toBe(1);
  });

  it('an offset past the end is an empty page, not an error', async () => {
    const far = await page('?limit=50&offset=500');
    expect(far.users).toEqual([]);
    expect(far.total).toBeGreaterThanOrEqual(SEEDED);
  });
});

// ---------------------------------------------------------------------------
// The panel
// ---------------------------------------------------------------------------

interface Rendered {
  text(sel: string): string;
  el(sel: string): Element | null;
  click(sel: string): Promise<void>;
  type(sel: string, value: string): Promise<void>;
  asked: string[];
  errors: string[];
}

const TOTAL = 137;

/** A page of `n` invented mothers, ids `u{offset+i}`. */
const rows = (offset: number, n: number) =>
  Array.from({ length: n }, (_, i) => ({
    id: `u${offset + i + 1}`,
    displayName: `Мама ${offset + i + 1}`,
    phone: `+770000000${String(offset + i).padStart(2, '0')}`,
    dueDate: null, lastMetricAt: null, latestSeverity: null,
  }));

async function boot(opts: { fail?: boolean } = {}): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const asked: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

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
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      window.fetch = (async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (p.startsWith('/admin/users?')) {
          asked.push(p);
          if (opts.fail) return { ok: false, status: 500, json: async () => ({ error: 'boom' }) };
          const u = new URL(p, 'http://localhost');
          const q = u.searchParams.get('q') ?? '';
          const offset = Number(u.searchParams.get('offset') ?? 0);
          const limit = Number(u.searchParams.get('limit') ?? 50);
          // A search narrows to three; otherwise the whole invented base.
          const total = q ? 3 : TOTAL;
          const n = Math.max(0, Math.min(limit, total - offset));
          return { ok: true, status: 200, json: async () => ({ total, users: rows(offset, n) }) };
        }
        return { ok: false, status: 500, json: async () => ({}) };
      }) as never;
    },
  });

  const { window } = dom;
  const settle = (ms = 200) => new Promise((r) => setTimeout(r, ms));
  await settle(150);
  window.document.querySelector('[data-view="users"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle(250);

  return {
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    el: (sel) => window.document.querySelector(sel),
    click: async (sel) => {
      const el = window.document.querySelector(sel) as HTMLElement | null;
      expect(el, `no ${sel}`).not.toBeNull();
      el!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
      await settle(250);
    },
    type: async (sel, value) => {
      const el = window.document.querySelector(sel) as HTMLInputElement;
      el.value = value;
      el.dispatchEvent(new window.Event('input', { bubbles: true }));
      await settle(500); // the box is debounced at 250 ms
    },
    asked, errors,
  };
}

describe('the caseload footer says how many there are', () => {
  it('boots without throwing', async () => {
    const p = await boot();
    expect(p.errors, p.errors.join('\n')).toEqual([]);
  });

  it('prints «Показано 1–50 из 137» — the served total, not the page size', async () => {
    const p = await boot();
    const foot = p.text('#usersFoot');
    expect(foot).toContain('137');
    expect(foot).toContain('1–50');
  });

  it('states the rule the list obeys, like every other table in the panel', async () => {
    const p = await boot();
    expect(p.text('#usersFoot')).toContain('последнему измерению');
  });

  it('asks the server with an offset at all', async () => {
    const p = await boot();
    expect(p.asked[0]).toContain('offset=0');
    expect(p.asked[0]).toContain('limit=50');
  });
});

describe('the pager reaches patient 51', () => {
  it('fetches the next fifty and renumbers the footer', async () => {
    const p = await boot();
    expect((p.el('#usersPrev') as HTMLButtonElement).disabled).toBe(true);
    expect((p.el('#usersNext') as HTMLButtonElement).disabled).toBe(false);

    await p.click('#usersNext');
    expect(p.asked.some((u) => u.includes('offset=50'))).toBe(true);
    expect(p.text('#usersFoot')).toContain('51–100');
    // And she is on screen — the row that did not exist before.
    expect(p.text('#usersBody')).toContain('Мама 51');
  });

  it('goes back, and cannot go back past the first page', async () => {
    const p = await boot();
    await p.click('#usersNext');
    await p.click('#usersPrev');
    expect(p.text('#usersFoot')).toContain('1–50');
    expect((p.el('#usersPrev') as HTMLButtonElement).disabled).toBe(true);
  });

  it('disables «Вперёд» on the last page rather than serving an empty one', async () => {
    const p = await boot();
    await p.click('#usersNext');
    await p.click('#usersNext'); // 101–137
    expect(p.text('#usersFoot')).toContain('101–137');
    expect((p.el('#usersNext') as HTMLButtonElement).disabled).toBe(true);
  });

  it('a new search starts at the first page of ITS results', async () => {
    // Otherwise a search typed on page three asks for rows 100–150 of three
    // matches and paints «Никто не найден» over a woman who is right there.
    const p = await boot();
    await p.click('#usersNext');
    await p.type('#userSearch', 'Мама');
    const last = p.asked[p.asked.length - 1];
    expect(last).toContain('offset=0');
    expect(p.text('#usersFoot')).toContain('из 3');
    // And the footer says which number «из 3» is — found, not the whole base.
    expect(p.text('#usersFoot')).toContain('нашлось по запросу');
  });
});

describe('a failed read is not an empty caseload', () => {
  it('says the list did not load, in the table and in the footer', async () => {
    const p = await boot({ fail: true });
    expect(p.text('#usersBody')).toContain('Не удалось загрузить');
    const foot = p.text('#usersFoot');
    expect(foot).toContain('сбой чтения');
    // No invented numbers over a list nobody received.
    expect(foot).not.toContain('из 0');
  });
});
