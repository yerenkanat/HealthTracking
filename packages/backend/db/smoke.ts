/**
 * Live smoke test of pgRepository against a real Postgres — the path that had
 * NEVER run against a database until now (pgSchema.test only parses the SQL).
 * Exercises the plain-PG geo rewrite (geofence circle + polygon round-trip,
 * location insert) and the ingest idempotency constraint (ON CONFLICT).
 *
 *   DATABASE_URL=postgres://umay@127.0.0.1:5433/umay npx tsx db/smoke.ts
 *
 * ---------------------------------------------------------------------------
 * THIS SCRIPT WRITES AND DELETES ROWS. Point it at a DISPOSABLE database built
 * by `npm run db:apply`, never at production. The retention section at the foot
 * of main() runs the real eight-table sweep — the same call the scheduler makes
 * every six hours — and a sweep does not know it is being tested.
 * ---------------------------------------------------------------------------
 */
import pg from 'pg';
import { createPgRepository } from '../src/db/pgRepository.js';
import { BUNDLE_DISCOUNT_MINOR } from '../src/db/repository.js';
import { RETENTION_SWEEPS, retentionCutoff, sweepAll } from '../src/privacy/retention.js';

const pool = new pg.Pool({ connectionString: process.env.DATABASE_URL });
const repo = createPgRepository(pool);
const ok = (cond: boolean, msg: string) => { if (!cond) { console.error('  ✗ ' + msg); process.exitCode = 1; } else console.log('  ✓ ' + msg); };

const U = '11111111-1111-1111-1111-111111111111';
const C = '22222222-2222-2222-2222-222222222222';
const D = '33333333-3333-3333-3333-333333333333';
/** The band's PHYSICAL id. insertHealthMetric resolves a device through its
 *  MAC, not its row uuid — a band has no idea what its primary key is. */
const D_MAC = 'AA:BB';

// ---------------------------------------------------------------------------
// Retention: the eight DELETEs that run against a real family's rows.
//
// Every behavioural test of the sweeps runs against createMemoryRepository.
// pgRepository is what actually deletes, and until this section nothing in the
// suite opened a database: eight DELETEs were scheduled to run every six hours
// in production having never once been executed.
//
// retentionSweeps.test.ts reads the SOURCE of those DELETEs and catches a `<=`
// or a table it must not name. It cannot catch a column, and that is the worst
// case: changing the geofence_events sweep to `WHERE created_at < $1` leaves
// the entire vitest suite green, while sweepOne() swallows the 42703 into
// RetentionResult.error — so in production a broken sweep is indistinguishable
// from a healthy one that had nothing to do, for ever.
//
// So each sweep is planted with three rows and run through the repository
// method the SCHEDULER calls — sweepAll(), not hand-written SQL, because a
// smoke test that re-implements the DELETE proves nothing about the code that
// ships:
//
//   older than the cutoff  -> must be gone
//   exactly at the cutoff  -> must SURVIVE (the predicate is `<`, never `<=`)
//   newer than the cutoff  -> must survive
//
// The survivors are the assertions that matter. Over-deletion takes a child's
// zone crossings, a mother's SOS history and the audit trail proving nobody
// read her record unexplained, and nothing brings any of it back.
// ---------------------------------------------------------------------------

/** Rows planted for the retention checks. Distinct from the ids above so the
 *  sweep's blast radius can be measured without the rest of the script in it. */
const RC = '44444444-4444-4444-4444-444444444444'; // child
const RG = 'aaaaaaaa-0000-0000-0000-000000000030'; // her zone
const rid = (n: number) => `bbbbbbbb-0000-0000-0000-0000000000${String(n).padStart(2, '0')}`;
/** Every sentinel phone starts here, so cleanup is one LIKE per table. */
const RPHONE = '7790000';
const DAY_MS = 86_400_000;

/** The period the SCHEDULER uses for this table, never a literal repeated here.
 *  Throws if the schedule is renamed out from under this script. */
function sweepDays(table: string): number {
  const s = RETENTION_SWEEPS.find((x) => x.table === table);
  if (!s) throw new Error(`RETENTION_SWEEPS has no entry for "${table}" — the schedule changed and this smoke test did not`);
  return s.days;
}

async function countRows(fromWhere: string, params: unknown[] = []): Promise<number> {
  const { rows } = await pool.query(`SELECT count(*)::int AS n FROM ${fromWhere}`, params);
  return rows[0].n as number;
}

async function retentionSweeps() {
  console.log('retention sweeps (the eight live DELETEs, run through sweepAll):');

  // Anchored to the real clock, not to a date in this file: the sweeps read a
  // cutoff derived from `now`, and rows dated relative to it keep this section
  // meaningful whenever it is run.
  const NOW = new Date();
  const cut = (t: string) => retentionCutoff(NOW, sweepDays(t));
  const at = (t: string) => cut(t);
  const older = (t: string) => new Date(Date.parse(cut(t)) - DAY_MS).toISOString();
  const newer = (t: string) => new Date(Date.parse(cut(t)) + DAY_MS).toISOString();

  // A sweep added to the schedule without a case below would otherwise ship
  // untested exactly as these eight did.
  const covered = ['location_history', 'geofence_events', 'safety_alerts', 'audit_log',
    'phone_codes', 'login_attempts', 'shop_leads', 'support_tickets'];
  ok(RETENTION_SWEEPS.length === covered.length && covered.every((t) => RETENTION_SWEEPS.some((s) => s.table === t)),
    `every scheduled sweep has a case here (${RETENTION_SWEEPS.length} scheduled, ${covered.length} covered)`);

  // --- plant ---------------------------------------------------------------
  await pool.query(`INSERT INTO children (id, guardian_id, name, beacon_uuid) VALUES ($1,$2,'Retention','r-uuid') ON CONFLICT DO NOTHING`, [RC, U]);
  await pool.query(`INSERT INTO geofences (id, guardian_id, child_id, name, shape, center_lat, center_lng, radius_m)
                    VALUES ($1,$2,$3,'RetentionZone','circle',43.2,76.9,100) ON CONFLICT DO NOTHING`, [RG, U, RC]);

  // location_history has no id column; the timestamp is the identity here.
  for (const ts of [older('location_history'), at('location_history'), newer('location_history')]) {
    await pool.query(`INSERT INTO location_history (child_id, observed_at, lat, lng, source) VALUES ($1,$2,43.2,76.9,'gps')`, [RC, ts]);
  }
  for (const [i, ts] of [older('geofence_events'), at('geofence_events'), newer('geofence_events')].entries()) {
    await pool.query(`INSERT INTO geofence_events (id, child_id, geofence_id, transition, source, occurred_at) VALUES ($1,$2,$3,'enter','ble',$4)`, [rid(1 + i), RC, RG, ts]);
  }
  for (const [i, ts] of [older('safety_alerts'), at('safety_alerts'), newer('safety_alerts')].entries()) {
    await pool.query(`INSERT INTO safety_alerts (id, user_id, child_id, kind, zone_name, at) VALUES ($1,$2,$3,'sos','RetentionZone',$4)`, [rid(11 + i), U, RC, ts]);
  }
  for (const [i, ts] of [older('audit_log'), at('audit_log'), newer('audit_log')].entries()) {
    await pool.query(`INSERT INTO audit_log (id, staff_id, action, target, reason, at) VALUES ($1,'smoke-retention','user.read','u','smoke',$2)`, [rid(21 + i), ts]);
  }
  for (const [i, ts] of [older('shop_leads'), at('shop_leads'), newer('shop_leads')].entries()) {
    await pool.query(`INSERT INTO shop_leads (id, customer_name, phone, created_at) VALUES ($1,'Смоук-ретеншн',$2,$3)`, [rid(31 + i), `${RPHONE}3${i}`, ts]);
  }

  // phone_codes sweeps on created_at and NOT on expires_at, deliberately: a
  // live code expires in minutes, so measuring thirty days from expiry would
  // measure from the wrong instant entirely. The two rows below fail in
  // opposite directions if the wrong column is read.
  const farFuture = new Date(NOW.getTime() + 3600_000).toISOString();
  const longExpired = new Date(NOW.getTime() - 5000 * DAY_MS).toISOString();
  await pool.query(`INSERT INTO phone_codes (phone, code_hash, expires_at, created_at) VALUES ($1,'h',$2,$3)`,
    [`${RPHONE}01`, farFuture, older('phone_codes')]);          // old row, unexpired: must GO
  await pool.query(`INSERT INTO phone_codes (phone, code_hash, expires_at, created_at) VALUES ($1,'h',$2,$3)`,
    [`${RPHONE}02`, longExpired, new Date(NOW.getTime() - 3600_000).toISOString()]); // fresh row, ancient expiry: must STAY
  await pool.query(`INSERT INTO phone_codes (phone, code_hash, expires_at, created_at) VALUES ($1,'h',$2,$3)`,
    [`${RPHONE}03`, farFuture, at('phone_codes')]);             // exactly at the cutoff: must STAY

  // One period over two tables. A later edit that moves one and forgets the
  // other is exactly what a single method with a single count is meant to stop.
  for (const [i, ts] of [older('login_attempts'), at('login_attempts'), newer('login_attempts')].entries()) {
    await pool.query(`INSERT INTO user_login_attempts (phone, at) VALUES ($1,$2)`, [`${RPHONE}1${i}`, ts]);
    await pool.query(`INSERT INTO staff_login_attempts (phone, at, succeeded) VALUES ($1,$2,false)`, [`${RPHONE}2${i}`, ts]);
  }

  // support_tickets is measured from LAST ACTIVITY: updated_at, plus a
  // NOT EXISTS over newer replies. A thread that ran for two years must not
  // lose its beginning while its end is still live, so the reply cases below
  // are the ones that test the clause rather than the date column.
  const ticket = async (id: string, updatedAt: string, subject: string) =>
    pool.query(`INSERT INTO support_tickets (id, phone, subject, body, created_at, updated_at)
                VALUES ($1,$2,$3,'смоук',$4,$4)`, [id, `${RPHONE}90`, subject, updatedAt]);
  const reply = async (id: string, ticketId: string, atIso: string) =>
    pool.query(`INSERT INTO support_replies (id, ticket_id, author, body, at) VALUES ($1,$2,'customer','ответ',$3)`, [id, ticketId, atIso]);

  const T = (n: number) => rid(40 + n);
  await ticket(T(1), older('support_tickets'), 'смоук: старый, без ответов');   // must GO
  await ticket(T(2), at('support_tickets'), 'смоук: ровно на границе');          // must STAY (`<`)
  await ticket(T(3), newer('support_tickets'), 'смоук: свежий');                 // must STAY
  await ticket(T(4), older('support_tickets'), 'смоук: старый, свежий ответ');   // must STAY (recent reply)
  await reply(rid(51), T(4), new Date(NOW.getTime() - DAY_MS).toISOString());
  await ticket(T(5), older('support_tickets'), 'смоук: старый, старый ответ');   // must GO, reply with it
  await reply(rid(52), T(5), new Date(Date.parse(cut('support_tickets')) - 50 * DAY_MS).toISOString());
  await ticket(T(6), older('support_tickets'), 'смоук: ответ ровно на границе');  // must STAY (r.at >= cutoff)
  await reply(rid(53), T(6), at('support_tickets'));

  // Accounting. RETENTION_KEPT says shop_orders has no sweep and must not gain
  // one in passing; five years old and it still has to be here afterwards.
  await pool.query(`INSERT INTO shop_orders (id, customer_name, phone, city, address, total_minor, created_at)
                    VALUES ($1,'Смоук-ретеншн-заказ',$2,'Алматы','ул. Абая 2',100000,$3)`,
    [rid(61), `${RPHONE}99`, new Date(NOW.getTime() - 5 * 365 * DAY_MS).toISOString()]);

  // --- sweep ---------------------------------------------------------------
  // Exactly what scheduleRetention() calls, with the same repository object the
  // server hands it. Nothing below re-implements a DELETE.
  const results = await sweepAll(repo, NOW);
  for (const r of results) ok(!r.error, `${r.table}: the DELETE executed against real Postgres${r.error ? ' — ' + r.error : ''}`);

  const removed = (t: string) => results.find((r) => r.table === t)?.removed ?? -1;

  // --- location_history ----------------------------------------------------
  ok(removed('location_history') >= 1, 'location_history: the old trail point was deleted');
  ok(await countRows('location_history WHERE child_id=$1 AND observed_at=$2', [RC, older('location_history')]) === 0, 'location_history: older than 90 days is gone');
  ok(await countRows('location_history WHERE child_id=$1 AND observed_at=$2', [RC, at('location_history')]) === 1, 'location_history: exactly 90 days old SURVIVES (< not <=)');
  ok(await countRows('location_history WHERE child_id=$1 AND observed_at=$2', [RC, newer('location_history')]) === 1, 'location_history: inside the window survives');

  // --- geofence_events -----------------------------------------------------
  ok(await countRows('geofence_events WHERE id=$1', [rid(1)]) === 0, 'geofence_events: the old crossing is gone');
  ok(await countRows('geofence_events WHERE id=$1', [rid(2)]) === 1, 'geofence_events: the crossing exactly at the cutoff SURVIVES');
  ok(await countRows('geofence_events WHERE id=$1', [rid(3)]) === 1, 'geofence_events: the recent crossing survives');

  // --- safety_alerts -------------------------------------------------------
  ok(await countRows('safety_alerts WHERE id=$1', [rid(11)]) === 0, 'safety_alerts: the alert past 12 months is gone');
  ok(await countRows('safety_alerts WHERE id=$1', [rid(12)]) === 1, 'safety_alerts: the alert exactly at 12 months SURVIVES');
  ok(await countRows('safety_alerts WHERE id=$1', [rid(13)]) === 1, "safety_alerts: this year's SOS survives");

  // --- audit_log -----------------------------------------------------------
  ok(await countRows('audit_log WHERE id=$1', [rid(21)]) === 0, 'audit_log: the entry past 3 years is gone');
  ok(await countRows('audit_log WHERE id=$1', [rid(22)]) === 1, 'audit_log: the entry exactly at 3 years SURVIVES');
  ok(await countRows('audit_log WHERE id=$1', [rid(23)]) === 1, 'audit_log: the recent access record survives');

  // --- phone_codes ---------------------------------------------------------
  ok(await countRows('phone_codes WHERE phone=$1', [`${RPHONE}01`]) === 0, 'phone_codes: created 30+ days ago is gone even though it has not expired');
  ok(await countRows('phone_codes WHERE phone=$1', [`${RPHONE}02`]) === 1, 'phone_codes: created an hour ago SURVIVES though it expired long ago — the sweep reads created_at, not expires_at');
  ok(await countRows('phone_codes WHERE phone=$1', [`${RPHONE}03`]) === 1, 'phone_codes: created exactly 30 days ago SURVIVES');

  // --- login_attempts (two tables, one period, one count) ------------------
  ok(await countRows('user_login_attempts WHERE phone=$1', [`${RPHONE}10`]) === 0, 'user_login_attempts: past 90 days is gone');
  ok(await countRows('user_login_attempts WHERE phone=$1', [`${RPHONE}11`]) === 1, 'user_login_attempts: exactly 90 days old SURVIVES');
  ok(await countRows('user_login_attempts WHERE phone=$1', [`${RPHONE}12`]) === 1, 'user_login_attempts: the recent attempt survives');
  ok(await countRows('staff_login_attempts WHERE phone=$1', [`${RPHONE}20`]) === 0, 'staff_login_attempts: past 90 days is gone (the same sweep reaches both tables)');
  ok(await countRows('staff_login_attempts WHERE phone=$1', [`${RPHONE}21`]) === 1, 'staff_login_attempts: exactly 90 days old SURVIVES');
  ok(await countRows('staff_login_attempts WHERE phone=$1', [`${RPHONE}22`]) === 1, 'staff_login_attempts: the recent attempt survives');
  ok(removed('login_attempts') >= 2, 'login_attempts: the returned count sums BOTH tables');

  // --- shop_leads ----------------------------------------------------------
  ok(await countRows('shop_leads WHERE id=$1', [rid(31)]) === 0, 'shop_leads: the lead past 12 months is gone');
  ok(await countRows('shop_leads WHERE id=$1', [rid(32)]) === 1, 'shop_leads: the lead exactly at 12 months SURVIVES');
  ok(await countRows('shop_leads WHERE id=$1', [rid(33)]) === 1, 'shop_leads: the recent lead survives');

  // --- support_tickets -----------------------------------------------------
  ok(await countRows('support_tickets WHERE id=$1', [T(1)]) === 0, 'support_tickets: a silent thread past 3 years is gone');
  ok(await countRows('support_tickets WHERE id=$1', [T(2)]) === 1, 'support_tickets: updated exactly 3 years ago SURVIVES');
  ok(await countRows('support_tickets WHERE id=$1', [T(3)]) === 1, 'support_tickets: the recent thread survives');
  ok(await countRows('support_tickets WHERE id=$1', [T(4)]) === 1, 'support_tickets: an OLD ticket with a RECENT reply survives (the NOT EXISTS clause)');
  ok(await countRows('support_replies WHERE id=$1', [rid(51)]) === 1, 'support_replies: that recent reply survives with its ticket');
  ok(await countRows('support_tickets WHERE id=$1', [T(5)]) === 0, 'support_tickets: an old ticket whose newest reply is also old is gone');
  ok(await countRows('support_replies WHERE id=$1', [rid(52)]) === 0, 'support_replies: its replies go with it (ON DELETE CASCADE)');
  ok(await countRows('support_tickets WHERE id=$1', [T(6)]) === 1, 'support_tickets: a reply exactly at the cutoff counts as activity, so the thread SURVIVES');
  ok(await countRows('support_replies WHERE id=$1', [rid(53)]) === 1, 'support_replies: that boundary reply survives too');
  ok(removed('support_tickets') === 2, 'support_tickets: the count is TICKETS, and exactly the two doomed threads');

  // --- what no sweep may touch --------------------------------------------
  ok(await countRows('shop_orders WHERE id=$1', [rid(61)]) === 1, 'shop_orders: a five-year-old order is untouched by all eight sweeps (RETENTION_KEPT — accounting)');
}

/** Take back everything the retention section planted and that survived. */
async function retentionCleanup() {
  await pool.query('DELETE FROM support_tickets WHERE phone LIKE $1', [`${RPHONE}%`]);
  await pool.query("DELETE FROM audit_log WHERE staff_id='smoke-retention'");
  await pool.query('DELETE FROM phone_codes WHERE phone LIKE $1', [`${RPHONE}%`]);
  await pool.query('DELETE FROM user_login_attempts WHERE phone LIKE $1', [`${RPHONE}%`]);
  await pool.query('DELETE FROM staff_login_attempts WHERE phone LIKE $1', [`${RPHONE}%`]);
  await pool.query('DELETE FROM shop_leads WHERE phone LIKE $1', [`${RPHONE}%`]);
  await pool.query('DELETE FROM shop_orders WHERE phone LIKE $1', [`${RPHONE}%`]);
  // children/geofences/location_history/safety_alerts cascade from users below.
}

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
  const reading = { deviceId: D_MAC, userId: U, recordedAt: '2026-07-24T08:00:00.000Z', systolicMmHg: 168, diastolicMmHg: 116, triageSeverity: 'emergency' };
  const first = await repo.insertHealthMetric(reading as never);
  const second = await repo.insertHealthMetric(reading as never);
  ok(first === false, 'first insert stores the reading (not a duplicate)');
  ok(second === true, 'identical resend is reported as a duplicate (ON CONFLICT DO NOTHING)');
  const cnt = await pool.query('SELECT count(*)::int AS n FROM pregnancy_health_metrics WHERE user_id=$1 AND device_id IS NOT NULL', [U]);
  ok(cnt.rows[0].n === 1, 'exactly one row stored despite two sends');

  console.log('manual reading (no device — the typed cuff path):');
  const manual = { deviceId: '', userId: U, recordedAt: '2026-07-24T12:00:00.000Z', systolicMmHg: 130, diastolicMmHg: 85, glucoseMmol: 8.2, triageSeverity: 'ok' };
  const m1 = await repo.insertHealthMetric(manual as never);
  const m2 = await repo.insertHealthMetric(manual as never);
  ok(m1 === false, 'a hand-typed reading (device_id NULL) is stored, not rejected by the uuid cast');
  ok(m2 === true, 'a resent manual reading dedups too (NULLS NOT DISTINCT)');
  const mcnt = await pool.query('SELECT count(*)::int AS n FROM pregnancy_health_metrics WHERE user_id=$1 AND device_id IS NULL', [U]);
  ok(mcnt.rows[0].n === 1, 'exactly one manual row despite two sends');

  console.log('restore: listManualVitals (device-less rows only):');
  const manualVitals = await repo.listManualVitals(U);
  ok(manualVitals.length === 1, 'returns only the hand-entered reading, not the band one');
  ok(manualVitals[0].glucoseMmol === 8.2 && manualVitals[0].systolicMmHg === 130, 'the manual reading carries its glucose + BP');

  console.log('sync writes + reads round-trip:');
  // No phone: it is the sign-in identity, not a profile field (see ProfileEdit).
  await repo.upsertProfile(U, { displayName: 'Aigerim', dueDate: '2026-11-14', locale: 'ru-KZ', birthDate: null, city: 'Almaty', doctorPhone: null, avgCycleLength: 28, avgPeriodLength: 5 } as never);
  const prof = await repo.getProfile(U);
  ok(prof?.displayName === 'Aigerim' && prof?.city === 'Almaty', 'profile upsert + read');

  await repo.recordSleep(U, { night: '2026-07-20', deepMin: 90, remMin: 70, lightMin: 260, awakeMin: 20 } as never);
  const sleep = await repo.listSleep(U, 7);
  ok(sleep.length >= 1 && sleep[0].deepMin === 90, 'sleep record + list');

  await repo.upsertAppointment(U, { id: 'aaaaaaaa-0000-0000-0000-000000000010', title: 'Ultrasound', at: '2026-08-01T09:00:00.000Z', note: '' } as never);
  const appts = await repo.listAppointments(U);
  ok(appts.some((a) => a.title === 'Ultrasound'), 'appointment upsert + list');

  await repo.insertBpCalibration(U, { systolicOffset: 8, diastolicOffset: 5, calibratedAt: '2026-07-22T10:00:00.000Z', cuffSystolic: 130, cuffDiastolic: 85, ppgSystolic: 122, ppgDiastolic: 80 } as never);
  const cal = await repo.latestBpCalibration(U);
  ok(cal?.systolicOffset === 8, 'BP calibration insert + read');

  console.log('admin reads (complex SQL, first run against real pg):');
  const list = await repo.adminListUsers('', 50, 0);
  ok(list.users.some((u) => u.id === U), 'adminListUsers returns the user');
  const detail = await repo.adminUserDetail(U);
  ok(!!detail && detail.children.some((c) => c.id === C), 'adminUserDetail assembles children');
  ok(!!detail && detail.latest.glucose === 8.2, 'adminUserDetail latest carries the manual glucose reading');

  console.log('remaining sync methods (first run against real pg):');
  await repo.recordWeight(U, { date: '2026-07-20', kg: 68.5 } as never);
  ok((await repo.listWeight(U, 30)).some((w) => w.kg === 68.5), 'weight record + list');

  const MED = 'aaaaaaaa-0000-0000-0000-000000000020';
  await repo.upsertMedication(U, { id: MED, name: 'Iron', dose: '30mg', perDay: 1 } as never);
  ok((await repo.listMedications(U)).some((m) => m.id === MED), 'medication upsert + list');
  await repo.upsertDose(U, { medId: MED, date: '2026-07-20', count: 1 } as never);
  ok((await repo.listDoses(U)).some((d) => d.medId === MED && d.count === 1), 'dose upsert + list');

  await repo.upsertGrowth(C, { at: '2026-07-20', weightKg: 3.4, heightCm: 51 } as never);
  ok((await repo.listGrowth(U)).some((g) => g.childId === C && g.heightCm === 51), 'child growth upsert + list');

  await repo.setVaccine(C, 'bcg', true);
  ok((await repo.listVaccines(U)).some((v) => v.childId === C && v.vaccineKey === 'bcg'), 'vaccine set + list');

  await repo.upsertChildEmergency(C, { bloodType: 'O+', allergies: 'penicillin', conditions: '', medications: '', doctorName: '', doctorPhone: '', contactName: '', contactPhone: '', notes: 'EpiPen' } as never);
  ok((await repo.listMedicalIds(U)).some((m) => m.childId === C && m.notes === 'EpiPen'), 'medical-ID upsert + list (with notes)');

  await repo.recordNewbornEvent(C, { at: '2026-07-20T06:00:00.000Z', kind: 'feed', detail: null, durationMin: 15 } as never);
  ok((await repo.listNewbornEvents(U, 20)).some((e) => e.childId === C && e.kind === 'feed'), 'newborn event record + list');

  await repo.upsertDayLog(U, { date: '2026-07-20', mood: 'good', symptoms: ['nausea'], kicks: 5, flow: null } as never);
  ok((await repo.listDayLogs(U, '2026-07-01', '2026-07-31')).some((d) => d.mood === 'good' && d.symptoms.includes('nausea')), 'cycle day-log upsert + list (array column)');

  await repo.recordKickSession(U, { endedAt: '2026-07-20T10:00:00.000Z', count: 10, durationSec: 1200 } as never);
  ok((await repo.listKickSessions(U, 14)).some((s) => s.count === 10), 'kick session record + list');
  await repo.recordContractionSession(U, { endedAt: '2026-07-20T11:00:00.000Z', count: 6, avgDurationSec: 45, avgIntervalSec: 300 } as never);
  ok((await repo.listContractionSessions(U, 14)).some((s) => s.count === 6), 'contraction session record + list');

  await repo.recordAlert(U, { childId: C, kind: 'left', zoneName: 'Home', at: '2026-07-20T12:00:00.000Z' } as never);
  ok((await repo.listAlerts(U, 50)).some((a) => a.zoneName === 'Home'), 'safety alert record + list');

  console.log('admin aggregate reads:');
  // `id` on this row is the BLE MAC the fleet screen shows; `deviceId` is the
  // primary key. Asserting on `id === D` passed only while nobody ran this.
  ok((await repo.adminDevices(100)).some((d) => d.deviceId === D && d.id === D_MAC), 'adminDevices returns the fleet row');
  const stats = await repo.childrenStats(new Date('2026-07-24').toISOString());
  ok(typeof stats.total === 'number' && stats.total >= 1, 'childrenStats aggregates');

  console.log('shop: products, atomic order, oversell guard, admin visibility:');
  const products = await repo.shopProducts();
  ok(products.some((p) => p.id === 'watch') && products.some((p) => p.id === 'tracker'), 'shopProducts returns both products');
  const watch = products.find((p) => p.id === 'watch')!;
  const variant = watch.variants[0];
  await repo.setShopVariantStock(variant.id, 2);
  const r1 = await repo.placeShopOrder({ customerName: 'Тест', phone: '+77000000000', city: 'Алматы', address: 'ул. Абая 1', items: [{ variantId: variant.id, qty: 1 }] });
  ok(r1.ok && r1.totalMinor === watch.priceMinor, 'order placed; total = product price');
  ok((await repo.adminShopVariants()).find((v) => v.id === variant.id)!.stock === 1, 'stock decremented by 1');
  const r2 = await repo.placeShopOrder({ customerName: 'Т', phone: '+77000000000', city: 'Алматы', address: 'ул', items: [{ variantId: variant.id, qty: 5 }] });
  ok(!r2.ok && r2.error === 'out_of_stock', 'oversell is blocked (out_of_stock)');
  ok((await repo.adminShopVariants()).find((v) => v.id === variant.id)!.stock === 1, 'stock unchanged after the blocked order (atomic rollback)');
  const orders = await repo.adminShopOrders(10);
  ok(orders.length >= 1 && orders[0].items[0].color === variant.color && orders[0].address === 'ул. Абая 1', 'order shows in admin with address + item snapshot');

  // Bundle: a watch + a tracker together are priced server-side, never by the
  // client. The per-pair discount is BUNDLE_DISCOUNT_MINOR — read from the
  // constant rather than repeated as a literal here, because it has already
  // moved once (to 0, when the landing stopped selling a discounted hardware
  // pair) and this script asserted the old 2 900 ₸ for as long as nobody ran it.
  const tracker = products.find((p) => p.id === 'tracker')!;
  const tVariant = tracker.variants[0];
  await repo.setShopVariantStock(variant.id, 1);
  await repo.setShopVariantStock(tVariant.id, 1);
  const rB = await repo.placeShopOrder({ customerName: 'Комплект', phone: '+77000000001', city: 'Астана', address: 'пр. Кабанбай 1', items: [{ variantId: variant.id, qty: 1 }, { variantId: tVariant.id, qty: 1 }] });
  ok(rB.ok && rB.discountMinor === BUNDLE_DISCOUNT_MINOR && rB.totalMinor === watch.priceMinor + tracker.priceMinor - BUNDLE_DISCOUNT_MINOR, `bundle order priced server-side (discount ${BUNDLE_DISCOUNT_MINOR})`);
  const bOrder = (await repo.adminShopOrders(10)).find((o) => o.customerName === 'Комплект');
  ok(!!bOrder && bOrder.discountMinor === BUNDLE_DISCOUNT_MINOR && bOrder.items.length === 2, 'bundle order shows in admin with its discount + both items');

  await retentionSweeps();

  // Clean up so the smoke test is repeatable.
  await retentionCleanup();
  await pool.query('DELETE FROM shop_orders WHERE customer_name IN ($1,$2,$3)', ['Тест', 'Т', 'Комплект']);
  await pool.query('DELETE FROM users WHERE id=$1', [U]);
  await pool.end();
  console.log(process.exitCode ? '\nSMOKE FAILED' : '\n✓ all pgRepository checks passed against real Postgres');
}
main().catch((e) => { console.error('smoke error:', e.message); process.exit(1); });
