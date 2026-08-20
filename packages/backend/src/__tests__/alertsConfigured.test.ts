/**
 * Does anyone find out when the site goes down?
 *
 * deploy/uptime-check.sh watches the landing, /ready and the TLS certificate
 * every few minutes and sends through the Telegram credentials stored in the
 * panel. Without a token it still runs, still detects the outage, and still
 * exits non-zero — into a journal nobody reads. The monitoring works and the
 * alert goes nowhere, so silence is indistinguishable from health.
 *
 * The panel now says so on the overview. These check the signal it reads.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { panelSettle } from './helpers/panelSettle';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';

const PANEL = resolve(dirname(fileURLToPath(import.meta.url)), '../../../admin/index.html');

let repo: Repository;
let app: FastifyInstance;
let cookie: string;

beforeEach(async () => {
  repo = createMemoryRepository();
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
  const res = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
});

const stats = async () =>
  (await app.inject({ method: 'GET', url: '/admin/stats', headers: { cookie } })).json();

describe('the server reports whether alerts would reach anyone', () => {
  it('says no when Telegram is not configured', async () => {
    expect((await stats()).alertsConfigured).toBe(false);
  });

  it('says yes once both the token and the chat are set', async () => {
    await repo.setShopSettings({ telegramBotToken: '123:abc', telegramChatId: '-1001' });
    expect((await stats()).alertsConfigured).toBe(true);
  });

  it('a token with no chat id is not configured — it would send nowhere', async () => {
    await repo.setShopSettings({ telegramBotToken: '123:abc' });
    expect((await stats()).alertsConfigured).toBe(false);
  });

  it('never returns the credentials themselves', async () => {
    await repo.setShopSettings({ telegramBotToken: '123:SECRET', telegramChatId: '-1001' });
    const body = (await app.inject({ method: 'GET', url: '/admin/stats', headers: { cookie } })).body;
    expect(body).not.toContain('SECRET');
  });
});

describe('the panel shows it where the owner looks', () => {
  async function overview(alertsConfigured: boolean) {
    const html = readFileSync(PANEL, 'utf8');
    const vc = new VirtualConsole();
    const settle = panelSettle();
  const dom = new JSDOM(html, {
      runScripts: 'dangerously', pretendToBeVisual: true,
      url: 'http://localhost/admin', virtualConsole: vc,
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
        (window as unknown as { alert: () => void }).alert = () => {};
        settle.attach(window as never, async (path: string) => {
          const p = String(path);
          if (p.includes('/admin/me')) {
            return { ok: true, status: 200, json: async () => ({ staffId: 's1', role: 'admin', displayName: 'Ерен', phone: '77073452244' }) };
          }
          const body = p.includes('/admin/stats')
            ? { activeUsers: 1, devicesOnline: 1, alertsToday: 0, ingestLastHour: 0, alertsConfigured }
            : {};
          return { ok: true, status: 200, text: async () => '', json: async () => body };
        });
      },
    });
    await settle.quiet('the overview');
    return dom.window;
  }

  it('warns when nobody would be told', async () => {
    const w = await overview(false);
    const banner = w.document.getElementById('alertsOff') as HTMLElement;
    expect(banner, 'no banner in the markup').not.toBeNull();
    expect(banner.hidden, 'the owner is not told that alerts go nowhere').toBe(false);
    expect(banner.textContent).toMatch(/Оповещения не настроены/);
  });

  it('says nothing once alerts are configured', async () => {
    // A warning that never goes away is a warning nobody reads.
    const w = await overview(true);
    expect((w.document.getElementById('alertsOff') as HTMLElement).hidden).toBe(true);
  });
});
