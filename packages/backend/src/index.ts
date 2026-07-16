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
    // TODO(auth): verify a Firebase ID token from the Authorization header.
    // Dev stub: trust an x-user-id header. DO NOT ship this to production.
    authUser: async (req) => {
      const id = req.headers['x-user-id'];
      return typeof id === 'string' && id.length > 0 ? { userId: id } : null;
    },
    // TODO(auth): verify a staff session/JWT with RBAC claims.
    // Dev stub: trust x-staff-id + x-staff-role headers. DO NOT ship this.
    authAdmin: async (req) => {
      const id = req.headers['x-staff-id'];
      const role = req.headers['x-staff-role'];
      const roles = ['admin', 'clinician', 'support'];
      return typeof id === 'string' && id.length > 0 && typeof role === 'string' && roles.includes(role)
        ? { staffId: id, role: role as 'admin' | 'clinician' | 'support' }
        : null;
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
