/**
 * Render the user drawer and read the family sections — children and devices.
 *
 * The backend returned children[] and devices[] in /admin/users/:id/detail all
 * along; the drawer never rendered them, so "how many kids, which watch/tracker,
 * what battery, what gestational week" was invisible in the back-office. This
 * executes the real page — boot it, open a user with a family, and assert the
 * drawer actually shows them — so the data can never silently go unrendered again.
 */

import { describe, it, expect, beforeAll } from 'vitest';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

const UID = '11111111-1111-1111-1111-111111111111';
const USERS = {
  total: 1,
  users: [{ id: UID, displayName: 'Айгерим', phone: '+77001112233', dueDate: null, lastMetricAt: null }],
};

// ~14 months old — stable enough that the label reads in months, not years.
const infantDob = new Date(Date.now() - 430 * 86400000).toISOString();

function detail(extra: Record<string, unknown>) {
  return {
    id: UID, displayName: 'Айгерим', phone: '+77001112233', dueDate: null,
    weeks: 28, // gestational week, so the drawer can show "28-я неделя"
    locale: 'ru-KZ', birthDate: null, city: null,
    latest: { hr: 78, spo2: 98, systolic: 118, diastolic: 76, temp: 36.6 },
    triage: [], children: [], devices: [], alerts: [], sleepNights: 0, loggedDays: 0,
    appointments: [], ...extra,
  };
}

function wellness(extra: Record<string, unknown> = {}) {
  return { sleep: [], days: [], alerts: [], weight: [], medications: [], medicalIds: [], kickSessions: [], contractionSessions: [], newbornEvents: [], bpCalibration: null, growth: [], doses: [], vaccines: [], ...extra };
}

async function openDrawer(detailExtra: Record<string, unknown>, wellnessExtra: Record<string, unknown> = {}): Promise<{ drawer: string; errors: string[] }> {
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
        // The panel now opens on a sign-in gate and asks who is signed in
        // before it renders anything. These tests are about the dashboard,
        // so they answer as a signed-in admin.
        if (p.includes('/admin/me')) {
          return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin' }) };
        }
        if (p.includes('/admin/bi') || p.includes('/admin/analytics')) {
          return { ok: false, status: 503, json: async () => ({}), text: async () => '' };
        }
        const body = p.includes('/wellness')
          ? wellness(wellnessExtra)
          : p.includes('/detail')
            ? detail(detailExtra)
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

  return { drawer: (window.document.querySelector('#drawer')?.textContent ?? '').replace(/\s+/g, ' ').trim(), errors };
}

describe('the family sections in the user drawer', () => {
  describe('with children and devices', () => {
    let drawer: string;
    let errors: string[];
    beforeAll(async () => {
      ({ drawer, errors } = await openDrawer({
        children: [
          { id: 'c1', name: 'Алия', dateOfBirth: infantDob, zones: 2 },
          { id: 'c2', name: 'Тимур', dateOfBirth: null, zones: 0 },
        ],
        devices: [
          { id: 'd1', name: 'RunmeFit S1', kind: 'watch', childId: null, batteryPct: 82 },
          { id: 'd2', name: 'Метка-2', kind: 'tracker', childId: 'c1', batteryPct: 45 },
        ],
      }));
    });

    it('runs without throwing', () => expect(errors).toEqual([]));

    it('shows the children with a count', () => {
      expect(drawer).toContain('Дети · 2');
      expect(drawer).toContain('Алия');
      expect(drawer).toContain('Тимур');
    });

    it('shows a child age and a zone count, and marks a missing birth date', () => {
      expect(drawer).toMatch(/2 зон/); // Алия has 2 zones
      expect(drawer).toContain('возраст не указан'); // Тимур has no dateOfBirth
    });

    it('shows the devices with kind, battery, and the child they follow', () => {
      expect(drawer).toContain('Устройства · 2');
      expect(drawer).toContain('Часы'); // watch → localized
      expect(drawer).toContain('Трекер'); // tracker → localized
      expect(drawer).toContain('82%'); // battery surfaced
      expect(drawer).toContain('45%');
    });

    it('shows the gestational week explicitly', () => {
      expect(drawer).toContain('28-я неделя');
    });
  });

  describe('with no children or devices', () => {
    it('omits the family sections without error', async () => {
      const { drawer, errors } = await openDrawer({ children: [], devices: [] });
      expect(errors).toEqual([]);
      expect(drawer).not.toContain('Дети ·');
      expect(drawer).not.toContain('Устройства ·');
    });
  });

  describe('blood glucose in the vitals block', () => {
    it('shows a graded glucose reading when she has one', async () => {
      const { drawer, errors } = await openDrawer({ latest: { hr: 78, spo2: 98, systolic: 118, diastolic: 76, temp: 36.6, glucose: 8.2 } });
      expect(errors).toEqual([]);
      expect(drawer).toContain('Glucose');
      expect(drawer).toContain('8.2');
      expect(drawer).toContain('mmol/L');
    });
    it('omits glucose when there is no reading', async () => {
      const { drawer, errors } = await openDrawer({ latest: { hr: 78, spo2: 98, systolic: 118, diastolic: 76, temp: 36.6 } });
      expect(errors).toEqual([]);
      expect(drawer).not.toContain('Glucose');
    });
  });

  describe('wellness fields that were returned but never rendered', () => {
    it("shows the emergency medical-ID free-text notes", async () => {
      const { drawer, errors } = await openDrawer({}, {
        medicalIds: [{ childName: 'Алия', bloodType: 'O+', allergies: '', conditions: '', medications: '', doctorName: '', doctorPhone: '', contactName: '', contactPhone: '', notes: 'носит с собой EpiPen' }],
      });
      expect(errors).toEqual([]);
      expect(drawer).toContain('Заметки');
      expect(drawer).toContain('носит с собой EpiPen');
    });

    it('shows awake time in the sleep breakdown', async () => {
      const { drawer, errors } = await openDrawer({}, {
        sleep: [{ night: '2026-07-20', deepMin: 90, remMin: 80, lightMin: 200, awakeMin: 35 }],
      });
      expect(errors).toEqual([]);
      expect(drawer).toContain('бодр.'); // awake minutes now surfaced
    });

    it('shows how much history exists (nights + diary days)', async () => {
      const { drawer, errors } = await openDrawer({ sleepNights: 23, loggedDays: 8 });
      expect(errors).toEqual([]);
      expect(drawer).toContain('История данных');
      expect(drawer).toContain('23');
      expect(drawer).toContain('8');
    });
  });
});
