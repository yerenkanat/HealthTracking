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
const appointmentBody = z.object({
  id: z.string().min(1).max(64),
  title: z.string().min(1).max(200),
  at: z.string().datetime({ offset: true }),
  note: z.string().max(2000).optional(),
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
const sleepBody = z.object({
  night: z.string(),
  deepMin: z.number().int().min(0).max(1440),
  remMin: z.number().int().min(0).max(1440),
  lightMin: z.number().int().min(0).max(1440),
  awakeMin: z.number().int().min(0).max(1440),
});
const dayLogBody = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  mood: z.enum(['happy', 'calm', 'anxious', 'tired', 'sad']).nullable().optional(),
  symptoms: z.array(z.enum(['allGood', 'cramps', 'spotting', 'headache', 'nausea', 'swelling'])).default([]),
  kicks: z.number().int().min(0).max(999).default(0),
  flow: z.enum(['light', 'medium', 'heavy']).nullable().optional(),
});
// Same date shape as dayLogBody.date, which was already validated. Without it
// an arbitrary string reached the date comparison in the query and surfaced as
// a 500 instead of an honest 400.
// Month and day ranges too, not just "three groups of digits" — \d{2} happily
// accepts 2026-13-45.
const isoDate = z.string().regex(/^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12]\d|3[01])$/);
const dayLogQuery = z
  .object({ from: isoDate, to: isoDate })
  .refine((q) => q.from <= q.to, { message: 'from must not be after to' });
const alertBody = z.object({
  childId: z.string().min(1),
  kind: z.enum(['entered', 'left']),
  zoneName: z.string().min(1).max(80),
  at: z.string(),
});
const profileBody = z.object({
  displayName: z.string().min(1).max(80),
  phone: z.string().max(30).nullable().optional(),
  dueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  locale: z.string().max(10).optional(),
  // Optional profile details, collected in-app with a stated reason. Both
  // nullable: declining is a supported answer, not a missing field.
  birthDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  city: z.string().max(80).nullable().optional(),
});
const reassignBody = z.object({ childId: z.string().min(1).nullable() });

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

  /// Authentication is not authorization. Any route that takes an id from the
  /// URL must also confirm the caller OWNS that id — otherwise one signed-in
  /// account can read or delete another family's child, tracker or safe zone
  /// just by supplying their identifier.
  ///
  /// A missing record answers 403 rather than 404 on purpose: replying "not
  /// found" for ids that don't exist and "forbidden" for ids that do would let
  /// anyone enumerate which children are registered.
  async function requireOwned(
    req: FastifyRequest,
    reply: import('fastify').FastifyReply,
    id: string,
    lookup: (id: string) => Promise<{ userId: string } | null>,
  ) {
    const u = await requireUser(req, reply);
    if (!u) return null;
    const owner = await lookup(id);
    if (!owner || owner.userId !== u.userId) {
      reply.code(403).send({ error: 'forbidden' });
      return null;
    }
    return u;
  }

  /// An id taken from the BODY needs the same check as one taken from the path.
  ///
  /// Returns true when the caller may attach things to [childId]. A null child
  /// is always allowed — it means "not assigned to anyone".
  async function mayUseChild(userId: string, childId: string | null | undefined): Promise<boolean> {
    if (!childId) return true;
    const owner = await repo.childOwner(childId);
    return !!owner && owner.userId === userId;
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

  // ---- Erase everything ----
  //
  // The app's reset dialog says "all data will be erased" and, until now, only
  // cleared the phone: nothing on the server was ever deleted. With telemetry
  // syncing, that left her blood-pressure history, her child's name and date
  // of birth, and the coordinates of her home and her child's school on a
  // server she believed she had erased herself from.
  //
  // Identity comes from authentication only — there is no id in the path, so
  // this route cannot be pointed at anybody else.
  app.delete('/account', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const erased = await repo.deleteAccount(u.userId);
    // 404 when there was nothing to erase, rather than reporting success for a
    // deletion that did not happen.
    return erased ? reply.code(204).send() : reply.code(404).send({ error: 'not_found' });
  });

  app.delete('/children/:id', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.childOwner))) return;
    await repo.deleteChild(id);
    return reply.code(204).send();
  });

  // ---- Appointments ----
  app.get('/appointments', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    return reply.send({ appointments: await repo.listAppointments(u.userId) });
  });

  app.post('/appointments', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = appointmentBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    // The id comes from the client so an appointment created offline keeps its
    // identity when it syncs; upsert makes the push idempotent (re-syncing the
    // same appointment updates rather than duplicates).
    await repo.upsertAppointment(u.userId, { ...parsed.data, note: parsed.data.note ?? '' });
    return reply.code(201).send({ ok: true });
  });

  app.delete('/appointments/:id', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.appointmentOwner))) return;
    await repo.deleteAppointment(id);
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

    // PATCH /devices/:id checks both ends of a device-to-child link and says
    // why in a comment. Registration reaches exactly the same state and
    // checked neither: `childId` came straight out of the body and was written
    // as given, so any signed-in account could register a tracker of its own
    // pointed at another family's child.
    if (!(await mayUseChild(u.userId, parsed.data.childId))) {
      return reply.code(403).send({ error: 'forbidden' });
    }

    // A device id is a physical identifier, and both repositories ignore an
    // insert that collides with one already registered — so this answered 201
    // for a registration that did not happen, and the tracker then never
    // appeared in her list with nothing on screen to explain it.
    //
    // Telling her the id is taken does reveal that it is registered somewhere.
    // That is unavoidable if the failure is to be reported at all, and the
    // alternative — a device that silently never works — is worse for the
    // person holding it.
    const existing = await repo.deviceOwner(parsed.data.id);
    if (existing) {
      return reply
        .code(409)
        .send({ error: 'device_already_registered', mine: existing.userId === u.userId });
    }

    await repo.createDevice(u.userId, { ...parsed.data, childId: parsed.data.childId ?? null });
    return reply.code(201).send({ ok: true });
  });

  app.delete('/devices/:id', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.deviceOwner))) return;
    await repo.deleteDevice(id);
    return reply.code(204).send();
  });

  // ---- Timeline content (read-only for the app) ----
  // The same catalogue the back-office edits. Authenticated because it is part
  // of the product rather than public marketing, but not per-user: everyone at
  // week 20 sees the same week 20.
  app.get('/content', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    return reply.send({ stages: await repo.contentCatalog() });
  });

  // ---- Geofences (per child) ----
  app.get('/children/:id/geofences', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.childOwner))) return;
    return reply.send({ geofences: await repo.loadGeofences(id) });
  });

  app.post('/children/:id/geofences', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.childOwner))) return;
    const parsed = geofenceBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const g = { id: '', ...parsed.data } as unknown as Geofence;
    return reply.code(201).send(await repo.createGeofence(id, g));
  });

  app.delete('/geofences/:id', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.geofenceOwner))) return;
    await repo.deleteGeofence(id);
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
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.childOwner))) return;
    const limit = Math.min(200, Number((req.query as { limit?: string }).limit ?? 50) || 50);
    return reply.send({ events: await repo.listGeofenceEvents(id, limit) });
  });

  // ---- Sleep (nightly summaries) ----
  app.get('/sleep', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const limit = Math.min(90, Number((req.query as { limit?: string }).limit ?? 30) || 30);
    return reply.send({ nights: await repo.listSleep(u.userId, limit) });
  });

  app.post('/sleep', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = sleepBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.recordSleep(u.userId, parsed.data);
    return reply.code(201).send({ ok: true });
  });

  // ---- Women's-health day logs ----
  app.get('/cycle/days', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = dayLogQuery.safeParse(req.query);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    return reply.send({ days: await repo.listDayLogs(u.userId, parsed.data.from, parsed.data.to) });
  });

  app.put('/cycle/days', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = dayLogBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.upsertDayLog(u.userId, {
      date: parsed.data.date,
      mood: parsed.data.mood ?? null,
      symptoms: parsed.data.symptoms,
      kicks: parsed.data.kicks,
      flow: parsed.data.flow ?? null,
    });
    return reply.send({ ok: true });
  });

  // ---- Child safety alerts (zone enter/exit) ----
  app.get('/alerts', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const limit = Math.min(200, Number((req.query as { limit?: string }).limit ?? 50) || 50);
    return reply.send({ alerts: await repo.listAlerts(u.userId, limit) });
  });

  app.post('/alerts', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = alertBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.recordAlert(u.userId, parsed.data);
    return reply.code(201).send({ ok: true });
  });

  // ---- Profile ----
  app.get('/profile', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const profile = await repo.getProfile(u.userId);
    if (!profile) return reply.code(404).send({ error: 'not_found' });
    return reply.send({ profile });
  });

  app.put('/profile', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = profileBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.upsertProfile(u.userId, {
      displayName: parsed.data.displayName,
      phone: parsed.data.phone ?? null,
      dueDate: parsed.data.dueDate ?? null,
      locale: parsed.data.locale ?? 'ru-KZ',
      birthDate: parsed.data.birthDate ?? null,
      city: parsed.data.city ?? null,
    });
    return reply.send({ ok: true });
  });

  // ---- Reassign a device (e.g. move a tracker tag to another child) ----
  app.patch('/devices/:id', async (req, reply) => {
    // BOTH ends need checking. Owning the device isn't enough — attaching it to
    // another family's child would wire a stranger's tracker to them — and
    // owning the child isn't enough either, since that would let anyone
    // commandeer someone else's tracker.
    const { id } = req.params as { id: string };
    const u = await requireOwned(req, reply, id, repo.deviceOwner);
    if (!u) return;
    const parsed = reassignBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const targetChild = parsed.data.childId;
    if (!(await mayUseChild(u.userId, targetChild))) {
      return reply.code(403).send({ error: 'forbidden' });
    }
    await repo.reassignDevice(id, targetChild);
    return reply.send({ ok: true });
  });
}
