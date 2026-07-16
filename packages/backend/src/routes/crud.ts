/**
 * Client CRUD + history routes: children, devices, geofences, metrics history,
 * geofence-event history. Registered onto the Fastify app by buildServer.
 *
 * Auth: an injected `authUser(req)` resolves the caller's userId (verify Firebase
 * token in prod; a fake in tests). Routes 401 when it returns null. The pure
 * handler logic + validation are testable in-process via fastify.inject().
 */

import type { FastifyInstance, FastifyRequest } from 'fastify';
import { z } from 'zod';
import type { Repository } from '../db/repository';
import type { Geofence } from '@fcs/shared';

export type AuthUser = (req: FastifyRequest) => Promise<{ userId: string } | null>;

const childBody = z.object({ name: z.string().min(1).max(80) });
const deviceBody = z.object({
  id: z.string().min(1),
  name: z.string().max(80).default(''),
  kind: z.enum(['band', 'tag']),
  childId: z.string().uuid().nullable().optional(),
});
const circleGeofence = z.object({
  name: z.string().min(1),
  shape: z.literal('circle'),
  center: z.object({ lat: z.number(), lng: z.number() }),
  radiusM: z.number().positive(),
});
const polygonGeofence = z.object({
  name: z.string().min(1),
  shape: z.literal('polygon'),
  vertices: z.array(z.object({ lat: z.number(), lng: z.number() })).min(3),
});
const geofenceBody = z.union([circleGeofence, polygonGeofence]);
const metricsQuery = z.object({
  from: z.string(),
  to: z.string(),
  metric: z.enum(['hr', 'spo2', 'systolic', 'diastolic', 'temp']),
});

export function registerCrudRoutes(app: FastifyInstance, repo: Repository, authUser: AuthUser): void {
  // Guard: resolve the user or 401.
  async function requireUser(req: FastifyRequest, reply: import('fastify').FastifyReply) {
    const u = await authUser(req);
    if (!u) {
      reply.code(401).send({ error: 'unauthorized' });
      return null;
    }
    return u;
  }

  // ---- Children ----
  app.get('/children', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    return reply.send({ children: await repo.listChildren(u.userId) });
  });

  app.post('/children', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = childBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    return reply.code(201).send(await repo.createChild(u.userId, parsed.data.name));
  });

  app.delete('/children/:id', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    await repo.deleteChild((req.params as { id: string }).id);
    return reply.code(204).send();
  });

  // ---- Devices ----
  app.get('/devices', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    return reply.send({ devices: await repo.listDevices(u.userId) });
  });

  app.post('/devices', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = deviceBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.createDevice(u.userId, { ...parsed.data, childId: parsed.data.childId ?? null });
    return reply.code(201).send({ ok: true });
  });

  app.delete('/devices/:id', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    await repo.deleteDevice((req.params as { id: string }).id);
    return reply.code(204).send();
  });

  // ---- Geofences (per child) ----
  app.get('/children/:id/geofences', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    return reply.send({ geofences: await repo.loadGeofences((req.params as { id: string }).id) });
  });

  app.post('/children/:id/geofences', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = geofenceBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const g = { id: '', ...parsed.data } as unknown as Geofence;
    return reply.code(201).send(await repo.createGeofence((req.params as { id: string }).id, g));
  });

  app.delete('/geofences/:id', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    await repo.deleteGeofence((req.params as { id: string }).id);
    return reply.code(204).send();
  });

  // ---- History ----
  app.get('/metrics', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = metricsQuery.safeParse(req.query);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    return reply.send({ points: await repo.queryMetrics(u.userId, parsed.data) });
  });

  app.get('/children/:id/events', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const limit = Math.min(200, Number((req.query as { limit?: string }).limit ?? 50) || 50);
    return reply.send({ events: await repo.listGeofenceEvents((req.params as { id: string }).id, limit) });
  });
}
