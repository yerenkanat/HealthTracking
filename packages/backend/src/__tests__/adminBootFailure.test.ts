/**
 * A panel that cannot boot must SAY so.
 *
 * The panel is one file whose JavaScript draws every screen, so an exception on
 * the way in leaves the shell standing and empty: a white page, with the reason
 * only in a console the operator will never open. That was reported twice as
 * "I deployed and I see nothing", and both times the server was fine — once a
 * stale session, once nothing at all. Twenty minutes went into each before
 * anybody knew which.
 *
 * These pin the recovery, not the cause: whatever breaks, the operator gets
 * words and two buttons.
 */
import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

interface Booted {
  hidden(id: string): boolean;
  text(sel: string): string;
  count(sel: string): number;
  loggedOut: number;
  click(sel: string): Promise<void>;
}

/**
 * Boot the panel signed IN, with the server returning a SHAPE boot() cannot
 * survive.
 *
 * Not a failing request: boot() guards each of its fetches individually, so one
 * endpoint going down costs a card and nothing else — which is right. The
 * unguarded part is the tail, after the data is in: `render()`,
 * `go(viewFromHash())`, `MOCK.emergencies.forEach(...)`, `startLive()`. Handing
 * back `{emergencies: "none"}` makes that forEach a TypeError, which is exactly
 * the class of failure start()'s own comment describes — "a KPI reading a field
 * the server had not sent".
 *
 * `/admin/me` still answers, so start() reveals the shell first. That ordering
 * is what produced the white page: shell up, boot dead, nothing drawn.
 */
async function bootWith(failOn: string): Promise<Booted> {
  const html = readFileSync(PANEL, 'utf8');
  const vc = new VirtualConsole();
  vc.on('jsdomError', () => {});   // the failure is the POINT here
  vc.on('error', () => {});
  let loggedOut = 0;

  const dom = new JSDOM(html, {
    runScripts: 'dangerously', pretendToBeVisual: true,
    url: 'http://localhost/admin', virtualConsole: vc,
    beforeParse(window) {
      window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
        const noop = () => {};
        return new Proxy(
          { canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true });
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 900 });
      window.scrollTo = () => {};
      // jsdom's `location` is non-configurable and its reload() is a no-op, so
      // the reload INTENT is not observable here. The logout request is, and
      // the buttons' presence is — those are what this file asserts, rather
      // than a stub of navigation that would only be testing itself.
      window.fetch = (async (path: string, opts?: { method?: string }) => {
        const p = String(path);
        if (p.includes('/admin/logout')) {
          loggedOut++;
          return { ok: true, status: 200, json: async () => ({}) };
        }
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin', displayName: 'Ерен' }) };
        }
        if (p.includes('/admin/stats')) {
          // A real server that just fell over. `api()` throws a plain Error for
          // any non-ok status other than 401/403, which lands in boot()'s catch
          // — the branch that used to be commented «not reachable».
          if (failOn === 'stats500') return { ok: false, status: 500, json: async () => ({}) };
          // Signed in, not allowed here. A different message, but the invented
          // patients must go in this case too.
          if (failOn === 'denied') return { ok: false, status: 403, json: async () => ({}) };
          return { ok: true, status: 200, json: async () => ({ activeUsers: 1, devicesOnline: 0, alertsToday: 0, ingestLastHour: 0 }) };
        }
        if (p.includes('/admin/emergencies')) {
          // The poisoned shape, when the caller asked for it: a row that is not
          // a row, which renderFeeds' sort turns into a TypeError inside the
          // unguarded tail of boot().
          //
          // It USED to be `{emergencies: 'none'}` — a string where an array
          // belongs. That no longer breaks anything: boot() checks
          // Array.isArray now and treats a shape it does not understand as a
          // feed that failed to load, which is a better outcome than the
          // failure screen and is asserted in adminEmergencyFrame19Render.
          // The screen this file is about still has to work, so the poison
          // moved one level in rather than being deleted with the bug.
          return {
            ok: true, status: 200,
            json: async () => (failOn === 'shape' ? { emergencies: [null] } : { emergencies: [] }),
          };
        }
        return { ok: true, status: 200, json: async () => ({}) };
      }) as never;
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
    },
  });
  const { window } = dom;
  const settle = () => new Promise((r) => setTimeout(r, 200));
  await settle();
  const d = window.document;
  return {
    hidden: (id) => !!d.getElementById(id)?.hasAttribute('hidden'),
    text: (sel) => (d.querySelector(sel)?.textContent ?? '').replace(/\s+/g, ' ').trim(),
    count: (sel) => d.querySelectorAll(sel).length,
    get loggedOut() { return loggedOut; },
    click: async (sel) => {
      d.querySelector(sel)!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
      await settle();
    },
  };
}

describe('when boot throws', () => {
  let page: Booted;
  beforeAll(async () => { page = await bootWith('shape'); });

  it('shows the failure instead of an empty shell', () => {
    // The whole point. Before this, the shell was revealed and left blank.
    expect(page.hidden('bootFail')).toBe(false);
    expect(page.hidden('appShell')).toBe(true);
  });

  it('does not leave the sign-in form up as well', () => {
    // Two screens at once is its own kind of broken.
    expect(page.hidden('loginGate')).toBe(true);
  });

  it('names the ACTUAL error, not «что-то пошло не так»', () => {
    // A generic message is what makes a support call take twenty minutes
    // instead of two. The engine's own words — here «Cannot read properties of
    // null (reading 'severity')» — are what a developer needs on the phone.
    const msg = page.text('#bootFailMsg');
    expect(msg).toMatch(/Cannot read|not a function|undefined|null/i);
    expect(msg).not.toMatch(/что-то пошло не так/i);
    expect(msg.length).toBeGreaterThan(10);
  });

  it('says the data is safe, because that is the first thing she will fear', () => {
    expect(page.text('#bootFail')).toContain('Данные не потеряны');
  });

  it('offers the two things that actually fix it', async () => {
    expect(page.count('#bootRetry')).toBe(1);
    expect(page.count('#bootSignOut')).toBe(1);

    // Signing out clears the session cookie, which is the commonest cause of a
    // panel that authenticates and then cannot boot.
    await page.click('#bootSignOut');
    expect(page.loggedOut).toBe(1);
  });
});

describe('when boot succeeds', () => {
  it('the failure screen stays out of the way', async () => {
    const page = await bootWith('healthy');
    expect(page.hidden('bootFail')).toBe(true);
    expect(page.hidden('appShell')).toBe(false);
  });
});

/**
 * A server that answered 500 must not become five invented patients.
 *
 * MOCK.emergencies carries «Aigerim S. · BP 162/108 · 2m ago», «Madina K. ·
 * SpO₂ 88% during sleep» and three more — names, triage codes, clinical
 * readings, each with acknowledgedAt:null so each draws a live «Подтвердить»
 * that POSTs to the real server. They exist so the panel can be demonstrated
 * without a backend, which is fair.
 *
 * boot()'s catch had an AccessDenied branch and then, for everything else, a
 * comment reading «not reachable — keep demo data» followed by render(). It WAS
 * reachable: api() throws a plain Error for every non-ok status that is not
 * 401/403. So a ninety-second database hiccup painted three medical crises with
 * working buttons, and the only contradiction was a pill in the header that
 * anyone working the feed has learned to ignore.
 *
 * On the one screen where "nothing is wrong" has to be trustworthy, the failure
 * state must be empty and must say why it is empty.
 */
describe('when the server fails on the way in', () => {
  it('paints no invented patients', async () => {
    const page = await bootWith('stats500');
    // NOT page.text('body') — jsdom's textContent includes <script> source, so
    // it matches the MOCK literal itself and would fail no matter what the
    // panel drew. Assert on the containers an operator actually looks at.
    const body = page.text('#feedFull') + ' ' + page.text('#kpis');
    for (const name of ['Aigerim S.', 'Madina K.', 'Zarina B.', 'Dana T.', 'Aruzhan M.']) {
      expect(body, `a fabricated patient survived a 500: ${name}`).not.toContain(name);
    }
    // The readings are the dangerous half — a name alone is embarrassing, a
    // name with a blood pressure beside it is clinical.
    expect(body).not.toContain('162/108');
    expect(body).not.toContain('88%');
    // And nothing to acknowledge, because there is nothing there.
    expect(page.count('#feedFull [data-ack]')).toBe(0);
  });

  it('says the feed is empty because it did not load, not because all is well', async () => {
    const page = await bootWith('stats500');
    const kpis = page.text('#kpis');
    expect(kpis).toContain('не смогла загрузиться');
    // The distinction the operator actually needs, in words.
    expect(kpis).toContain('НЕ значит');
    expect(page.count('#statsRetry')).toBe(1);
  });

  it('does not claim to be showing demo data, and does not claim access was denied', async () => {
    const page = await bootWith('stats500');
    // «Демо-данные» would be a lie — nobody chose a demo, a request failed.
    // «Нет доступа» would send the operator to ask for permissions she has.
    expect(page.text('#modePill')).toBe('Нет связи');
  });

  it('still empties the patients when access is refused', async () => {
    // 403 already had a message, and still fell through to render() with the
    // five people intact — the card said «всё, что показано ниже,
    // демонстрационное» while a clinician looked at invented blood pressures.
    const page = await bootWith('denied');
    expect(page.text('#feedFull')).not.toContain('Aigerim S.');
    expect(page.text('#modePill')).toBe('Нет доступа');
  });
});
