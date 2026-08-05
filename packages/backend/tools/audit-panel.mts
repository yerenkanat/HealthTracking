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
import { buildServer } from './src/server';
import { createMemoryRepository, DEMO_USER } from './src/db/memoryRepository';

const PANEL = fileURLToPath(new URL('../admin/index.html', import.meta.url));
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
async function main() {
await app.ready();

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
        headers: init?.headers as Record<string, string>,
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
