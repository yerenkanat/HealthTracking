/**
 * Why somebody opened a mother's record, recorded next to who and when.
 *
 * The log was complete and unreviewable. «s-4 просмотрел здоровье u-91» is the
 * same row whether a clinician was returning a call or somebody was reading a
 * neighbour's blood pressure, so the only question it could answer was "did
 * anyone look", after it was already too late to matter.
 *
 * docs/CLAUDE-admin-design.md §"Доступ к чувствительному": «Показатели здоровья
 * и геолокация — только владелец, каждый просмотр в журнале с указанием
 * причины.»
 *
 * Three levels, because each catches a different way this goes wrong:
 *   - the route refuses without a reason (not: defaults one in);
 *   - the reason reaches the log and comes back out of it;
 *   - the panel asks before it fetches, and the log shows the answer.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import { answerReasonPrompt } from './helpers/reasonPrompt.js';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

let app: FastifyInstance;

beforeEach(() => {
  app = buildServer(
    {
      repo: createMemoryRepository(),
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

const get = (url: string) => app.inject({ method: 'GET', url });
/**
 * The per-person reads, all of them.
 *
 * There were three; `/health` was deleted (docs/BACKLOG.md §3) because
 * `/detail` already returns the `latest` and `triage` it served, under the same
 * capability, the same reason gate and the same audit — see the note where it
 * used to be in routes/admin.ts. The cases below moved onto `/detail` rather
 * than being dropped: what they check is the reason contract, and that contract
 * belongs to whichever route opens a named woman's record.
 */
const PER_PERSON = ['wellness', 'detail'];
/** The audited read the reason cases drive. */
const AUDITED = { path: 'detail', action: 'view_user_detail' };

describe('a record does not open without a stated reason', () => {
  it.each(PER_PERSON)('/admin/users/:id/%s refuses a bare request', async (path) => {
    const res = await get(`/admin/users/${DEMO_USER}/${path}`);
    expect(res.statusCode).toBe(400);
    expect(res.json().error).toBe('reason_required');
    // The message is read by a person, so it says what to do.
    expect(res.json().message).toContain('причину');
  });

  it.each(PER_PERSON)('/admin/users/:id/%s opens with one', async (path) => {
    const res = await get(`/admin/users/${DEMO_USER}/${path}?reason=${encodeURIComponent('Обращение клиента')}`);
    expect(res.statusCode, res.body).toBe(200);
  });

  it('refuses an answer that is not an answer', async () => {
    // A required field with no floor fills up with "-" and "ok", and a log of
    // those is exactly as unreviewable as a log of nothing.
    for (const reason of ['', ' ', 'ok', '.', 'нужно']) {
      const res = await get(`/admin/users/${DEMO_USER}/${AUDITED.path}?reason=${encodeURIComponent(reason)}`);
      expect(res.statusCode, `"${reason}" was accepted as a reason`).toBe(400);
    }
  });

  it('reads nothing when it refuses', async () => {
    // Refusing after the query has run has still run the query, and a 400 with
    // the record already fetched is a record already read.
    await get(`/admin/users/${DEMO_USER}/${AUDITED.path}`);
    const { audit } = (await get('/admin/audit')).json();
    expect(audit.some((a: { action: string }) => a.action === AUDITED.action),
      'a refused read was logged as a read').toBe(false);
  });
});

describe('the reason reaches the log', () => {
  it('is stored beside who and when, and comes back out', async () => {
    await get(`/admin/users/${DEMO_USER}/${AUDITED.path}?reason=${encodeURIComponent('Разбор жалобы №14')}`);
    const { audit } = (await get('/admin/audit')).json();
    const row = audit.find((a: { action: string }) => a.action === AUDITED.action);
    expect(row).toBeDefined();
    expect(row.reason).toBe('Разбор жалобы №14');
    expect(row.target).toBe(DEMO_USER);
    expect(row.staffId).toBe('s1');
  });

  it('each of the reads carries its own', async () => {
    await get(`/admin/users/${DEMO_USER}/${AUDITED.path}?reason=${encodeURIComponent('Проверка тревоги')}`);
    await get(`/admin/users/${DEMO_USER}/wellness?reason=${encodeURIComponent('Медицинская консультация')}`);
    const { audit } = (await get('/admin/audit')).json();
    const by = (action: string) => audit.find((a: { action: string }) => a.action === action)?.reason;
    expect(by(AUDITED.action)).toBe('Проверка тревоги');
    expect(by('view_wellness')).toBe('Медицинская консультация');
  });

  it('an action that explains itself has no reason, and that is not a blank one', () => {
    // Listing orders needs no justification. What must not happen is a written
    // "не указана" — that makes an unreviewable row look reviewed.
    return get('/admin/users').then(async () => {
      const { audit } = (await get('/admin/audit')).json();
      const row = audit.find((a: { action: string }) => a.action === 'list_users');
      expect(row).toBeDefined();
      expect(row.reason).toBeNull();
    });
  });

  it('an over-long reason is trimmed, not refused', async () => {
    // Somebody pasting a whole email in should get their record, not a 400.
    const long = 'ж'.repeat(1000);
    const res = await get(`/admin/users/${DEMO_USER}/${AUDITED.path}?reason=${encodeURIComponent(long)}`);
    expect(res.statusCode).toBe(200);
    const { audit } = (await get('/admin/audit')).json();
    expect(audit.find((a: { action: string }) => a.action === AUDITED.action).reason.length).toBe(300);
  });
});

// ---------------------------------------------------------------------------

async function openPanel() {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const asked: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: 'http://localhost/admin',
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

      window.fetch = (async (path: string) => {
        const p = String(path);
        asked.push(p);
        const body =
          p.includes('/admin/me') ? { staffId: 's1', role: 'owner', displayName: 'Ерен' }
          : p.includes('/admin/users/') ? { displayName: 'Айгерім', phone: '+77001112233', children: [] }
          : p.includes('/admin/users') ? { total: 1, users: [{ id: 'u1', displayName: 'Айгерім', phone: '+77001112233' }] }
          : {};
        return { ok: true, status: 200, text: async () => '', json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 250));
  window.document.querySelector('[data-view="users"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 400));
  const row = window.document.querySelector('#usersBody tr[data-user="u1"]');
  row?.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 200));

  return { window, errors, asked };
}

describe('the panel asks before it fetches', () => {
  it('raises the prompt and requests nothing until it is answered', async () => {
    const { window, asked, errors } = await openPanel();
    expect(errors, errors.join('\n')).toEqual([]);

    const wrap = window.document.querySelector('#reasonWrap') as HTMLElement;
    expect(wrap.hidden, 'the record opened without asking why').toBe(false);
    // The crucial half: nothing has been fetched yet. A prompt shown over an
    // already-loaded drawer records a reason for a record that is on screen.
    expect(asked.some((p) => p.includes('/detail'))).toBe(false);
    expect(asked.some((p) => p.includes('/wellness'))).toBe(false);
  });

  it('sends the typed reason with every request the card makes', async () => {
    const { window, asked } = await openPanel();
    await answerReasonPrompt(window, 'Разбор жалобы №14');

    const withReason = asked.filter((p) => p.includes('/detail') || p.includes('/wellness'));
    expect(withReason.length, 'the card fetched nothing after the prompt').toBeGreaterThan(0);
    for (const p of withReason) {
      expect(decodeURIComponent(p), p).toContain('reason=Разбор жалобы №14');
    }
  });

  it('will not accept an answer too short for the server', async () => {
    // A prompt that takes "ok" and then watches the server refuse it is worse
    // than no prompt: the person learns the panel is broken, not the rule.
    const { window } = await openPanel();
    const text = window.document.querySelector('#reasonText') as HTMLInputElement;
    const ok = window.document.querySelector('#reasonOk') as HTMLButtonElement;
    text.value = 'ok';
    text.dispatchEvent(new window.Event('input', { bubbles: true }));
    expect(ok.disabled).toBe(true);
  });

  it('cancelling opens nothing', async () => {
    const { window, asked } = await openPanel();
    (window.document.querySelector('#reasonCancel') as HTMLElement)
      .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    await new Promise((r) => setTimeout(r, 150));
    expect((window.document.querySelector('#reasonWrap') as HTMLElement).hidden).toBe(true);
    expect(asked.some((p) => p.includes('/detail'))).toBe(false);
  });

  it('offers reasons rather than an empty box', async () => {
    // A required free-text field with no suggestions fills up with "-".
    const { window } = await openPanel();
    const presets = window.document.querySelectorAll('#reasonPresets button');
    expect(presets.length).toBeGreaterThan(2);
    const chosen = presets[0] as HTMLButtonElement;
    chosen.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
    const text = window.document.querySelector('#reasonText') as HTMLInputElement;
    expect(text.value).toBe(chosen.textContent);
    expect((window.document.querySelector('#reasonOk') as HTMLButtonElement).disabled).toBe(false);
  });
});
