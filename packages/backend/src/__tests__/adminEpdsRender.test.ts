/**
 * «Скрининг ЭШПД · 15 из 30», actually painted in the mother's drawer.
 *
 * The route returns `epds` and the repository stores it; neither fact puts a
 * number in front of an operator, and this repository's signature defect is
 * exactly that gap. So this boots the real panel, opens a real mother, and
 * reads the drawer's text.
 *
 * It also reads the drawer for what must NOT be there: an answer to any of the
 * ten questions, and any word that turns a screening score into a verdict.
 */

import { describe, it, expect } from 'vitest';
import { answerReasonPromptIfShown } from './helpers/reasonPrompt.js';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const UID = '11111111-1111-1111-1111-111111111111';
const USERS = {
  total: 1,
  users: [{ id: UID, displayName: 'Айгерим', phone: '+77015551122', dueDate: null, lastMetricAt: null }],
};

const DETAIL = {
  id: UID, displayName: 'Айгерим', phone: '+77015551122', dueDate: null,
  locale: 'ru-KZ', birthDate: null, city: null,
  latest: { hr: 78, spo2: 98, systolic: 118, diastolic: 76, temp: 36.6 },
  triage: [], children: [], devices: [], alerts: [], sleepNights: 0, loggedDays: 0,
  appointments: [],
};

function wellness(epds: unknown) {
  return {
    sleep: [], days: [], alerts: [], weight: [], medications: [], medicalIds: [],
    kickSessions: [], contractionSessions: [], newbornEvents: [], bpCalibration: null,
    growth: [], doses: [], vaccines: [], epds,
  };
}

/** One boot per fixture — the panel costs over a second to start in jsdom. */
const drawn = new Map<string, Promise<{ drawer: string; errors: string[] }>>();

function openDrawer(epds: unknown) {
  const key = JSON.stringify(epds) ?? 'undefined';
  let hit = drawn.get(key);
  if (!hit) {
    hit = renderDrawer(epds);
    drawn.set(key, hit);
  }
  return hit;
}

async function renderDrawer(epds: unknown): Promise<{ drawer: string; errors: string[] }> {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const vc = new VirtualConsole();
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
      (window as unknown as { CSS: unknown }).CSS = { escape: (s: string) => String(s).replace(/["\\]/g, '\\$&') };
      window.fetch = (async (path: string) => {
        const p = String(path);
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (p.includes('/admin/bi') || p.includes('/admin/analytics')) {
          return { ok: false, status: 503, json: async () => ({}), text: async () => '' };
        }
        const body = p.includes('/wellness')
          ? wellness(epds)
          : p.includes('/detail')
            ? DETAIL
            : p.includes('/admin/users')
              ? USERS
              : p.includes('/admin/stats')
                ? { activeUsers: 1, devicesOnline: 0, alertsToday: 0, ingestLastHour: 0 }
                : {};
        return { ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) };
      }) as never;
    },
  });

  const { window } = dom;
  const wait = (ms: number) => new Promise((r) => setTimeout(r, ms));
  await wait(200);
  window.document.querySelector('[data-view="users"]')!.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(500);
  const row = window.document.querySelector(`#usersBody tr[data-user="${UID}"]`);
  if (!row) throw new Error('no user row rendered');
  row.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await wait(200);
  await answerReasonPromptIfShown(window);

  return { drawer: (window.document.querySelector('#drawer')?.textContent ?? '').replace(/\s+/g, ' ').trim(), errors };
}

const HIGH = [{ id: 'e1', takenAt: '2026-08-12T09:30:00.000Z', score: 15, band: 'high' }];
const LOW = [{ id: 'e2', takenAt: '2026-08-12T09:30:00.000Z', score: 4, band: 'low' }];

describe('the screening section in the mother drawer', () => {
  it('renders without throwing', async () => {
    const { errors } = await openDrawer(HIGH);
    expect(errors).toEqual([]);
  });

  it('prints the score, out of thirty, under the instrument name', async () => {
    const { drawer } = await openDrawer(HIGH);
    expect(drawer).toContain('Скрининг ЭШПД');
    expect(drawer).toContain('15 из 30');
  });

  it('says whose instrument it is and that it is self-reported', async () => {
    // An operator who cannot tell what «15 из 30» measures will either ignore
    // it or over-read it. Both are worse than the number not being there.
    const { drawer } = await openDrawer(HIGH);
    expect(drawer).toContain('Эдинбургская шкала');
    expect(drawer).toContain('мама заполняет его сама');
  });

  it('never prints a verdict', async () => {
    const { drawer } = await openDrawer(HIGH);
    // The score is a screening result. Nothing beside it may read as a
    // condition somebody has been given.
    expect(drawer).not.toMatch(/депресси/i);
    expect(drawer).not.toMatch(/диагноз[^ ]* (поставлен|подтвер)/i);
    // …and the card says outright that it is not one.
    expect(drawer).toContain('не диагноз');
  });

  it('never shows an answer to any of the ten questions', async () => {
    // The strongest form of this guard: the payload itself carries a stray
    // `answers` (an older or buggier client), and the drawer must still print
    // nothing but the number.
    const { drawer } = await openDrawer([
      { ...HIGH[0], answers: [1, 2, 1, 0, 0, 2, 3, 1, 2, 3], item10: 2 },
    ]);
    expect(drawer).toContain('15 из 30');
    expect(drawer).not.toContain('навредить');
    expect(drawer).not.toMatch(/вопрос\s*10/i);
    expect(drawer).not.toContain('[1,2,1');
    expect(drawer).toContain('Ответы на вопросы не сохраняются');
  });

  it('marks a result at or above the published threshold as a fact about the scale', async () => {
    const { drawer } = await openDrawer(HIGH);
    expect(drawer).toContain('выше порога 13');
    const low = await openDrawer(LOW);
    expect(low.drawer).toContain('4 из 30');
    expect(low.drawer).not.toContain('выше порога');
  });

  it('shows nothing at all when she has never taken it', async () => {
    // An empty «Скрининг ЭШПД» heading reads as a screening that scored zero.
    const { drawer, errors } = await openDrawer([]);
    expect(errors).toEqual([]);
    expect(drawer).not.toContain('Скрининг ЭШПД');
  });

  it('survives an older server that sends no epds key at all', async () => {
    const { drawer, errors } = await openDrawer(undefined);
    expect(errors).toEqual([]);
    expect(drawer).toContain('Профиль');
    expect(drawer).not.toContain('Скрининг ЭШПД');
  });
});
