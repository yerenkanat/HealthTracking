/**
 * Composition root — wires the real collaborators into buildServer() and listens.
 * This is the ONLY place that knows about pg + Redis + firebase + Anthropic all at
 * once; every other module depends on interfaces, which is what made the safety
 * logic testable with fakes.
 */

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { FastifyRequest } from 'fastify';
import { buildServer } from './server';
import type { ServerDeps } from './server';
import { createMemoryRepository } from './db/memoryRepository';
import { makeAuthUser } from './http/auth';
import type { BandTelemetry, ChildLocationFix } from '@fcs/shared';
import { assessTelemetry } from '@fcs/shared';

const REAL_AUTH = process.env.REAL_AUTH === '1';

/** Verifies a Firebase ID token → uid. Null until wired in production (needs a
 * service account); firebase-admin is loaded lazily so dev never touches it. */
let verifyIdToken: ((token: string) => Promise<string | null>) | undefined;
async function initFirebaseAuth(): Promise<void> {
  if (!REAL_AUTH || verifyIdToken) return;
  const admin = await import('firebase-admin');
  if (!admin.apps.length) admin.initializeApp();
  verifyIdToken = async (t) => {
    const decoded = await admin.auth().verifyIdToken(t);
    return decoded.uid;
  };
}

// NOTE: pg / Redis / Anthropic / push are imported *dynamically* inside
// productionDeps() so memory mode (npm run dev) never loads them — importing the
// Redis module eagerly connects a client, which we must avoid without a stack.

// Verifies a Bearer token (Firebase in prod) and, in dev, honours the app's
// stub session token so real sign-in works against the in-memory backend. Falls
// back to the x-user-id dev header. See http/auth.ts.
const authUser = (req: FastifyRequest) =>
  makeAuthUser({ verifyIdToken, allowStubToken: !REAL_AUTH })(req);
// TODO(auth): verify a staff session/JWT with RBAC claims.
// Dev stub: trust x-staff-id + x-staff-role headers. DO NOT ship this.
const authAdmin = async (req: FastifyRequest) => {
  const id = req.headers['x-staff-id'];
  const role = req.headers['x-staff-role'];
  const roles = ['admin', 'clinician', 'support'];
  return typeof id === 'string' && id.length > 0 && typeof role === 'string' && roles.includes(role)
    ? { staffId: id, role: role as 'admin' | 'clinician' | 'support' }
    : null;
};

/** Real deps: pg + Redis + Anthropic + push (loaded lazily). */
async function productionDeps(): Promise<ServerDeps> {
  const { Pool } = await import('pg');
  const { createPgRepository } = await import('./db/pgRepository');
  const { createAnthropicCaller } = await import('./ai/anthropicClient');
  const { getChildLastLocation, setChildLastLocation, setBpCalibration, resolveTransition } = await import('./cache/redis');
  const { emergencyCopy, geofenceCopy, sendPush, toPushLocale } =
    await import('./notifications/push');
  type PushResult = Awaited<ReturnType<typeof sendPush>>;
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const repo = createPgRepository(pool);

  /// Forget dead tokens, and SAY when a push did not land.
  ///
  /// sendPush reports instead of throwing, so without this the result would be
  /// discarded and a failed emergency notification would leave no trace at all
  /// — the one push in the product where nobody finding out is the whole
  /// problem.
  async function afterPush(kind: string, res: PushResult): Promise<void> {
    for (const token of res.dead) {
      // pruneToken() used to live in push.ts as an empty function with a
      // comment saying to wire it to the database. Nobody did, so tokens from
      // reinstalled apps accumulated and quietly swallowed every push.
      await repo.deletePushToken(token).catch(() => {});
    }
    if (res.error || res.failed > 0) {
      console.warn(
        `push(${kind}): ${res.sent} delivered, ${res.failed} failed` +
          (res.error ? ` — ${res.error}` : '') +
          (res.dead.length ? `, ${res.dead.length} dead token(s) removed` : ''),
      );
    }
  }
  return {
    repo,
    guardrail: { callLLM: createAnthropicCaller() },
    ingest: {
      cacheLocation: (fix: ChildLocationFix) => setChildLastLocation(fix),
      resolveTransition: (childId, fenceId, inside) => resolveTransition(childId, fenceId, inside),
      sendEmergencyPush: async (userId, triage) => {
        const { tokens, locale } = await repo.guardianPushTokensForUser(userId);
        const res = await sendPush(tokens, emergencyCopy(triage, toPushLocale(locale)));
        await afterPush('emergency', res);
      },
      sendGeofencePush: async (evt) => {
        const { tokens, childName, locale } = await repo.guardianPushTokens(evt.childId);
        const res = await sendPush(tokens, geofenceCopy(evt, childName, toPushLocale(locale)));
        await afterPush('geofence', res);
      },
    },
    authUser,
    authAdmin,
    // Readiness: the DB answers a trivial query. (Redis failure degrades to the
    // DB path rather than taking the service down, so it is not gated here.)
    checkReady: async () => {
      try {
        await pool.query('SELECT 1');
        return { ready: true, deps: { postgres: true } };
      } catch {
        return { ready: false, deps: { postgres: false } };
      }
    },
    cacheLastLocation: (childId) => getChildLastLocation(childId),
    setBpCalibration: (userId, offsets) =>
      setBpCalibration(userId, {
        systolicOffset: offsets.systolicOffset,
        diastolicOffset: offsets.diastolicOffset,
        calibratedAt: offsets.calibratedAt,
      }),
    cryAnalyze: forwardCry,
  };
}

/** Forward a recorded cry clip to the internal cry-classifier service
 * (CRY_API_URL) verbatim and return its JSON. Used by POST /cry/analyze. */
async function forwardCry(audio: Buffer, contentType: string): Promise<unknown> {
  const base = process.env.CRY_API_URL ?? 'http://localhost:8000';
  const res = await fetch(`${base}/api/v1/predict-cry`, {
    method: 'POST',
    headers: { 'content-type': contentType },
    body: new Uint8Array(audio), // fetch's BodyInit doesn't accept Buffer directly
  });
  if (!res.ok) throw new Error(`cry-classifier ${res.status}`);
  return res.json();
}

/** In-memory deps: no external services — for `npm run dev` on test data. */
function memoryDeps(): ServerDeps {
  const repo = createMemoryRepository();
  const lastLoc = new Map<string, ChildLocationFix>();
  const fenceState = new Map<string, 'in' | 'out'>();
  return {
    repo,
    guardrail: { callLLM: async () => 'Rest and hydrate gently. (dev echo — set an ANTHROPIC key for real replies)' },
    ingest: {
      cacheLocation: async (fix) => void lastLoc.set(fix.childId, fix),
      resolveTransition: async (childId, fenceId, inside) => {
        const key = `${childId}:${fenceId}`;
        const next = inside ? 'in' : 'out';
        const prev = fenceState.get(key) ?? null;
        fenceState.set(key, next);
        if (prev === next) return null;
        if (prev === null && next === 'out') return null;
        return inside ? 'enter' : 'exit';
      },
      sendEmergencyPush: async () => {},
      sendGeofencePush: async () => {},
    },
    authUser,
    authAdmin,
    cacheLastLocation: async (childId) => lastLoc.get(childId) ?? null,
    setBpCalibration: async () => {},
    cryAnalyze: forwardCry, // works in dev too if a CRY_API_URL is reachable
  };
}

async function main(): Promise<void> {
  await initFirebaseAuth(); // wires real token verification when REAL_AUTH=1
  const memoryMode = process.env.USE_MEMORY_DB === 'true' || !process.env.DATABASE_URL;
  const app = buildServer(memoryMode ? memoryDeps() : await productionDeps());
  if (memoryMode) {
    app.log.warn('USE_MEMORY_DB / no DATABASE_URL → in-memory repository (dev only; data is not persisted)');
  }

  // Guard: never let a broken triage import ship. Fail fast at boot.
  const probe = assessTelemetry({ deviceId: 'boot', recordedAt: new Date(0).toISOString(), systolicMmHg: 145 } as BandTelemetry);
  if (!probe.forceEmergencyScreen) throw new Error('Triage self-check failed at boot');

  // Serve the admin dashboard (static HTML) at /admin/ui. It calls the /admin API
  // same-origin with the staff headers. Loaded once at boot.
  try {
    const adminBody = readFileSync(fileURLToPath(new URL('../../admin/index.html', import.meta.url)), 'utf8');
    const adminHtml = `<!doctype html><html lang="en"><head><meta charset="utf-8">` +
      `<meta name="viewport" content="width=device-width,initial-scale=1">` +
      `<title>Umay Back-office</title></head><body>${adminBody}</body></html>`;
    app.get('/admin/ui', async (_req, reply) => reply.type('text/html').send(adminHtml));
    // The page carries the stub staff headers in its own source, so serving it
    // IS granting admin: anyone who can reach this route can read every
    // family's data and edit what every user sees. The default bind is
    // 127.0.0.1 and production refuses to start on stub auth, but neither is
    // obvious from a log that says nothing.
    app.log.warn(
      '/admin/ui is served with NO authentication and the page embeds the ' +
        'staff header stub — reaching this route is equivalent to admin access. ' +
        'Local development only.',
    );
  } catch {
    app.log.warn('admin dashboard html not found; /admin/ui disabled');
  }

  // ---- Refuse to serve real users with fake authentication ----
  //
  // authUser and authAdmin are header stubs: `x-user-id`, and `x-staff-id` plus
  // `x-staff-role`. Anyone who can reach this port can claim to be an admin by
  // typing a header, and read every family's data, every child's location and
  // the whole content catalogue. That is fine on a laptop and catastrophic
  // anywhere else.
  //
  // A TODO comment does not stop a deploy. This does.
  const usingStubAuth = !process.env.REAL_AUTH;
  if (usingStubAuth && process.env.NODE_ENV === 'production') {
    app.log.fatal(
      'Refusing to start: authentication is still the development header stub ' +
        '(x-user-id / x-staff-role), which anyone can forge. Wire real token ' +
        'verification and set REAL_AUTH=1.',
    );
    process.exit(1);
  }

  // Localhost by DEFAULT. It bound to 0.0.0.0, which put a server trusting a
  // forgeable admin header on every network the machine was joined to — a
  // café's Wi-Fi is enough. Set HOST explicitly to widen it, which at least
  // makes the exposure a decision someone made.
  const port = Number(process.env.PORT ?? 8080);
  const host = process.env.HOST ?? '127.0.0.1';
  await app.listen({ port, host });
  if (usingStubAuth) {
    app.log.warn(
      `Development authentication in use — any caller can claim any identity. ` +
        `Listening on ${host}:${port}.`,
    );
  }
  app.log.info(`FCS backend listening on ${host}:${port}`);
}

main().catch((err) => {
  console.error('fatal', err);
  process.exit(1);
});
