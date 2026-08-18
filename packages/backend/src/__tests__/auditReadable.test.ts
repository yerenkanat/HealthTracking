/**
 * The audit log has to be readable by the person who reads it.
 *
 * It answers one question — who in the back office looked at this mother's
 * data — and it answered it with "971d2b2d-aecb-4698-8682-a447dab43f6d". The
 * panel printed that verbatim, next to the raw action key. Everything was
 * recorded correctly and none of it could be used.
 *
 * Both halves are checked here: the API resolving ids to people, and the panel
 * drawing what it is given.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashPassword, hashToken, readSessionCookie } from '../http/staffAuth';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const OWNER = { phone: '77073452244', password: 'owner-password' };

let repo: Repository;
let app: FastifyInstance;

beforeEach(async () => {
  repo = createMemoryRepository();
  await repo.upsertStaffAccount({
    phone: OWNER.phone, passwordHash: await hashPassword(OWNER.password),
    role: 'admin', displayName: 'Ерен',
  });
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
      authAdmin: async (req) => {
        const token = readSessionCookie(req.headers.cookie);
        if (!token) return null;
        return repo.staffBySessionToken(hashToken(token));
      },
    },
    { logger: false },
  );
});

const signIn = async () => {
  const res = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: OWNER.phone, password: OWNER.password },
  });
  return String(res.headers['set-cookie'] ?? '').split(';')[0];
};

const auditRows = async (cookie: string) =>
  (await app.inject({ method: 'GET', url: '/admin/audit?limit=50', headers: { cookie } })).json().audit;

describe('the log names people', () => {
  it('resolves the staff id to a name and phone', async () => {
    const cookie = await signIn();
    const rows = await auditRows(cookie);
    const login = rows.find((r: { action: string }) => r.action === 'staff_login');
    expect(login, 'signing in was not recorded').toBeTruthy();
    expect(login.staffName).toBe('Ерен');
    expect(login.staffPhone).toBe(OWNER.phone);
    // The id stays: it is what the row is keyed on, and the panel shows it on
    // hover for when two colleagues share a first name.
    expect(login.staffId).toBeTruthy();
  });

  it('names the colleague an action was done TO', async () => {
    const cookie = await signIn();
    await app.inject({
      method: 'POST', url: '/admin/staff', headers: { cookie },
      payload: { phone: '77011112233', displayName: 'Айгерім', role: 'support', password: 'nurse-password' },
    });

    const rows = await auditRows(cookie);
    const created = rows.find((r: { action: string }) => r.action === 'staff_create');
    expect(created.targetName, 'the target id was left unresolved').toBe('Айгерім');
  });

  it('records signing out, not only signing in', async () => {
    // Otherwise the log can say when someone started and never when they
    // stopped, and "was anyone in the system at 02:00" is unanswerable.
    const cookie = await signIn();
    await app.inject({ method: 'POST', url: '/admin/logout', headers: { cookie } });

    const second = await signIn();
    const rows = await auditRows(second);
    expect(rows.some((r: { action: string }) => r.action === 'staff_logout')).toBe(true);
  });

  it('keeps rows it cannot name', async () => {
    // Entries from before accounts existed, or from an account since removed.
    // Hiding them would make the log lie by omission — the opposite of its job.
    await repo.writeAudit({ staffId: 'a-vanished-account', action: 'view_health', target: DEMO_USER });
    const rows = await auditRows(await signIn());
    const orphan = rows.find((r: { staffId: string }) => r.staffId === 'a-vanished-account');
    expect(orphan, 'the row disappeared with the account').toBeTruthy();
    expect(orphan.staffName).toBeNull();
  });
});

describe('the panel draws it', () => {
  async function openAudit(rows: unknown[]) {
    const html = readFileSync(PANEL, 'utf8');
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
        window.fetch = (async (path: string) => {
          const p = String(path);
          if (p.includes('/admin/me')) {
            return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin', displayName: 'Ерен', phone: '77073452244' }) };
          }
          if (p.includes('/admin/audit')) {
            return { ok: true, status: 200, text: async () => '', json: async () => ({ audit: rows }) };
          }
          const body = p.includes('/admin/stats')
            ? { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0 } : {};
          return { ok: true, status: 200, text: async () => '', json: async () => body };
        }) as never;
      },
    });

    const { window } = dom;
    await new Promise((r) => setTimeout(r, 200));
    window.document.querySelector('[data-view="audit"]')!
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 250));
    return { window, errors };
  }

  it('shows the name, not the UUID', async () => {
    const { window, errors } = await openAudit([
      {
        at: '2026-08-04T09:00:00Z', staffId: '971d2b2d-aecb-4698-8682-a447dab43f6d',
        staffName: 'Ерен', staffPhone: '77073452244',
        action: 'view_health', target: 'user-1', targetName: null,
      },
    ]);
    expect(errors, errors.join('\n')).toEqual([]);
    const body = window.document.getElementById('auditBody')!;
    expect(body.textContent).toContain('Ерен');
    expect(body.textContent).not.toContain('971d2b2d');
    // Still reachable, for when two colleagues share a first name.
    expect(body.innerHTML).toContain('971d2b2d');
    // And the action is Russian rather than a database key.
    expect(body.textContent).toContain('Открыл(а) медданные');
  });

  it('labels the actions the sign-in work added', async () => {
    // These were recorded from the day sign-in shipped and rendered as
    // "staff_login" — correct, and meaningless to the person reading it.
    const { window } = await openAudit(
      ['staff_login', 'staff_logout', 'staff_create', 'staff_update', 'staff_password_change'].map((action) => ({
        at: '2026-08-04T09:00:00Z', staffId: 's1', staffName: 'Ерен', staffPhone: '77073452244',
        action, target: null, targetName: null,
      })),
    );
    const body = window.document.getElementById('auditBody')!.textContent ?? '';
    expect(body).not.toMatch(/staff_/);
    expect(body).toContain('Вход в панель');
    expect(body).toContain('Выход из панели');
    expect(body).toContain('Сменил(а) свой пароль');
  });

  it('labels what the immunisation calendar writes — the strings the ROUTES use', async () => {
    // Frames 15 / 15a / 15b write four actions, and the panel had a label for
    // none of them: an edit to the national vaccination schedule appeared in
    // the log as «edit_vaccine» beside «pcv/2» — English, in a Russian panel,
    // on exactly the rows the log exists for, the age of an injection and the
    // clinician who signed it.
    //
    // The rows below are not typed by hand: they are driven through the real
    // routes and read back out of /admin/audit, so renaming an action on either
    // side fails here rather than silently going untranslated again.
    const cookie = await signIn();
    const body = {
      atMonth: 9, dose: 2,
      ru: { name: 'Пневмококковая', note: 'Против пневмонии и отита' },
      kk: { name: 'Пневмококк', note: 'Пневмония мен отитке қарсы' },
    };
    const drafted = await app.inject({
      method: 'PUT', url: '/admin/vaccination/schedule/pcv/2', headers: { cookie },
      payload: { ...body, draft: true },
    });
    expect(drafted.statusCode, drafted.body).toBe(200);
    const signed = await app.inject({
      method: 'POST', url: '/admin/vaccination/schedule/pcv/2/review', headers: { cookie },
    });
    expect(signed.statusCode, signed.body).toBe(200);
    const published = await app.inject({
      method: 'PUT', url: '/admin/vaccination/schedule/pcv/2', headers: { cookie },
      payload: { ...body, draft: false },
    });
    expect(published.statusCode, published.body).toBe(200);
    const window9 = await app.inject({
      method: 'PUT', url: '/admin/vaccination/settings', headers: { cookie },
      payload: { dueWindowMonths: 2 },
    });
    expect(window9.statusCode, window9.body).toBe(200);

    const rows = await auditRows(cookie);
    const actions = rows.map((r: { action: string }) => r.action);
    for (const a of ['edit_vaccine_draft', 'vaccine_review', 'edit_vaccine', 'edit_vaccination_settings']) {
      expect(actions, `${a} was never recorded`).toContain(a);
    }

    const { window } = await openAudit(rows);
    const painted = window.document.getElementById('auditBody')!.textContent ?? '';
    expect(painted).toContain('Сохранил(а) прививку черновиком');
    expect(painted).toContain('Подписал(а) прививку в календаре');
    expect(painted).toContain('Изменил(а) прививку в календаре');
    expect(painted).toContain('Изменил(а) догоняющее окно прививок');
    // ...and not one raw key left standing.
    expect(painted).not.toMatch(/edit_vaccin/);
    expect(painted).not.toMatch(/vaccine_review/);
    // The target is still there — which injection, and which window.
    expect(painted).toContain('pcv/2');
    expect(painted).toContain('dueWindowMonths=2');
  });

  it('falls back to the id when there is no name', async () => {
    const { window } = await openAudit([
      {
        at: '2026-08-04T09:00:00Z', staffId: 'a-vanished-account',
        staffName: null, staffPhone: null,
        action: 'view_health', target: null, targetName: null,
      },
    ]);
    expect(window.document.getElementById('auditBody')!.textContent).toContain('a-vanished-account');
  });
});
