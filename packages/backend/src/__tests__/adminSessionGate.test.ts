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
  /** Request bodies, for asserting what was actually sent. */
  const bodies: Array<{ path: string; body: unknown }> = [];
  /** Every GET, for watching the poll loop. */
  const gets: string[] = [];
  /**
   * Every repeating timer the panel starts, with its callback.
   *
   * Captured because the live poll runs every 20 seconds and no test is going
   * to wait that long: a test that merely lets 200ms pass proves nothing about
   * whether a tick was skipped, and passed with the guard removed.
   */
  const intervals: Array<{ ms: number; fn: () => void }> = [];
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
      const realSetInterval = window.setInterval.bind(window);
      (window as unknown as { setInterval: unknown }).setInterval = ((fn: () => void, ms: number, ...rest: unknown[]) => {
        intervals.push({ ms, fn });
        return realSetInterval(fn as never, ms, ...(rest as never[]));
      }) as never;

      window.fetch = (async (path: string, init?: RequestInit) => {
        const p = String(path);
        if (!init?.method || init.method === 'GET') gets.push(p);
        if (init?.method && init.method !== 'GET') {
          posts.push(p);
          bodies.push({ path: p, body: init.body ? JSON.parse(String(init.body)) : null });
        }

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
  return { window, posts, bodies, gets, intervals, reloaded, jsdomErrors };
}

const visible = (w: JSDOM['window'], id: string) =>
  !(w.document.getElementById(id) as HTMLElement).hidden;


describe('the panel says which product it belongs to', () => {
  it('shows Ana-Bala in the sidebar, not the old brand', async () => {
    // The sidebar read "Umay" with a U for a logo, next to a login card that
    // already said Ana-Bala. The product was renamed; the back office was not.
    const { window } = await boot();
    const brand = window.document.querySelector('.brand')!;
    expect(brand.textContent).toContain('Ana-Bala');
    expect(brand.textContent, 'the old brand is still in the sidebar').not.toContain('Umay');
  });
});

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

describe('signing in the way a person does', () => {
  it('clicking Войти sends the credentials', async () => {
    // Every other test in this file dispatches a synthetic submit event, which
    // is NOT the path a person takes. A real click runs the browser's own
    // constraint validation first, and a form that fails it never fires submit
    // at all — no request, no error, nothing in any server log. That is
    // indistinguishable from "the button does nothing", which is exactly how
    // it was reported.
    const { window, posts } = await boot({ signedOut: true });
    (window.document.getElementById('loginPhone') as HTMLInputElement).value = '+77073452244';
    (window.document.getElementById('loginPass') as HTMLInputElement).value = 'a-password';

    (window.document.getElementById('loginBtn') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true, cancelable: true }));
    await new Promise((r) => setTimeout(r, 250));

    expect(posts.some((p) => p.includes('/admin/login')), 'the button sent nothing').toBe(true);
  });

  it('always says something, even with the fields empty', async () => {
    // The failure mode this closes: with the browser's own validation on, a
    // click that fails it fires no submit event at all. No request, no
    // message, nothing in any log — and the person reporting it can only say
    // "it does not log in", which is true and unfalsifiable.
    const { window, posts } = await boot({ signedOut: true });
    (window.document.getElementById('loginBtn') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true, cancelable: true }));
    await new Promise((r) => setTimeout(r, 150));

    expect(posts.some((p) => p.includes('/admin/login')), 'empty fields should not be sent').toBe(false);
    expect(window.document.getElementById('loginErr')!.textContent, 'the button did nothing visible')
      .toMatch(/введите/i);
  });

  it('trims the phone but never the password', async () => {
    // A pasted number often carries a space. A password might legitimately end
    // with one, and eating it silently would make this form disagree with
    // every other place the same password is entered.
    const { window, posts, bodies } = await boot({ signedOut: true });
    (window.document.getElementById('loginPhone') as HTMLInputElement).value = '  +7 707 345 22 44 ';
    (window.document.getElementById('loginPass') as HTMLInputElement).value = 'secret ';
    (window.document.getElementById('loginBtn') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true, cancelable: true }));
    await new Promise((r) => setTimeout(r, 200));

    expect(posts.some((p) => p.includes('/admin/login'))).toBe(true);
    const sent = bodies.find((b) => b.path.includes('/admin/login'))!.body as { phone: string; password: string };
    expect(sent.phone).toBe('+7 707 345 22 44');
    expect(sent.password).toBe('secret ');
  });

  it('the reveal button never submits the form', async () => {
    // A <button> inside a <form> defaults to type="submit". If the eye were
    // left as one, looking at your password would post the form.
    const { window, posts } = await boot({ signedOut: true });
    expect((window.document.getElementById('loginEye') as HTMLButtonElement).type).toBe('button');

    (window.document.getElementById('loginEye') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true, cancelable: true }));
    await new Promise((r) => setTimeout(r, 150));
    expect(posts.some((p) => p.includes('/admin/login')), 'the eye submitted the form').toBe(false);
  });
});

describe('the sign-in form lets you see what you typed', () => {
  // From an hour lost to exactly this: the account was fine and the password
  // was right, but the field held something else — a stale autofill, or Latin
  // letters typed with the Russian layout active. A masked field renders both
  // as the same row of dots, and "Неверный пароль" is all the server can say.
  it('reveals the password on demand, and hides it again', async () => {
    const { window } = await boot({ signedOut: true });
    const pass = window.document.getElementById('loginPass') as HTMLInputElement;
    const eye = window.document.getElementById('loginEye') as HTMLButtonElement;
    expect(eye, 'no way to check what is in the field').not.toBeNull();
    expect(pass.type).toBe('password');

    eye.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    expect(pass.type, 'the password should be readable').toBe('text');
    expect(eye.getAttribute('aria-pressed')).toBe('true');

    eye.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    expect(pass.type, 'and hideable again').toBe('password');
    expect(eye.getAttribute('aria-pressed')).toBe('false');
  });

  it('warns about Caps Lock while typing, and stops when the field is left', async () => {
    const { window } = await boot({ signedOut: true });
    const pass = window.document.getElementById('loginPass') as HTMLInputElement;
    const hint = window.document.getElementById('capsHint') as HTMLElement;
    expect(hint.hidden).toBe(true);

    const ev = new window.KeyboardEvent('keydown', { bubbles: true, key: 'a' });
    Object.defineProperty(ev, 'getModifierState', { value: () => true });
    pass.dispatchEvent(ev);
    expect(hint.hidden, 'Caps Lock was on and nothing said so').toBe(false);

    pass.dispatchEvent(new window.FocusEvent('blur', { bubbles: true }));
    expect(hint.hidden).toBe(true);
  });
});

describe('the live feed in a background tab', () => {
  /** The panel's live poll — the slow repeating timer, not the "Ns ago" ticker. */
  const liveTicker = (intervals: Array<{ ms: number; fn: () => void }>) => {
    const t = intervals.filter((i) => i.ms >= 10_000).pop();
    // Without this, a renamed or removed timer would leave the tests below
    // asserting nothing at all, quietly.
    expect(t, 'no live poll timer was started — these tests would prove nothing').toBeTruthy();
    return t!;
  };

  const emergencyCalls = (gets: string[]) => gets.filter((p) => p.includes('/admin/emergencies')).length;

  it('skips the tick while the tab is hidden', async () => {
    // liveTick guards this itself. The guard is old and untested, and it is
    // what stops a laptop left open on this page from polling all night —
    // /admin/emergencies is audited, so those polls would also be audit rows.
    //
    // The tick is invoked directly. Waiting for it is not an option at a
    // twenty-second interval, and a test that just lets 200ms pass proves
    // nothing: the first version of this passed with the guard removed.
    const { window, gets, intervals } = await boot();
    const tick = liveTicker(intervals);

    Object.defineProperty(window.document, 'hidden', { configurable: true, get: () => true });
    const before = emergencyCalls(gets);
    tick.fn();
    tick.fn();
    await new Promise((r) => setTimeout(r, 150));

    expect(emergencyCalls(gets), 'a hidden tab kept polling').toBe(before);
  });

  it('polls normally while the tab is in front', async () => {
    // The mirror image, and the thing that stops the fix above from being
    // "switch the live feed off".
    const { window, gets, intervals } = await boot();
    const tick = liveTicker(intervals);

    Object.defineProperty(window.document, 'hidden', { configurable: true, get: () => false });
    const before = emergencyCalls(gets);
    tick.fn();
    await new Promise((r) => setTimeout(r, 150));

    expect(emergencyCalls(gets), 'a visible tab stopped polling').toBeGreaterThan(before);
  });

  it('refreshes the moment you come back to it', async () => {
    // Pausing must not mean stale numbers on the screen you just returned to.
    const { window, gets } = await boot();
    Object.defineProperty(window.document, 'hidden', { configurable: true, get: () => false });

    const before = emergencyCalls(gets);
    window.document.dispatchEvent(new window.Event('visibilitychange'));
    await new Promise((r) => setTimeout(r, 200));

    expect(emergencyCalls(gets), 'coming back should refresh immediately').toBeGreaterThan(before);
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

