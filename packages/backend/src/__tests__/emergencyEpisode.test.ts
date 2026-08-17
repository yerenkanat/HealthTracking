/**
 * The server pushed once per READING. It now pushes once per EPISODE.
 *
 * THE MEASUREMENT THAT STARTED THIS. Before any of the code under test existed,
 * five telemetry items one minute apart at 145/95 were driven through
 * `handleIngestBatch` with a counting push spy. The result was
 * `{telemetryCount: 5, emergencies: 5}` and FIVE calls to the spy. Each of
 * those is `critical: true` on the `medical_critical` channel — the one that
 * bypasses Do Not Disturb and plays `emergency.caf` at volume 1.0. The band
 * samples continuously and `TelemetryBatcher` drains an offline queue in a
 * single flush (maxBatch 500), so this is an hour of alarms for one condition,
 * or a whole backlog fired in one second when a phone reconnects.
 *
 * WHAT IS NOT BEING BUILT HERE, stated because the obvious next patch is the
 * wrong one. This is NOT a server-side port of `EmergencyConfirmation`. That
 * gate decides whether ONE sensor estimate may take over her screen, and its
 * answer to "not yet" is an in-app «take another reading» prompt, not silence.
 * The server has no middle branch — its choices are the critical push or
 * nothing — so copying the gate would substitute silence where the approved
 * policy substitutes a prompt. That is gating a warning, which the absorber
 * corollary in docs/CLINICAL-REVIEW-WATCH.md refuses in terms. Every test below
 * exists to pin the difference: a FIRST alert is never withheld, from any
 * source, at any freshness.
 *
 * Driven over HTTP against the real memory repository, because the decision
 * spans the wire schema, the handler and both repository implementations — and
 * a unit test of the handler with a stub repository is exactly the shape that
 * would pass while the query returned nothing.
 */

import { describe, it, expect, beforeEach, afterEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';
import type { Repository } from '../db/repository';
import { EMERGENCY_EPISODE_WINDOW_MS, emergencyFamily } from '../emergency/episode';

const USER = '11111111-1111-1111-1111-111111111111';
const BAND = 'AA:BB:CC:DD:EE:01';

/** Over 140/90 — `PREECLAMPSIA_BP`, emergency severity, from every source. */
const HIGH_BP = { systolicMmHg: 145, diastolicMmHg: 95 };

let app: FastifyInstance;
let repo: Repository;
/** The triage code of every emergency push that went out, in order. */
let pushed: string[];

function buildWith(r: Repository): FastifyInstance {
  return buildServer(
    {
      repo: r,
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        resolveTransition: async () => null,
        sendEmergencyPush: async (_u: string, triage: { findings: Array<{ code: string }> }) => {
          pushed.push(triage.findings[0]?.code ?? 'UNKNOWN');
        },
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: USER }),
      authAdmin: async () => null,
    } as never,
    { logger: false },
  );
}

beforeEach(async () => {
  repo = createMemoryRepository();
  await repo.createDevice(USER, { id: BAND, name: 'GTS10', kind: 'band', childId: null });
  pushed = [];
  app = buildWith(repo);
  await app.ready();
});
afterEach(async () => { await app.close(); });

/** One telemetry item, posted the way the batcher posts it. */
const post = (payload: Record<string, unknown>) =>
  app.inject({
    method: 'POST', url: '/ingest/batch',
    payload: { items: [{ type: 'telemetry', payload }] },
  });

/** A whole batch in one request — the offline-drain shape. */
const postAll = (payloads: Array<Record<string, unknown>>) =>
  app.inject({
    method: 'POST', url: '/ingest/batch',
    payload: { items: payloads.map((payload) => ({ type: 'telemetry', payload })) },
  });

const band = (minute: number, extra: Record<string, unknown>) => ({
  deviceId: BAND,
  recordedAt: `2026-08-17T09:${String(minute).padStart(2, '0')}:00.000Z`,
  ...extra,
});

describe('one alert per episode', () => {
  it('five band frames at 145/95, one minute apart, alarm her once', async () => {
    const items = [0, 1, 2, 3, 4].map((m) => band(m, HIGH_BP));
    for (const p of items) expect((await post(p)).statusCode).toBe(200);

    expect(
      pushed.length,
      'every crossing pushed its own critical, DND-bypassing notification — ' +
        'the alarm fatigue emergency_confirmation.dart names in its own header',
    ).toBe(1);
    expect(pushed[0]).toBe('PREECLAMPSIA_BP');
  });

  it('says so in the response rather than swallowing the four it held', async () => {
    const r = await postAll([0, 1, 2, 3, 4].map((m) => band(m, HIGH_BP)));
    expect(r.statusCode).toBe(200);
    const s = r.json();
    // A suppression nobody can count is a suppression nobody can audit.
    expect(s.emergencies, 'crossings').toBe(5);
    expect(s.repeatEmergencies, 'crossings that joined an episode already alerted').toBe(4);
    expect(s.emergencies - s.repeatEmergencies).toBe(pushed.length);
  });

  it('an offline backlog arriving in one flush is still one alert', async () => {
    // The whole batch in a single request: `maxBatch` is 500, so this is what a
    // phone that has been out of signal actually sends.
    await postAll([0, 2, 4, 6, 8, 10, 12, 14].map((m) => band(m, HIGH_BP)));
    expect(pushed.length).toBe(1);
  });
});

describe('what a first alert is, and that nothing withholds one', () => {
  it('a single band crossing pushes immediately — no confirmation is required', async () => {
    // THE LOAD-BEARING TEST. If someone ports EmergencyConfirmation to the
    // server, this is what turns red: one sensor estimate would produce no push
    // at all, which is silence where the phone shows «take another reading».
    await post(band(0, HIGH_BP));
    expect(
      pushed,
      'the server withheld the FIRST alert of an episode — that is gating a ' +
        'warning, not de-duplicating one',
    ).toEqual(['PREECLAMPSIA_BP']);
  });

  it('a new episode after the window pushes again', async () => {
    await post(band(0, HIGH_BP));
    // 31 minutes later: past EmergencyConfirmation.window, so the phone would
    // have expired the first crossing too. A separate condition, a separate
    // alert.
    await post({ ...band(0, HIGH_BP), recordedAt: '2026-08-17T09:31:00.000Z' });
    expect(pushed).toEqual(['PREECLAMPSIA_BP', 'PREECLAMPSIA_BP']);
  });

  it('a different measurement is a different episode', async () => {
    await post(band(0, HIGH_BP));
    await post(band(1, { spo2Pct: 84 }));
    expect(
      pushed,
      'a hypoxia emergency was swallowed by an unrelated blood-pressure alert',
    ).toEqual(['PREECLAMPSIA_BP', 'HYPOXIA_SEVERE']);
  });

  it('the ordinary threshold and then the severe one are ONE preeclampsia', async () => {
    await post(band(0, HIGH_BP));
    await post(band(1, { systolicMmHg: 168, diastolicMmHg: 114 }));
    // `emergencyFamily` groups PREECLAMPSIA_BP with PREECLAMPSIA_BP_SEVERE for
    // exactly this reason on the phone. It is the same condition getting worse,
    // and the push copy is identical either way — `emergencyCopy` sends one
    // title and one body for every code.
    expect(pushed).toEqual(['PREECLAMPSIA_BP']);
  });

  it('a reading she typed in is never held, even inside a band episode', async () => {
    await post(band(0, HIGH_BP));
    expect(pushed.length).toBe(1);
    // She saw the alert, put a cuff on, and typed what it said. That is the
    // confirmation the product asks her for, and it is the one source the
    // clinical gate grants full emergency weight.
    const r = await post({
      deviceId: '', source: 'manual',
      recordedAt: '2026-08-17T09:03:00.000Z',
      systolicMmHg: 168, diastolicMmHg: 114,
    });
    expect(r.statusCode).toBe(200);
    expect(
      pushed.length,
      'her cuff reading was folded into the band\'s episode and silenced',
    ).toBe(2);
    expect(r.json().repeatEmergencies).toBe(0);
  });

  it('a band frame AFTER her typed reading is still a repeat', async () => {
    await post({
      deviceId: '', source: 'manual',
      recordedAt: '2026-08-17T09:00:00.000Z', ...HIGH_BP,
    });
    await post(band(2, HIGH_BP));
    expect(pushed.length, 'the band re-stated what she had just been alerted about').toBe(1);
  });
});

describe('the evidence, and the direction it errs in', () => {
  it('readings that arrive out of order still produce one alert', async () => {
    // A requeued batch, or two handsets on one account. Keyed on arrival order,
    // each of these is "the first crossing the server saw" and both alert.
    await post(band(5, HIGH_BP));
    await post(band(0, HIGH_BP));
    expect(pushed.length).toBe(1);
  });

  it('a repository failure pushes rather than staying quiet', async () => {
    await app.close();
    const broken: Repository = {
      ...repo,
      recentEmergencyReadings: async () => { throw new Error('db down'); },
    };
    app = buildWith(broken);
    await app.ready();
    await post(band(0, HIGH_BP));
    await post(band(1, HIGH_BP));
    expect(
      pushed.length,
      'a database hiccup silenced an emergency — the suppression must fail toward sending',
    ).toBe(2);
  });

  it('a stored grade is not evidence — the values are re-judged by TODAY\'s rules', async () => {
    // The stored `triage_severity` is whatever the rules said on the day the
    // row was written, and those rules change: the 2026-08-13 ruling stopped a
    // device temperature raising `emergency`, and every row written before it
    // is still in the table saying `emergency`. Trusting the column would let a
    // retired verdict go on swallowing live alerts, for as long as the rows
    // live.
    //
    // The row below is graded `emergency` while carrying only a sleeping SpO2
    // of 93 — which today is HYPOXIA_SLEEP, a warning. It is in the `spo2`
    // family either way, so if `familyOfStored` reported a family without first
    // checking that the replay still finds an emergency, this row would silence
    // the real hypoxia five minutes later.
    await repo.insertHealthMetric({
      deviceId: BAND, userId: USER,
      recordedAt: '2026-08-17T08:55:00.000Z',
      spo2Pct: 93, duringSleep: true, triageSeverity: 'emergency',
    });
    await post(band(0, { spo2Pct: 84 }));
    expect(
      pushed,
      'a row graded by a retired rule was treated as a live episode and ' +
        'suppressed a genuine one',
    ).toEqual(['HYPOXIA_SEVERE']);
  });

  it('a resent batch is still not a second alert', async () => {
    // The pre-existing duplicate guard, re-asserted here because the episode
    // rule now sits behind it: a resend must be caught by `insertHealthMetric`
    // returning true, never by the episode lookup, or `duplicates` and
    // `repeatEmergencies` would start reporting each other's work.
    const p = band(0, HIGH_BP);
    await post(p);
    const again = await post(p);
    expect(again.json().duplicates).toBe(1);
    expect(again.json().repeatEmergencies).toBe(0);
    expect(pushed.length).toBe(1);
  });
});

describe('the Postgres query names columns that exist', () => {
  const root = fileURLToPath(new URL('../../', import.meta.url));
  const schema = readFileSync(`${root}db/schema.sql`, 'utf8');
  const pg = readFileSync(`${root}src/db/pgRepository.ts`, 'utf8');

  it('every column recentEmergencyReadings selects is in schema.sql', () => {
    // Nothing in this suite executes the pg SELECT — there is no Postgres in
    // the test environment — so a mistyped column name would reach production
    // untouched. And it would fail QUIETLY: the handler catches a throwing
    // repository and pushes, so the symptom is the storm coming back on the
    // live server while the memory-repository suite stays green. This parses
    // both files instead.
    //
    // No migration and no new column: the query reads what
    // `pregnancy_health_metrics` already stores, and idx_phm_user_time
    // (user_id, recorded_at DESC) already serves it.
    // Anchored on `device_id IS NULL AS manual`, which only this query has.
    // Anchoring on `SELECT recorded_at` instead matched from listManualVitals's
    // SELECT all the way through this one, so the span contained a `core_temp_c`
    // belonging to the OTHER query and a typo here passed — found by reverting.
    const select = pg.match(
      /SELECT recorded_at, device_id IS NULL AS manual[\s\S]*?ORDER BY recorded_at DESC`/,
    );
    expect(select, 'the recentEmergencyReadings query was not found — this guard parses nothing')
      .not.toBeNull();

    const table = schema.match(/CREATE TABLE pregnancy_health_metrics\s*\(([\s\S]*?)\n\);/);
    expect(table, 'pregnancy_health_metrics was not found in schema.sql').not.toBeNull();

    for (const col of [
      'recorded_at', 'device_id', 'core_temp_c', 'heart_rate_bpm',
      'spo2_pct', 'systolic_mmhg', 'diastolic_mmhg', 'during_sleep',
      'user_id', 'triage_severity',
    ]) {
      expect(select![0], `${col} is not read by the query`).toContain(col);
      expect(
        new RegExp(`^\\s*${col}\\s`, 'm').test(table![1]),
        `the query reads ${col}, which pregnancy_health_metrics does not have`,
      ).toBe(true);
    }
  });

  it('reads provenance the only way Postgres stores it', () => {
    // There is no `source` column. `device_id IS NULL` is the whole of what the
    // database knows about where a reading came from — the same rule
    // listManualVitals states — and it has to travel, because the episode rule
    // replays assessTelemetry and the fever branch reads provenance.
    expect(pg).toMatch(/device_id IS NULL AS manual/);
    expect(schema).not.toMatch(/\n\s+source\s+\w+[\s\S]{0,80}?pregnancy_health_metrics/);
  });
});

describe('the episode window is the app\'s own number', () => {
  const dart = readFileSync(
    fileURLToPath(new URL('../../../../app/lib/domain/emergency_confirmation.dart', import.meta.url)),
    'utf8',
  );

  it('matches EmergencyConfirmation.window in the Dart source', () => {
    // Not a number invented on this side. It is «How long a crossing stays
    // pending. Past this it is treated as a one-off» — the same quantity read
    // from the other end, and if either side moves the two stop agreeing about
    // where one episode ends.
    const m = dart.match(/this\.window\s*=\s*const Duration\(minutes:\s*(\d+)\)/);
    expect(m, 'EmergencyConfirmation.window was not found — this guard parses nothing').not.toBeNull();
    expect(EMERGENCY_EPISODE_WINDOW_MS).toBe(Number(m![1]) * 60 * 1000);
  });

  it('groups codes exactly as the Dart emergencyFamily does', () => {
    // The two functions are twins and the rules are load-bearing on both sides:
    // `endsWith('FEVER')` is why the device-temperature code is named
    // DEVICE_TEMP_HIGH rather than DEVICE_FEVER.
    for (const [pattern, family] of [
      ['PREECLAMPSIA_BP', 'bp'], ['PREECLAMPSIA_BP_SEVERE', 'bp'],
      ['HIGH_FEVER', 'fever'], ['LOW_FEVER', 'fever'],
      ['HYPOXIA_SEVERE', 'spo2'], ['HYPOXIA_SLEEP', 'spo2'],
      ['TACHYCARDIA_SEVERE', 'hr'], ['BRADYCARDIA_SEVERE', 'hr'],
    ] as const) {
      expect(emergencyFamily(pattern), pattern).toBe(family);
    }
    // A code nobody has classified stands alone rather than joining someone
    // else's episode — the safe default, and the same one the Dart file takes.
    expect(emergencyFamily('DEVICE_TEMP_HIGH')).toBe('DEVICE_TEMP_HIGH');
    expect(emergencyFamily(null)).toBeNull();
    expect(emergencyFamily(undefined)).toBeNull();

    for (const rule of [
      "code.startsWith('PREECLAMPSIA_BP')", "code.endsWith('FEVER')",
      "code.startsWith('HYPOXIA')", "code.startsWith('TACHY')", "code.startsWith('BRADY')",
    ]) {
      expect(dart, `the Dart twin no longer contains ${rule}`).toContain(rule);
    }
  });
});
