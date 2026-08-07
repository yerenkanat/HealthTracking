/**
 * Composition root — wires the real collaborators into buildServer() and listens.
 * This is the ONLY place that knows about pg + Redis + firebase + Anthropic all at
 * once; every other module depends on interfaces, which is what made the safety
 * logic testable with fakes.
 */

import type { FastifyRequest } from 'fastify';
import { buildServer } from './server';
import type { ServerDeps } from './server';
import { authPosture } from './authPosture';
import { createMemoryRepository } from './db/memoryRepository';
import { logOnlySmsSender, type SmsSender } from './routes/phoneAuth';
import type { Repository } from './db/repository';
import { makeAuthUser } from './http/auth';
import { registerLanding } from './http/landing';
import { registerStaticPages } from './http/staticPages';
import { hashToken, readSessionCookie } from './http/staffAuth';
import { esc, requestBase } from './http/pageMeta';
import { createInProcessTransitions, withInProcessFallback } from './geofence/inProcessTransitions';
import { createLeadNotifier } from './notifications/leadAlert';
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
// The session verifier is bound to the repository once it exists (see below);
// until then only Firebase and the dev paths are available.
let verifyUserSession: ((token: string) => Promise<{ userId: string } | null>) | undefined;
// The dev shortcuts — the stub token and the x-user-id header — are gated on
// the SAME rule as the staff header shortcut: they exist only where there is no
// database. They used to be gated on !REAL_AUTH, which was about Firebase, so
// production (which has no Firebase and never will if we keep our own sign-in)
// left them switched on.
const authUser = (req: FastifyRequest) =>
  makeAuthUser({
    verifySessionToken: verifyUserSession,
    verifyIdToken,
    allowStubToken: ALLOW_DEV_SHORTCUTS,
  })(req);
// TODO(auth): verify a staff session/JWT with RBAC claims.
/**
 * Who is asking, for /admin — the signed-in staff session.
 *
 * This used to trust `x-staff-id` and `x-staff-role` outright, so anyone who
 * could reach the route could name themselves an admin. The only thing stopping
 * them was Caddy's basic_auth in front of it, which made a reverse-proxy line
 * the entire authorisation model.
 *
 * The header path is kept for LOCAL development only, where there is no
 * database to hold an account, and it is refused whenever a real one exists.
 */
const authAdminFor = (repo: Repository) => async (req: FastifyRequest) => {
  const token = readSessionCookie(req.headers.cookie);
  if (token) {
    const session = await repo.staffBySessionToken(hashToken(token));
    if (session) return { staffId: session.staffId, role: session.role };
  }
  if (!ALLOW_HEADER_STAFF) return null;
  const id = req.headers['x-staff-id'];
  const role = req.headers['x-staff-role'];
  const roles = ['admin', 'clinician', 'support'];
  return typeof id === 'string' && id.length > 0 && typeof role === 'string' && roles.includes(role)
    ? { staffId: id, role: role as 'admin' | 'clinician' | 'support' }
    : null;
};

/**
 * Whether the x-staff-role dev shortcut is honoured.
 *
 * Off wherever a database is configured, which is every deployment. Setting it
 * by hand in production would hand the back office to anyone who can send a
 * header, so it is deliberately not a plain boolean env var read.
 */
const ALLOW_DEV_SHORTCUTS =
  process.env.USE_MEMORY_DB === 'true' || !process.env.DATABASE_URL;
/** Kept as the old name for the staff path, which reads better at its use site. */
const ALLOW_HEADER_STAFF = ALLOW_DEV_SHORTCUTS;

/**
 * How a sign-in code reaches her phone.
 *
 * There is no gateway account yet, so there is no real sender yet. The choice
 * is deliberate and narrow:
 *
 *   * on a dev box (no DATABASE_URL / USE_MEMORY_DB) the code is written to the
 *     server log, so the whole flow can be exercised without a provider;
 *   * anywhere else, returning `undefined` leaves buildServer with its refusing
 *     sender, and `/auth/phone/start` answers 503 `sms_unavailable`.
 *
 * That second branch is the important one. Signing in used to require nothing
 * at all, and the tempting "fallback" — let her in when no SMS can be sent —
 * would put the hole straight back. Better that nobody signs in on a box with
 * no gateway than that anybody does.
 *
 * Adding a provider means returning its sender here and nothing else.
 */
function smsSender(): SmsSender | undefined {
  if (!ALLOW_DEV_SHORTCUTS) return undefined;
  return logOnlySmsSender((msg) => console.warn(msg));
}

/** Real deps: pg + Redis + Anthropic + push (loaded lazily). */
async function productionDeps(): Promise<ServerDeps> {
  const { Pool } = await import('pg');
  const { createPgRepository } = await import('./db/pgRepository');
  const { createAnthropicCaller } = await import('./ai/anthropicClient');
  const { createAnthropicVitalsExtractor } = await import('./ai/vitalsVision');
  const { createAnthropicMedicationExtractor } = await import('./ai/medicationVision');
  const { createAnthropicAppointmentExtractor } = await import('./ai/appointmentVision');
  const { getChildLastLocation, setChildLastLocation, setBpCalibration, resolveTransition } = await import('./cache/redis');
  const { emergencyCopy, geofenceCopy, sendPush, toPushLocale } =
    await import('./notifications/push');
  type PushResult = Awaited<ReturnType<typeof sendPush>>;
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const repo = createPgRepository(pool);
  // Phone sign-in for the app: a token minted by POST /auth/phone, looked up in
  // user_sessions. This is what makes authUser real without Firebase.
  verifyUserSession = async (token) => repo.userBySessionToken(hashToken(token));
  // Redis normally holds the cross-request geofence state. While it is
  // refusing connections this carries it instead, for as long as the outage
  // lasts — a cache being down must not silently switch off the alerts.
  const fallbackTransitions = withInProcessFallback(
    (childId, fenceId, inside) => resolveTransition(childId, fenceId, inside),
    (err) => console.warn(`geofence: Redis unavailable, debouncing in-process — ${err.message}`),
  );

  // Integration keys managed from the admin panel fill in any that the
  // environment doesn't already set (env always wins). Stored keys take effect
  // on the next restart, which is fine for keys that change rarely.
  //
  // GOOGLE_MAPS_API_KEY used to be copied here too, and nothing on this side
  // has ever read it: the app's map key is a BUILD-time input, baked into the
  // Android manifest from the environment of `flutter build` (see
  // android/app/build.gradle.kts). So an owner could paste a real key into the
  // panel, save it, restart the server, and the map would stay blank with
  // nothing anywhere saying why. The field is gone from the panel.
  try {
    const stored = await repo.getShopSettings();
    for (const [envName, key] of [['ANTHROPIC_API_KEY', 'anthropicApiKey']] as const) {
      if (!process.env[envName] && stored[key]) process.env[envName] = stored[key];
    }
  } catch {
    /* settings table absent (unmigrated DB) — env-only until migrated */
  }

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
      // Redis holds the cross-request geofence state. When it is unreachable,
      // debounce in this process rather than dropping the crossing: a cache
      // outage must not silently switch off the alerts this product exists to
      // send. See inProcessTransitions for what that trade costs.
      resolveTransition: fallbackTransitions,
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
    authAdmin: authAdminFor(repo),
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
    // Reads the token from shop_settings on every lead, so pasting one into the
    // admin panel takes effect immediately — unlike the API keys above, which
    // are copied into the environment at boot.
    notifyLead: createLeadNotifier({
      loadConfig: async () => {
        const s = await repo.getShopSettings();
        return { telegramBotToken: s.telegramBotToken, telegramChatId: s.telegramChatId };
      },
    }),
    setBpCalibration: (userId, offsets) =>
      setBpCalibration(userId, {
        systolicOffset: offsets.systolicOffset,
        diastolicOffset: offsets.diastolicOffset,
        calibratedAt: offsets.calibratedAt,
      }),
    cryAnalyze: forwardCry,
    // Photo → vitals / medication need the vision model; without a key the
    // routes 503 and the app falls back to manual entry rather than erroring.
    extractVitals: process.env.ANTHROPIC_API_KEY ? createAnthropicVitalsExtractor() : undefined,
    extractMedication: process.env.ANTHROPIC_API_KEY ? createAnthropicMedicationExtractor() : undefined,
    extractAppointment: process.env.ANTHROPIC_API_KEY ? createAnthropicAppointmentExtractor() : undefined,
    contentApiKey: process.env.CONTENT_API_KEY,
    sms: smsSender(),
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
  const fences = createInProcessTransitions();
  // The same line productionDeps runs, and it was missing here.
  //
  // POST /auth/phone works in memory mode — it mints a real token and stores a
  // real session — but nothing was ever wired to CHECK one, so every token it
  // handed out was rejected by every endpoint that needed it. Sign-in
  // succeeded and then the whole app API answered 401, which is the most
  // confusing possible shape for a bug: the thing that authenticates works,
  // and everything downstream says you are not authenticated.
  verifyUserSession = async (token) => repo.userBySessionToken(hashToken(token));
  return {
    repo,
    guardrail: { callLLM: async () => 'Rest and hydrate gently. (dev echo — set an ANTHROPIC key for real replies)' },
    ingest: {
      cacheLocation: async (fix) => void lastLoc.set(fix.childId, fix),
      resolveTransition: async (childId, fenceId, inside) => fences.resolve(childId, fenceId, inside),
      sendEmergencyPush: async () => {},
      sendGeofencePush: async () => {},
    },
    authUser,
    authAdmin: authAdminFor(repo),
    cacheLastLocation: async (childId) => lastLoc.get(childId) ?? null,
    setBpCalibration: async () => {},
    cryAnalyze: forwardCry, // works in dev too if a CRY_API_URL is reachable
    contentApiKey: process.env.CONTENT_API_KEY,
    sms: smsSender(),
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

  // The pages a person reaches by typing an address. They used to be written
  // out here, in the boot file, which no test can import — so /admin/ui, /shop
  // and the social cards sat outside every guard the rest of the code has, and
  // two 404s reached production before anyone noticed. See http/staticPages.ts.
  {
    const pages = registerStaticPages(app);
    if (!pages.adminUi) app.log.warn('admin dashboard html not found; /admin/ui disabled');
    if (!pages.apiDocs) app.log.warn('api docs html not found; /api-docs disabled');
    if (!pages.shop) app.log.warn('shop storefront images not found; /shop pages disabled');

    // Serving the panel grants nothing on its own: it opens on the sign-in
    // form, and every request behind it needs the staff session cookie. That
    // is only true while the x-staff-role shortcut is off, which it is
    // wherever DATABASE_URL is set — so say so when it is not, rather than
    // warning unconditionally and training everyone to ignore the line.
    if (pages.adminUi && ALLOW_HEADER_STAFF) {
      app.log.warn(
        '/admin/ui is served unauthenticated AND the x-staff-role shortcut is ' +
          'enabled (no DATABASE_URL) — reaching this route is equivalent to ' +
          'admin access. Local development only.',
      );
    }
  }

  // ---- The Ana-Bala landing page (the site root) ------------------------------
  // Built from the exported artifact by tools/build-landing.mjs — see its header
  // for why we unpack rather than serve the export as-is. Everything under
  // /landing/a/ is content-addressed by uuid and regenerated on each build, so
  // it is immutable for as long as the URL exists: cache it for a year. The HTML
  // itself must never be cached that way — it is what points at new asset uuids.
  try {
    const assets = registerLanding(app);
    app.log.info(`landing page served at / (${assets} assets)`);
  } catch (err) {
    // Without this the root is a 404 — loud, because it is the whole site.
    app.log.error({ err }, 'landing page not built; / is unavailable. Run: node packages/backend/tools/build-landing.mjs');
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
  //
  // REAL_AUTH secures only the USER path; authAdmin is a separate header stub that
  // it does NOT cover. Guarding on `!REAL_AUTH` alone let a REAL_AUTH=1 deploy ship
  // a back-office anyone could enter with a forged x-staff-role header, while the
  // log said authentication was real. The guard now refuses whenever EITHER path
  // is still a stub.
  const posture = authPosture(process.env);
  const usingStubAuth = posture.userStub || posture.adminStub;
  if (usingStubAuth && process.env.NODE_ENV === 'production') {
    app.log.fatal(
      'Refusing to start: authentication is still a development stub, which anyone ' +
        'who can reach the port can forge. ' +
        (posture.userStub
          ? 'User auth: set REAL_AUTH=1 with a Firebase service account. '
          : '') +
        (posture.adminStub
          ? 'Staff/back-office auth still trusts x-staff-id / x-staff-role — no real ' +
            'verifier is wired, and REAL_AUTH does not cover it. '
          : ''),
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
