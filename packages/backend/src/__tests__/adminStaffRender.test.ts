/**
 * The Персонал tab, rendered.
 *
 * The routes are covered by staffAdmin.test.ts. This is about the half that
 * cannot be tested from the server: whether the roster actually draws, whether
 * a clinician gets an explanation instead of an empty table, and whether a
 * refused change is reported rather than left on screen looking saved.
 *
 * ---------------------------------------------------------------------------
 * WAITING
 *
 * This file used to boot, sleep 200 ms, click, sleep 300 ms, and read the DOM,
 * with a further 200–250 ms after every action — eleven fixed waits deciding
 * their verdict on elapsed wall-clock rather than on the work being finished.
 * Under a loaded pool those windows close mid-render, which is how the same
 * tree gave two different answers on consecutive runs.
 *
 * Every one of them is now `settle.quiet()`: it returns when no request is in
 * flight, none has been issued for several consecutive turns, and the page has
 * no timer outstanding — and it THROWS rather than hand a half-drawn screen to
 * an assertion. See helpers/panelSettle.ts.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle, type PanelRequestInit } from './helpers/panelSettle';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const ME = { staffId: 'staff-1', role: 'admin', displayName: 'Ерен', phone: '77073452244' };
const ROSTER = {
  me: 'staff-1',
  staff: [
    { id: 'staff-1', phone: '77073452244', role: 'admin', displayName: 'Ерен', disabled: false, createdAt: '2026-08-01T10:00:00Z', lastLoginAt: '2026-08-04T09:00:00Z' },
    { id: 'staff-2', phone: '77011112233', role: 'support', displayName: 'Айгерім', disabled: false, createdAt: '2026-08-02T10:00:00Z', lastLoginAt: null },
    { id: 'staff-3', phone: '77019998877', role: 'clinician', displayName: 'Мадина', disabled: true, createdAt: '2026-08-03T10:00:00Z', lastLoginAt: '2026-08-03T12:00:00Z' },
  ],
};

interface Sent { path: string; method: string; body: unknown }

interface Opts {
  /** 403 the roster — what a clinician or support account gets. */
  notAdmin?: boolean;
  /** Refuse every PATCH with this error code. */
  refuseWith?: string;
  /** What window.confirm answers. */
  confirm?: boolean;
  /** Slow the transport, to prove the verdict does not depend on the machine. */
  latencyMs?: number;
}

interface Staff {
  window: JSDOM['window'];
  sent: Sent[];
  errors: string[];
  confirms: string[];
  /** Resolves when the panel has stopped working, never after a fixed delay. */
  quiet: (label?: string) => Promise<void>;
}

async function openStaff(opts: Opts = {}): Promise<Staff> {
  const html = readFileSync(PANEL, 'utf8');
  const sent: Sent[] = [];
  const confirms: string[] = [];
  const vc = new VirtualConsole();
  const errors: string[] = [];
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  const settle = panelSettle({ latencyMs: opts.latencyMs });

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
      (window as unknown as { confirm: (m: string) => boolean }).confirm = (m: string) => {
        confirms.push(m);
        return opts.confirm !== false;
      };

      settle.attach(window as never, async (path: string, init?: PanelRequestInit) => {
        const p = path;
        const method = init?.method ?? 'GET';
        if (method !== 'GET') sent.push({ path: p, method, body: init?.body ? JSON.parse(String(init.body)) : null });

        if (p.includes('/admin/me')) return { ok: true, status: 200, json: async () => ME };
        if (p.includes('/admin/staff')) {
          if (method !== 'GET') {
            return opts.refuseWith
              ? { ok: false, status: 409, text: async () => '', json: async () => ({ error: opts.refuseWith }) }
              : { ok: true, status: 200, text: async () => '', json: async () => ({ ok: true }) };
          }
          return opts.notAdmin
            ? { ok: false, status: 403, text: async () => '', json: async () => ({ error: 'forbidden' }) }
            : { ok: true, status: 200, text: async () => '', json: async () => ROSTER };
        }
        const body = p.includes('/admin/stats')
          ? { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 }
          : {};
        return { ok: true, status: 200, text: async () => '', json: async () => body };
      });
    },
  });

  const { window } = dom;
  await settle.quiet('boot');
  window.document.querySelector('[data-view="staff"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await settle.quiet('the Персонал tab');
  return { window, sent, errors, confirms, quiet: settle.quiet };
}

const text = (w: JSDOM['window'], sel: string) => w.document.querySelector(sel)!.textContent ?? '';

describe('the roster', () => {
  it('lists everyone who can sign in, with role and last sign-in', async () => {
    const { window, errors } = await openStaff();
    expect(errors, errors.join('\n')).toEqual([]);

    const body = text(window, '#staffBody');
    expect(body).toContain('Ерен');
    expect(body).toContain('Айгерім');
    expect(body).toContain('77011112233');
    // Someone who has never signed in is worth seeing as such — it is how a
    // colleague who was set up and never told their password shows up.
    expect(body).toContain('не входил');
  });

  it('marks you, so you do not act on your own row by accident', async () => {
    const { window } = await openStaff();
    const mine = window.document.querySelector('tr[data-sid="staff-1"]')!;
    expect(mine.textContent).toMatch(/\(вы\)/);
  });

  it('shows a disabled colleague as disabled, with a way back', async () => {
    const { window } = await openStaff();
    const row = window.document.querySelector('tr[data-sid="staff-3"]')!;
    expect(row.className).toContain('off');
    expect(row.textContent).toContain('Вернуть доступ');
  });
});

/**
 * Load as an INPUT, not as a hope.
 *
 * SLOW_MS is derived, not guessed, and the derivation is the point. The first
 * attempt copied the reference file's 40 ms and was DECORATION: with the old
 * fixed waits reinstated the sabotaged run still passed, because two chained
 * requests at 40 ms land comfortably inside a 300 ms window on an idle runner.
 *
 * The rule instead: SLOW_MS is larger than the longest fixed wait these files
 * ever contained (300 ms). At that latency a SINGLE request cannot land inside
 * the old window, so any reinstated sleep truncates the screen and this test
 * fails with an empty card — which is exactly the half-drawn state the whole
 * exercise is about.
 *
 * One latency is still a sample. The property that holds for every latency is
 * that quiet() THROWS rather than returning early; this test is the evidence
 * that the throw is reachable and that nothing downstream reads a partial page.
 */
const SLOW_MS = 320;
/**
 * Load as an INPUT, not as a hope.
 *
 * The property the eleven sleeps could not have: boot the same screen twice,
 * once with every request answering forty times slower, and require the drawn
 * roster and the requests issued to be identical. Reinstate any fixed wait and
 * the slow run reads a half-filled table.
 */
describe('the verdict does not depend on how fast the machine is', () => {
  it('draws the same roster whether the server answers in one turn or slowly', async () => {
    const fast = await openStaff();
    const slow = await openStaff({ latencyMs: SLOW_MS });

    const fastBody = text(fast.window, '#staffBody').replace(/\s+/g, ' ').trim();
    const slowBody = text(slow.window, '#staffBody').replace(/\s+/g, ' ').trim();
    expect(slowBody, 'the roster was drawn differently when the server was slower').toBe(fastBody);
    // Non-vacuity: two empty tables must not be what passed.
    expect(fastBody.length).toBeGreaterThan(40);
    expect(fastBody).toContain('Айгерім');

    // …and the same holds for a write, which is where a fixed wait used to
    // decide whether the PATCH had left at all.
    for (const page of [fast, slow]) {
      const sel = page.window.document.querySelector('tr[data-sid="staff-2"] .rolesel') as HTMLSelectElement;
      sel.value = 'clinician';
      sel.dispatchEvent(new page.window.Event('change', { bubbles: true }));
      await page.quiet('the role change');
    }
    expect(slow.sent.filter((s) => s.method === 'PATCH'))
      .toEqual(fast.sent.filter((s) => s.method === 'PATCH'));
    expect(fast.sent.filter((s) => s.method === 'PATCH')).toHaveLength(1);
  });
});

describe('what a non-admin sees', () => {
  it('gets an explanation, not an empty table', async () => {
    // The failure this avoids: a 403 caught by the loader, an empty <tbody>,
    // and a support account concluding the company has no staff.
    const { window } = await openStaff({ notAdmin: true });
    expect(text(window, '#staffBody')).toMatch(/только роли admin/i);
    expect((window.document.getElementById('staffAddForm') as HTMLElement).hidden).toBe(true);
  });

  it('still offers the password form — it is their own password', async () => {
    const { window } = await openStaff({ notAdmin: true });
    expect(window.document.getElementById('pwForm')).not.toBeNull();
    expect((window.document.getElementById('pwForm') as HTMLElement).hidden).toBe(false);
  });
});

describe('changing someone', () => {
  it('sends the new role', async () => {
    const { window, sent, quiet } = await openStaff();
    const sel = window.document.querySelector('tr[data-sid="staff-2"] .rolesel') as HTMLSelectElement;
    sel.value = 'clinician';
    sel.dispatchEvent(new window.Event('change', { bubbles: true }));
    await quiet('the role change');

    const write = sent.find((s) => s.method === 'PATCH');
    expect(write, 'the dropdown changed nothing').toBeTruthy();
    expect(write!.path).toContain('staff-2');
    expect(write!.body).toEqual({ role: 'clinician' });
  });

  it('asks before closing access, and does nothing if you say no', async () => {
    const { window, sent, confirms, quiet } = await openStaff({ confirm: false });
    (window.document.querySelector('tr[data-sid="staff-2"] .staffoff') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the cancelled close');
    // The handler ran and reached the question: without this, "nothing was
    // sent" would also pass for a button wired to nothing at all.
    expect(confirms, 'access was closed without asking').not.toEqual([]);
    expect(sent.filter((s) => s.method === 'PATCH'), 'a cancelled confirm still sent it').toHaveLength(0);
  });

  it('closes access when confirmed', async () => {
    const { window, sent, quiet } = await openStaff();
    (window.document.querySelector('tr[data-sid="staff-2"] .staffoff') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the close');
    const write = sent.find((s) => s.method === 'PATCH');
    expect(write!.body).toEqual({ disabled: true });
  });

  it('re-opening access is not gated behind a confirm', async () => {
    // Restoring someone is not destructive, and a dialog on a safe action
    // teaches people to click through the one that matters.
    const { window, sent, quiet } = await openStaff({ confirm: false });
    (window.document.querySelector('tr[data-sid="staff-3"] .staffoff') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the re-open');
    expect(sent.find((s) => s.method === 'PATCH')!.body).toEqual({ disabled: false });
  });

  it('names the refusal instead of saying "не удалось"', async () => {
    // Both refusals are states nobody can undo from this screen, so the panel
    // has to say which one happened.
    const { window, quiet } = await openStaff({ refuseWith: 'last_admin' });
    (window.document.querySelector('tr[data-sid="staff-2"] .staffoff') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the refused close');
    expect(text(window, '#staffMsg')).toMatch(/последний admin/i);
  });

  it('says so when you try to lock yourself out', async () => {
    const { window, quiet } = await openStaff({ refuseWith: 'cannot_lock_yourself_out' });
    (window.document.querySelector('tr[data-sid="staff-1"] .staffoff') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await quiet('the refused self-lockout');
    expect(text(window, '#staffMsg')).toMatch(/самому себе/i);
  });
});

describe('adding a colleague', () => {
  it('sends what the form holds', async () => {
    const { window, sent, quiet } = await openStaff();
    (window.document.getElementById('stName') as HTMLInputElement).value = 'Динара';
    (window.document.getElementById('stPhone') as HTMLInputElement).value = '+7 702 000 11 22';
    (window.document.getElementById('stRole') as HTMLSelectElement).value = 'clinician';
    (window.document.getElementById('stPass') as HTMLInputElement).value = 'a-good-password';
    window.document.getElementById('staffAddForm')!
      .dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
    await quiet('the new colleague');

    const post = sent.find((s) => s.method === 'POST' && s.path.endsWith('/admin/staff'));
    expect(post, 'nothing was sent').toBeTruthy();
    expect(post!.body).toEqual({
      phone: '+7 702 000 11 22', displayName: 'Динара',
      role: 'clinician', password: 'a-good-password',
    });
  });

  it('does not leave the password in the form afterwards', async () => {
    const { window, quiet } = await openStaff();
    (window.document.getElementById('stName') as HTMLInputElement).value = 'Динара';
    (window.document.getElementById('stPhone') as HTMLInputElement).value = '77020001122';
    (window.document.getElementById('stPass') as HTMLInputElement).value = 'a-good-password';
    window.document.getElementById('staffAddForm')!
      .dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
    await quiet('the new colleague');
    expect((window.document.getElementById('stPass') as HTMLInputElement).value).toBe('');
  });
});

describe('your own password', () => {
  it('sends both fields and clears them', async () => {
    const { window, sent, quiet } = await openStaff();
    (window.document.getElementById('pwCurrent') as HTMLInputElement).value = 'old-password';
    (window.document.getElementById('pwNew') as HTMLInputElement).value = 'new-password';
    window.document.getElementById('pwForm')!
      .dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
    await quiet('the password change');

    const post = sent.find((s) => s.path.includes('/me/password'));
    expect(post!.body).toEqual({ currentPassword: 'old-password', newPassword: 'new-password' });
    expect((window.document.getElementById('pwCurrent') as HTMLInputElement).value).toBe('');
  });
});
