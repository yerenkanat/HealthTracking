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
import type { LeadNotifier } from '../notifications/leadAlert';
import { normalizePhone } from '../http/staffAuth';
import { CLAIM_WINDOW_MS, MAX_CLAIMS } from './phoneAuth';
import { buildDayHistory, isSosOutcome, SOS_OUTCOMES } from '../safety/dayHistory';
import { ROUTE_RETENTION_DAYS } from '../privacy/retention';
import { orderProgress, visibleOrders } from '../shop/orderProgress';
import { SUPPORT_SLA_HOURS } from '../admin/support';
import { createHash, randomBytes } from 'node:crypto';
import {
  ACCESS_LEVELS, canWrite, checkInvite, grantCovers, inviteExpiry, isAccessLevel,
  isOpen, MAX_OPEN_INVITES, SHAREABLE, type Shareable,
} from '../family/access';

/**
 * Only the hash is stored, so the table is not a set of working links.
 *
 * SHA-256 without a salt on purpose: this is a 256-bit random token, not a
 * password. There is no dictionary to attack, and a per-row salt would make
 * the lookup-by-token the accept route needs impossible.
 */
function hashInviteToken(token: string): string {
  return createHash('sha256').update(token).digest('hex');
}

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
const shopOrderBody = z.object({
  customerName: z.string().trim().min(1).max(120),
  phone: z.string().trim().min(5).max(40),
  city: z.string().trim().min(1).max(120),
  address: z.string().trim().min(3).max(400),
  note: z.string().trim().max(500).optional(),
  items: z.array(z.object({ variantId: z.string().min(1).max(64), qty: z.number().int().min(1).max(20) })).min(1).max(10),
  // Sold as a set: the lines are still the parts (that is what leaves the
  // warehouse and what stock comes off), and this says which bundle priced
  // them. The server checks the lines really contain the bundle's parts, so
  // claiming it over one tracker cannot buy the course for 4 900.
  bundleId: z.string().min(1).max(64).optional(),
});
// A landing-page callback request. Looser than an order on purpose: the visitor
// typed two fields on their way past, and a rejected lead is a lost customer.
// Only name and phone are required; the package label is whatever option they
// left selected.
const shopLeadBody = z.object({
  customerName: z.string().trim().min(1).max(120),
  phone: z.string().trim().min(5).max(40),
  package: z.string().trim().max(200).optional(),
  locale: z.enum(['ru', 'kz']).optional(),
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
  // Provenance for a hand-entered night; the app omits both for band nights.
  source: z.enum(['band', 'manual']).optional(),
  manualAsleepMin: z.number().int().min(0).max(1440).nullable().optional(),
});
const cryResultBody = z.object({
  at: z.string(),
  reason: z.string().max(40),
  confidence: z.number().min(0).max(1),
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
  note: z.string().max(2000).optional(), // free-text note the user typed for the day
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
// The third place the same two-kind restriction lived. The app's AlertKind has
// five and its alerts screen offers a filter chip for each; this schema, the
// SafetyAlertRow type and the table's CHECK all admitted two, so a synced SOS,
// check-in or low-battery alert was rejected with a 400 before it ever reached
// the constraint that would also have rejected it. See migration 030.
const alertBody = z.object({
  childId: z.string().min(1),
  kind: z.enum(['entered', 'left', 'checkIn', 'sos', 'lowBattery']),
  // An SOS happens wherever she is, not in a zone, so the name may be empty —
  // min(1) here is what would have refused every SOS the app tried to sync.
  zoneName: z.string().max(80).default(''),
  at: z.string(),
});
// NOTE: there is deliberately no `phone` here.
//
// It used to be accepted and written to `users.phone_e164` — the column
// POST /auth/phone resolves an account by — so a signed-in user could claim
// any number that had not registered yet, and the real owner's first sign-in
// dropped her into the claimant's session: her pregnancy, her children, their
// live locations, plus the course entitlement and orders that are keyed on the
// same number. The number comes from sign-in and from nowhere else.
//
// Zod strips unknown keys by default, so an older app that still sends one is
// ignored rather than refused — the field is dead, not a 400.
//
// `doctorPhone` below is unrelated: a number she calls, never one she is
// identified by, and nothing resolves an account with it.
const profileBody = z.object({
  displayName: z.string().min(1).max(80),
  dueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  locale: z.string().max(10).optional(),
  // Optional profile details, collected in-app with a stated reason. Both
  // nullable: declining is a supported answer, not a missing field.
  birthDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable().optional(),
  city: z.string().max(80).nullable().optional(),
  doctorPhone: z.string().max(30).nullable().optional(),
  avgCycleLength: z.number().int().min(15).max(60).nullable().optional(),
  avgPeriodLength: z.number().int().min(1).max(14).nullable().optional(),
});
const reassignBody = z.object({ childId: z.string().min(1).nullable() });

export function registerCrudRoutes(
  app: FastifyInstance,
  repo: Repository,
  authUser: AuthUser,
  notifyLead?: LeadNotifier,
  /**
   * Refuse a device that is not in our registry, or only record that we would
   * have.
   *
   * A parameter rather than an env read at module load: this is the switch that
   * decides whether a real customer can use what she bought, so it has to be
   * settable per server — which is also the only way a test can cover both
   * sides of it.
   */
  enforceDeviceRegistry = false,
): void {
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

  /**
   * The caller may see this child — as its owner, OR as a relative let in on
   * screen 40.
   *
   * DELIBERATELY SEPARATE from [requireOwned], which stays owner-only. Every
   * route keeps the strict guard unless somebody moves it here on purpose, so
   * a route added next year is private by default. Widening this list is a
   * visible act; forgetting to narrow a shared default is not, and the thing
   * being protected is a child's location.
   *
   * [write] distinguishes the two levels: a viewer looks, a guardian acts.
   * Returns the caller, or null having already answered 403.
   */
  async function requireChildAccess(
    req: FastifyRequest,
    reply: import('fastify').FastifyReply,
    childId: string,
    what: Shareable,
    write = false,
  ) {
    const u = await requireUser(req, reply);
    if (!u) return null;
    const owner = await repo.childOwner(childId);
    if (!owner) {
      reply.code(403).send({ error: 'forbidden' });
      return null;
    }
    if (owner.userId === u.userId) return u;

    const level = await repo.familyLevel(owner.userId, u.userId).catch(() => null);
    const allowed = level != null
      && (write ? isAccessLevel(level) && canWrite(level, what) : grantCovers(level, what));
    if (!allowed) {
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

    // ---- Is this one of OUR devices? --------------------------------------
    //
    // The same watches and tags are sold on other marketplaces. Pairing used to
    // ask only whether the id was already taken, so any compatible unit from
    // any seller got the app, the tracking backend and the course — the
    // hardware is generic, the service is the product, and the service was
    // going out in somebody else's box.
    //
    // LOG-ONLY until DEVICE_REGISTRY_ENFORCE=1. The day this starts refusing,
    // every unit missing from the registry becomes a paying customer who cannot
    // use what she bought — and we would hear about it through angry WhatsApp
    // messages rather than a log. So it records what it WOULD have refused
    // first, and somebody looks at that number before switching it on.
    // try/catch, not .catch(): a repository that does not implement this at all
    // throws SYNCHRONOUSLY, before there is a promise to attach to, and that
    // turned a failed lookup into a 500 on the one route a customer uses to
    // make her new watch work. This check is an addition to pairing; it must
    // never be the reason pairing fails.
    let registered: Awaited<ReturnType<Repository['deviceRegistryEntry']>> = null;
    let registryReadable = true;
    try {
      registered = await repo.deviceRegistryEntry(parsed.data.id);
    } catch {
      registryReadable = false;
    }
    // A registry we could not read is not evidence against the device. Refusing
    // on a failed lookup would turn a database blip into every customer being
    // told her watch is counterfeit.
    const refuse = registryReadable
        && (registered == null || registered.status === 'blocked');
    if (refuse) {
      req.log.warn({
        deviceId: parsed.data.id,
        reason: registered == null ? 'not_in_registry' : 'blocked',
        enforcing: enforceDeviceRegistry,
      }, 'device pairing not in registry');
    }
    if (refuse && enforceDeviceRegistry) {
      // Says what to do next. A bare refusal costs the customer AND the support
      // conversation; somebody holding a grey-market tag still wants the
      // service, and that is a sale to have rather than a review to lose.
      return reply.code(403).send({
        error: registered == null ? 'device_not_ours' : 'device_blocked',
      });
    }

    await repo.createDevice(u.userId, { ...parsed.data, childId: parsed.data.childId ?? null });

    // Bind it, so the same unit cannot be activated on a second account. Best
    // effort: the device is already registered above, and failing to record
    // provenance must not undo a pairing that worked.
    if (registered != null) {
      const profile = await repo.getProfile(u.userId).catch(() => null);
      const phone = normalizePhone(profile?.phone ?? '');
      if (phone) await repo.markDeviceActivated(parsed.data.id, phone).catch(() => false);
    }
    return reply.code(201).send({ ok: true });
  });

  /**
   * "This really is our device — here is the code on the box."
   *
   * The way through the pairing gate for a unit the registry does not recognise
   * by its BLE address. `deviceByActivationCode` was written for exactly this —
   * documented as "the fallback path: units already in the wild whose serial
   * nobody captured" — and had no route, so it was reachable only from tests.
   *
   * That is not a tidiness problem. The pairing gate refuses `device_not_ours`
   * the day DEVICE_REGISTRY_ENFORCE=1 is switched on, and the reason that
   * switch is still off is precisely that flipping it would refuse real
   * customers with no recourse. This is the recourse. Without it the choice was
   * between an unenforced gate and refusing people who paid us.
   *
   * Claiming BINDS the unit to her number, so the same code cannot walk onto a
   * second account — which is what stops the code itself becoming the
   * grey-market product.
   */
  app.post('/devices/claim', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;

    const parsed = z.object({ code: z.string().trim().min(3).max(40) }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: 'bad_request' });

    const profile = await repo.getProfile(u.userId).catch(() => null);
    const phone = normalizePhone(profile?.phone ?? '');
    if (!phone) {
      // Nothing to bind the unit to. Better to say so than to consume the
      // code against an account that cannot own it.
      return reply.code(409).send({ error: 'no_phone_on_account' });
    }

    // Rate limited on the PHONE, reusing the counter the sign-in path uses.
    // These codes are short enough to guess, and a claim endpoint with no
    // ceiling is a way to enumerate our whole stock from a phone.
    const since = new Date(Date.now() - CLAIM_WINDOW_MS);
    if ((await repo.recentPhoneClaims(phone, since).catch(() => 0)) >= MAX_CLAIMS) {
      return reply.code(429).send({
        error: 'too_many_attempts',
        retryAfterMinutes: Math.ceil(CLAIM_WINDOW_MS / 60000),
      });
    }
    await repo.recordPhoneClaim(phone).catch(() => {});

    const unit = await repo.deviceByActivationCode(parsed.data.code).catch(() => null);
    // Same answer for "no such code" as for a code belonging to a blocked
    // unit would tell somebody probing which of their guesses exist. It does
    // not: a blocked unit is a support conversation with its own answer, and
    // the person holding it is far more often a customer than an attacker.
    if (!unit) return reply.code(404).send({ error: 'unknown_code' });
    if (unit.status === 'blocked') return reply.code(403).send({ error: 'device_blocked' });

    if (unit.activatedByPhone && unit.activatedByPhone !== phone) {
      // Single use is the whole point. Without it one code posted in a chat
      // group unlocks every unit somebody cares to pair.
      return reply.code(409).send({ error: 'already_claimed' });
    }

    // Idempotent: re-claiming her own unit after a reinstall must work rather
    // than telling her the watch she is holding belongs to somebody else.
    const bound = unit.activatedByPhone === phone
      ? true
      : await repo.markDeviceActivated(unit.serial, phone).catch(() => false);
    if (!bound) return reply.code(409).send({ error: 'already_claimed' });

    // The serial comes back so the app can pair without the customer reading a
    // MAC address off a sticker.
    return reply.send({ ok: true, serial: unit.serial, kind: unit.kind });
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
    const catalog = await repo.contentCatalog();

    // Drafts never reach a reader, and neither does the reviewer's signature.
    //
    // The draft flag is what lets an unfinished medical card be written at all
    // — see content/medicalReview.ts — and it exists in the same store the app
    // reads, so filtering it here is the only thing standing between a
    // half-written paragraph about bleeding in pregnancy and somebody's phone.
    //
    // `review` is stripped because it names a member of staff. It is a
    // back-office record of who took responsibility, not a byline.
    const published: Record<string, unknown[]> = {};
    for (const [stage, items] of Object.entries(catalog)) {
      published[stage] = items
        .filter((i) => (i as { draft?: boolean }).draft !== true)
        .map((i) => {
          const { review: _staffOnly, ...rest } = i;
          return rest;
        });
    }
    return reply.send({ stages: published });
  });

  // ---- Geofences (per child) ----
  app.get('/children/:id/geofences', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireChildAccess(req, reply, id, 'child_zones'))) return;
    return reply.send({ geofences: await repo.loadGeofences(id) });
  });

  app.post('/children/:id/geofences', async (req, reply) => {
    const { id } = req.params as { id: string };
    // A guardian may move a zone; a viewer may not touch somebody else's.
    if (!(await requireChildAccess(req, reply, id, 'child_zones', true))) return;
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

  // Her own hand-entered readings, to restore a typed vitals/glucose history on a
  // new device. Only device-less (manual) rows — band readings are re-supplied by
  // the device, so pulling them back would duplicate stale data.
  app.get('/vitals/manual', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    return reply.send({ readings: await repo.listManualVitals(u.userId) });
  });

  // ---- Shop (public storefront — no auth: customers are not signed in) ----
  /**
   * The live catalogue the app's screen 41 renders.
   *
   * Each product now carries what an operator edits in frame 08a — the Kazakh
   * name, the descriptions, the stage, the child age band — plus a derived
   * `inStock`. Before that this route answered with id/name/price/kind/variants
   * and the app hard-coded three products and their prices, so changing a price
   * in the panel changed nothing a customer could see.
   *
   * Still unauthenticated, and therefore still free of `costMinor`, margin and
   * anything else a customer has no business reading: [ShopProduct] does not
   * carry them, which is the guarantee — not a field list maintained here.
   */
  app.get('/shop/products', async (_req, reply) => reply.send({ products: await repo.shopProducts() }));
  // Public store config the landing pages read: WhatsApp order number + Kaspi
  // link. A whitelist of the settings table — secrets never leave here.
  app.get('/shop/config', async (_req, reply) => {
    const s = await repo.getShopSettings();
    return reply.send({
      whatsapp: s.whatsapp ?? '', kaspiUrl: s.kaspiUrl ?? '',
      reviews: s.reviews ?? '', rating: s.rating ?? '', reviewCount: s.reviewCount ?? '',
    });
  });
  app.post('/shop/orders', async (req, reply) => {
    const parsed = shopOrderBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const res = await repo.placeShopOrder(parsed.data);
    if (!res.ok) {
      // out_of_stock → 409 (the client re-reads stock and re-picks); the rest → 400.
      return reply.code(res.error === 'out_of_stock' ? 409 : 400).send({ error: res.error, variantId: res.variantId });
    }
    return reply.code(201).send({ id: res.id, totalMinor: res.totalMinor, discountMinor: res.discountMinor });
  });
  /**
   * Screen 42 — «Мой заказ». Her own orders.
   *
   * POST /shop/orders existed and nothing could read one back: a woman paid
   * 39 000 ₸ through the app and the app never mentioned it again. The only
   * way to find out where the parcel was, was to message somebody on WhatsApp.
   *
   * Matched on her PHONE, not on a user id, because that is what an order
   * carries — the shop takes orders from the landing page too, and the woman
   * who ordered on a laptop before installing anything is the same customer.
   */
  app.get('/shop/my-orders', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const profile = await repo.getProfile(u.userId).catch(() => null);
    const phone = normalizePhone(profile?.phone ?? '');
    // No number on the profile means nothing can be matched. An empty list is
    // the honest answer — and `phone: null` lets the screen say WHY rather
    // than implying she has never ordered anything.
    if (!phone) return reply.send({ orders: [], phone: null });

    const orders = await repo.shopOrdersByPhone(phone, 20).catch(() => []);
    return reply.send({
      phone,
      orders: visibleOrders(orders, new Date()).map(orderProgress),
    });
  });

  /**
   * Call off an order that has not shipped.
   *
   * Guarded on the same rule the screen uses to decide whether to offer the
   * button — a client that offered it anyway must still be refused here, and
   * `cancellable` on the response is a courtesy to the UI, not the check.
   */
  app.post('/shop/my-orders/:id/cancel', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const { id } = req.params as { id: string };
    const profile = await repo.getProfile(u.userId).catch(() => null);
    const phone = normalizePhone(profile?.phone ?? '');
    if (!phone) return reply.code(403).send({ error: 'forbidden' });

    // Hers, or nobody's. Without this an id from someone else's order would
    // cancel a stranger's delivery.
    const mine = await repo.shopOrdersByPhone(phone, 50).catch(() => []);
    const order = mine.find((o) => o.id === id);
    if (!order) return reply.code(404).send({ error: 'not_found' });

    if (!orderProgress(order).cancellable) {
      // Already with a courier. Cancelling in an app does not stop a van, and
      // saying it did would be found out on the doorstep.
      return reply.code(409).send({ error: 'too_late', status: order.status });
    }
    await repo.setShopOrderStatus(id, 'cancelled');
    return reply.send({ ok: true });
  });

  // "Оставьте номер — перезвоним сами" on the landing page. Public and
  // unauthenticated like the rest of the storefront: whoever fills this in is a
  // prospective customer, not a user of the app.
  app.post('/shop/leads', async (req, reply) => {
    const parsed = shopLeadBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    const { id } = await repo.recordShopLead(parsed.data);
    // Answer the customer FIRST. Their row is committed above, which is the
    // commitment; telling staff is a separate concern and must not put a call
    // to api.telegram.org between a mother tapping "send" and the page saying
    // it worked.
    //
    // Still awaited after that, rather than left dangling: the notifier never
    // throws, and awaiting keeps it from being cut short if the process is
    // stopped mid-flight.
    reply.code(201).send({ id });
    if (notifyLead) await notifyLead(parsed.data);
    return reply;
  });

  app.get('/children/:id/events', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireChildAccess(req, reply, id, 'child_zones'))) return;
    const limit = Math.min(200, Number((req.query as { limit?: string }).limit ?? 50) || 50);
    return reply.send({ events: await repo.listGeofenceEvents(id, limit) });
  });

  /**
   * Frame 47 — «История дня». Where she went, and what happened.
   *
   * The trail has been written on every fix since the first one and deleted at
   * ninety days, and nothing could read it in between: retention cost without
   * the use. This is the read.
   *
   * `day` is a calendar date (YYYY-MM-DD) rather than a range, because that is
   * the question — «где она была сегодня» — and a from/to pair invites a client
   * to ask for the whole ninety days at once.
   */
  app.get('/children/:id/day', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireChildAccess(req, reply, id, 'child_location'))) return;

    const q = req.query as { day?: string };
    const day = /^\d{4}-\d{2}-\d{2}$/.test(q.day ?? '')
      ? q.day!
      : new Date().toISOString().slice(0, 10);
    const from = `${day}T00:00:00.000Z`;
    const to = new Date(Date.parse(from) + 86_400_000).toISOString();

    // A tracker reporting every thirty seconds makes 2 880 fixes a day. The cap
    // is generous enough to hold a real day and low enough that a misbehaving
    // device cannot pull an unbounded read.
    // Alerts are stored per USER, so the owner has to be resolved first. The
    // ownership guard above already proved the caller is that owner.
    const owner = await repo.childOwner(id).catch(() => null);
    const [fixes, crossings, alerts] = await Promise.all([
      repo.locationHistory(id, from, to, 5000).catch(() => []),
      repo.listGeofenceEvents(id, 200).catch(() => []),
      owner ? repo.listAlerts(owner.userId, 500).catch(() => []) : Promise.resolve([]),
    ]);

    const inDay = (at: string) => at >= from && at < to;
    const history = buildDayHistory({
      fixes,
      crossings: crossings
        .filter((c) => inDay(c.at))
        .map((c) => ({
          at: c.at,
          transition: c.transition === 'enter' ? ('enter' as const) : ('exit' as const),
          zoneName: c.geofenceName || null,
        })),
      // listAlerts is per USER, so it carries this child's siblings too.
      sos: alerts
        .filter((a) => a.childId === id && a.kind === 'sos' && inDay(a.at))
        .map((a) => ({ at: a.at, outcome: a.outcome ?? null })),
    });

    return reply.send({
      day,
      ...history,
      // The promise the screen prints, from the constant the sweep uses — so
      // «маршруты хранятся 90 дней» cannot drift from what actually happens.
      retentionDays: ROUTE_RETENTION_DAYS,
    });
  });

  /**
   * Frame 48 — «Сохранить отметку». Close an SOS with the parent's verdict.
   *
   * `child_alerts` rather than `child_location`: this writes to the alarm
   * record, and a relative who may see where the child is has not thereby been
   * given the right to decide what an emergency was.
   *
   * Keyed on the instant, since the alert feed carries no id. A miss is a 404
   * and not a silent 200 — the screen prints the result of this request, and a
   * tick over an UPDATE that matched no row is how a parent comes to believe an
   * alarm is closed when it is still open.
   */
  app.post('/children/:id/day/outcome', async (req, reply) => {
    const { id } = req.params as { id: string };
    if (!(await requireChildAccess(req, reply, id, 'child_alerts'))) return;

    const body = (req.body ?? {}) as { at?: unknown; outcome?: unknown };
    if (typeof body.at !== 'string' || Number.isNaN(Date.parse(body.at))) {
      return reply.code(400).send({ error: 'at must be an ISO timestamp' });
    }
    if (!isSosOutcome(body.outcome)) {
      return reply.code(400).send({
        error: 'outcome must be one of ' + SOS_OUTCOMES.map((o) => o.key).join(', '),
      });
    }

    const owner = await repo.childOwner(id).catch(() => null);
    if (!owner) return reply.code(404).send({ error: 'not found' });

    const ok = await repo.setAlertOutcome(
      owner.userId, id, new Date(body.at).toISOString(), body.outcome);
    if (!ok) return reply.code(404).send({ error: 'no SOS at that time' });
    return reply.send({ ok: true, outcome: body.outcome });
  });

  // ---- Family access (screen 40) ----
  //
  // «здоровье и цикл не видит никто». Nothing under this heading reads the
  // mother's own record, and there is no level that could — see
  // src/family/access.ts, where that is a property of the code rather than a
  // sentence on a screen.

  /** Who I have let in, and my outstanding invitations. */
  app.get('/family/access', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const now = new Date();
    // No .catch(() => []) on any of these. An empty list here is
    // indistinguishable from «никого не пускала», and the member ids this list
    // carries are the only way DELETE /family/access/:memberUserId can be
    // called — so a swallowed read error silently removed revocation from the
    // product, which is exactly how a broken column survived for months. Let it
    // throw: a 500 the screen reports is recoverable, a comfortable lie is not.
    const [members, invites, memberships] = await Promise.all([
      repo.familyMembers(u.userId),
      repo.familyInvites(u.userId, 50),
      repo.familyMemberships(u.userId),
    ]);
    return reply.send({
      members,
      // Expired links are dropped rather than shown dead: reading a link that
      // no longer works and not being told is worse than not seeing it.
      invites: invites
        .filter((i) => isAccessLevel(i.level) && isOpen({ ...i, level: i.level }, now))
        .map((i) => ({
          tokenHash: i.tokenHash,
          level: i.level,
          label: i.label,
          createdAt: i.createdAt,
          expiresAt: i.expiresAt,
        })),
      /// The other direction — whose children I can see. A father's app asks
      /// this on launch, and without it his account looks empty.
      memberships,
      /// What a grant can ever cover, so the app's green banner is a statement
      /// about the server rather than a claim typed into the screen.
      shareable: SHAREABLE,
    });
  });

  /** «Пригласить» — a one-time link, good for 24 hours. */
  app.post('/family/invites', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = z.object({
      level: z.enum(ACCESS_LEVELS),
      label: z.string().trim().max(40).default(''),
    }).safeParse(req.body ?? {});
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    const now = new Date();
    const open = (await repo.familyInvites(u.userId, 100).catch(() => []))
      .filter((i) => isAccessLevel(i.level) && isOpen({ ...i, level: i.level }, now));
    if (open.length >= MAX_OPEN_INVITES) {
      return reply.code(429).send({ error: 'too_many_invites', max: MAX_OPEN_INVITES });
    }

    // The token is returned ONCE, in this response, and only its hash is
    // stored — so a copy of the table is not a set of working invitations, and
    // a link cannot be recovered from the server if she loses it. She makes a
    // new one, which is also the safer behaviour.
    const token = randomBytes(32).toString('base64url');
    await repo.createFamilyInvite({
      ownerUserId: u.userId,
      tokenHash: hashInviteToken(token),
      level: parsed.data.level,
      label: parsed.data.label,
      expiresAt: inviteExpiry(now),
    });
    return reply.code(201).send({
      token,
      level: parsed.data.level,
      label: parsed.data.label,
      expiresAt: inviteExpiry(now),
    });
  });

  /** Accepting one. The person tapping the link is already signed in. */
  app.post('/family/invites/accept', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = z.object({ token: z.string().min(10).max(200) }).safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    const hash = hashInviteToken(parsed.data.token);
    const row = await repo.familyInviteByHash(hash).catch(() => null);
    const verdict = checkInvite(
      row && isAccessLevel(row.level) ? { ...row, level: row.level } : null,
      u.userId,
      new Date(),
    );
    // Distinct reasons, because they need different words: an expired link
    // needs a new one, a used one probably means somebody else already joined.
    if (!verdict.ok) return reply.code(409).send({ error: verdict.reason });

    // Claim FIRST, then grant. The claim is one conditional write, so two
    // people opening the same link from a family chat cannot both win it; if
    // this loses, nothing was granted.
    const claimed = await repo.claimFamilyInvite(hash, u.userId, new Date().toISOString());
    if (!claimed) return reply.code(409).send({ error: 'already_used' });

    await repo.upsertFamilyAccess({
      ownerUserId: row!.ownerUserId,
      memberUserId: u.userId,
      level: verdict.level,
      label: row!.label,
    });
    return reply.send({ ok: true, ownerUserId: row!.ownerUserId, level: verdict.level });
  });

  app.delete('/family/invites/:tokenHash', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const { tokenHash } = req.params as { tokenHash: string };
    const ok = await repo.revokeFamilyInvite(u.userId, tokenHash).catch(() => false);
    // 404 rather than a cheerful ok: "I revoked it" over a link that is still
    // live is the one wrong answer this route can give.
    if (!ok) return reply.code(404).send({ error: 'not_found' });
    return reply.send({ ok: true });
  });

  /** Take somebody's access away. */
  app.delete('/family/access/:memberUserId', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const { memberUserId } = req.params as { memberUserId: string };
    const ok = await repo.removeFamilyAccess(u.userId, memberUserId).catch(() => false);
    if (!ok) return reply.code(404).send({ error: 'not_found' });
    return reply.send({ ok: true });
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

  // ---- Baby cry-analysis history (push a result; restore the list) ----
  // Distinct from the /cry/analyze proxy (server.ts): this is the saved history.
  app.get('/cry/results', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const limit = Math.min(200, Number((req.query as { limit?: string }).limit ?? 50) || 50);
    return reply.send({ results: await repo.listCry(u.userId, limit) });
  });

  app.post('/cry/results', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = cryResultBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });
    await repo.recordCry(u.userId, parsed.data);
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
      note: parsed.data.note ?? '',
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

  // ---- Support (frame 43 · «Поддержка · оператор») -------------------------
  //
  // The receiving end of the operator's desk. Frame 12 has been able to WRITE
  // to a customer since it shipped — POST /admin/support/:id/reply appends to
  // support_replies and sets the ticket to «ждём клиента» — waiting on a woman
  // who had no surface anywhere that could show her the answer. The 'app'
  // channel the migration allows had never been written by anything.
  //
  // ON THE OWNERSHIP RULE. Every route here resolves the ticket and compares
  // its user_id to the session's, and a ticket that is not hers answers 403 —
  // including one that does not exist, so nobody can walk the id space to learn
  // which tickets are real. A ticket with user_id NULL (somebody who wrote from
  // WhatsApp before having an account) therefore belongs to no app session at
  // all. That is deliberate: the alternative is matching on the phone, which
  // hands a stranger's support conversation to whoever signs in with that
  // number next.

  const supportNewBody = z.object({
    subject: z.string().trim().min(1).max(200),
    body: z.string().trim().min(1).max(4000),
    /**
     * What the app knew when she wrote — version, device, offline. Composed by
     * support_context.dart, free text on purpose: pinning a shape here would
     * mean a change on both sides every time the app learns a new fact.
     */
    appContext: z.string().trim().max(1000).optional(),
  });
  const supportReplyBody = z.object({ body: z.string().trim().min(1).max(4000) });

  /** Her ticket, or 403 having already answered. Never 404 — see above. */
  async function requireOwnTicket(
    req: FastifyRequest, reply: import('fastify').FastifyReply, id: string,
  ) {
    const u = await requireUser(req, reply);
    if (!u) return null;
    const ticket = await repo.getSupportTicket(id);
    if (!ticket || ticket.userId !== u.userId) {
      reply.code(403).send({ error: 'forbidden' });
      return null;
    }
    return { userId: u.userId, ticket };
  }

  app.get('/support', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const tickets = await repo.listSupportTicketsForUser(u.userId, 20);
    // The threads come WITH the tickets. A list that made her tap to discover
    // whether anybody had answered would be the same silence in a new shape,
    // and twenty threads is a handful of rows.
    const threads = await Promise.all(tickets.map(async (t) => ({
      ...t,
      replies: await repo.listSupportReplies(t.id).catch(() => []),
    })));
    return reply.send({
      tickets: threads,
      // What the desk promises, from the same constant the operator's board
      // shows — two numbers for one promise drift within a month.
      slaHours: SUPPORT_SLA_HOURS,
    });
  });

  app.post('/support', async (req, reply) => {
    const u = await requireUser(req, reply);
    if (!u) return;
    const parsed = supportNewBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    // The name and number come from the PROFILE, not from the request: they are
    // how the operator finds the account and the order, and letting the client
    // supply them would let anyone file a ticket under somebody else's number.
    const profile = await repo.getProfile(u.userId).catch(() => null);
    const id = await repo.createSupportTicket({
      userId: u.userId,
      phone: profile?.phone ?? null,
      customerName: profile?.displayName ?? null,
      channel: 'app',
      subject: parsed.data.subject,
      body: parsed.data.body,
      appContext: parsed.data.appContext ?? null,
    });
    return reply.code(201).send({ ok: true, id });
  });

  app.post('/support/:id/reply', async (req, reply) => {
    const { id } = req.params as { id: string };
    const owned = await requireOwnTicket(req, reply, id);
    if (!owned) return;
    const parsed = supportReplyBody.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    await repo.addSupportReply({ ticketId: id, author: 'customer', body: parsed.data.body });

    // Back into the operator's queue. «ждём клиента» is precisely the state
    // where the ball is in her court, and she has just played it; leaving the
    // status alone would file her answer somewhere nobody is looking.
    //
    // A CLOSED ticket reopens for the same reason — «ничего не удаляется» cuts
    // both ways, and a message into a closed thread that nobody sees is the
    // one-way desk again with an extra step.
    //
    // Through updateSupportTicket, never a raw status write: it is what keeps
    // answeredAt/closedAt consistent, and the SLA clock is read off them.
    const { status } = owned.ticket;
    if (status === 'waiting' || status === 'closed') {
      await repo.updateSupportTicket(id, {
        status: 'open',
        ...(status === 'closed' ? { closedAt: null } : {}),
      });
    }
    // She has, by definition, just read everything in it: she wrote back.
    // Without this the badge she came to clear relights the moment the screen
    // reloads, over her own message.
    await repo.markSupportTicketRead(id, new Date().toISOString()).catch(() => false);

    // answeredAt is deliberately LEFT ALONE. It records when WE last spoke, and
    // clearing it would make a ticket we have answered twice report that nobody
    // ever replied to her. The board compares it against her last message
    // instead — see buildSupportBoard.
    return reply.send({ ok: true });
  });

  /**
   * She opened the thread — the only way the «Есть ответ поддержки» badge on
   * «Помощь» has DOWN.
   *
   * The badge counts tickets the desk answered and is waiting on. Nothing used
   * to take it down: reading changed no state, so a mint «1» sat on the row for
   * weeks until an operator happened to close the ticket, and a badge that is
   * permanently lit is one she stops reading. This records the instant; an
   * answer newer than it lights the badge again, an answer older does not.
   *
   * It does NOT touch the status. «ждём клиента» is the operator's queue state
   * and hers to answer, and moving her ticket out of the board the desk works
   * from because she glanced at the screen would lose the ticket, not the badge.
   */
  app.post('/support/:id/read', async (req, reply) => {
    const { id } = req.params as { id: string };
    // Same 403-never-404 rule as the reply route: reading is a write like any
    // other, and «not found» for ids that do not exist would let anyone walk
    // the id space to learn which tickets are real.
    const owned = await requireOwnTicket(req, reply, id);
    if (!owned) return;
    const at = new Date().toISOString();
    await repo.markSupportTicketRead(id, at);
    // The instant comes back so the app can settle its own copy without a
    // second round trip, and so a client that got a 200 can prove what was
    // written rather than assuming the request succeeded.
    return reply.send({ ok: true, readAt: at });
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
    // No `phone`: the sign-in identity is not the user's to set. See profileBody.
    await repo.upsertProfile(u.userId, {
      displayName: parsed.data.displayName,
      dueDate: parsed.data.dueDate ?? null,
      locale: parsed.data.locale ?? 'ru-KZ',
      birthDate: parsed.data.birthDate ?? null,
      city: parsed.data.city ?? null,
      doctorPhone: parsed.data.doctorPhone ?? null,
      avgCycleLength: parsed.data.avgCycleLength ?? null,
      avgPeriodLength: parsed.data.avgPeriodLength ?? null,
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
