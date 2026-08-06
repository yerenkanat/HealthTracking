/**
 * End-to-end audit of the landing page — the public face of the business.
 *
 * Same approach as audit-panel.mts: the real page, answered by the real
 * routes. Checks the things a visitor would notice and a test never does —
 * that every asset it references actually resolves, that every link goes
 * somewhere real, that the lead form posts to something that accepts it, and
 * that the copy is not still carrying placeholders.
 */

import { JSDOM, VirtualConsole } from 'jsdom';
import { buildServer } from '../src/server';
import { createMemoryRepository, DEMO_USER } from '../src/db/memoryRepository';
import { registerLanding } from '../src/http/landing';
import { registerStaticPages } from '../src/http/staticPages';

/** The host the page is actually served under, so it renders as it ships. */
const PROD_HOST = 'ana-bala.kz';

/**
 * External hosts the page is MEANT to reach.
 *
 * mama.nureke.kz is the Ма!Ма! course's own site: the landing links to it for
 * "Всё о курсе" and embeds its trailer, deliberately. It sat on the
 * placeholder blacklist as "old domain", so the audit reported a failure on
 * every single run — and a check that always fails is a check nobody reads,
 * which costs the day something genuinely stale does appear.
 *
 * An allow-list is also the stronger check: it catches a link to a host we
 * never intended, which is the thing actually worth knowing about.
 */
const EXPECTED_HOSTS = new Set([
  'wa.me', // the order button
  'mama.nureke.kz', // the course partner
  'fonts.googleapis.com',
  'fonts.gstatic.com',
]);

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
  // registerLanding and registerStaticPages are called by index.ts, the boot
  // file, not by buildServer — so a harness has to wire them the same way the
  // server does. (staticPages moved out of index.ts for exactly this reason;
  // the landing has not.)
  registerLanding(app);
  registerStaticPages(app);
  await app.ready();

  // With the real Host header. The page builds og:url and rel=canonical from
  // the request, so fetching it as "localhost" makes every absolute URL on the
  // page say localhost — which then trips the audit's own placeholder check
  // and reports a shipped bug that does not exist.
  const page = await app.inject({
    method: 'GET', url: '/',
    headers: { host: PROD_HOST, 'x-forwarded-proto': 'https' },
  });
  console.log(`\nGET /  →  ${page.statusCode}, ${page.body.length} bytes`);
  if (page.statusCode !== 200) { console.log('the landing does not load'); process.exit(1); }

  const html = page.body;

  // ---- 1. Every asset the page references -----------------------------------
  const refs = new Set<string>();
  for (const m of html.matchAll(/(?:src|href)="(\/[^"]+)"/g)) refs.add(m[1]);
  console.log(`\nassets and links referenced: ${refs.size}`);
  const broken: string[] = [];
  for (const r of refs) {
    const res = await app.inject({ method: 'GET', url: r });
    if (res.statusCode >= 400) broken.push(`${res.statusCode}  ${r}`);
  }
  console.log(broken.length ? `  BROKEN (${broken.length}):` : '  all resolve');
  broken.forEach((b) => console.log(`    ${b}`));

  // ---- 2. Outbound links ----------------------------------------------------
  const external = [...html.matchAll(/href="(https?:\/\/[^"]+)"/g)].map((m) => m[1]);
  const hosts = new Map<string, number>();
  for (const u of external) {
    try { const h = new URL(u).host; hosts.set(h, (hosts.get(h) ?? 0) + 1); } catch { /* ignore */ }
  }
  console.log(`\noutbound links: ${external.length}`);
  for (const [h, n] of [...hosts].sort((a, b) => b[1] - a[1])) {
    // Flagged by whether we MEANT to link there, not by a blacklist of things
    // that were once wrong.
    const known = EXPECTED_HOSTS.has(h) || h === PROD_HOST;
    console.log(`  ${known ? ' ' : '!'} ${String(n).padStart(3)}  ${h}${known ? '' : '   UNEXPECTED'}`);
  }

  // ---- 3. Placeholders and leftovers ---------------------------------------
  const smells: Array<[string, RegExp]> = [
    ['old brand', /\bUmay\b/i],
    ['lorem', /lorem ipsum/i],
    ['TODO/FIXME', /TODO|FIXME|PLACEHOLDER/],
    ['example.com', /example\.(com|org)/i],
    // A dev origin left in the copy. Checked against the page as SERVED,
    // which is why the fetch above sends the production Host header — read
    // over localhost, every absolute URL on the page said localhost and this
    // reported a shipped bug that did not exist.
    ['localhost', /localhost:\d+/],
  ];
  console.log('\ncopy check:');
  for (const [name, re] of smells) {
    const hit = html.match(re);
    console.log(`  ${hit ? '✗' : '✓'} ${name}${hit ? `  → ${hit[0]}` : ''}`);
  }

  // ---- 4. Crawler basics ----------------------------------------------------
  console.log('\ncrawlers and metadata:');
  for (const p of ['/robots.txt', '/sitemap.xml']) {
    const r = await app.inject({ method: 'GET', url: p });
    console.log(`  ${r.statusCode === 200 ? '✓' : '✗'} ${p} → ${r.statusCode}`);
  }
  for (const tag of ['<title>', 'og:title', 'og:image', 'og:description', 'rel="canonical"', 'name="description"']) {
    console.log(`  ${html.includes(tag) ? '✓' : '✗'} ${tag}`);
  }

  // ---- 5. The lead form actually posts somewhere that accepts it ------------
  const lead = await app.inject({
    method: 'POST', url: '/shop/leads',
    payload: { customerName: 'Аудит', phone: '+7 707 000 00 00', package: 'Комплект', locale: 'ru' },
  });
  // 201, not 200: a lead is CREATED, and that is what the route has always
  // answered. Checking for 200 marked a working form as broken on every run.
  console.log(`\nlead form: POST /shop/leads → ${lead.statusCode} ${lead.statusCode === 201 ? '✓' : '✗'}`);
  // And the row has to exist. A 201 proves the route answered, not that the
  // lead was kept — which is the failure this whole file exists to catch.
  const leads = await repo.adminShopLeads(5);
  console.log(`  stored: ${leads.some((l) => l.customerName === 'Аудит') ? '✓' : '✗ the 201 was not a row'}`);
  const bad = await app.inject({ method: 'POST', url: '/shop/leads', payload: { customerName: '', phone: '' } });
  console.log(`  empty submission refused: ${bad.statusCode === 400 ? '✓ 400' : `✗ ${bad.statusCode}`}`);

  // ---- 6. The config the page reads at runtime ------------------------------
  const cfg = await app.inject({ method: 'GET', url: '/shop/config' });
  console.log(`\n/shop/config → ${cfg.statusCode}`);
  try {
    const c = JSON.parse(cfg.body);
    for (const k of Object.keys(c)) {
      const v = JSON.stringify(c[k]);
      console.log(`  ${k.padEnd(14)} ${v.length > 60 ? v.slice(0, 57) + '…' : v}`);
    }
  } catch { console.log('  (unparseable)'); }

  // ---- 7. Render it, and see what JavaScript does ---------------------------
  const vc = new VirtualConsole();
  const errors: string[] = [];
  vc.on('jsdomError', (e: Error) => errors.push(e.message));
  const dom = new JSDOM(html, {
    runScripts: 'outside-only', pretendToBeVisual: true,
    url: 'https://ana-bala.kz/', virtualConsole: vc,
  });
  const text = (dom.window.document.body.textContent ?? '').replace(/\s+/g, ' ').trim();
  console.log(`\nvisible text: ${text.length} chars`);
  console.log(`  ${text.slice(0, 200)}`);

  await app.close();
  process.exit(0);
}

main();
