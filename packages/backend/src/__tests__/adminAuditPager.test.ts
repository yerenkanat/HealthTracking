/**
 * The Журнал had no pager — BACKLOG.md §4.4.
 *
 * `GET /admin/audit` served the newest 100 rows and nothing else: no offset,
 * no total, no signal that anything existed behind them. The panel asked for
 * `?limit=100`, printed the rows and drew no footer at all. So a reviewer
 * could read the most recent page of the log and no other page, ever.
 *
 * That is not a cosmetic gap. Opening one mother's record costs a written
 * reason of eight characters or more, refused rather than auto-filled, and the
 * only thing that makes that cost mean anything is that somebody can read the
 * log afterwards. A log whose older half is unreachable from the UI makes the
 * guarantee thinner than it looks.
 *
 * `hasMore`, not `total`, and the panel says so on screen: `audit_log` is
 * append-only and grows with every back-office action, so `count(*)` is a full
 * scan of an unbounded table on every open of the tab. The honest answer to
 * "how many are there" is "we do not count them, and here is whether there is
 * another page" — see AuditPage in db/repository.ts.
 *
 * Two halves, because either alone would pass while the feature stayed broken:
 *   - the ROUTE, over HTTP against a real memory repository — page two holds
 *     the entries page one did not, and `hasMore` goes false exactly at the
 *     end;
 *   - the PANEL, executed in jsdom — the footer and the two buttons exist, the
 *     Next button actually asks the server for `offset=100`, and the rows that
 *     come back are drawn.
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
import { panelSettle } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

// ---------------------------------------------------------------------------
// The route
// ---------------------------------------------------------------------------

let app: FastifyInstance;
let repo: Repository;

/** Two and a half pages at the default limit — the case that was unreachable. */
const SEEDED = 250;
const PAGE = 100;

function serve(role: 'owner' | 'clinician' = 'owner'): FastifyInstance {
  return buildServer(
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
      authAdmin: async () => ({ staffId: 's1', role }),
    },
    { logger: false },
  );
}

beforeEach(async () => {
  repo = createMemoryRepository();
  for (let i = 0; i < SEEDED; i += 1) {
    // Through writeAudit, the only door a real entry comes through. They land
    // inside the same millisecond, which is the interesting case: `at` alone
    // cannot order them, so a page boundary that relied on the timestamp would
    // show a row twice or lose it.
    await repo.writeAudit({
      staffId: 's1',
      action: 'view_user_detail',
      target: `запись-${String(i).padStart(3, '0')}`,
      reason: 'плановая проверка доступа',
    });
  }
  app = serve();
});
afterEach(async () => { await app.close(); });

const page = async (qs: string) => (await app.inject({ method: 'GET', url: `/admin/audit${qs}` })).json();

describe('GET /admin/audit pages the log', () => {
  it('serves a page and says whether there is another one', async () => {
    const first = await page(`?limit=${PAGE}&offset=0`);
    expect(first.audit).toHaveLength(PAGE);
    expect(first.hasMore).toBe(true);
    // Echoed back, so the panel numbers the footer from what was served.
    expect(first.limit).toBe(PAGE);
    expect(first.offset).toBe(0);
  });

  it('never invents a count of the log', async () => {
    // The whole reason this is `hasMore`. A `total` here would be a full scan
    // of an append-only table on every open of the tab, and a number that is
    // not a real count would be worse than no number at all.
    const first = await page(`?limit=${PAGE}&offset=0`);
    expect(first).not.toHaveProperty('total');
    expect(first).not.toHaveProperty('count');
  });

  it('hands over the entries that did not fit on page one', async () => {
    const first = await page(`?limit=${PAGE}&offset=0`);
    const second = await page(`?limit=${PAGE}&offset=${PAGE}`);
    expect(second.audit).toHaveLength(PAGE);
    const firstTargets = new Set(first.audit.map((a: { target: string }) => a.target));
    for (const a of second.audit) expect(firstTargets.has(a.target)).toBe(false);
  });

  it('the pages together are the whole log, each entry exactly once', async () => {
    const seen: string[] = [];
    for (const offset of [0, PAGE, PAGE * 2]) {
      for (const a of (await page(`?limit=${PAGE}&offset=${offset}`)).audit) seen.push(a.target);
    }
    expect(seen).toHaveLength(SEEDED);
    expect(new Set(seen).size).toBe(SEEDED);
  });

  it('newest first, and the oldest entry is reachable at all', async () => {
    const first = await page(`?limit=${PAGE}&offset=0`);
    expect(first.audit[0].target).toBe('запись-249');
    const last = await page(`?limit=${PAGE}&offset=${PAGE * 2}`);
    // The row written first — the one the panel could never reach.
    expect(last.audit[last.audit.length - 1].target).toBe('запись-000');
  });

  it('hasMore turns false on the last page, not one page late', async () => {
    expect((await page(`?limit=${PAGE}&offset=${PAGE}`)).hasMore).toBe(true);
    const last = await page(`?limit=${PAGE}&offset=${PAGE * 2}`);
    expect(last.audit).toHaveLength(50);
    expect(last.hasMore).toBe(false);
  });

  it('an exact fit is not reported as having another page', async () => {
    // limit 125 × 2 = 250 exactly. The off-by-one that shows an empty page.
    const second = await page('?limit=125&offset=125');
    expect(second.audit).toHaveLength(125);
    expect(second.hasMore).toBe(false);
  });

  it('an offset past the end is an empty page, not an error', async () => {
    const far = await page('?limit=100&offset=5000');
    expect(far.audit).toEqual([]);
    expect(far.hasMore).toBe(false);
  });

  it('a junk or negative offset reads as the first page', async () => {
    for (const qs of ['?offset=-40', '?offset=abc', '']) {
      const r = await page(qs);
      expect(r.offset).toBe(0);
      expect(r.audit[0].target).toBe('запись-249');
    }
  });

  it('the page size stays clamped — paging did not open a way to pull it all', async () => {
    const r = await page('?limit=100000&offset=0');
    expect(r.limit).toBe(500);
    expect(r.audit.length).toBeLessThanOrEqual(500);
  });

  it('reading the log is still `staff`, on every page', async () => {
    // Being allowed to read health records is not being allowed to read the
    // record of everyone reading them. Paging must not have opened a side door.
    const clinician = serve('clinician');
    await clinician.ready();
    for (const qs of ['', '?offset=100', '?limit=500&offset=200']) {
      expect((await clinician.inject({ method: 'GET', url: `/admin/audit${qs}` })).statusCode).toBe(403);
    }
    await clinician.close();
  });

  it('paging does not itself flood the log it is paging', async () => {
    // GET /admin/audit is exempt from writing an audit row — otherwise the log
    // fills with the reading of the log. Three page turns must not change what
    // is in it.
    const before = (await page('?limit=500&offset=0')).audit.length;
    await page('?offset=100');
    await page('?offset=200');
    expect((await page('?limit=500&offset=0')).audit.length).toBe(before);
  });
});

describe('the repository page is the same shape in both implementations', () => {
  it('memory honours limit and offset and reports hasMore from the data', async () => {
    // The fake is the only implementation the tests can run. If it answered
    // from `audit.length` instead of one row past the page, it would be
    // blessing a total that pg deliberately refuses to compute.
    const one = await repo.listAudit(10, 0);
    const two = await repo.listAudit(10, 10);
    expect(one.entries).toHaveLength(10);
    expect(one.hasMore).toBe(true);
    expect(two.entries[0].target).toBe('запись-239');
    expect((await repo.listAudit(10, SEEDED - 10)).hasMore).toBe(false);
    expect((await repo.listAudit(10, SEEDED)).entries).toEqual([]);
  });

  it('offset defaults to the newest page, for the callers that want the lot', async () => {
    // /admin/owner and /admin/security both read a wide slice and no page.
    const wide = await repo.listAudit(5000);
    expect(wide.entries).toHaveLength(SEEDED);
    expect(wide.hasMore).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// The panel
// ---------------------------------------------------------------------------

interface Rendered {
  window: Window & typeof globalThis;
  text(sel: string): string;
  el(sel: string): Element | null;
  click(sel: string): Promise<void>;
  asked: string[];
  errors: string[];
  /** Resolves when the panel has stopped working, never after a fixed delay. */
  quiet: (label?: string) => Promise<void>;
}

/** «Hidden vs painted»: a display rule beats the hidden attribute. */
function painted(p: Rendered, sel: string): boolean {
  const el = p.window.document.querySelector(sel) as HTMLElement | null;
  if (!el) return false;
  for (let n: HTMLElement | null = el; n; n = n.parentElement) {
    if (n.hasAttribute('hidden')) return false;
    if (n.classList.contains('view') && !n.classList.contains('active')) return false;
  }
  return true;
}

/** Invented entries for the browser half — ids `n` counting down from the top. */
const entries = (offset: number, n: number) =>
  Array.from({ length: n }, (_, i) => ({
    staffId: 's1',
    staffName: 'Нуржан Ахметов',
    staffPhone: '+77010000001',
    action: 'view_user_detail',
    target: `u-${offset + i + 1}`,
    targetName: `Запись ${offset + i + 1}`,
    reason: 'проверка доступа',
    at: '2026-08-19T09:41:00.000Z',
  }));

const IN_LOG = 250;

async function boot(opts: { fail?: boolean } = {}): Promise<Rendered> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const asked: string[] = [];
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
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      settle.attach(window as never, async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (p.startsWith('/admin/audit')) {
          asked.push(p);
          if (opts.fail) return { ok: false, status: 500, json: async () => ({ error: 'boom' }) };
          const u = new URL(p, 'http://localhost');
          const offset = Number(u.searchParams.get('offset') ?? 0);
          const limit = Number(u.searchParams.get('limit') ?? 100);
          const n = Math.max(0, Math.min(limit, IN_LOG - offset));
          return {
            ok: true, status: 200,
            json: async () => ({ audit: entries(offset, n), hasMore: offset + n < IN_LOG, limit, offset }),
          };
        }
        return { ok: false, status: 500, json: async () => ({}) };
      });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  window.document.querySelector('[data-view="audit"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Журнал tab');

  const p: Rendered = {
    window: window as unknown as Window & typeof globalThis,
    text: (sel) => (window.document.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    el: (sel) => window.document.querySelector(sel),
    click: async (sel) => {
      const el = window.document.querySelector(sel) as HTMLElement | null;
      expect(el, `no ${sel}`).not.toBeNull();
      el!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
      await settle.quiet(`the click on ${sel}`);
    },
    quiet: settle.quiet,
    asked, errors,
  };
  return p;
}

describe('the Журнал draws a footer at all', () => {
  it('boots and opens without throwing', async () => {
    const p = await boot();
    expect(p.errors, p.errors.join('\n')).toEqual([]);
    expect(p.text('#pageTitle')).toBe('Журнал действий');
  });

  it('the footer is on the screen a browser would be showing', async () => {
    const p = await boot();
    expect(painted(p, '#auditFoot'), 'the pager footer is not painted').toBe(true);
    expect(painted(p, '#auditNext'), 'the Next button is not painted').toBe(true);
  });

  it('asks the server with an offset at all', async () => {
    const p = await boot();
    expect(p.asked[0]).toContain('offset=0');
    expect(p.asked[0]).toContain('limit=100');
  });

  it('numbers the page from what was served', async () => {
    const p = await boot();
    expect(p.text('#auditFoot')).toContain('Показано 1–100');
  });

  it('states its rule, and states that the log is not counted', async () => {
    const foot = (await boot()).text('#auditFoot');
    expect(foot).toContain('Сначала новые');
    expect(foot).toContain('сервер их не считает');
  });

  it('prints no invented total anywhere on the screen', async () => {
    // The one number this screen must never grow. «из 250» would be a count
    // nobody performed; «из N» inside the explanation is the explanation.
    const p = await boot();
    expect(p.text('#auditFoot'), 'the footer grew a count').not.toMatch(/из\s+\d/);
  });
});

describe('the pager reaches the older half of the log', () => {
  it('cannot go back from the first page, and can go forward', async () => {
    const p = await boot();
    expect((p.el('#auditPrev') as HTMLButtonElement).disabled).toBe(true);
    expect((p.el('#auditNext') as HTMLButtonElement).disabled).toBe(false);
    expect(p.text('#auditFoot')).toContain('есть ещё');
  });

  it('fetches the next hundred and draws them', async () => {
    const p = await boot();
    // Page one holds 1–100 and not 101.
    expect(p.text('#auditBody')).toContain('Запись 100');
    expect(p.text('#auditBody')).not.toContain('Запись 101');

    await p.click('#auditNext');
    expect(p.asked.some((u) => u.includes('offset=100'))).toBe(true);
    expect(p.text('#auditFoot')).toContain('Показано 101–200');
    // The rows that did not exist to a reviewer before.
    expect(p.text('#auditBody')).toContain('Запись 101');
    expect(p.text('#auditBody')).not.toContain('Запись 100 ');
  });

  it('goes back, and lands on the page it came from', async () => {
    const p = await boot();
    await p.click('#auditNext');
    await p.click('#auditPrev');
    expect(p.text('#auditFoot')).toContain('Показано 1–100');
    expect(p.text('#auditBody')).toContain('Запись 1');
    expect((p.el('#auditPrev') as HTMLButtonElement).disabled).toBe(true);
  });

  it('stops at the end instead of serving an empty page', async () => {
    const p = await boot();
    await p.click('#auditNext');
    await p.click('#auditNext'); // 201–250
    expect(p.text('#auditFoot')).toContain('Показано 201–250');
    expect(p.text('#auditFoot')).toContain('это конец журнала');
    expect((p.el('#auditNext') as HTMLButtonElement).disabled).toBe(true);
  });

  it('the rows on page two are still readable Russian, not raw keys', async () => {
    // 1e25233 made the actions legible; this is the other half of the same
    // job, and it would be pointless if page two printed `view_user_detail`.
    const p = await boot();
    await p.click('#auditNext');
    const body = p.text('#auditBody');
    expect(body).toContain('Открыл(а) карточку пациентки');
    expect(body).not.toContain('view_user_detail');
    expect(body).toContain('проверка доступа');
  });
});

describe('a failed read is not an empty log', () => {
  it('says the journal did not load, in the table and in the footer', async () => {
    const p = await boot({ fail: true });
    expect(p.text('#auditBody')).toContain('Не удалось загрузить журнал');
    const foot = p.text('#auditFoot');
    expect(foot).toContain('сбой чтения');
    expect(foot).toContain('Показано —');
    // No page numbers over rows nobody received.
    expect(foot).not.toContain('Показано 1');
    expect(foot).not.toContain('это конец журнала');
  });
});
