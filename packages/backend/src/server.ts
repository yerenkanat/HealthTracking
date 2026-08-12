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
import { phoneCodeWarning } from './authPosture';
import { grantCovers } from './family/access';
import { checkGeofenceBoundary } from './geofence/geofence';
import { scheduleRouteRetention, type RetentionResult } from './privacy/retention';
import { handleIngestBatch, type IngestDeps } from './routes/ingestHandler';
import {
  processWithGuardrails,
  type GuardrailDeps,
} from './ai/AIGuardrailProcessor';
import { computeBpOffsets } from './health/bpCalibration';
import { registerCrudRoutes, type AuthUser } from './routes/crud';
import type { LeadNotifier } from './notifications/leadAlert';
import { registerAdminRoutes, type AdminNotifiers, type AuthAdmin } from './routes/admin';
import { registerStaffLoginRoutes } from './routes/staffLogin';
import { registerPhoneAuthRoutes } from './routes/phoneAuth';
import { registerStaffAdminRoutes } from './routes/staffAdmin';
import { registerInventoryRoutes } from './routes/inventory';
import { registerEntitlementRoutes } from './routes/entitlements';
import { registerPublicApiRoutes } from './routes/publicApi';
import type { SmsSender } from './routes/phoneAuth';
import { RateLimiter } from './http/rateLimit';
import { antenatalProtocol } from './antenatal/protocol';
import { servedCalendar, weekOf } from './pregnancy/served';
import { childDevCalendar, devWeekContent } from './child/development';
import { appVersionInfo } from './app/version';
import { vaccinationSchedule } from './vaccination/schedule';
import type { VitalsExtractor } from './ai/vitalsVision';
import type { MedicationExtractor } from './ai/medicationVision';
import type { AppointmentExtractor } from './ai/appointmentVision';
import type { Repository } from './db/repository';

export interface ServerDeps {
  repo: Repository;
  ingest: Omit<IngestDeps, 'repo'>;
  guardrail: GuardrailDeps;
  /// Injected so tests can drive the boundary without a real clock. Defaults
  /// to 20 messages per 5 minutes per authenticated user.
  chatLimiter?: RateLimiter;
  /// Same, for /ingest/batch. Defaults to 120 requests per 5 minutes.
  ingestLimiter?: RateLimiter;
  /// Backstop for all other authenticated writes (sync endpoints). Defaults to
  /// 1000 per 5 minutes per identity — far above any real client, so it only
  /// ever bounds a runaway/abusive one. /ingest and /ai/chat keep their own.
  writeLimiter?: RateLimiter;
  cacheLastLocation: (childId: string) => Promise<unknown>;
  /** Tell staff about a new callback request. Omitted = no channel configured;
   *  the lead is still recorded. Must never throw — see notifications/leadAlert. */
  notifyLead?: LeadNotifier;
  setBpCalibration: (userId: string, offsets: { systolicOffset: number; diastolicOffset: number; calibratedAt: string }) => Promise<void>;
  /** Resolve the caller's user from the request (verify Firebase token in prod). */
  authUser?: AuthUser;
  /** Resolve the caller's staff identity + role for /admin routes. */
  authAdmin?: AuthAdmin;
  /** Readiness: pings the real dependencies (DB, Redis). Omitted = always ready
   * (in-memory dev). /ready reports 503 with the per-dependency breakdown when
   * any is down, so a load balancer can pull the instance before it serves errors. */
  checkReady?: () => Promise<{ ready: boolean; deps?: Record<string, boolean> }>;
  /** Forward a recorded cry clip to the (separate, internal) cry-classifier
   * service and return its JSON. Injected so the route is testable without the
   * Python service; omitted = the feature is unavailable (route 503s). */
  cryAnalyze?: (audio: Buffer, contentType: string) => Promise<unknown>;
  /** Read vitals off a photo of a device/lab slip (Claude vision). Injected so
   * the route is testable without the network; omitted (no API key) = the
   * feature is unavailable and /vitals/extract returns 503. */
  extractVitals?: VitalsExtractor;
  /** Read a medication (name/dose/times-a-day) off a photo of a prescription or
   * box. Same injection contract as extractVitals; /medications/extract 503s
   * when omitted. */
  extractMedication?: MedicationExtractor;
  /** Read an appointment (title/date/time/place) off a photo of a referral slip
   * or talon. Same contract; /appointments/extract 503s when omitted. */
  extractAppointment?: AppointmentExtractor;
  /** API key for the public content API (/api/v1/*). When set, every request must
   * carry it as `x-api-key`; omitted = the API is open (dev). */
  contentApiKey?: string;
  /**
   * How the sign-in code is sent. Omitted means NO gateway is configured, and
   * /auth/phone/start answers 503 rather than letting anyone in — the failure
   * this replaced was exactly a sign-in that asked for nothing.
   */
  sms?: SmsSender;
  /**
   * Require an SMS code to sign in. Off today — there is no gateway, and
   * demanding a code nobody can receive locks every customer out.
   *
   * The whole verified flow is built and tested behind this; turning it on is
   * this flag plus a real [sms], with no app release. See routes/phoneAuth.ts
   * for what leaving it off costs.
   */
  requirePhoneCode?: boolean;
  /**
   * What the OPERATOR asked for — REQUIRE_PHONE_CODE=1 in the environment —
   * regardless of whether it could be honoured.
   *
   * Separate from [requirePhoneCode], which is the EFFECTIVE gate: the
   * composition root ANDs the request with the existence of a sender, and there
   * is no sender on any deployment with a database. The two therefore disagree
   * exactly when somebody has switched verification on and got nothing, which
   * is the one case worth shouting about — so it is carried rather than
   * collapsed, warned about at boot, and shown on «Интеграции».
   */
  phoneCodeRequested?: boolean;
  /**
   * Whether push can actually DELIVER — frame 24 «Интеграции».
   *
   * `ingest.sendEmergencyPush` is always supplied, including as a no-op by
   * every test, so its presence proves nothing. firebase-admin authenticates
   * with applicationDefault(), which needs a service-account credential on the
   * server; without one, sends fail at the point of use and an SOS reaches
   * nobody whose app is closed. Set by the composition root, which is the only
   * place that knows.
   *
   * False by default: reporting an alarm channel as working when it is not is
   * the wrong direction to be wrong in.
   */
  pushIsReal?: boolean;
  /**
   * Refuse pairing for a device that is not in our registry.
   *
   * OFF by default. The day it goes on, every unit missing from the registry
   * is a paying customer who cannot use what she bought — so it ships in
   * log-only mode and somebody reads that log first.
   */
  enforceDeviceRegistry?: boolean;
  /**
   * Tell a customer an operator answered her — frame 43.
   *
   * Omitted = no push channel on this box; the reply is still saved and the
   * panel still reports success, because it succeeded. See AdminNotifiers.
   */
  notifySupportReply?: AdminNotifiers['supportReply'];
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
    // Blood glucose in mmol/L. A wide, physiologically-possible band — reject the
    // impossible, not the alarming (a real hypo/hyper must get through).
    glucoseMmol: z.number().finite().min(1).max(40).optional(),
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
// A photographed device/lab slip, base64-encoded. Bounded so a hostile client
// cannot post gigabytes: ~9M base64 chars ≈ a 6.7 MB image, and the route's own
// 7 MB bodyLimit rejects anything larger before this even runs.
const extractSchema = z.object({
  imageBase64: z.string().min(16).max(9_000_000),
  mediaType: z.enum(['image/jpeg', 'image/png', 'image/webp']),
});
const bpCalSchema = z.object({
  // OPTIONAL, and checked only if sent. Identity comes from the session — every
  // other user-scoped write derives it from the caller and takes no body userId.
  // Requiring it here made the route unimplementable: the app holds a session
  // token, not its own internal DB uuid, so it could never echo a matching id.
  // The app now omits it, and the offsets are written for `caller.userId`.
  userId: z.string().uuid().optional(),
  // Bounded to physiologically possible readings. Unbounded integers here let a
  // typo — or a hostile client — write an offset that silently distorts every
  // later blood-pressure reading for this user.
  cuffSystolic: z.number().int().min(60).max(260),
  cuffDiastolic: z.number().int().min(30).max(200),
  ppgSystolic: z.number().int().min(60).max(260),
  ppgDiastolic: z.number().int().min(30).max(200),
  // A calibration is dated so staleness can be judged against it
  // (bpCalibrationIsStale), and a string with no zone cannot be. Note for the
  // app: Dart's toIso8601String() omits the offset entirely on a LOCAL DateTime,
  // so it sends .toUtc().toIso8601String() as the ingest path already does.
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
///
/// A uuid rule is not enough on its own, because the identifiers that hurt
/// most are not uuids. They are matched by ROUTE rather than by shape: a
/// blanket "redact the last segment" would eat `/admin/content/w20` and
/// `/pregnancy/weeks/32`, which name content and no person, while still
/// missing anything sitting mid-path. Each entry below names one route whose
/// own parameter is a secret or points at a human, and each keeps the rest of
/// the shape intact.
///
/// Every rule carries `i`, like the uuid rule above. Nothing normalises the
/// case of an incoming URL before it is logged — Caddy passes the path through
/// as sent — so `GET /JOIN/<token>` reached the serializer as-is, an anchored
/// case-sensitive rule did not match it, and the token went to stdout in full
/// while the redaction looked like it was working.
const SENSITIVE_PATH_SEGMENTS: ReadonlyArray<readonly [RegExp, string]> = [
  // `/join/<token>` is the whole grant. The token is base64url of
  // randomBytes(32) — no dashes, no query string, so neither rule above
  // touched it — and for 24 hours it is redeemable by ANYONE who has it, for
  // a child's live location and day trail. A log line is a copy of the key.
  [/^\/join\/[^/?]+/i, '/join/:token'],
  // The same grant seen from the other end: `:tokenHash` is the sha256 of
  // that token, the handle the owner revokes by. Not redeemable itself, but
  // it names one specific live invitation to one specific child, which is the
  // fact the access log is not the place for. `accept` is a literal route
  // segment, not a hash, and is kept so the accept path stays debuggable.
  [/^\/family\/invites\/(?!accept(?:[/?]|$))[^/?]+/i, '/family/invites/:tokenHash'],
  // A customer's phone number, in the URL, on a staff action. The feature is
  // kept — knowing a course entitlement was revoked is the debuggable part;
  // knowing whose is the audit log's job, and it already records it.
  [/^\/admin\/entitlements\/([^/?]+)\/[^/?]+/i, '/admin/entitlements/$1/:phone'],
  // A device serial is a MAC. device_registry carries `activated_by_phone`
  // beside it, so a serial in a log resolves to a named customer with one
  // query — a personal identifier wearing a hardware label.
  [/^\/admin\/device-registry\/[^/?]+/i, '/admin/device-registry/:serial'],
];

export function redactPathIds(url: string): string {
  let out = url
    .replace(/\b[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\b/gi, ':id')
    // Query strings can carry a search term — the back-office user search puts
    // a name or phone number in `?q=`.
    .replace(/\?.*$/, '?…');
  for (const [pattern, shape] of SENSITIVE_PATH_SEGMENTS) out = out.replace(pattern, shape);
  return out;
}

export function buildServer(
  deps: ServerDeps,
  opts: {
    logger?: boolean;
    /// Where the log actually goes. Injected ONLY so a test can read what was
    /// written: the redaction bug that survived a green suite did so because
    /// every test called redactPathIds directly and nothing ever asserted on
    /// the bytes the logger emits. See __tests__/logRedaction.test.ts.
    logStream?: { write(msg: string): void };
  } = {},
): FastifyInstance {
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
            ...(opts.logStream ? { stream: opts.logStream } : {}),
          },
  });

  // Fastify's own 404 answer logs `Route ${method}:${url} not found` — a
  // message STRING, which no `req` serializer touches. So a NEAR-MISS URL went
  // to stdout verbatim right beside the correctly-redacted «incoming request»
  // line: `/join/<token>/` with one trailing slash (Caddy passes it through
  // unnormalised) printed a live, redeemable invitation token, and
  // `GET /admin/entitlements/course/+7701…` — the wrong verb for a DELETE
  // route — printed a customer's phone number.
  //
  // Same answer as Fastify's, with the path redacted the one way this server
  // redacts paths. The body carries the redacted path too: the caller already
  // knows what it asked for, so echoing it back buys nothing.
  app.setNotFoundHandler((req, reply) => {
    const message = `Route ${req.method}:${redactPathIds(req.url)} not found`;
    req.log.info(message);
    reply.code(404).type('application/json; charset=utf-8').send({
      message,
      error: 'Not Found',
      statusCode: 404,
    });
  });

  // The cry-analysis proxy forwards the raw multipart body straight through to
  // the classifier service, so buffer multipart/form-data verbatim rather than
  // parsing fields here. Only /cry/analyze sends this content-type; everything
  // else is JSON and untouched. Capped at 6 MB — a 5-second clip is well under.
  app.addContentTypeParser(
    /^multipart\/form-data/,
    { parseAs: 'buffer', bodyLimit: 6 * 1024 * 1024 },
    (_req, body, done) => done(null, body),
  );

  // Daily-calendar audio clips uploaded from the admin panel arrive as raw audio
  // bytes on POST /admin/audio/*. Buffer them (capped at 15 MB — a spoken clip is
  // well under); the route validates the type and stores them.
  app.addContentTypeParser(
    /^audio\//,
    { parseAs: 'buffer', bodyLimit: 15 * 1024 * 1024 },
    (_req, body, done) => done(null, body),
  );

  // 20 assistant messages per 5 minutes per user. A real conversation is
  // nowhere near this; a runaway client hits it in seconds. Overridable so the
  // tests can drive the boundary without waiting on a wall clock.
  const chatLimiter = deps.chatLimiter ?? new RateLimiter({ limit: 20, windowMs: 5 * 60_000 });

  // Ingest: see the note on the route. Generous by design — this exists to
  // bound a runaway, not to shape normal traffic.
  const ingestLimiter = deps.ingestLimiter ?? new RateLimiter({ limit: 120, windowMs: 5 * 60_000 });

  // Every OTHER authenticated write (the sync endpoints) shares one generous
  // per-identity budget, so no single route needs its own limiter and a runaway
  // client is bounded whichever endpoint it hammers. Applied via a preHandler
  // below. Keyed by a cheap identity (the auth header) — a throttle bucket, not
  // a security check; real auth still runs in each route.
  const writeLimiter = deps.writeLimiter ?? new RateLimiter({ limit: 1000, windowMs: 5 * 60_000 });
  app.addHook('preHandler', async (req, reply) => {
    if (req.method === 'GET' || req.method === 'HEAD' || req.method === 'OPTIONS') return;
    const url = req.url;
    // These carry their own limiter, or are staff/public and not user writes.
    if (url.startsWith('/ingest') || url.startsWith('/ai/') || url.startsWith('/admin')) return;
    const key = String(req.headers['authorization'] ?? req.headers['x-user-id'] ?? req.ip);
    const rl = writeLimiter.take(key);
    if (!rl.allowed) {
      reply.header('retry-after', String(rl.retryAfterSec));
      return reply.code(429).send({ error: 'rate_limited', retryAfterSec: rl.retryAfterSec });
    }
  });

  // Expired windows are dropped periodically — otherwise the map keeps one
  // entry per user who ever chatted, which is a leak that only surfaces months
  // into production. unref() so this timer never holds the process open.
  const sweeper = setInterval(() => {
    chatLimiter.sweep();
    ingestLimiter.sweep();
    writeLimiter.sweep();
  }, 5 * 60_000);
  if (typeof sweeper.unref === 'function') sweeper.unref();
  app.addHook('onClose', async () => clearInterval(sweeper));

  // «Маршруты хранятся 90 дней» — the one promise this product makes that has
  // to be kept by DOING something on a schedule. db/schema.sql has carried the
  // DELETE as a comment since the Timescale retention policy was dropped, with
  // a note to run it from pg_cron "or an app cron". This is that app cron: a
  // note is not a job, and every child's trail has been kept since the first
  // fix. See privacy/retention.ts.
  const stopRetention = scheduleRouteRetention(deps.repo, {
    log: (r: RetentionResult) => {
      // Logged either way. A retention sweep that stops running is invisible
      // unless success is as loud as failure.
      if (r.error) app.log.error({ err: r.error, cutoff: r.cutoff }, 'route retention sweep failed');
      else if (r.removed > 0) app.log.info({ removed: r.removed, cutoff: r.cutoff }, 'pruned location history');
      else app.log.debug({ cutoff: r.cutoff }, 'route retention: nothing older than the window');
    },
  });
  app.addHook('onClose', async () => stopRetention());

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

  // Public app-version policy: the app checks this on launch to force or nudge
  // an update. No auth — a too-old client must be able to learn it is too old.
  app.get('/app/version', async () => appVersionInfo());

  // Public reference data: the childhood immunisation schedule.
  app.get('/vaccination/schedule', async () => vaccinationSchedule);

  // Public reference data: the week-by-week pregnancy calendar (ru + kk).
  //
  // The shipped contract WITH the back office's edits on top — frames 14a/14b.
  // Until this merge existed the route served a compiled-in file, so a typo in
  // week 22 was a release; now the panel changes it and this changes with it.
  // `version` moves on every edit so a client caching the calendar knows.
  //
  // The app still bundles the contract as an asset and layers this over it, so
  // a phone with no signal reads the shipped week rather than nothing.
  app.get('/pregnancy/weeks', async () => servedCalendar(deps.repo));
  app.get('/pregnancy/weeks/:week', async (req, reply) => {
    const week = Number((req.params as { week: string }).week);
    if (!Number.isFinite(week)) return reply.code(400).send({ error: 'bad_week' });
    const content = weekOf(await servedCalendar(deps.repo), week);
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

  // Public daily-calendar audio playback: streams the clip for a given
  // (track, day, locale). Ungated so the app can play it directly; the bytes are
  // uploaded/managed from the admin panel. 404 when that day has no clip.
  app.get('/audio/:track/:day/:locale', async (req, reply) => {
    const { track, day, locale } = req.params as { track: string; day: string; locale: string };
    const d = Number(day);
    if ((track !== 'pregnancy' && track !== 'child') || !Number.isInteger(d) || (locale !== 'ru' && locale !== 'kk')) {
      return reply.code(400).send({ error: 'bad_request' });
    }
    const a = await deps.repo.getDailyAudio(track, d, locale);
    if (!a) return reply.code(404).send({ error: 'not_found' });
    // Range support (206) — Android's MediaPlayer streams audio over HTTP with a
    // Range request and refuses a plain 200 for some sources, so honour it.
    const total = a.bytes.length;
    reply.header('accept-ranges', 'bytes').header('cache-control', 'public, max-age=3600').type(a.mime);
    const range = /^bytes=(\d*)-(\d*)$/.exec(String(req.headers.range ?? ''));
    if (range) {
      const start = range[1] ? parseInt(range[1], 10) : 0;
      let end = range[2] ? parseInt(range[2], 10) : total - 1;
      if (Number.isNaN(start) || start >= total || start < 0) {
        return reply.code(416).header('content-range', `bytes */${total}`).send();
      }
      end = Math.min(Number.isNaN(end) ? total - 1 : end, total - 1);
      return reply.code(206).header('content-range', `bytes ${start}-${end}/${total}`).send(a.bytes.subarray(start, end + 1));
    }
    return reply.header('content-length', String(total)).send(a.bytes);
  });

  // Client CRUD + history routes (require an authUser resolver).
  if (deps.authUser) {
    registerCrudRoutes(app, deps.repo, deps.authUser, deps.notifyLead,
      deps.enforceDeviceRegistry ?? false);
  }
  // Admin / back-office routes (require an authAdmin resolver).
  // Sign-in first: these three are the only /admin paths without a session, and
  // registering them here keeps that fact in one place.
  registerStaffLoginRoutes(app, deps.repo);
  registerPhoneAuthRoutes(
    app,
    deps.repo,
    deps.sms ?? {
      newCode: () => '000000',
      // Only reached when a code IS required and no gateway exists, which is a
      // misconfiguration: refuse rather than inventing a code nobody receives.
      send: async () => false,
    },
    deps.requirePhoneCode ?? false,
  );

  // ---- The code gate that cannot engage -----------------------------------
  //
  // Said here rather than in index.ts so it is on the path every deployment AND
  // every test takes, and so it can be proved to fire. onReady, because a line
  // logged while the server is still assembling is the easiest one to lose.
  const phoneCodeAlarm = phoneCodeWarning(
    deps.phoneCodeRequested ?? false, !!deps.sms);
  if (phoneCodeAlarm) app.addHook('onReady', async () => { app.log.warn(phoneCodeAlarm); });
  if (deps.authAdmin) registerAdminRoutes(app, deps.repo, deps.authAdmin, {
    // What was ACTUALLY injected, for frame 24. `deps.sms` being present is the
    // only honest signal that codes can be sent — index.ts substitutes a
    // console logger under dev shortcuts, and that one is deliberately not
    // passed here, so the panel reports SMS as off rather than as working.
    smsSenderIsReal: !!deps.sms,
    requirePhoneCode: deps.requirePhoneCode ?? false,
    // What was ASKED for, so the screen can report a REQUIRE_PHONE_CODE=1 that
    // is being ignored instead of showing the same "выключен" as an operator
    // who never set it.
    phoneCodeRequested: deps.phoneCodeRequested ?? false,
    // Emergency push is injected by index.ts only when a real sender loads.
    pushWired: !!deps.pushIsReal,
  }, { supportReply: deps.notifySupportReply });
  if (deps.authAdmin) registerStaffAdminRoutes(app, deps.repo, deps.authAdmin);
  if (deps.authAdmin) registerInventoryRoutes(app, deps.repo, deps.authAdmin);
  if (deps.authAdmin && deps.authUser) registerEntitlementRoutes(app, deps.repo, deps.authAdmin, deps.authUser);
  // Public content API (/api/v1) — calendars, protocols, personalised timelines
  // for an external consumer (e.g. a WhatsApp bot). Key-gated when configured.
  registerPublicApiRoutes(app, deps.repo, { apiKey: deps.contentApiKey });

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

  // Authenticated proxy to the cry-classifier service, so the app talks to one
  // API surface (with the session token) instead of a second service directly.
  // The raw multipart body is forwarded verbatim; the classifier extracts the
  // `file` field itself.
  app.post('/cry/analyze', async (req, reply) => {
    const caller = await requireCaller(req, reply);
    if (!caller) return;
    if (!deps.cryAnalyze) return reply.code(503).send({ error: 'cry_service_unavailable' });
    const body = req.body;
    if (!Buffer.isBuffer(body) || body.length === 0) {
      return reply.code(400).send({ error: 'empty_audio' });
    }
    try {
      const result = await deps.cryAnalyze(body, String(req.headers['content-type'] ?? 'application/octet-stream'));
      return reply.send(result);
    } catch {
      // Upstream (the classifier) is down or errored — a clean 502, not a 500.
      return reply.code(502).send({ error: 'cry_upstream_unavailable' });
    }
  });

  // Read vitals off a photo of a home device or a lab slip, so the user can snap
  // a picture instead of typing. The image rides as base64 in JSON (the app
  // downscales it first), so this one route lifts the body limit to 7 MB while
  // every other JSON route keeps the tight default. Returns the values it could
  // read; the app pre-fills them and the user still confirms and saves normally.
  app.post('/vitals/extract', { bodyLimit: 7 * 1024 * 1024 }, async (req, reply) => {
    const caller = await requireCaller(req, reply);
    if (!caller) return;
    if (!deps.extractVitals) return reply.code(503).send({ error: 'vision_unavailable' });
    const parsed = extractSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    // Each call reaches a paid third party, so bound it per user exactly like the
    // chat assistant — a broken retry loop costs as much as a hostile one.
    const rl = chatLimiter.take(caller.userId);
    if (!rl.allowed) {
      reply.header('retry-after', String(rl.retryAfterSec));
      return reply.code(429).send({ error: 'rate_limited', retryAfterSec: rl.retryAfterSec });
    }
    try {
      const vitals = await deps.extractVitals(parsed.data.imageBase64, parsed.data.mediaType);
      return reply.send(vitals);
    } catch {
      return reply.code(502).send({ error: 'vision_upstream_unavailable' });
    }
  });

  // Read a medication off a photo of a prescription, label, or box. Same shape
  // and guards as /vitals/extract — image as base64 JSON, 7 MB cap, per-user
  // rate limit — returning name/dose/times-a-day for the editor to pre-fill.
  app.post('/medications/extract', { bodyLimit: 7 * 1024 * 1024 }, async (req, reply) => {
    const caller = await requireCaller(req, reply);
    if (!caller) return;
    if (!deps.extractMedication) return reply.code(503).send({ error: 'vision_unavailable' });
    const parsed = extractSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    const rl = chatLimiter.take(caller.userId);
    if (!rl.allowed) {
      reply.header('retry-after', String(rl.retryAfterSec));
      return reply.code(429).send({ error: 'rate_limited', retryAfterSec: rl.retryAfterSec });
    }
    try {
      const med = await deps.extractMedication(parsed.data.imageBase64, parsed.data.mediaType);
      return reply.send(med);
    } catch {
      return reply.code(502).send({ error: 'vision_upstream_unavailable' });
    }
  });

  // Read an appointment off a photo of a referral slip / talon. Same shape and
  // guards as the other extract routes; returns title/date/time/place for the
  // editor to pre-fill, with the pickers right there to correct a misread.
  app.post('/appointments/extract', { bodyLimit: 7 * 1024 * 1024 }, async (req, reply) => {
    const caller = await requireCaller(req, reply);
    if (!caller) return;
    if (!deps.extractAppointment) return reply.code(503).send({ error: 'vision_unavailable' });
    const parsed = extractSchema.safeParse(req.body);
    if (!parsed.success) return reply.code(400).send({ error: parsed.error.flatten() });

    const rl = chatLimiter.take(caller.userId);
    if (!rl.allowed) {
      reply.header('retry-after', String(rl.retryAfterSec));
      return reply.code(429).send({ error: 'rate_limited', retryAfterSec: rl.retryAfterSec });
    }
    try {
      const appt = await deps.extractAppointment(parsed.data.imageBase64, parsed.data.mediaType);
      return reply.send(appt);
    } catch {
      return reply.code(502).send({ error: 'vision_upstream_unavailable' });
    }
  });

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
    // If a userId is sent it must be the caller's — a client may not write another
    // account's calibration. When omitted (the app's path), identity is the
    // session's alone.
    if (parsed.data.userId && parsed.data.userId !== caller.userId) {
      return reply.code(403).send({ error: 'forbidden' });
    }
    const userId = caller.userId;
    const d = parsed.data;
    const { rejectedBecause, ...offsets } = computeBpOffsets(
      d.cuffSystolic, d.cuffDiastolic, d.ppgSystolic, d.ppgDiastolic,
    );
    // Storing an implausible calibration is worse than storing none: it would
    // shift every later reading, and a large negative offset can hide exactly
    // the hypertension this app exists to catch.
    if (rejectedBecause) return reply.code(422).send({ error: rejectedBecause });
    await deps.repo.insertBpCalibration(userId, {
      ...offsets,
      calibratedAt: d.measuredAt,
      cuffSystolic: d.cuffSystolic,
      cuffDiastolic: d.cuffDiastolic,
      ppgSystolic: d.ppgSystolic,
      ppgDiastolic: d.ppgDiastolic,
    });
    await deps.setBpCalibration(userId, { ...offsets, calibratedAt: d.measuredAt });
    return reply.send({ ok: true, ...offsets });
  });

  // Her latest calibration, for the new-device restore. The app keeps only the
  // offset locally; this returns it (with the raw cuff+ppg) so a fresh install
  // resumes correcting the band's BP instead of reporting raw PPG.
  app.get('/calibration/bp', async (req, reply) => {
    const caller = await requireCaller(req, reply);
    if (!caller) return;
    return reply.send({ calibration: await deps.repo.latestBpCalibration(caller.userId) });
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
    if (!owner) return reply.code(403).send({ error: 'forbidden' });
    if (owner.userId !== user.userId) {
      // A relative let in on screen 40. This route lives here rather than in
      // crud.ts, so it did not get requireChildAccess with the others — and
      // "where is she now" is the single thing family access exists for. A
      // father could read the day's trail and the zones and not the live pin.
      const level = await deps.repo
        .familyLevel(owner.userId, user.userId)
        .catch(() => null);
      if (!grantCovers(level ?? '', 'child_location')) {
        return reply.code(403).send({ error: 'forbidden' });
      }
    }
    // Redis first (this is the latency-sensitive read the cache exists for),
    // then the table every fix is also written to on the way in.
    //
    // index.ts documents that "Redis failure degrades to the DB path rather
    // than taking the service down", and leaves Redis out of the readiness
    // check on that basis. It did not degrade: a cache outage threw straight
    // out of the handler, so the box reported itself ready while answering
    // "where is my child" with a 500. Now the outage costs latency only.
    let last: unknown = null;
    try {
      last = await deps.cacheLastLocation(id);
    } catch (err) {
      req.log.warn({ err, childId: id }, 'location cache unavailable; falling back to the database');
    }
    last ??= await deps.repo.lastLocation(id);
    if (!last) return reply.code(404).send({ error: 'no recent location' });
    return reply.send(last);
  });

  return app;
}
