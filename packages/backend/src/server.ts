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
import { RateLimiter } from './http/rateLimit';
import { antenatalProtocol } from './antenatal/protocol';
import { pregnancyCalendar, weekContent } from './pregnancy/weeks';
import { childDevCalendar, devWeekContent } from './child/development';
import { vaccinationSchedule } from './vaccination/schedule';
import type { Repository } from './db/repository';

export interface ServerDeps {
  repo: Repository;
  ingest: Omit<IngestDeps, 'repo' | 'checkInside'>;
  guardrail: GuardrailDeps;
  /// Injected so tests can drive the boundary without a real clock. Defaults
  /// to 20 messages per 5 minutes per authenticated user.
  chatLimiter?: RateLimiter;
  /// Same, for /ingest/batch. Defaults to 120 requests per 5 minutes.
  ingestLimiter?: RateLimiter;
  cacheLastLocation: (childId: string) => Promise<unknown>;
  setBpCalibration: (userId: string, offsets: { systolicOffset: number; diastolicOffset: number; calibratedAt: string }) => Promise<void>;
  /** Resolve the caller's user from the request (verify Firebase token in prod). */
  authUser?: AuthUser;
  /** Resolve the caller's staff identity + role for /admin routes. */
  authAdmin?: AuthAdmin;
  /** Readiness: pings the real dependencies (DB, Redis). Omitted = always ready
   * (in-memory dev). /ready reports 503 with the per-dependency breakdown when
   * any is down, so a load balancer can pull the instance before it serves errors. */
  checkReady?: () => Promise<{ ready: boolean; deps?: Record<string, boolean> }>;
}

// ---- Edge validation schemas (reject malformed/hostile payloads) ----
/// An instant, not merely a string.
///
/// These were `z.string()`, so "yesterday-ish" was stored verbatim and reached
/// the app, which subtracts it from now to decide how fresh a reading is. That
/// parse yields NaN, and every comparison against NaN is false — so the value
/// came out neither fresh nor stale, and fell through whichever branch happened
/// to be last.
///
/// Offsets are allowed: a phone in Almaty legitimately sends +05:00.
const isoInstant = z.string().datetime({ offset: true });

// The plain object is kept separately because .refine() produces a ZodEffects,
// which has no .partial() — and /ai/chat needs a partial of this shape.
const telemetryBase = z.object({
    // Empty is allowed ONLY for a hand-entered reading — see the refine below.
    // A cuff reading a mother types in has no device to name, and requiring one
    // rejected the most trustworthy numbers the product has at the edge, before
    // any handler saw them.
    deviceId: z.string(),
    recordedAt: isoInstant,
    source: z.enum(['band', 'manual']).optional(),
    // Bounded to what a human body can produce.
    //
    // /calibration/bp below already says why unbounded integers are dangerous,
    // and this — the path that reaches her chart, her clinician's view and the
    // server-side triage that sends an emergency push — bounded nothing. A
    // systolic of 999999 was stored and, being over the threshold, sent her a
    // "seek care now" push for a number no person has ever had.
    //
    // WIDER than the calibration bounds on purpose. Calibration is a pair she
    // types in to offset every later reading, so it can demand a plausible
    // one; this carries whatever is actually happening, and a woman in shock
    // reads low. Rejecting a real emergency would be the worse mistake, so
    // these reject only the impossible.
    coreTempC: z.number().finite().min(20).max(45).optional(),
    skinTempC: z.number().finite().min(10).max(45).optional(),
    heartRateBpm: z.number().int().min(20).max(300).optional(),
    spo2Pct: z.number().int().min(1).max(100).optional(),
    systolicMmHg: z.number().int().min(40).max(300).optional(),
    diastolicMmHg: z.number().int().min(20).max(220).optional(),
    duringSleep: z.boolean().optional(),
});
const telemetrySchema = telemetryBase.refine(
  (t) => t.source === 'manual' || t.deviceId.length > 0,
  {
    // A band reading with no device still cannot be attributed to anyone, and
    // must keep failing at the edge rather than being silently dropped later.
    message: 'deviceId is required unless source is "manual"',
    path: ['deviceId'],
  },
);
const locationSchema = z.object({
  childId: z.string().uuid(),
  // A position has to be on Earth.
  //
  // A bare z.number() accepts 5000 and, reachable over the wire because
  // JSON.parse('1e999') is Infinity, accepts Infinity too. Either then flows
  // into the geofence distance maths, where every comparison against Infinity
  // is false — so a child at that position is inside no zone, and leaving
  // none. The map would show them nowhere while every safe-zone alert quietly
  // stopped working.
  coords: z.object({
    lat: z.number().finite().min(-90).max(90),
    lng: z.number().finite().min(-180).max(180),
    // A negative radius of uncertainty is not a radius. The upper bound is
    // half the planet — past that the fix says nothing about where anyone is.
    accuracyM: z.number().finite().min(0).max(20_000_000).optional(),
  }),
  source: z.enum(['gps', 'wifi', 'lbs', 'ble']),
  observedAt: isoInstant,
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
  latestTelemetry: telemetryBase.partial({ deviceId: true, recordedAt: true }).optional(),
});
const bpCalSchema = z.object({
  userId: z.string().uuid(),
  // Bounded to physiologically possible readings. Unbounded integers here let a
  // typo — or a hostile client — write an offset that silently distorts every
  // later blood-pressure reading for this user.
  cuffSystolic: z.number().int().min(60).max(260),
  cuffDiastolic: z.number().int().min(30).max(200),
  ppgSystolic: z.number().int().min(60).max(260),
  ppgDiastolic: z.number().int().min(30).max(200),
  // Tightened while nothing calls this yet — the app has a TODO where the POST
  // will go. A calibration is dated so staleness can be judged against it
  // (bpCalibrationIsStale), and a string with no zone cannot be. Note for
  // whoever wires it: Dart's toIso8601String() omits the offset entirely on a
  // LOCAL DateTime, so send .toUtc().toIso8601String() as the ingest path
  // already does.
  measuredAt: isoInstant,
});

/// Replace id-looking path segments with `:id`.
///
/// Request logging is pino's default, which records method and url and — good
/// — neither headers nor bodies, so no readings, names, phone numbers or chat
/// messages reach it. What it did record was the URL verbatim, and these URLs
/// carry identifiers: `/admin/users/{uuid}/health` in an access log states
/// which staff member opened which patient's record, and `/children/{uuid}/
/// location` states whose child was looked up and when.
///
/// That question already has a deliberate home — the audit log, which is
/// written on purpose, queryable, and behind admin auth. Access logs are the
/// thing most likely to be shipped wholesale to a third-party aggregator, so
/// duplicating it there puts the same fact somewhere with weaker controls and
/// no retention policy.
///
/// The route SHAPE is what debugging actually needs, and that is kept.
export function redactPathIds(url: string): string {
  return url
    .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi, ':id')
    // Query strings can carry a search term — the back-office user search puts
    // a name or phone number in `?q=`.
    .replace(/\?.*$/, '?…');
}

export function buildServer(deps: ServerDeps, opts: { logger?: boolean } = {}): FastifyInstance {
  const app = Fastify({
    logger:
      opts.logger === false
        ? false
        : {
            serializers: {
              req(req) {
                return {
                  method: req.method,
                  url: redactPathIds(req.url),
                  remoteAddress: req.ip,
                };
              },
            },
          },
  });

  // 20 assistant messages per 5 minutes per user. A real conversation is
  // nowhere near this; a runaway client hits it in seconds. Overridable so the
  // tests can drive the boundary without waiting on a wall clock.
  const chatLimiter = deps.chatLimiter ?? new RateLimiter({ limit: 20, windowMs: 5 * 60_000 });

  // Ingest: see the note on the route. Generous by design — this exists to
  // bound a runaway, not to shape normal traffic.
  const ingestLimiter = deps.ingestLimiter ?? new RateLimiter({ limit: 120, windowMs: 5 * 60_000 });

  // Expired windows are dropped periodically — otherwise the map keeps one
  // entry per user who ever chatted, which is a leak that only surfaces months
  // into production. unref() so this timer never holds the process open.
  const sweeper = setInterval(() => {
    chatLimiter.sweep();
    ingestLimiter.sweep();
  }, 5 * 60_000);
  if (typeof sweeper.unref === 'function') sweeper.unref();
  app.addHook('onClose', async () => clearInterval(sweeper));

  // Liveness: the process is up. Kept trivial so it never fails for a reason a
  // restart would not fix.
  app.get('/health', async () => ({ ok: true }));

  // Readiness: the process can actually serve — its dependencies answer. A load
  // balancer routes on this, not liveness. 200 ready / 503 not-ready + breakdown.
  app.get('/ready', async (_req, reply) => {
    if (!deps.checkReady) return reply.send({ ready: true }); // in-memory dev
    try {
      const r = await deps.checkReady();
      return reply.code(r.ready ? 200 : 503).send(r);
    } catch {
      return reply.code(503).send({ ready: false });
    }
  });

  // Public reference data: the Kazakhstan antenatal 8-visit schedule, from the
  // shared contract. No auth — it is the same clinical schedule the app bundles
  // and the admin panel renders; keeping one served copy stops the three drifting.
  app.get('/antenatal/protocol', async () => antenatalProtocol);

  // Public reference data: the childhood immunisation schedule.
  app.get('/vaccination/schedule', async () => vaccinationSchedule);

  // Public reference data: the week-by-week pregnancy calendar (ru + kk).
  app.get('/pregnancy/weeks', async () => pregnancyCalendar);
  app.get('/pregnancy/weeks/:week', async (req, reply) => {
    const week = Number((req.params as { week: string }).week);
    if (!Number.isFinite(week)) return reply.code(400).send({ error: 'bad_week' });
    const content = weekContent(week);
    if (!content) return reply.code(404).send({ error: 'not_found' });
    return reply.send(content);
  });

  // Public reference data: the week-by-week baby-development calendar (ru + kk).
  app.get('/child/development', async () => childDevCalendar);
  app.get('/child/development/:week', async (req, reply) => {
    const week = Number((req.params as { week: string }).week);
    if (!Number.isFinite(week)) return reply.code(400).send({ error: 'bad_week' });
    const content = devWeekContent(week);
    if (!content) return reply.code(404).send({ error: 'not_found' });
    return reply.send(content);
  });

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

    // Ingest was left unlimited on the reasoning that it is high-volume by
    // design and dropping it would lose health data. The first half is true;
    // the second is not, because a 429 does not drop anything. The client is
    // offline-first: TelemetryBatcher requeues the whole batch on ANY failed
    // flush and retries with backoff, which is the same path it already takes
    // when the phone has no signal. So the choice is not "limit or keep the
    // data" — it is "limit, or let one authenticated client write to a
    // timeseries database as fast as it can post 500-item batches".
    //
    // Sized around the legitimate worst case, which is a drain after a long
    // spell offline: a full 5000-item queue leaves in 25 back-to-back requests
    // at maxFlushItems=200. 120 per five minutes clears that almost five times
    // over, so real traffic never meets the limit — and a runaway is bounded.
    const rl = ingestLimiter.take(caller.userId);
    if (!rl.allowed) {
      reply.header('retry-after', String(rl.retryAfterSec));
      return reply.code(429).send({
        error: 'rate_limited',
        retryAfterSec: rl.retryAfterSec,
      });
    }

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

    // Every call here costs money and reaches a third party. A broken retry
    // loop is as expensive as a hostile one, so the limit is per authenticated
    // caller and generous enough that a real conversation never meets it.
    //
    // Deliberately AFTER the auth and ownership checks: an unauthenticated or
    // forbidden request should not consume somebody else's budget, and taking
    // a token before knowing who is asking would let an attacker exhaust it.
    const rl = chatLimiter.take(caller.userId);
    if (!rl.allowed) {
      reply.header('retry-after', String(rl.retryAfterSec));
      return reply.code(429).send({
        error: 'rate_limited',
        retryAfterSec: rl.retryAfterSec,
      });
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
    const { rejectedBecause, ...offsets } = computeBpOffsets(
      d.cuffSystolic, d.cuffDiastolic, d.ppgSystolic, d.ppgDiastolic,
    );
    // Storing an implausible calibration is worse than storing none: it would
    // shift every later reading, and a large negative offset can hide exactly
    // the hypertension this app exists to catch.
    if (rejectedBecause) return reply.code(422).send({ error: rejectedBecause });
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
