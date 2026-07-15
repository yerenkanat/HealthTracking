/**
 * End-to-end smoke test against a RUNNING backend + Postgres + Redis.
 * Uses fixtures from seed.sql. No external deps (node 24 global fetch).
 *
 *   docker compose -f infra/docker-compose.yml up -d
 *   docker compose -f infra/docker-compose.yml exec -T db psql -U fcs -d fcs < infra/seed.sql
 *   (cd packages/backend && npm install && \
 *      DATABASE_URL=postgres://fcs:fcs@localhost:5432/fcs \
 *      REDIS_URL=redis://localhost:6379 \
 *      ANTHROPIC_API_KEY=sk-... npm run dev &)
 *   node infra/integration_smoke.mjs
 *
 * The pure request-handling logic is already unit-tested; this proves the wiring
 * (validation, DB writes, Redis dedup, geofence transitions) against real services.
 */

const BASE = process.env.BASE_URL ?? 'http://localhost:8080';
const DEVICE = '22222222-2222-2222-2222-222222222222';
const CHILD = '33333333-3333-3333-3333-333333333333';
const USER = '11111111-1111-1111-1111-111111111111';

let pass = 0, fail = 0;
const chk = (n, ok) => { ok ? pass++ : fail++; console.log(`${ok ? 'PASS' : 'FAIL'}  ${n}`); };

async function post(path, body) {
  const res = await fetch(BASE + path, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(body),
  });
  return { status: res.status, json: await res.json().catch(() => null) };
}
async function get(path) {
  const res = await fetch(BASE + path);
  return { status: res.status, json: await res.json().catch(() => null) };
}

async function main() {
  chk('health ok', (await get('/health')).json?.ok === true);

  // 1. Ingest an emergency telemetry frame + a Home-enter location, then an exit.
  const home = { lat: 43.238949, lng: 76.889709 };
  const away = { lat: 43.30, lng: 77.0 };
  const batch = await post('/ingest/batch', {
    items: [
      { type: 'telemetry', payload: { deviceId: DEVICE, recordedAt: new Date().toISOString(), systolicMmHg: 148, diastolicMmHg: 95 } },
      { type: 'location', payload: { childId: CHILD, coords: home, source: 'gps', observedAt: new Date().toISOString() } },
    ],
  });
  chk('ingest 200', batch.status === 200);
  chk('ingest counted telemetry', batch.json?.telemetryCount === 1);
  chk('ingest flagged emergency', batch.json?.emergencies === 1);
  chk('ingest emitted Home enter', (batch.json?.geofenceEvents ?? []).some((e) => e.geofenceName === 'Home' && e.transition === 'enter'));

  // Re-send the same Home location → must NOT emit a duplicate enter (Redis dedup).
  const dup = await post('/ingest/batch', {
    items: [{ type: 'location', payload: { childId: CHILD, coords: home, source: 'gps', observedAt: new Date().toISOString() } }],
  });
  chk('duplicate Home fix suppressed', (dup.json?.geofenceEvents ?? []).length === 0);

  // Move away → exit.
  const exit = await post('/ingest/batch', {
    items: [{ type: 'location', payload: { childId: CHILD, coords: away, source: 'gps', observedAt: new Date().toISOString() } }],
  });
  chk('leaving Home emits exit', (exit.json?.geofenceEvents ?? []).some((e) => e.transition === 'exit'));

  // 2. Last-known location cached in Redis.
  const loc = await get(`/children/${CHILD}/location`);
  chk('last location returns the away fix', loc.status === 200 && Math.abs(loc.json?.coords?.lat - away.lat) < 1e-6);

  // 3. BP calibration.
  const cal = await post('/calibration/bp', {
    userId: USER, cuffSystolic: 128, cuffDiastolic: 82, ppgSystolic: 120, ppgDiastolic: 78,
    measuredAt: new Date().toISOString(),
  });
  chk('calibration computes offsets', cal.status === 200 && cal.json?.systolicOffset === 8 && cal.json?.diastolicOffset === 4);

  // 4. AI chat with a critical reading attached → server forces the emergency screen.
  const chat = await post('/ai/chat', {
    userId: USER, locale: 'ru-KZ', message: 'is everything okay?',
    latestTelemetry: { systolicMmHg: 150, diastolicMmHg: 96 },
  });
  chk('chat escalates to emergency screen', chat.json?.action === 'SHOW_EMERGENCY_SCREEN');

  console.log(`\nIntegration smoke: ${pass} passed, ${fail} failed`);
  process.exit(fail ? 1 : 0);
}

main().catch((e) => { console.error(e); process.exit(1); });
