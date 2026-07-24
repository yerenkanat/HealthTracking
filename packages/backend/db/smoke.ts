/**
 * Live smoke test of pgRepository against a real Postgres — the path that had
 * NEVER run against a database until now (pgSchema.test only parses the SQL).
 * Exercises the plain-PG geo rewrite (geofence circle + polygon round-trip,
 * location insert) and the ingest idempotency constraint (ON CONFLICT).
 *
 *   DATABASE_URL=postgres://umay@127.0.0.1:5433/umay npx tsx db/smoke.ts
 */
import pg from 'pg';
import { createPgRepository } from '../src/db/pgRepository.js';

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const repo = createPgRepository(pool);
const ok = (cond: boolean, msg: string) => { if (!cond) { console.error('  ✗ ' + msg); process.exitCode = 1; } else console.log('  ✓ ' + msg); };

const U = '11111111-1111-1111-1111-111111111111';
const C = '22222222-2222-2222-2222-222222222222';
const D = '33333333-3333-3333-3333-333333333333';

async function main() {
  // Minimal FK graph: a guardian, her band, her child.
  await pool.query(`INSERT INTO users (id, email, display_name) VALUES ($1,'a@b.co','Aigerim') ON CONFLICT DO NOTHING`, [U]);
  await pool.query(`INSERT INTO devices (id, user_id, ble_mac, kind) VALUES ($1,$2,'AA:BB','band') ON CONFLICT DO NOTHING`, [D, U]);
  await pool.query(`INSERT INTO children (id, guardian_id, name, beacon_uuid) VALUES ($1,$2,'Sultan','b-uuid') ON CONFLICT DO NOTHING`, [C, U]);

  console.log('geofence — circle round-trip:');
  await repo.upsertGeofence(C, { id: 'aaaaaaaa-0000-0000-0000-000000000001', name: 'Home', shape: 'circle', center: { lat: 43.238, lng: 76.889 }, radiusM: 150 });
  let zones = await repo.loadGeofences(C);
  const circle = zones.find((z) => z.id === 'aaaaaaaa-0000-0000-0000-000000000001');
  ok(!!circle && circle.shape === 'circle', 'circle stored + read back');
  ok(circle?.shape === 'circle' && Math.abs(circle.center.lat - 43.238) < 1e-6 && circle.radiusM === 150, 'center + radius survive the round-trip');

  console.log('geofence — polygon round-trip:');
  await repo.upsertGeofence(C, { id: 'aaaaaaaa-0000-0000-0000-000000000002', name: 'Park', shape: 'polygon', vertices: [{ lat: 43.1, lng: 76.8 }, { lat: 43.2, lng: 76.8 }, { lat: 43.2, lng: 76.9 }] });
  zones = await repo.loadGeofences(C);
  const poly = zones.find((z) => z.id === 'aaaaaaaa-0000-0000-0000-000000000002');
  ok(!!poly && poly.shape === 'polygon', 'polygon stored + read back');
  ok(poly?.shape === 'polygon' && Math.abs(poly.vertices[0].lat - 43.1) < 1e-6 && Math.abs(poly.vertices[0].lng - 76.8) < 1e-6, 'first vertex survives the round-trip');

  console.log('location insert (plain lat/lng):');
  await repo.insertLocation({ childId: C, observedAt: new Date('2026-07-24T10:00:00Z').toISOString(), coords: { lat: 43.238, lng: 76.889, accuracyM: 12 }, source: 'gps' } as never);
  const loc = await pool.query('SELECT lat, lng, source FROM location_history WHERE child_id=$1', [C]);
  ok(loc.rows.length === 1 && Math.abs(loc.rows[0].lat - 43.238) < 1e-6, 'location stored as lat/lng');

  console.log('ingest idempotency (real ON CONFLICT constraint):');
  const reading = { deviceId: D, userId: U, recordedAt: '2026-07-24T08:00:00.000Z', systolicMmHg: 168, diastolicMmHg: 116, triageSeverity: 'emergency' };
  const first = await repo.insertHealthMetric(reading as never);
  const second = await repo.insertHealthMetric(reading as never);
  ok(first === false, 'first insert stores the reading (not a duplicate)');
  ok(second === true, 'identical resend is reported as a duplicate (ON CONFLICT DO NOTHING)');
  const cnt = await pool.query('SELECT count(*)::int AS n FROM pregnancy_health_metrics WHERE user_id=$1', [U]);
  ok(cnt.rows[0].n === 1, 'exactly one row stored despite two sends');

  // Clean up so the smoke test is repeatable.
  await pool.query('DELETE FROM users WHERE id=$1', [U]);
  await pool.end();
  console.log(process.exitCode ? '\nSMOKE FAILED' : '\n✓ all pgRepository checks passed against real Postgres');
}
main().catch((e) => { console.error('smoke error:', e.message); process.exit(1); });
