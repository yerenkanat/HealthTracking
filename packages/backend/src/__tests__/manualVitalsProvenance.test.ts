/**
 * A restored reading must still say who measured it.
 *
 * `listManualVitals` selects `WHERE user_id = $1 AND device_id IS NULL`, so
 * every row it returns is hand-typed BY CONSTRUCTION — the server has always
 * known. It just never said so: the response carried the seven numbers and no
 * provenance at all.
 *
 * The app reads an absent `source` as a SENSOR reading, deliberately and
 * correctly (`BandTelemetry.sourceFromWire`) — an unlabelled stored row cannot
 * be shown to have come off a thermometer, and defaulting the other way would
 * hand a wrist estimate the one entitlement this product reserves for a real
 * instrument. Both halves are individually right; together they meant that a
 * woman who changed handsets got every thermometer reading she had ever typed
 * back labelled a wrist estimate. Then:
 *
 *   1. her measured 38.6 stops escalating — a device temperature is
 *      warning-only by ruling (docs/CLINICAL-REVIEW-WATCH.md);
 *   2. her typed readings drop out of the summary she shows a doctor, which now
 *      filters on provenance;
 *   3. the manual-diary card disappears for exactly the woman using it.
 *
 * None of it is visible on the phone where she typed the readings. It appears
 * only on the next one — which is why this is driven over HTTP end to end
 * against a real memory repository: the value of the fix is entirely in the
 * join, and a per-unit test of the repository would have passed either way.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

const USER = '11111111-1111-1111-1111-111111111111';
const BAND = 'AA:BB:CC:DD:EE:01';

let app: FastifyInstance;
let repo: Repository;

beforeEach(async () => {
  repo = createMemoryRepository();
  await repo.createDevice(USER, { id: BAND, name: 'GTS10', kind: 'band', childId: null });
  app = buildServer(
    {
      repo,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        resolveTransition: async () => null,
        sendEmergencyPush: async () => {},
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: USER }),
      authAdmin: async () => null,
    } as never,
    { logger: false },
  );
  await app.ready();
});
afterEach(async () => { await app.close(); });

const post = (items: unknown[]) =>
  app.inject({ method: 'POST', url: '/ingest/batch', payload: { items } });

type Restored = {
  recordedAt: string; source?: string; coreTempC: number | null; systolicMmHg: number | null;
};
const restore = async (): Promise<Restored[]> => {
  const r = await app.inject({ method: 'GET', url: '/vitals/manual' });
  expect(r.statusCode).toBe(200);
  return (r.json() as { readings: Restored[] }).readings;
};

// A thermometer reading she typed in, in the range that is entitled to escalate.
const TYPED_FEVER = {
  type: 'telemetry',
  payload: {
    source: 'manual', deviceId: '', recordedAt: '2026-08-10T06:30:00.000Z',
    coreTempC: 38.6,
  },
};

describe('GET /vitals/manual states the provenance its own WHERE clause guarantees', () => {
  it('labels a restored hand-typed reading `manual`', async () => {
    await post([TYPED_FEVER]);

    const readings = await restore();
    expect(readings).toHaveLength(1);
    expect(readings[0].coreTempC).toBe(38.6);
    expect(
      readings[0].source,
      'no provenance on the restore: the app reads an absent `source` as a wrist ' +
        'estimate, so this thermometer reading loses its emergency entitlement on ' +
        'her new phone — and nothing on the old one shows it',
    ).toBe('manual');
  });

  it('says it for every row, not only the newest', async () => {
    // The label travels with the ROW. A response that stated it once, at the
    // top, would restore one honest reading and a history of demoted ones.
    await post([
      TYPED_FEVER,
      {
        type: 'telemetry',
        payload: {
          source: 'manual', deviceId: '', recordedAt: '2026-08-09T21:00:00.000Z',
          systolicMmHg: 152, diastolicMmHg: 96,
        },
      },
    ]);

    const readings = await restore();
    expect(readings).toHaveLength(2);
    expect(readings.map((r) => r.source)).toEqual(['manual', 'manual']);
  });

  it('never returns a band reading, so the label can never be wrong', async () => {
    // The claim is only safe because the filter makes it true. If a device row
    // could reach this list, `source: 'manual'` would be a lie printed on a
    // wrist estimate — the mirror image of the defect above, and worse.
    await post([
      TYPED_FEVER,
      {
        type: 'telemetry',
        payload: { deviceId: BAND, recordedAt: '2026-08-10T07:00:00.000Z', coreTempC: 38.9 },
      },
    ]);

    const readings = await restore();
    expect(readings).toHaveLength(1);
    expect(readings[0].recordedAt).toBe('2026-08-10T06:30:00.000Z');
  });

  it('uses the exact word the app accepts, not a synonym', () => {
    // A value the app does not recognise is the same defect wearing a different
    // hat: `sourceFromWire` reads anything that is not literally 'manual' —
    // including 'MANUAL', 'typed', 'hand' — as a sensor, silently. So the word
    // is read out of the app's own decoder rather than restated here.
    const triage = readFileSync(
      fileURLToPath(new URL('../../../../app/lib/core/triage.dart', import.meta.url)),
      'utf8',
    );
    const decoder = triage.match(/sourceFromWire\(Object\?\s+v\)\s*=>\s*([\s\S]*?);/);
    expect(decoder, 'sourceFromWire moved — this pin no longer reads the app decoder').not.toBeNull();
    const accepted = decoder![1].match(/'([a-z]+)'/)?.[1];
    expect(accepted, 'the app decodes provenance from a literal this test could not find').toBe('manual');
  });
});
