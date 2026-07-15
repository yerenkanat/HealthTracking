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

import Fastify, { type FastifyInstance } from 'fastify';
import { z } from 'zod';
import { checkGeofenceBoundary } from './geofence/geofence';
import { handleIngestBatch, type IngestDeps } from './routes/ingestHandler';
import {
  processWithGuardrails,
  type GuardrailDeps,
} from './ai/AIGuardrailProcessor';
import { computeBpOffsets } from './health/bpCalibration';
import type { Repository } from './db/repository';

export interface ServerDeps {
  repo: Repository;
  ingest: Omit<IngestDeps, 'repo' | 'checkInside'>;
  guardrail: GuardrailDeps;
  cacheLastLocation: (childId: string) => Promise<unknown>;
  setBpCalibration: (userId: string, offsets: { systolicOffset: number; diastolicOffset: number; calibratedAt: string }) => Promise<void>;
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

export function buildServer(deps: ServerDeps): FastifyInstance {
  const app = Fastify({ logger: true });

  app.get('/health', async () => ({ ok: true }));

  app.post('/ingest/batch', async (req, reply) => {
    const parsed = batchSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const summary = await handleIngestBatch(parsed.data.items, {
      repo: deps.repo,
      checkInside: (coords, fence) => checkGeofenceBoundary(coords, fence).inside,
      ...deps.ingest,
    });
    return reply.send(summary);
  });

  app.post('/ai/chat', async (req, reply) => {
    const parsed = chatSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
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
    const parsed = bpCalSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
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

  app.get('/children/:id/location', async (req, reply) => {
    const { id } = req.params as { id: string };
    const last = await deps.cacheLastLocation(id);
    if (!last) return reply.code(404).send({ error: 'no recent location' });
    return reply.send(last);
  });

  return app;
}
