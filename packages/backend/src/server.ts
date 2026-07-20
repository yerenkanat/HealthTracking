/**
 * Fastify HTTP surface — the endpoints the Flutter app talks to.
 *   POST /ingest/batch            ← TelemetryBatcher flushes here
 *   POST /ai/chat                 ← guardrailed assistant
 *   POST /calibration/bp          ← weekly cuff reading → PPG offsets
 *   GET  /children/:id/location   ← last known location (Redis)
 *   GET  /health                  ← liveness
 *
 * `buildServer(deps)` takes injected collaborators so the same app can run against
 * real Postgres/Redis/Anthropic in prod and fakes in tests (fastify.inject()).
 * Specialists: Backend Engineer + DevOps + Cybersecurity (validation at the edge).
 */

import Fastify, { type FastifyInstance, type FastifyReply, type FastifyRequest } from 'fastify';
import { z } from 'zod';
import { checkGeofenceBoundary } from './geofence/geofence';
import { handleIngestBatch, type IngestDeps } from './routes/ingestHandler';
import {
  processWithGuardrails,
  type GuardrailDeps,
} from './ai/AIGuardrailProcessor';
import { computeBpOffsets } from './health/bpCalibration';
import { registerCrudRoutes, type AuthUser } from './routes/crud';
import { registerAdminRoutes, type AuthAdmin } from './routes/admin';
import type { Repository } from './db/repository';

export interface ServerDeps {
  repo: Repository;
  ingest: Omit<IngestDeps, 'repo' | 'checkInside'>;
  guardrail: GuardrailDeps;
  cacheLastLocation: (childId: string) => Promise<unknown>;
  setBpCalibration: (userId: string, offsets: { systolicOffset: number; diastolicOffset: number; calibratedAt: string }) => Promise<void>;
  /** Resolve the caller's user from the request (verify Firebase token in prod). */
  authUser?: AuthUser;
  /** Resolve the caller's staff identity + role for /admin routes. */
  authAdmin?: AuthAdmin;
}

// ---- Edge validation schemas (reject malformed/hostile payloads) ----
const telemetrySchema = z.object({
  deviceId: z.string().min(1),
  recordedAt: z.string(),
  coreTempC: z.number().optional(),
  skinTempC: z.number().optional(),
  heartRateBpm: z.number().int().optional(),
  spo2Pct: z.number().int().optional(),
  systolicMmHg: z.number().int().optional(),
  diastolicMmHg: z.number().int().optional(),
  duringSleep: z.boolean().optional(),
});
const locationSchema = z.object({
  childId: z.string().uuid(),
  coords: z.object({ lat: z.number(), lng: z.number(), accuracyM: z.number().optional() }),
  source: z.enum(['gps', 'wifi', 'lbs', 'ble']),
  observedAt: z.string(),
});
const batchSchema = z.object({
  items: z
    .array(
      z.union([
        z.object({ type: z.literal('telemetry'), payload: telemetrySchema }),
        z.object({ type: z.literal('location'), payload: locationSchema }),
      ]),
    )
    .max(500),
});
const chatSchema = z.object({
  userId: z.string().uuid(),
  locale: z.string().default('ru-KZ'),
  message: z.string().min(1).max(2000),
  latestTelemetry: telemetrySchema.partial({ deviceId: true, recordedAt: true }).optional(),
});
const bpCalSchema = z.object({
  userId: z.string().uuid(),
  cuffSystolic: z.number().int(),
  cuffDiastolic: z.number().int(),
  ppgSystolic: z.number().int(),
  ppgDiastolic: z.number().int(),
  measuredAt: z.string(),
});

export function buildServer(deps: ServerDeps, opts: { logger?: boolean } = {}): FastifyInstance {
  const app = Fastify({ logger: opts.logger ?? true });

  app.get('/health', async () => ({ ok: true }));

  // Client CRUD + history routes (require an authUser resolver).
  if (deps.authUser) registerCrudRoutes(app, deps.repo, deps.authUser);
  // Admin / back-office routes (require an authAdmin resolver).
  if (deps.authAdmin) registerAdminRoutes(app, deps.repo, deps.authAdmin);

  /// Identity comes from authentication, never from the payload.
  /// Returns the caller, or null after already sending 401.
  async function requireCaller(req: FastifyRequest, reply: FastifyReply) {
    const user = deps.authUser ? await deps.authUser(req) : null;
    if (!user) {
      reply.code(401).send({ error: 'unauthorized' });
      return null;
    }
    return user;
  }

  app.post('/ingest/batch', async (req, reply) => {
    // Unauthenticated ingest let anyone fabricate a child's position — forging
    // a "left school" alert or masking a real departure — and inject vitals
    // that trigger a false emergency for the mother.
    const caller = await requireCaller(req, reply);
    if (!caller) return;
    const parsed = batchSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const summary = await handleIngestBatch(parsed.data.items, {
      repo: deps.repo,
      checkInside: (coords, fence) => checkGeofenceBoundary(coords, fence).inside,
      callerUserId: caller.userId,
      ...deps.ingest,
    });
    return reply.send(summary);
  });

  app.post('/ai/chat', async (req, reply) => {
    // The userId came from the BODY, unauthenticated: any caller could ask as
    // somebody else and receive that person's emergency contacts in the reply.
    const caller = await requireCaller(req, reply);
    if (!caller) return;
    const parsed = chatSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    if (parsed.data.userId !== caller.userId) {
      return reply.code(403).send({ error: 'forbidden' });
    }
    const { userId, locale, message, latestTelemetry } = parsed.data;
    const [ragPassages, emergencyContacts] = await Promise.all([
      deps.repo.retrieveRagPassages(message, locale),
      deps.repo.emergencyContacts(userId),
    ]);
    const outcome = await processWithGuardrails(
      {
        userId,
        locale,
        userMessage: message,
        latestTelemetry: latestTelemetry as never,
        ragPassages,
        emergencyContacts,
      },
      deps.guardrail,
    );
    // Emergencies are still a 200 — the app switches screens on `action`.
    return reply.send(outcome);
  });

  app.post('/calibration/bp', async (req, reply) => {
    // Calibration offsets shift every later blood-pressure reading, and those
    // readings feed preeclampsia triage. Writing them for an arbitrary userId
    // could suppress a real emergency or manufacture a false one.
    const caller = await requireCaller(req, reply);
    if (!caller) return;
    const parsed = bpCalSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    if (parsed.data.userId !== caller.userId) {
      return reply.code(403).send({ error: 'forbidden' });
    }
    const d = parsed.data;
    const offsets = computeBpOffsets(d.cuffSystolic, d.cuffDiastolic, d.ppgSystolic, d.ppgDiastolic);
    await deps.repo.insertBpCalibration(d.userId, {
      ...offsets,
      calibratedAt: d.measuredAt,
      cuffSystolic: d.cuffSystolic,
      cuffDiastolic: d.cuffDiastolic,
      ppgSystolic: d.ppgSystolic,
      ppgDiastolic: d.ppgDiastolic,
    });
    await deps.setBpCalibration(d.userId, { ...offsets, calibratedAt: d.measuredAt });
    return reply.send({ ok: true, ...offsets });
  });

  // "Where is this child right now" — the most sensitive answer this service
  // gives. It had NO auth check at all: anyone who knew or guessed a child id
  // could track them. It now requires a signed-in caller who is that child's
  // guardian. A stranger and a wrong-parent both get 403, never a hint that
  // the id exists.
  app.get('/children/:id/location', async (req, reply) => {
    const { id } = req.params as { id: string };
    // authUser is optional in ServerDeps. If no resolver is configured this
    // route must fail CLOSED — an unauthenticated deployment serving child
    // locations to anyone is the failure this check exists to prevent.
    const user = deps.authUser ? await deps.authUser(req) : null;
    if (!user) return reply.code(401).send({ error: 'unauthorized' });
    const owner = await deps.repo.childOwner(id);
    if (!owner || owner.userId !== user.userId) {
      return reply.code(403).send({ error: 'forbidden' });
    }
    const last = await deps.cacheLastLocation(id);
    if (!last) return reply.code(404).send({ error: 'no recent location' });
    return reply.send(last);
  });

  return app;
}
