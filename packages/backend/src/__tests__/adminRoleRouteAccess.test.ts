/**
 * A tab a role can SEE must have a data source that role can READ — and where
 * it cannot, the screen must say «отказано», never «сервер не ответил».
 *
 * Two live defects motivated this, and neither was catchable by the tests that
 * existed:
 *
 *  1. «Сводка» is the landing view and carries no `data-cap`, so all eight
 *     roles land on it. It calls /admin/dashboard, which is requireCap
 *     'finance' — held only by owner and admin. Six of eight roles therefore
 *     began every shift being told «бэкенд не ответил на /admin/dashboard» by
 *     a backend that had answered in under ten milliseconds. A person who
 *     cannot tell a refusal from an outage escalates the wrong one.
 *  2. «Финансы» was drawn with `data-cap="stock"` while GET /admin/finance
 *     requires 'finance'. A warehouse hand could see the tab, opened it, and
 *     read a raw «403 {…}» pasted into a sentence about loading.
 *
 * adminRoleUiRender.test.ts checks that every `data-cap` token is a REAL
 * capability — `stock` is real, so defect 2 passed it — and which tabs are
 * visible per role. Neither question is "can the role read what the tab shows".
 *
 * ---------------------------------------------------------------------------
 * HOW IT OBSERVES, and why it was rewritten
 *
 * The first version answered every request from a hand-written fixture table,
 * `{}` for anything absent, and decided a view was "done" after a fixed 250 ms.
 * Both were wrong, and they failed together:
 *
 *   · `{}` is not a shape any route returns. Renders that read `.retention.d7`
 *     or `.map` threw TypeErrors that had nothing to do with authorization, and
 *     those rejections were then swallowed by a handler this file installed and
 *     removed on the same timer — so under full-suite load they escaped to
 *     vitest ("80 unhandled errors") and the run's verdict changed between
 *     identical runs.
 *   · 250 ms is a guess about someone else's machine. Under parallel load a
 *     role took seconds, so the window closed mid-render and the assertions
 *     read a half-drawn screen.
 *
 * Now: every /admin request is served by the REAL server — `buildServer` over a
 * real memory repository, with the real `requireCap`, so a 403 here is the
 * production guard refusing, not a table in this file saying it would. And the
 * harness waits for the requests it has counted to settle, then for the panel
 * to stop issuing new ones, with a bound that FAILS rather than proceeds. No
 * assertion depends on elapsed milliseconds.
 *
 * The rejection channel is now a subject, not plumbing: the handler stays
 * installed for the whole role, and its contents are asserted empty.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import { ROLE_CAPS, STAFF_ROLES, type Capability, type StaffRole } from '../auth/capabilities.js';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');
const ROUTE_FILES = ['admin.ts', 'entitlements.ts', 'inventory.ts', 'staffAdmin.ts']
  .map((f) => resolve(here, '../routes', f));

// ---------------------------------------------------------------------------
// 1. What each /admin route demands, read off the handlers.
//
// The server enforces this for real below; the parse is kept because two of
// this file's rules need to know WHICH capability a refused url wanted, and
// because a parse that disagrees with the live server is itself a finding —
// see «the parse agrees with the running server» at the end.
// ---------------------------------------------------------------------------

interface RouteGuard {
  method: string;
  /** As declared, params included: `/admin/users/:id/health`. */
  path: string;
  cap: Capability | null;
  staffOnly: boolean;
}

function parseRouteGuards(): RouteGuard[] {
  const out: RouteGuard[] = [];
  for (const file of ROUTE_FILES) {
    const src = readFileSync(file, 'utf8');
    const decl = /app\.(get|post|put|patch|delete)\(\s*'(\/admin\/[^']*)'/g;
    const marks: Array<{ m: string; p: string; i: number }> = [];
    let mm: RegExpExecArray | null;
    while ((mm = decl.exec(src)) !== null) marks.push({ m: mm[1], p: mm[2], i: mm.index });
    marks.forEach((mk, idx) => {
      // Up to the NEXT route declaration, so a handler without a guard cannot
      // borrow its neighbour's.
      const slice = src.slice(mk.i, idx + 1 < marks.length ? marks[idx + 1].i : src.length);
      const cap = /requireCap\(\s*req,\s*reply,\s*'([a-z]+)'/.exec(slice);
      out.push({
        method: mk.m.toUpperCase(),
        path: mk.p,
        cap: cap ? (cap[1] as Capability) : null,
        staffOnly: !cap && /require(Staff|Admin)\(/.test(slice),
      });
    });
  }
  return out;
}

const ROUTES = parseRouteGuards();

/** Longest, least-wildcard match for a concrete URL. */
function guardFor(method: string, url: string): RouteGuard | null {
  const path = url.split('?')[0];
  const segs = path.split('/').filter(Boolean);
  let best: RouteGuard | null = null;
  let bestParams = Infinity;
  for (const r of ROUTES) {
    if (r.method !== method.toUpperCase()) continue;
    const rs = r.path.split('/').filter(Boolean);
    if (rs.length !== segs.length) continue;
    let params = 0;
    let ok = true;
    for (let i = 0; i < rs.length; i++) {
      if (rs[i].startsWith(':')) { params++; continue; }
      if (rs[i] !== segs[i]) { ok = false; break; }
    }
    if (ok && params < bestParams) { best = r; bestParams = params; }
  }
  return best;
}

const capsOfRole = (role: StaffRole): readonly Capability[] => ROLE_CAPS[role];

// ---------------------------------------------------------------------------
// 2. The panel, booted as one role, against the real routes.
// ---------------------------------------------------------------------------

/**
 * Fetches the panel itself declares optional — `api(url)` … `.catch(` with no
 * other api() call in between, the shape it uses for a nice-to-have (product
 * «охват», course progress). A refusal there is allowed to leave no trace on
 * the screen; the card that would have used it says why when it is opened.
 *
 * Derived from the panel source rather than listed here, so it cannot become a
 * place to bury a real dependency: adding a url to it means writing a swallowed
 * catch, in the file, where a reviewer sees it.
 */
function parseOptionalUrls(html: string): Set<string> {
  const out = new Set<string>();
  const re = /api\(\s*[`"']([^`"']+)[`"']((?:(?!api\()[\s\S]){0,300}?)\.catch\(/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(html)) !== null) out.add(m[1]);
  return out;
}
const PANEL_HTML = readFileSync(PANEL, 'utf8');
const OPTIONAL = parseOptionalUrls(PANEL_HTML);
const isOptional = (call: string) => {
  const url = call.split(' ')[1]?.split('?')[0] ?? '';
  return OPTIONAL.has(url);
};

/** Text a person can actually read: hidden subtrees do not count. */
function visibleText(el: Element): string {
  let out = '';
  for (const node of Array.from(el.childNodes)) {
    if (node.nodeType === 3) { out += node.textContent ?? ''; continue; }
    if (node.nodeType !== 1) continue;
    const e = node as HTMLElement;
    if (e.hasAttribute('hidden')) continue;
    if ((e.getAttribute('style') ?? '').includes('display:none')) continue;
    out += ' ' + visibleText(e);
  }
  return out.replace(/\s+/g, ' ').trim();
}

/** The real backend, answering as this role. */
function serverAs(role: StaffRole): FastifyInstance {
  return buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => null,
      // The identity is stubbed and the AUTHORIZATION is not: requireCap reads
      // this role and asks the real `can()`. Sessions are a different file's
      // subject (adminSessionGate), and needing one here would only add a
      // cookie to every assertion about capabilities.
      authAdmin: async () => ({ staffId: 's1', role }),
    },
    { logger: false },
  );
}

interface Booted {
  window: Window & typeof globalThis;
  errors: string[];
  rejections: string[];
  refusals: string[];
  /** Calls the role WAS allowed to make — a view with none of these and some
   *  refusals is a tab it can open and cannot use. */
  allowed: string[];
  /** Wait until every issued request has settled and no new one appears. */
  quiet: () => Promise<void>;
  clearCalls: () => void;
  close: () => Promise<void>;
}

/**
 * Boot, and hand back a page that knows when it is finished.
 *
 * `quiet()` is the whole point. It waits on two things it can observe — the
 * number of requests still in flight, and whether the panel has issued a NEW
 * one since the last turn (a render chains its next fetch off the previous
 * answer, so "none in flight" alone is not "done") — and it throws when it
 * runs out of turns rather than returning a half-drawn screen as a verdict.
 */
async function bootAs(role: StaffRole, latencyMs = 0): Promise<Booted> {
  const app = serverAs(role);
  await app.ready();

  const errors: string[] = [];
  const rejections: string[] = [];
  const refusals: string[] = [];
  const allowed: string[] = [];
  let inFlight = 0;
  let issued = 0;

  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  const onRejection = (r: unknown) => rejections.push(String(r));
  process.on('unhandledRejection', onRejection);

  const dom = new JSDOM(PANEL_HTML, {
    runScripts: 'dangerously', pretendToBeVisual: true, url: 'http://localhost/admin/ui',
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
      window.fetch = (async (path: string, opts?: { method?: string; body?: string; headers?: Record<string, string> }) => {
        const url = String(path);
        const method = (opts?.method ?? 'GET').toUpperCase();
        issued++;
        inFlight++;
        try {
          // Stands in for a loaded machine. A real answer under a full parallel
          // suite takes tens of milliseconds; on an idle box inject returns in
          // one turn, which is why a fixed window looked fine here and changed
          // the verdict on the runner. See «the verdict does not depend on how
          // fast the machine is» below.
          if (latencyMs) await new Promise((r) => setTimeout(r, latencyMs));
          // The one stub. /admin/me resolves a session cookie, which this file
          // does not have and does not need: it is the panel's "who am I", and
          // the role it answers with is the role the server above enforces.
          if (url.includes('/admin/me')) {
            return { ok: true, status: 200, text: async () => '', json: async () => ({ staffId: 's1', role, displayName: 'Тест' }) };
          }
          const res = await app.inject({
            method: method as 'GET', url,
            ...(opts?.body ? { payload: opts.body } : {}),
            headers: { 'content-type': 'application/json', ...(opts?.headers ?? {}) },
          });
          const call = `${method} ${url}`;
          if (res.statusCode === 403) refusals.push(call); else allowed.push(call);
          return {
            ok: res.statusCode < 400,
            status: res.statusCode,
            text: async () => res.body,
            json: async () => { try { return JSON.parse(res.body || '{}'); } catch { return {}; } },
          };
        } finally {
          inFlight--;
        }
      }) as never;
    },
  });

  const { window } = dom;
  const turn = () => new Promise((r) => setTimeout(r, 0));
  /** Bounded by observed progress, never by a deadline. */
  const quiet = async () => {
    const MAX_TURNS = 3000;      // generous; only a livelock can reach it
    const CALM_TURNS = 5;        // consecutive turns with nothing in flight and nothing new
    let calm = 0;
    let lastIssued = -1;
    for (let i = 0; i < MAX_TURNS; i++) {
      await turn();
      if (inFlight === 0 && issued === lastIssued) calm++; else calm = 0;
      lastIssued = issued;
      if (calm >= CALM_TURNS) return;
    }
    throw new Error(
      `panel never went quiet as ${role}: ${inFlight} request(s) still in flight after ${MAX_TURNS} turns`,
    );
  };

  await quiet();
  return {
    window: window as unknown as Window & typeof globalThis,
    errors, rejections, refusals, allowed, quiet,
    clearCalls: () => { refusals.length = 0; allowed.length = 0; },
    close: async () => {
      process.off('unhandledRejection', onRejection);
      window.close();
      await app.close();
    },
  };
}

/** Wording that asserts an outage, and the raw status a person cannot act on. */
const OUTAGE = /бэкенд не ответил|нет связи с сервером|проверьте соединение|сервер не ответил/i;
const RAW_STATUS = /(^|\D)40[13](\D|$)/;
const REFUSAL = /нет доступа|нет прав|отказ|доступ выдаёт|у вашей роли/i;

// ---------------------------------------------------------------------------

describe('the derivation itself', () => {
  it('resolved real guards — an empty parse would pass every assertion below', () => {
    expect(ROUTES.length).toBeGreaterThan(60);
    const cap = (m: string, p: string) => {
      const g = guardFor(m, p);
      return g ? (g.cap ?? (g.staffOnly ? 'staff' : 'none')) : 'unresolved';
    };
    // The two screens this test exists for, plus one of each other kind.
    expect(cap('GET', '/admin/dashboard')).toBe('finance');
    expect(cap('GET', '/admin/finance')).toBe('finance');
    expect(cap('GET', '/admin/safety')).toBe('health');
    expect(cap('GET', '/admin/emergencies')).toBe('emergencies');
    expect(cap('GET', '/admin/shop/orders')).toBe('orders');
    expect(cap('GET', '/admin/inventory')).toBe('stock');
    expect(cap('GET', '/admin/stats')).toBe('staff');
    // Params resolve rather than falling through to a wildcard-free sibling.
    expect(cap('GET', '/admin/users/u1/health')).toBe('health');
    // And the matrix is the real one.
    expect(capsOfRole('warehouse')).toEqual(['stock']);
    expect(capsOfRole('operator')).not.toContain('finance');
    // The optional-fetch escape hatch must stay an escape hatch: it exists,
    // and a regex that swallowed the whole panel would turn this file green
    // while asserting nothing at all.
    expect([...OPTIONAL].sort()).toEqual(['/admin/children/stats', '/admin/course/progress']);
  });
});

/**
 * Which views ask the server for anything at all — measured, as the owner.
 *
 * This is the guard on the guard. Every rule below is written «if this view was
 * refused something, then…», so a harness that reads the screen before the
 * request has landed records no refusals, skips every rule and reports nine
 * green tests having asserted nothing. That is not a hypothetical: with the
 * completion-wait replaced by a 1 ms sleep this file passed in 9 s instead of
 * 37, measuring nothing.
 *
 * The owner holds every capability, so it exercises every loader, and a loader
 * does not branch on role — so a view that fetches for the owner must fetch for
 * anyone who can open it. If the observation channel breaks, this set collapses
 * and the assertion under it fails loudly instead of the file going quietly
 * green.
 */
const FETCHING_VIEWS = new Map<string, Set<Capability>>();

beforeAll(async () => {
  const b = await bootAs('owner');
  const record = (view: string, calls: string[]) => {
    if (!calls.length) return;
    const need = FETCHING_VIEWS.get(view) ?? new Set<Capability>();
    for (const call of calls) {
      const [m, u] = call.split(' ');
      const cap = guardFor(m, u)?.cap;
      if (cap) need.add(cap);
    }
    FETCHING_VIEWS.set(view, need);
  };
  try {
    const doc = b.window.document;
    const landing = doc.querySelector('section.view.active') as HTMLElement | null;
    if (landing) record(landing.id, [...b.allowed, ...b.refusals]);
    for (const tab of Array.from(doc.querySelectorAll<HTMLElement>('.nav[data-view]')).filter((e) => !e.hidden)) {
      const view = tab.dataset.view!;
      if (landing && view === landing.id) continue;
      b.clearCalls();
      tab.dispatchEvent(new b.window.MouseEvent('click', { bubbles: true }));
      await b.quiet();
      record(view, [...b.allowed, ...b.refusals]);
    }
  } finally {
    await b.close();
  }
}, 120_000);

/** What this file saw, per view — the thing every rule below is computed from. */
async function observe(role: StaffRole, latencyMs: number): Promise<Map<string, string>> {
  const b = await bootAs(role, latencyMs);
  const seen = new Map<string, string>();
  try {
    const doc = b.window.document;
    const landing = doc.querySelector('section.view.active') as HTMLElement | null;
    const snap = () => [...b.refusals].sort().join('|') + ' // ' + [...b.allowed].sort().join('|');
    if (landing) seen.set(landing.id, snap());
    for (const tab of Array.from(doc.querySelectorAll<HTMLElement>('.nav[data-view]')).filter((e) => !e.hidden)) {
      const view = tab.dataset.view!;
      if (landing && view === landing.id) continue;
      b.clearCalls();
      tab.dispatchEvent(new b.window.MouseEvent('click', { bubbles: true }));
      await b.quiet();
      seen.set(view, snap());
    }
  } finally {
    await b.close();
  }
  return seen;
}

describe('the harness measures completion, not elapsed time', () => {
  /**
   * The same role, twice, with the transport made forty times slower.
   *
   * This is the property the file was rewritten for. It used to drive the panel
   * and then read the screen after a flat 250 ms; on an idle machine every
   * request had landed and it passed, and under a full parallel suite the
   * window closed mid-render, so the same tree produced «1 failed» and «165
   * passed» on consecutive runs. A test that guards an authorization boundary
   * cannot have a verdict that depends on what else the machine is doing.
   *
   * Latency is an input here rather than a hope: 40 ms per request is what a
   * loaded box does, and every observation must come out identical. Reinstate
   * any fixed wait and this fails — the slow run records fewer calls per view,
   * or none.
   */
  it('the verdict does not depend on how fast the machine is', async () => {
    const [fast, slow] = [await observe('seller', 0), await observe('seller', 40)];
    expect([...slow.keys()]).toEqual([...fast.keys()]);
    for (const [view, calls] of fast) {
      expect(slow.get(view), `«${view}» was observed differently when the server was slower`).toBe(calls);
    }
    // Non-vacuity: this role really does make requests, so an equality of two
    // empty maps cannot be what passed.
    expect([...fast.values()].filter((v) => v.replace(' // ', '').length > 0).length).toBeGreaterThan(5);
  }, 180_000);
});

describe('a visible tab must be readable by the role that sees it', () => {
  it('the observation channel works at all', () => {
    // Measured at 17 on the tree this was written against. The floor is well
    // under it so that deleting a tab does not fail this, and far above what a
    // truncated window produces (1 — only the landing view, whose requests go
    // out during boot).
    expect(FETCHING_VIEWS.size,
      'almost no view was seen to fetch: the harness is reading the screen before the panel has finished, ' +
      'so every rule below is being skipped rather than passed')
      .toBeGreaterThan(10);
    expect([...FETCHING_VIEWS.keys()]).toContain('overview');
    // …and the landing view really does depend on money, which is finding 1.
    expect([...(FETCHING_VIEWS.get('overview') ?? [])]).toContain('finance');
  });

  it.each(STAFF_ROLES)('%s', async (role) => {
    const b = await bootAs(role);
    try {
      expect(b.errors, `${role}: script error`).toEqual([]);

      const doc = b.window.document;
      const tabs = Array.from(doc.querySelectorAll<HTMLElement>('.nav[data-view]'))
        .filter((el) => !el.hidden);
      expect(tabs.length, `${role}: no tab at all is visible`).toBeGreaterThan(0);

      /**
       * A refusal the SCREEN already accounts for.
       *
       * «Экстренные» is `emergencies` and carries two `health` cards inside it
       * — the SOS card and the SOS/zone table — which applyCaps hides from an
       * operator. /admin/safety being refused for her is that design working,
       * not a mismatch, and the section is not empty: the alarm feed is the
       * rest of the screen. Derived from the hidden elements themselves, so a
       * view cannot claim the exemption without actually gating that part.
       */
      const capOfCall = (call: string) => {
        const [m, u] = call.split(' ');
        return guardFor(m, u)?.cap ?? null;
      };
      const unexplained = (section: HTMLElement, calls: string[]) => {
        const hiddenCaps = new Set(
          Array.from(section.querySelectorAll<HTMLElement>('[data-cap]'))
            .filter((e) => e.hidden)
            .map((e) => e.dataset.cap),
        );
        return calls
          .filter((u) => !isOptional(u))
          .filter((u) => { const cap = capOfCall(u); return !(cap && hiddenCaps.has(cap)); });
      };

      const landing = doc.querySelector('section.view.active') as HTMLElement | null;
      const checks: Array<{ view: string; cap: string | null; refused: string[]; allowed: string[]; text: string; observed: number }> = [
        ...(landing
          ? [{
              view: landing.id,
              cap: (doc.querySelector(`.nav[data-view="${landing.id}"]`) as HTMLElement | null)?.dataset.cap ?? null,
              refused: unexplained(landing, b.refusals), allowed: [...b.allowed], text: visibleText(landing),
              observed: b.refusals.length + b.allowed.length,
            }]
          : []),
      ];

      for (const tab of tabs) {
        const view = tab.dataset.view!;
        if (landing && view === landing.id) continue;
        b.clearCalls();
        tab.dispatchEvent(new b.window.MouseEvent('click', { bubbles: true }));
        // Completion, not a deadline: the view is read once the panel has
        // stopped asking for things.
        await b.quiet();
        const section = doc.querySelector(`section#${view}`) as HTMLElement | null;
        if (!section) continue;
        checks.push({
          view, cap: tab.dataset.cap ?? null,
          refused: unexplained(section, b.refusals), allowed: [...b.allowed], text: visibleText(section),
          observed: b.refusals.length + b.allowed.length,
        });
      }

      // Same guard, per role: a view the owner was seen to load must have been
      // seen to load here too. Without this, a window that closes early makes
      // every rule below skip — silently, and only for the role whose renders
      // happened to be slow that run, which is exactly how this file used to
      // give two different verdicts on one tree.
      //
      // Only where the role holds every capability those requests needed: some
      // views decline to ask on purpose. «Персонал» is reachable by everyone
      // because «Мой пароль» lives on it, and its loader hides the roster and
      // sends nothing when `can('staff')` is false — «a 403 here would be a
      // guaranteed one, and reading a colleague list is an audited action».
      // That is the panel being careful, not the harness being early.
      for (const c of checks) {
        const need = FETCHING_VIEWS.get(c.view);
        if (!need) continue;
        if (![...need].every((cap) => capsOfRole(role).includes(cap))) continue;
        expect(c.observed,
          `${role} → ${c.view}: no request was observed, though this view loads for the owner ` +
          `and this role holds everything it needs (${[...need].join(', ') || 'staff-level only'}). ` +
          'The screen was read before the panel asked for anything, so nothing below was checked.')
          .toBeGreaterThan(0);
      }

      // Every 403 the RUNNING server issued was one the matrix says this role
      // lacks — the parse above and the live guard agree about every refusal
      // that actually happened.
      for (const call of checks.flatMap((c) => c.refused)) {
        const cap = capOfCall(call);
        expect(cap, `${role}: ${call} was refused by a route this file could not resolve`).not.toBeNull();
        expect(capsOfRole(role), `${role}: ${call} refused though the matrix grants ${cap}`)
          .not.toContain(cap!);
      }

      for (const c of checks) {
        const refused = c.refused;
        if (!refused.length) continue;
        const where = `${role} → ${c.view} (refused: ${refused.join(', ')})`;

        // A tab whose EVERY data source is refused is a tab this role should
        // not have been shown: its `data-cap` disagrees with the capability its
        // own route asks for. «Финансы» carried data-cap="stock" over a route
        // that requires 'finance' — visible to a warehouse hand, empty for her.
        const usable = c.allowed.filter((u) => !isOptional(u));
        expect(usable.length,
          `${where}: the tab is visible to this role and every one of its data sources is refused — ` +
          `data-cap="${c.cap ?? '(none)'}" does not match what the route requires`)
          .toBeGreaterThan(0);

        // The screen must own up to a refusal…
        expect(c.text, `${where}: a 403 happened and the screen never says so`).toMatch(REFUSAL);
        // …and must not call it an outage, nor paste the status at the reader.
        expect(c.text, `${where}: calls a permission refusal an outage`).not.toMatch(OUTAGE);
        expect(c.text, `${where}: shows a raw status code`).not.toMatch(RAW_STATUS);
      }

      // The channel that used to be plumbing is now a subject. A render that
      // throws leaves the screen half-drawn and every other assertion here
      // still passing — and, escaping to the runner, makes a neighbouring
      // file's verdict depend on this one.
      expect(b.rejections, `${role}: a render rejected while the panel was drawing`).toEqual([]);
    } finally {
      await b.close();
    }
  }, 120_000);
});
