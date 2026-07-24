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

const childBody = z.object({
  // Client-supplied UUID (same shape ingest requires), so the app's local id is
  // authoritative and its geofences reference it directly.
  id: z.string().uuid(),
  name: z.string().min(1).max(80),
  gender: z.enum(['boy', 'girl']).nullable().optional(),
  dateOfBirth: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
});
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
const medicationBody = z.object({
  id: z.string().min(1).max(64),
  name: z.string().min(1).max(120),
  dose: z.string().max(120).default(''),
  perDay: z.number().int().min(1).max(24).default(1),
});
const newbornEventBody = z.object({
  at: z.string().datetime({ offset: true }),
  kind: z.enum(['feed', 'diaper', 'sleep']),
  detail: z.string().max(40).nullable().optional(),
  durationMin: z.number().int().min(0).max(1440).nullable().optional(),
});
// A child growth measurement. `at` accepts a date or a full timestamp (the app
// sends a local ISO); only the calendar day is kept, one row per day. Bounds are
// the app's typo-filter, not a medical judgement (see child_growth.dart).
const growthBody = z.object({
  at: z.string().regex(/^\d{4}-\d{2}-\d{2}/),
  weightKg: z.number().min(0.3).max(60).nullable().optional(),
  heightCm: z.number().min(20).max(160).nullable().optional(),
}).refine((g) => g.weightKg != null || g.heightCm != null, {
  message: 'a growth measurement needs a weight or a height',
});
// Doses of a medication taken on a day. count is bounded to something sane; the
// app already caps it at the med's perDay, this is only a typo/abuse guard.
const doseBody = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  count: z.number().int().min(0).max(50),
});
// One vaccination toggle. The key is the app's "<id>/<dose>" — opaque here, so
// just a bounded string; `done` decides insert vs delete.
const vaccineBody = z.object({
  vaccineKey: z.string().min(1).max(64),
  done: z.boolean(),
});
const _med = z.string().max(500).default(''); // free-text, bounded
const medicalIdBody = z.object({
  bloodType: _med, allergies: _med, conditions: _med, medications: _med,
  doctorName: _med, doctorPhone: _med, contactName: _med, contactPhone: _med, notes: _med,
});
const circleGeofence = z.object({
  id: z.string().uuid(),
  name: z.string().min(1),
  shape: z.literal('circle'),
  center: z.object({ lat: z.number(), lng: z.number() }),
  radiusM: z.number().positive(),
});
const polygonGeofence = z.object({
  id: z.string().uuid(),
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
const weightBody = z.object({
  date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  kg: z.number().min(20).max(400), // sane human range; rejects a fat-fingered 3.5 or 3500
});
const iso = z.string().datetime({ offset: true });
const kickSessionBody = z.object({
  endedAt: iso,
  count: z.number().int().min(0).max(999),
  durationSec: z.number().int().min(0).max(86400),
});
const contractionSessionBody = z.object({
  endedAt: iso,
  count: z.number().int().min(0).max(999),
  avgDurationSec: z.number().int().min(0).max(86400),
  avgIntervalSec: z.number().int().min(0).max(86400),
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
    // Upsert on the client id so re-syncing the same child updates rather than
    // duplicates (offline-first, like appointments).
    await repo.upsertChild(u.userId, {
      id: parsed.data.id,
      name: parsed.data.name,
      gender: parsed.data.gender ?? null,
      dateOfBirth: parsed.data.dateOfBirth ?? null,
    });
    return reply.code(201).send({ ok: true });
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

  // ---- Medications / supplements (client keeps the id) ----
  app.get('/medications', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    return reply.send({ medications: await repo.listMedications(u.userId) });
  });

  app.post('/medications', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = medicationBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.upsertMedication(u.userId, parsed.data);
    return reply.code(201).send({ ok: true });
  });

  app.delete('/medications/:id', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.medicationOwner))) return;
    await repo.deleteMedication(id);
    return reply.code(204).send();
  });

  // ---- Medication adherence (doses taken per day) ----
  app.put('/medications/:id/doses', async (req, reply) => {
    const { id } = req.params as { id: string };
    const owner = await requireOwned(req, reply, id, repo.medicationOwner);
    if (!owner) return;
    const parsed = doseBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.upsertDose(owner.userId, { medId: id, date: parsed.data.date, count: parsed.data.count });
    return reply.code(200).send({ ok: true });
  });

  app.get('/doses', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    return reply.send({ doses: await repo.listDoses(u.userId) });
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
    await repo.upsertGeofence(id, parsed.data as unknown as Geofence);
    return reply.code(201).send({ ok: true });
  });

  app.delete('/geofences/:id', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.geofenceOwner))) return;
    await repo.deleteGeofence(id);
    return reply.code(204).send();
  });

  // ---- Newborn care events (feed/diaper/sleep, per child, push-only) ----
  app.post('/children/:id/newborn-events', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.childOwner))) return;
    const parsed = newbornEventBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.recordNewbornEvent(id, {
      at: parsed.data.at, kind: parsed.data.kind,
      detail: parsed.data.detail ?? null, durationMin: parsed.data.durationMin ?? null,
    });
    return reply.code(201).send({ ok: true });
  });

  // All the caller's newborn-care events (across her children), each tagged with
  // its childId, so a new device can restore the log grouped per child.
  app.get('/newborn-events', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const limit = Math.min(2000, Number((req.query as { limit?: string }).limit ?? 1000) || 1000);
    return reply.send({ events: await repo.listNewbornEvents(u.userId, limit) });
  });

  // ---- Child growth (weight/height), one measurement per child per day ----
  app.post('/children/:id/growth', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.childOwner))) return;
    const parsed = growthBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.upsertGrowth(id, {
      at: parsed.data.at.slice(0, 10), // keep the calendar day only
      weightKg: parsed.data.weightKg ?? null,
      heightCm: parsed.data.heightCm ?? null,
    });
    return reply.code(201).send({ ok: true });
  });

  // All the caller's growth measurements, tagged with childId, for the admin
  // drawer and the new-device restore (grouped per child).
  app.get('/growth', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    return reply.send({ growth: await repo.listGrowth(u.userId) });
  });

  // ---- Child vaccination record (parent-marked) ----
  app.put('/children/:id/vaccines', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.childOwner))) return;
    const parsed = vaccineBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.setVaccine(id, parsed.data.vaccineKey, parsed.data.done);
    return reply.code(200).send({ ok: true });
  });

  app.get('/vaccines', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    return reply.send({ vaccines: await repo.listVaccines(u.userId) });
  });

  // ---- Child emergency medical-ID (per child, upsert) ----
  app.put('/children/:id/emergency', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.childOwner))) return;
    const parsed = medicalIdBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.upsertChildEmergency(id, parsed.data);
    return reply.code(200).send({ ok: true });
  });

  app.get('/children/:id/emergency', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireOwned(req, reply, id, repo.childOwner))) return;
    return reply.send({ medicalId: await repo.getChildEmergency(id) });
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

  // ---- Maternal weight (upsert on the date) ----
  app.get('/weight', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const limit = Math.min(365, Number((req.query as { limit?: string }).limit ?? 90) || 90);
    return reply.send({ entries: await repo.listWeight(u.userId, limit) });
  });

  app.post('/weight', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = weightBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.recordWeight(u.userId, parsed.data);
    return reply.code(201).send({ ok: true });
  });

  // ---- Pregnancy timed sessions (fetal movement + labour timing) ----
  app.get('/kick-sessions', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const limit = Math.min(200, Number((req.query as { limit?: string }).limit ?? 50) || 50);
    return reply.send({ sessions: await repo.listKickSessions(u.userId, limit) });
  });
  app.post('/kick-sessions', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = kickSessionBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.recordKickSession(u.userId, parsed.data);
    return reply.code(201).send({ ok: true });
  });

  app.get('/contraction-sessions', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const limit = Math.min(200, Number((req.query as { limit?: string }).limit ?? 50) || 50);
    return reply.send({ sessions: await repo.listContractionSessions(u.userId, limit) });
  });
  app.post('/contraction-sessions', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = contractionSessionBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.recordContractionSession(u.userId, parsed.data);
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
