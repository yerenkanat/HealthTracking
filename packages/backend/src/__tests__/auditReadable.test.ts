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
import { auditActionKeys, panelAuditLabels, RETIRED_ACTIONS } from './helpers/auditActions';

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

/**
 * Boot the real panel and open the Журнал over the rows it is given.
 *
 * At module scope rather than inside one describe, because the label work
 * below has to paint too — a map with the right key in it and a column that
 * never shows it is the same defect one step earlier.
 */
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

describe('the panel draws it', () => {
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

  /**
   * The whole vocabulary, painted.
   *
   * Not a list typed here: `auditActionKeys()` reads every `writeAudit` call
   * site in `packages/backend/src`, so a route added tomorrow is in this test
   * the moment it is written, and its action shows up in the panel as a raw
   * English key until somebody labels it. That is the guard the four-key
   * version of this file could not give — it named its four and would have let
   * a fifth through in silence.
   *
   * Painted, not looked up. Reading AUDIT_ACTIONS proves the map has an entry;
   * only rendering proves the entry reaches the column, and this file already
   * exists because everything was recorded correctly and none of it could be
   * used.
   */
  it('paints a Russian phrase for every action any route can write', async () => {
    const keys = [...auditActionKeys().keys()].sort();
    expect(keys.length, 'no writeAudit call sites were found — the scanner is broken').toBeGreaterThan(60);

    const { window, errors } = await openAudit(keys.map((action, i) => ({
      at: `2026-08-04T09:${String(i % 60).padStart(2, '0')}:00Z`,
      staffId: 's1', staffName: 'Ерен', staffPhone: '77073452244',
      action, target: null, targetName: null,
    })));
    expect(errors, errors.join('\n')).toEqual([]);

    const body = window.document.getElementById('auditBody')!;
    expect(body.querySelectorAll('tr').length, 'the panel dropped rows').toBe(keys.length);

    const painted = body.textContent ?? '';
    const labels = panelAuditLabels();
    const raw = keys.filter((k) => painted.includes(k));
    expect(
      raw,
      `the Журнал printed these as raw English keys to a Russian-speaking reviewer:\n` +
      raw.map((k) => `  ${k}  (${auditActionKeys().get(k)})`).join('\n'),
    ).toEqual([]);
    for (const k of keys) {
      expect(painted, `«${labels[k]}» never reached the column for ${k}`).toContain(labels[k]);
    }
  });
});

/**
 * The map and the call sites, in both directions.
 *
 * §4.6: about twenty actions were reaching the Журнал with no label at all —
 * `broadcast_publish`, `view_finance`, `view_wearable` among them — and the
 * only reason anybody knew is that somebody diffed the two lists by hand once.
 * A test that repeats that list by hand rots the same way; these derive it.
 */
describe('the label map and the routes agree', () => {
  it('labels every action a route can write', () => {
    const labels = panelAuditLabels();
    const missing = [...auditActionKeys()].filter(([key]) => !(key in labels));
    expect(
      missing.map(([key, where]) => `${key} — ${where}`),
      'these writeAudit actions have no entry in AUDIT_ACTIONS, so the Журнал ' +
      'prints the raw English key beside the row',
    ).toEqual([]);
  });

  it('has no label for an action nothing writes', () => {
    // The repo's dominant defect in miniature: finished work with no caller. A
    // label for an action no route emits is dead weight that reads as coverage.
    // Retirement is allowed and has to be declared, because rows already in the
    // production table still have to be readable.
    const written = auditActionKeys();
    const orphans = Object.keys(panelAuditLabels())
      .filter((key) => !written.has(key) && !(key in RETIRED_ACTIONS));
    expect(
      orphans,
      'AUDIT_ACTIONS labels these, and no route writes them. Delete the label, ' +
      'or add it to RETIRED_ACTIONS naming the action that replaced it',
    ).toEqual([]);
  });

  it('keeps the retired labels, and each names its replacement', () => {
    // Deleting these would make months of production rows print raw keys —
    // exactly the defect being fixed, applied backwards in time.
    const labels = panelAuditLabels();
    const written = auditActionKeys();
    for (const [gone, replacement] of Object.entries(RETIRED_ACTIONS)) {
      expect(labels[gone], `${gone} lost its label; old rows now print the raw key`).toBeTruthy();
      expect(written.has(gone), `${gone} is written again — take it out of RETIRED_ACTIONS`).toBe(false);
      expect(
        written.has(replacement) || replacement in labels,
        `${gone} claims ${replacement} replaced it, and nothing writes or labels that`,
      ).toBe(true);
    }
  });

  it('writes phrases, not the key again', () => {
    // A label that is the key with the underscores taken out is not a
    // translation, and the reviewer is no better off.
    const labels = panelAuditLabels();
    const bad = Object.entries(labels).filter(([key, label]) =>
      !label.trim() || label === key || !/[А-Яа-яЁё]/.test(label) || label.includes('_'));
    expect(bad, 'these read as keys rather than as Russian').toEqual([]);
  });
});

/**
 * The keys, driven through the real routes.
 *
 * §4.6 named seven families by hand. These are the ones a reviewer of a
 * mother's record is most likely to be reading — who wrote to forty women, who
 * opened her wristband data, who read the books — so they are not typed into a
 * fixture here: they are produced by the routes and read back out of
 * /admin/audit, so a rename on either side fails here rather than going
 * untranslated again.
 */
describe('the §4.6 actions, end to end', () => {
  it('records and labels broadcasts, categories, support, finance and wearable', async () => {
    const cookie = await signIn();
    const ok = <T extends { statusCode: number; body: string }>(res: T, what: string): T => {
      // The status is asserted, not assumed: a route that 400s here would leave
      // no audit row, and the label check below would then pass by drawing
      // nothing at all.
      expect(res.statusCode, `${what}: ${res.body}`).toBeLessThan(300);
      return res;
    };

    // Рассылки — a draft, an edit, and the send itself.
    const bc = {
      id: 'august-checkup', titleRu: 'Плановый осмотр', bodyRu: 'Не забудьте про приём',
      titleKk: 'Жоспарлы тексеру', bodyKk: 'Қабылдауды ұмытпаңыз',
    };
    ok(await app.inject({ method: 'POST', url: '/admin/broadcasts', headers: { cookie }, payload: bc }), 'broadcast_create');
    ok(await app.inject({
      method: 'PUT', url: '/admin/broadcasts/august-checkup', headers: { cookie },
      payload: { ...bc, bodyRu: 'Не забудьте про приём у врача' },
    }), 'broadcast_edit');
    ok(await app.inject({
      method: 'POST', url: '/admin/broadcasts/august-checkup/publish', headers: { cookie },
    }), 'broadcast_publish');

    // Категории магазина.
    ok(await app.inject({
      method: 'PUT', url: '/admin/shop/categories/bracelets', headers: { cookie },
      payload: { nameRu: 'Браслеты', nameKk: 'Білезіктер', sort: 1 },
    }), 'category_upsert');
    ok(await app.inject({
      method: 'DELETE', url: '/admin/shop/categories/bracelets', headers: { cookie },
    }), 'category_delete');

    // Поддержка — открытие списка, карточки, создание, ответ и смена статуса.
    ok(await app.inject({ method: 'GET', url: '/admin/support', headers: { cookie } }), 'view_support');
    const created = ok(await app.inject({
      method: 'POST', url: '/admin/support', headers: { cookie },
      payload: { subject: 'Браслет не заряжается', body: 'Второй день', phone: '77011112233', channel: 'whatsapp' },
    }), 'support_create');
    const ticketId = created.json().id as string;
    ok(await app.inject({ method: 'GET', url: `/admin/support/${ticketId}`, headers: { cookie } }), 'view_support_ticket');
    ok(await app.inject({
      method: 'POST', url: `/admin/support/${ticketId}/reply`, headers: { cookie },
      payload: { body: 'Проверьте контакты зарядки', waiting: true },
    }), 'support_reply');
    ok(await app.inject({
      method: 'PATCH', url: `/admin/support/${ticketId}`, headers: { cookie },
      payload: { status: 'closed' },
    }), 'support_update');

    // Финансы и данные браслета конкретной женщины — the two reads whose whole
    // point is that somebody can be asked about them afterwards.
    ok(await app.inject({
      method: 'GET', url: '/admin/finance?from=2026-08-01&to=2026-08-31', headers: { cookie },
    }), 'view_finance');
    ok(await app.inject({
      method: 'GET', url: `/admin/users/${DEMO_USER}/wearable?reason=жалоба на браслет`, headers: { cookie },
    }), 'view_wearable');

    const rows = await auditRows(cookie);
    const actions = rows.map((r: { action: string }) => r.action);
    const expected = [
      'broadcast_create', 'broadcast_edit', 'broadcast_publish',
      'category_upsert', 'category_delete',
      'view_support', 'support_create', 'view_support_ticket', 'support_reply', 'support_update',
      'view_finance', 'view_wearable',
    ];
    for (const a of expected) expect(actions, `${a} was never recorded`).toContain(a);

    const { window } = await openAudit(rows);
    const painted = window.document.getElementById('auditBody')!.textContent ?? '';
    const labels = panelAuditLabels();
    for (const a of expected) {
      expect(painted, `${a} printed raw`).not.toContain(a);
      expect(painted, `${a} has no phrase on screen`).toContain(labels[a]);
    }
    // The reason survives the trip: a wearable read without one is refused, and
    // a read whose reason is not on the row is not reviewable.
    expect(painted).toContain('жалоба на браслет');
    // And the send says who it reached, rather than only that it happened.
    expect(painted).toMatch(/доставлено \d+ из \d+/);
  });
});
