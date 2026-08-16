/**
 * The watch's own temperature now reaches the server — and stops there.
 *
 * `BandTelemetry.deviceTempC` was introduced at ed2a0d0 when the Starmax value
 * was deliberately moved OUT of `coreTempC`: the vendor names the quantity
 * (`当前体温`) and states neither a measurement site nor an accuracy, so there is
 * no defensible conversion to a core estimate. The app has been sending it on
 * every batch since. Zod strips keys a schema does not name, so it died at the
 * edge: the number reached her chart and her advisor on the handset and was
 * stored nowhere, for anyone.
 *
 * Two things have to be true at once, and the second is why this file is not
 * simply "carry one more field":
 *
 *   1. it must survive the wire and reach the repository;
 *   2. it must NEVER be graded as a core temperature — not written to
 *      `coreTempC`, not merged into it on read, not fed to triage. A device
 *      path may not raise `emergency` on a temperature (the room, the bedding
 *      and the strap are the dominant error terms and none of them is an input
 *      to the conversion), and the clinician's «температура» must keep meaning
 *      an estimate of her core. See docs/CLINICAL-REVIEW-WATCH.md, "Device
 *      temperature — closed 2026-08-13".
 *
 * Driven over HTTP against a real memory repository, because the defect was at
 * the edge: every unit test of the ingest handler passed while the field never
 * arrived.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import {
  createMemoryRepository, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD,
} from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';

const USER = '11111111-1111-1111-1111-111111111111';
const BAND = 'AA:BB:CC:DD:EE:01';
const REASON = 'разбор жалобы на температуру';

let app: FastifyInstance;
let repo: Repository;
let cookie: string;
/** Every reading that reached the repository, as it reached it. */
let stored: Array<Record<string, unknown>>;
let pushes: number;

beforeEach(async () => {
  repo = createMemoryRepository();
  await repo.createDevice(USER, { id: BAND, name: 'GTS10', kind: 'band', childId: null });
  stored = [];
  pushes = 0;
  // A thin spy over the REAL repository: the question is what survived the wire
  // schema, and the answer is whatever the repository is handed. Everything
  // else still goes to the memory implementation, so the reads below are the
  // ones production performs.
  const spied: Repository = {
    ...repo,
    insertHealthMetric: async (m) => {
      stored.push(m as unknown as Record<string, unknown>);
      return repo.insertHealthMetric(m);
    },
  };
  app = buildServer(
    {
      repo: spied,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        resolveTransition: async () => null,
        sendEmergencyPush: async () => { pushes++; },
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: USER }),
      authAdmin: async (req: { headers: { cookie?: string } }) => {
        const token = readSessionCookie(req.headers.cookie);
        if (!token) return null;
        return repo.staffBySessionToken(hashToken(token));
      },
    } as never,
    { logger: false },
  );
  await app.ready();
  const res = await app.inject({
    method: 'POST', url: '/admin/login',
    payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
  });
  cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
});
afterEach(async () => { await app.close(); });

const post = (payload: Record<string, unknown>) =>
  app.inject({
    method: 'POST', url: '/ingest/batch',
    payload: { items: [{ type: 'telemetry', payload }] },
  });

/** A watch reading whose only temperature is the site-less device one. */
const WATCH = {
  deviceId: BAND, recordedAt: '2026-08-11T09:00:00.000Z',
  deviceTempC: 39.2, heartRateBpm: 88,
};

describe('POST /ingest/batch carries the device temperature instead of dropping it', () => {
  it('the value survives the wire schema and reaches the repository', async () => {
    const r = await post(WATCH);
    expect(r.statusCode).toBe(200);
    expect(r.json().telemetryCount).toBe(1);

    expect(stored).toHaveLength(1);
    expect(
      stored[0].deviceTempC,
      'zod strips keys a schema does not name — the watch temperature reached her ' +
        'chart and her advisor and then died at the edge of the server',
    ).toBe(39.2);
  });

  it('does not become a core temperature anywhere along the way', async () => {
    await post(WATCH);
    expect(
      stored[0].coreTempC,
      'folded into coreTempC, the site-less reading becomes an estimate of her ' +
        'core — the exact conversion the vendor gives no grounds for',
    ).toBeUndefined();

    // And the back office, which is the untrained reader here, still sees no
    // temperature: `adminUserHealth` reads core_temp_c alone, and a 39.2 that
    // appeared under «температура» would be a fever verdict the product has
    // ruled it may not state from a wrist.
    const h = await app.inject({
      method: 'GET',
      // The mother card's own read. `/admin/users/:id/health` served exactly
      // this `latest` and was deleted as a duplicate (docs/BACKLOG.md §3);
      // `/detail` calls the same `adminUserHealth` and is what the panel opens.
      url: `/admin/users/${USER}/detail?reason=${encodeURIComponent(REASON)}`,
      headers: { cookie },
    });
    expect(h.statusCode).toBe(200);
    expect(h.json().latest.temp).toBeNull();
  });

  it('raises no emergency, at a value that would be one from a thermometer', async () => {
    // 39.2 is over every fever threshold this product holds. From a typed
    // thermometer reading it escalates; from a wrist it may not, and storing
    // the wrist value must not quietly create a second route to the same push.
    await post(WATCH);
    expect(pushes, 'a device temperature raised an emergency').toBe(0);
    expect(stored[0].triageSeverity).toBe('ok');
  });

  it('does not reappear in the hand-typed restore', async () => {
    // GET /vitals/manual is the thermometer diary. A band row cannot enter it
    // (device_id IS NULL), and this is the assertion that keeps the new column
    // from arriving there by another door — labelled `manual`, which would be
    // the provenance defect inverted.
    await post(WATCH);
    const r = await app.inject({ method: 'GET', url: '/vitals/manual' });
    expect(r.statusCode).toBe(200);
    expect((r.json() as { readings: unknown[] }).readings).toEqual([]);
  });

  it('rejects only the impossible: a mis-decoded frame, never an alarming body', async () => {
    // The raw field is a u16 at a tenth of a degree, so a corrupt frame reads
    // 400 °C. It must not be stored; 42 °C must be.
    const bad = await post({ ...WATCH, deviceTempC: 400 });
    expect(bad.statusCode).toBe(400);

    const hot = await post({ ...WATCH, recordedAt: '2026-08-11T10:00:00.000Z', deviceTempC: 42 });
    expect(hot.statusCode).toBe(200);
    expect(stored.at(-1)!.deviceTempC).toBe(42);
  });
});

describe('the wire bound and the column CHECK are one decision', () => {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const schema = readFileSync(`${root}db/schema.sql`, 'utf8');
  const migration = readFileSync(`${root}db/migrations/048_device_temp.sql`, 'utf8');

  it('both schema.sql and the migration create the column', () => {
    // schema.sql builds a fresh database; the migration brings an existing one
    // to the same state. A column in only one of them means either new installs
    // or upgraded installs write to a column that is not there.
    expect(schema).toMatch(/device_temp_c\s+REAL/i);
    expect(migration).toMatch(/add column if not exists device_temp_c/i);
  });

  it('the CHECK matches the wire bound exactly, in both files', () => {
    // The telemetry path has no `plausible()` filter between the schema and the
    // INSERT — unlike the wearable path, the zod bound IS the guard. A CHECK
    // narrower than the wire fails the write, the batch-level catch counts the
    // item `rejected`, and the client resends that same reading for ever; a
    // CHECK wider is a bound that is not enforced where it is written down.
    const server = readFileSync(`${root}src/server.ts`, 'utf8');
    const wire = server.match(/deviceTempC:\s*z\.number\(\)\.finite\(\)\.min\((\d+)\)\.max\((\d+)\)/);
    expect(wire, 'the deviceTempC wire bound was not found — this guard parses nothing').not.toBeNull();

    for (const [where, sql] of [['schema.sql', schema], ['048_device_temp.sql', migration]] as const) {
      const check = sql.match(/device_temp_c\s+BETWEEN\s+(\d+)\s+AND\s+(\d+)/i);
      expect(check, `no CHECK on device_temp_c in ${where}`).not.toBeNull();
      expect([check![1], check![2]], `wire and CHECK disagree in ${where}`)
        .toEqual([wire![1], wire![2]]);
    }
  });
});
