/**
 * Composition root — wires the real collaborators into buildServer() and listens.
 * This is the ONLY place that knows about pg + Redis + firebase + Anthropic all at
 * once; every other module depends on interfaces, which is what made the safety
 * logic testable with fakes.
 */

import { Pool } from 'pg';
import { buildServer } from './server';
import { createPgRepository } from './db/pgRepository';
import { createAnthropicCaller } from './ai/anthropicClient';
import {
  getChildLastLocation,
  setChildLastLocation,
  setBpCalibration,
  resolveTransition,
} from './cache/redis';
import { emergencyCopy, geofenceCopy, sendPush } from './notifications/push';
import type { BandTelemetry, ChildLocationFix } from '@fcs/shared';
import { assessTelemetry } from '@fcs/shared';

async function main(): Promise<void> {
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const repo = createPgRepository(pool);

  const app = buildServer({
    repo,
    guardrail: { callLLM: createAnthropicCaller() },
    ingest: {
      cacheLocation: (fix: ChildLocationFix) => setChildLastLocation(fix),
      resolveTransition: (childId, fenceId, inside) => resolveTransition(childId, fenceId, inside),
      sendEmergencyPush: async (userId, triage) => {
        const tokens = await repo.guardianPushTokensForUser(userId);
        await sendPush(tokens, emergencyCopy(triage));
      },
      sendGeofencePush: async (evt) => {
        const { tokens, childName } = await repo.guardianPushTokens(evt.childId);
        await sendPush(tokens, geofenceCopy(evt, childName));
      },
    },
    cacheLastLocation: (childId) => getChildLastLocation(childId),
    setBpCalibration: (userId, offsets) =>
      setBpCalibration(userId, {
        systolicOffset: offsets.systolicOffset,
        diastolicOffset: offsets.diastolicOffset,
        calibratedAt: offsets.calibratedAt,
      }),
  });

  // Guard: never let a broken triage import ship. Fail fast at boot.
  const probe = assessTelemetry({ deviceId: 'boot', recordedAt: new Date(0).toISOString(), systolicMmHg: 145 } as BandTelemetry);
  if (!probe.forceEmergencyScreen) throw new Error('Triage self-check failed at boot');

  const port = Number(process.env.PORT ?? 8080);
  await app.listen({ port, host: '0.0.0.0' });
  app.log.info(`FCS backend listening on :${port}`);
}

main().catch((err) => {
  console.error('fatal', err);
  process.exit(1);
});
