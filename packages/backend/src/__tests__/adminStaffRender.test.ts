/**
 * The Персонал tab, rendered.
 *
 * The routes are covered by staffAdmin.test.ts. This is about the half that
 * cannot be tested from the server: whether the roster actually draws, whether
 * a clinician gets an explanation instead of an empty table, and whether a
 * refused change is reported rather than left on screen looking saved.
 */

import { describe, it, expect } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

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
}

async function openStaff(opts: Opts = {}) {
  const html = readFileSync(PANEL, 'utf8');
  const sent: Sent[] = [];
  const vc = new VirtualConsole();
  const errors: string[] = [];
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

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
      (window as unknown as { confirm: () => boolean }).confirm = () => opts.confirm !== false;

      window.fetch = (async (path: string, init?: RequestInit) => {
        const p = String(path);
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
      }) as never;
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 200));
  window.document.querySelector('[data-view="staff"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 300));
  return { window, sent, errors };
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
    const { window, sent } = await openStaff();
    const sel = window.document.querySelector('tr[data-sid="staff-2"] .rolesel') as HTMLSelectElement;
    sel.value = 'clinician';
    sel.dispatchEvent(new window.Event('change', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 200));

    const write = sent.find((s) => s.method === 'PATCH');
    expect(write, 'the dropdown changed nothing').toBeTruthy();
    expect(write!.path).toContain('staff-2');
    expect(write!.body).toEqual({ role: 'clinician' });
  });

  it('asks before closing access, and does nothing if you say no', async () => {
    const { window, sent } = await openStaff({ confirm: false });
    (window.document.querySelector('tr[data-sid="staff-2"] .staffoff') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 200));
    expect(sent.filter((s) => s.method === 'PATCH'), 'a cancelled confirm still sent it').toHaveLength(0);
  });

  it('closes access when confirmed', async () => {
    const { window, sent } = await openStaff();
    (window.document.querySelector('tr[data-sid="staff-2"] .staffoff') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 200));
    const write = sent.find((s) => s.method === 'PATCH');
    expect(write!.body).toEqual({ disabled: true });
  });

  it('re-opening access is not gated behind a confirm', async () => {
    // Restoring someone is not destructive, and a dialog on a safe action
    // teaches people to click through the one that matters.
    const { window, sent } = await openStaff({ confirm: false });
    (window.document.querySelector('tr[data-sid="staff-3"] .staffoff') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 200));
    expect(sent.find((s) => s.method === 'PATCH')!.body).toEqual({ disabled: false });
  });

  it('names the refusal instead of saying "не удалось"', async () => {
    // Both refusals are states nobody can undo from this screen, so the panel
    // has to say which one happened.
    const { window } = await openStaff({ refuseWith: 'last_admin' });
    (window.document.querySelector('tr[data-sid="staff-2"] .staffoff') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 250));
    expect(text(window, '#staffMsg')).toMatch(/последний admin/i);
  });

  it('says so when you try to lock yourself out', async () => {
    const { window } = await openStaff({ refuseWith: 'cannot_lock_yourself_out' });
    (window.document.querySelector('tr[data-sid="staff-1"] .staffoff') as HTMLButtonElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 250));
    expect(text(window, '#staffMsg')).toMatch(/самому себе/i);
  });
});

describe('adding a colleague', () => {
  it('sends what the form holds', async () => {
    const { window, sent } = await openStaff();
    (window.document.getElementById('stName') as HTMLInputElement).value = 'Динара';
    (window.document.getElementById('stPhone') as HTMLInputElement).value = '+7 702 000 11 22';
    (window.document.getElementById('stRole') as HTMLSelectElement).value = 'clinician';
    (window.document.getElementById('stPass') as HTMLInputElement).value = 'a-good-password';
    window.document.getElementById('staffAddForm')!
      .dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
    await new Promise((r) => setTimeout(r, 250));

    const post = sent.find((s) => s.method === 'POST' && s.path.endsWith('/admin/staff'));
    expect(post, 'nothing was sent').toBeTruthy();
    expect(post!.body).toEqual({
      phone: '+7 702 000 11 22', displayName: 'Динара',
      role: 'clinician', password: 'a-good-password',
    });
  });

  it('does not leave the password in the form afterwards', async () => {
    const { window } = await openStaff();
    (window.document.getElementById('stName') as HTMLInputElement).value = 'Динара';
    (window.document.getElementById('stPhone') as HTMLInputElement).value = '77020001122';
    (window.document.getElementById('stPass') as HTMLInputElement).value = 'a-good-password';
    window.document.getElementById('staffAddForm')!
      .dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
    await new Promise((r) => setTimeout(r, 250));
    expect((window.document.getElementById('stPass') as HTMLInputElement).value).toBe('');
  });
});

describe('your own password', () => {
  it('sends both fields and clears them', async () => {
    const { window, sent } = await openStaff();
    (window.document.getElementById('pwCurrent') as HTMLInputElement).value = 'old-password';
    (window.document.getElementById('pwNew') as HTMLInputElement).value = 'new-password';
    window.document.getElementById('pwForm')!
      .dispatchEvent(new window.Event('submit', { bubbles: true, cancelable: true }));
    await new Promise((r) => setTimeout(r, 250));

    const post = sent.find((s) => s.path.includes('/me/password'));
    expect(post!.body).toEqual({ currentPassword: 'old-password', newPassword: 'new-password' });
    expect((window.document.getElementById('pwCurrent') as HTMLInputElement).value).toBe('');
  });
});
