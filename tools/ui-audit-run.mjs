/**
 * Drive the prepared panel through real Chrome at several widths and views,
 * printing every layout overflow. Chrome's DevTools protocol over the
 * --remote-debugging-port, so we can navigate hashes and read return values —
 * --dump-dom alone cannot run our measuring function.
 */
const { spawn } = require('child_process');
const http = require('http');

const CHROME = process.argv[2];
const FILE = process.argv[3];
const WIDTHS = (process.argv[4] || '1440,1280,1024,900,768,600,420').split(',').map(Number);
const VIEWS = (process.argv[5] || 'overview,shop,stock,users,catalog,finance,support,devices,emergencies,course,audit,staff,analytics').split(',');

const PORT = 9223;

function get(path) {
  return new Promise((res, rej) => {
    http.get({ host: '127.0.0.1', port: PORT, path }, (r) => {
      let d = ''; r.on('data', (c) => (d += c)); r.on('end', () => res(JSON.parse(d)));
    }).on('error', rej);
  });
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
  const args = [
    '--headless=new', '--disable-gpu', '--no-sandbox', '--hide-scrollbars',
    `--remote-debugging-port=${PORT}`, '--remote-allow-origins=*',
    `--user-data-dir=${process.env.TEMP}\\graphify-chrome-audit`,
    'about:blank',
  ];
  const chrome = spawn(CHROME, args, { stdio: 'ignore' });
  await sleep(2500);

  const WebSocket = require('ws');
  const targets = await get('/json/list');
  const page = targets.find((t) => t.type === 'page');
  const ws = new WebSocket(page.webSocketDebuggerUrl, { perMessageDeflate: false });
  let id = 0;
  const pending = new Map();
  ws.on('message', (m) => {
    const msg = JSON.parse(m);
    if (msg.id && pending.has(msg.id)) { pending.get(msg.id)(msg); pending.delete(msg.id); }
  });
  await new Promise((r) => ws.on('open', r));
  const send = (method, params) => new Promise((res) => {
    const i = ++id; pending.set(i, res); ws.send(JSON.stringify({ id: i, method, params }));
  });

  await send('Page.enable');
  await send('Runtime.enable');

  for (const w of WIDTHS) {
    await send('Emulation.setDeviceMetricsOverride',
      { width: w, height: 900, deviceScaleFactor: 1, mobile: false });
    await send('Page.navigate', { url: 'file:///' + FILE.replace(/\\/g, '/') });
    await sleep(1400);
    for (const view of VIEWS) {
      await send('Runtime.evaluate', { expression: `location.hash='#${view}'` });
      await sleep(450);
      const r = await send('Runtime.evaluate', {
        expression: 'window.__audit ? window.__audit() : Promise.resolve({page:"NO AUDIT FN",overflow:[],unreachable:[]})',
        awaitPromise: true, returnByValue: true,
      });
      const v = r.result?.result?.value;
      if (!v) { console.log(`${w}px ${view}: no result`); continue; }
      const bad = v.overflow.length || v.unreachable.length || (v.flush||[]).length || v.page !== 'page ok';
      if (bad) {
        console.log(`\n=== ${w}px · ${view} ===`);
        if (v.page !== 'page ok') console.log('  ' + v.page);
        v.overflow.slice(0, 6).forEach((o) => console.log('  ' + o));
        if (v.overflow.length > 6) console.log(`  … and ${v.overflow.length - 6} more`);
        v.unreachable.slice(0, 4).forEach((o) => console.log('  UNREACHABLE ' + o));
        (v.flush||[]).slice(0, 10).forEach((o) => console.log('  ' + o));
        if ((v.flush||[]).length > 10) console.log('  … and ' + (v.flush.length-10) + ' more flush');
      }
    }
  }
  console.log('\ndone');
  ws.close(); chrome.kill(); process.exit(0);
})().catch((e) => { console.error('audit failed:', e.message); process.exit(1); });
