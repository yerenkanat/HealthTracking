/**
 * What the panel does about the session: whose name it shows, how you leave,
 * and what happens when the session dies while someone is using it.
 *
 * The last one is the reason this file exists. A session lasts twelve hours,
 * so it WILL expire mid-shift. Every loader in the panel catches its own
 * failure and renders "нет данных" — which is pixel-identical to a working
 * panel with an empty database. Staff would sit in front of a back office
 * showing no leads, no orders and no devices, and conclude the business had a
 * quiet day.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const ME = { staffId: 'staff-1', role: 'admin', displayName: 'Ерен', phone: '77073452244' };
const STATS = { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 };

interface Opts {
  /** Answer /admin/me, but 401 everything after it — a cookie that just died. */
  expireAfterMe?: boolean;
  /** 401 /admin/me itself — arriving signed out. */
  signedOut?: boolean;
}

async function boot(opts: Opts = {}) {
  const html = readFileSync(PANEL, 'utf8');
  const vc = new VirtualConsole();
  const posts: string[] = [];
  // jsdom will not navigate and will not let Location be stubbed either — it
  // reports the attempt on the virtual console instead, which is the only
  // honest way to observe the reload without shaping the panel around a test.
  const jsdomErrors: string[] = [];
  vc.on('jsdomError', (e: Error) => jsdomErrors.push(e.message));
  const reloaded = () => jsdomErrors.some((m) => /navigation|reload/i.test(m));

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
      (window as unknown as { alert: (m: string) => void }).alert = () => {};

      window.fetch = (async (path: string, init?: RequestInit) => {
        const p = String(path);
        if (init?.method && init.method !== 'GET') posts.push(p);

        if (p.includes('/admin/me')) {
          return opts.signedOut
            ? { ok: false, status: 401, json: async () => ({ error: 'unauthenticated' }) }
            : { ok: true, status: 200, json: async () => ME };
        }
        if (p.includes('/admin/logout')) return { ok: true, status: 200, json: async () => ({ ok: true }) };
        if (opts.expireAfterMe) {
          return { ok: false, status: 401, text: async () => '', json: async () => ({ error: 'unauthenticated' }) };
        }
        const body = p.includes('/admin/stats') ? STATS : {};
        return { ok: true, status: 200, text: async () => '', json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 400));
  return { window, posts, reloaded, jsdomErrors };
}

const visible = (w: JSDOM['window'], id: string) =>
  !(w.document.getElementById(id) as HTMLElement).hidden;

describe('the header names the person who signed in', () => {
  it('shows the name from /admin/me, not a hardcoded one', async () => {
    // It used to read "Dr. Nurlan" — a person who does not exist — beside an
    // audit log recording every action against a made-up staff id.
    const { window } = await boot();
    expect(window.document.getElementById('staffName')!.textContent).toBe('Ерен');
    expect(window.document.getElementById('staffRole')!.textContent).toBe('admin');
    expect(window.document.getElementById('staffAv')!.textContent).toBe('Е');
  });

  it('has a way out', async () => {
    const { window, posts, reloaded } = await boot();
    const btn = window.document.getElementById('logoutBtn') as HTMLButtonElement;
    expect(btn, 'no sign-out control').not.toBeNull();

    btn.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 150));

    expect(posts.some((p) => p.includes('/admin/logout')), 'nothing was sent').toBe(true);
    // Reloading is what clears the loaded rows, charts and selected user from
    // memory. Hiding the panel would leave all of it one Escape key away.
    expect(reloaded(), 'the page must be reloaded, not just hidden').toBe(true);
  });
});

describe('a session that dies mid-shift', () => {
  it('sends the operator back to the form instead of showing empty views', async () => {
    const { window } = await boot({ expireAfterMe: true });

    expect(visible(window, 'loginGate'), 'the login form should be back').toBe(true);
    expect(visible(window, 'appShell'), 'the stale panel should be hidden').toBe(false);
    expect(window.document.getElementById('loginErr')!.textContent)
      .toMatch(/сесси/i);
  });

  it('does not hide the panel over a 401 that never happened', async () => {
    // The mirror image: a healthy session must not be interrupted.
    const { window } = await boot();
    expect(visible(window, 'loginGate')).toBe(false);
    expect(visible(window, 'appShell')).toBe(true);
  });
});

describe('arriving signed out', () => {
  it('opens on the form with no name in the header', async () => {
    const { window } = await boot({ signedOut: true });
    expect(visible(window, 'loginGate')).toBe(true);
    expect(visible(window, 'appShell')).toBe(false);
    expect(window.document.getElementById('staffName')!.textContent).not.toMatch(/Nurlan/);
  });
});

describe('a broken dashboard is not a sign-in problem', () => {
  it('stays on the panel when a KPI payload is incomplete', async () => {
    // Found by this file: /admin/bi answering without `devices` threw inside
    // render(), start() caught it alongside the sign-in check, and the whole
    // panel was replaced by a login form saying "Нет связи с сервером". Signing
    // in again cannot fix a rendering bug, and the real error went unlogged.
    //
    // The stub here returns {} for /admin/bi, which is exactly that shape.
    const { window } = await boot();

    expect(visible(window, 'loginGate'), 'a render failure must not demand a password').toBe(false);
    expect(visible(window, 'appShell')).toBe(true);
    // And the tiles still say something rather than staying empty.
    expect(window.document.getElementById('kpis')!.textContent).toMatch(/Устройств онлайн/);
  });
});
