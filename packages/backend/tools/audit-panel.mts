/**
 * End-to-end audit of the back office: the real panel, against the real server.
 *
 * Not fixtures. window.fetch is wired to app.inject, so every request the panel
 * makes is answered by the actual route handlers and the actual repository
 * shapes. Fixture-driven checks kept telling me tabs were broken when only my
 * invented payloads were.
 */

import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { buildServer } from '../src/server';
import { createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD } from '../src/db/memoryRepository';

const PANEL = fileURLToPath(new URL('../../admin/index.html', import.meta.url));
const repo = createMemoryRepository();

const app = buildServer(
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
    authAdmin: async () => ({ staffId: 'staff-dev', role: 'admin' as const }),
  },
  { logger: false },
);
/**
 * The session cookie the panel carries.
 *
 * The first version of this tool did not sign in. /admin/me answered 401, the
 * panel sat on its login gate for the whole run, and boot() never fetched
 * /admin/stats, /admin/bi, /admin/users or /admin/audit. Every tab still drew —
 * clicking a nav item renders a view whether or not anyone is signed in — so
 * the report read "16 of 16 render" while the dashboard data had never been
 * loaded, and analytics was reported broken when it had simply never been
 * asked for. An audit that authenticates as nobody measures nothing.
 */
let cookie = '';

async function signIn() {
  const res = await app.inject({
    method: 'POST',
    url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  if (res.statusCode !== 200) throw new Error(`sign-in failed: ${res.statusCode} ${res.body}`);
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
  if (!cookie) throw new Error('sign-in returned no cookie');
  console.log(`signed in as ${DEV_STAFF_PHONE}`);
}

async function main() {
await app.ready();
await signIn();

const html = readFileSync(PANEL, 'utf8');
const vc = new VirtualConsole();
const jsdomErrors: string[] = [];
const rejections: string[] = [];
vc.on('jsdomError', (e: Error) => jsdomErrors.push(e.message));
process.on('unhandledRejection', (e) => rejections.push(String(e)));

const requests: Array<{ url: string; status: number }> = [];

const dom = new JSDOM(html, {
  runScripts: 'dangerously',
  pretendToBeVisual: true,
  url: 'http://localhost/admin',
  virtualConsole: vc,
  beforeParse(window) {
    window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
      const noop = () => {};
      return new Proxy(
        { canvas: { width: 900, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
        { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true },
      );
    }) as never;
    Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 900 });
    window.scrollTo = () => {};
    Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
    (window as unknown as { alert: () => void }).alert = () => {};

    window.fetch = (async (path: string, init?: RequestInit) => {
      const res = await app.inject({
        method: (init?.method ?? 'GET') as 'GET',
        url: String(path),
        payload: init?.body as string | undefined,
        headers: { ...(init?.headers as Record<string, string>), cookie },
      });
      requests.push({ url: String(path), status: res.statusCode });
      return {
        ok: res.statusCode >= 200 && res.statusCode < 300,
        status: res.statusCode,
        text: async () => res.body,
        json: async () => { try { return JSON.parse(res.body); } catch { return {}; } },
      };
    }) as never;
  },
});

const { window } = dom;
await new Promise((r) => setTimeout(r, 600));

const views = [...window.document.querySelectorAll('.nav[data-view]')]
  .map((n) => (n as HTMLElement).dataset.view!);

console.log(`\n${views.length} tabs\n${'─'.repeat(72)}`);

const problems: string[] = [];
for (const v of views) {
  (window.document.querySelector(`.nav[data-view="${v}"]`) as HTMLElement)
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 300));

  const section = window.document.getElementById(v);
  const title = window.document.getElementById('pageTitle')!.textContent;
  const text = (section?.textContent ?? '').replace(/\s+/g, ' ').trim();

  const flags: string[] = [];
  if (text.length < 20) flags.push('NEARLY EMPTY');
  if (/undefined|NaN|\[object Object\]/.test(text)) flags.push('BROKEN VALUE');
  if (/не удалось|недоступ|когда панель обслуживается/i.test(text)) flags.push('UNAVAILABLE');
  if (flags.length) problems.push(`${v}: ${flags.join(', ')}`);

  console.log(`${flags.length ? '✗' : '✓'} ${v.padEnd(12)} «${title}» ${text.length} chars ${flags.join(', ')}`);
  if (flags.length) console.log(`    ${text.slice(0, 200)}`);
}

// Re-open analytics after everything has settled: if it renders the second
// time, the first was a race against BI loading rather than a broken tab.
  (window.document.querySelector(`.nav[data-view="analytics"]`) as HTMLElement)
    .dispatchEvent(new window.MouseEvent("click", { bubbles: true }));
  await new Promise((r) => setTimeout(r, 800));
  const again = (window.document.getElementById('analytics')?.textContent ?? '').replace(/\s+/g, ' ');
  console.log(`\nanalytics on second open: ${/недоступ/.test(again) ? 'STILL unavailable' : 'renders'} (${again.length} chars)`);

  console.log('\nrequests made:');
  for (const r of requests) console.log(`   ${r.status}  ${r.url}`);

  const failed = requests.filter((r) => r.status >= 400);
console.log(`${'─'.repeat(72)}`);
console.log(`requests: ${requests.length}, failed: ${failed.length}`);
for (const f of failed.slice(0, 10)) console.log(`   ${f.status}  ${f.url}`);
console.log(`jsdom errors: ${jsdomErrors.length}`);
jsdomErrors.slice(0, 5).forEach((e) => console.log(`   ${e.slice(0, 150)}`));
console.log(`unhandled rejections: ${rejections.length}`);
rejections.slice(0, 5).forEach((e) => console.log(`   ${e.slice(0, 150)}`));
console.log(`\nproblem tabs: ${problems.length ? problems.join(' | ') : 'none'}`);

await app.close();
process.exit(0);
}
main();
