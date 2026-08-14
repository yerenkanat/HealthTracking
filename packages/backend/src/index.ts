/**
 * Composition root — wires the real collaborators into buildServer() and listens.
 * This is the ONLY place that knows about pg + Redis + firebase + Anthropic all at
 * once; every other module depends on interfaces, which is what made the safety
 * logic testable with fakes.
 */

import type { FastifyRequest } from 'fastify';
import { buildServer } from './server';
import type { ServerDeps } from './server';
import { authPosture, phoneCodePosture } from './authPosture';
import { isStaffRole } from './auth/capabilities';
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
  return typeof id === 'string' && id.length > 0 && isStaffRole(role)
    ? { staffId: id, role }
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
 *
 * READ THAT LAST LINE AGAIN BEFORE TRUSTING REQUIRE_PHONE_CODE. Because this
 * returns undefined whenever a database exists, `REQUIRE_PHONE_CODE=1 &&
 * !!smsSender()` is false on every deployment, and the code gate can never
 * engage no matter what is put in the environment. Turning verification on is
 * a change HERE, not a change in backend.env — see phoneCodePosture() and the
 * boot warning it feeds.
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
  const { announcementCopy, emergencyCopy, geofenceCopy, sendPush, sosCopy, supportReplyCopy, toPushLocale } =
    await import('./notifications/push');
  const { createPushDispatch } = await import('./notifications/dispatch');
  const pool = new Pool({ connectionString: process.env.DATABASE_URL });
  const repo = createPgRepository(pool);
  // One call, so the effective flag and the warning can never disagree — and so
  // it is impossible to read `requirePhoneCode` below without also carrying
  // what the operator actually asked for.
  const phoneCode = phoneCodePosture(process.env, !!smsSender());
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

  /**
   * The ONE way this process sends a push — frame 25.
   *
   * It consults her notification switches and her quiet hours (in HER
   * timezone, off `users.timezone`), forgets the tokens FCM declares dead, and
   * writes one `push_deliveries` row per attempt INCLUDING the held ones.
   *
   * This replaced a local `afterPush(kind, res)` that pruned dead tokens and
   * console.warn'd the rest. Two things were wrong with it and both are the
   * same defect: nothing consulted the preferences the app had been collecting
   * for months, and nothing anywhere recorded that a notification had not gone
   * out — so «мне не пришло» had no answer but a guess.
   *
   * `deliver` never holds an `emergency` or an `sos`. That rule lives in
   * notifications/gate.ts, in one function, so it cannot be half-applied here.
   */
  const push = createPushDispatch({
    repo,
    send: sendPush,
    warn: (line) => console.warn(line),
  });
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
      // NEVER gated. `emergency` is her own vitals crossing a threshold the
      // triage module calls serious; no switch and no quiet hour holds it, and
      // the dispatcher enforces that rather than trusting this call site.
      sendEmergencyPush: async (userId, triage) => {
        const { tokens, locale } = await repo.guardianPushTokensForUser(userId);
        await push.deliver('emergency', userId, tokens, emergencyCopy(triage, toPushLocale(locale)));
      },
      // Gated by «Зоны». The owner is read from the CHILD rather than assumed,
      // because the preferences belong to a person and this event names only a
      // child — without the lookup the gate would have nobody to ask and every
      // zone alert would go out regardless, which is the bug being fixed.
      sendGeofencePush: async (evt) => {
        const { tokens, childName, locale } = await repo.guardianPushTokens(evt.childId);
        const owner = await repo.childOwner(evt.childId).catch(() => null);
        await push.deliver(
          'geofence',
          owner?.userId ?? null,
          tokens,
          geofenceCopy(evt, childName, toPushLocale(locale)),
        );
      },
    },
    // Screen 21 — a child pressed the button.
    //
    // The one push that goes to more than one household member. Everybody with
    // family access can READ the alert feed (family/access.ts: `child_alerts`
    // is in SHAREABLE for both levels), and the whole point of screen 40 is
    // that the father and the grandmother find out too — so the alarm goes to
    // the owner's devices AND to each member's, rather than only to the phone
    // the mother happens to be holding.
    //
    // The child's NAME is read from her own children rather than from
    // guardianPushTokens's join, which falls back to a literal when the owner
    // has no registered device: a name nobody chose must never appear on this
    // notification. No name means the copy that needs none.
    notifySos: async (userId, alert) => {
      const kids = await repo.listChildren(userId).catch(() => []);
      const child = kids.find((k) => k.id === alert.childId);
      // Where she was, best-effort. The cache first (it is what the live map
      // reads), the table behind it, and no position at all rather than a stale
      // guess if both are unavailable — screen 21 has wording for that.
      let coords: { lat: number; lng: number } | null = null;
      try {
        const fix =
          ((await getChildLastLocation(alert.childId)) as
            | { coords?: { lat?: number; lng?: number } }
            | null) ?? (await repo.lastLocation(alert.childId));
        const c = (fix as { coords?: { lat?: number; lng?: number } } | null)?.coords;
        if (typeof c?.lat === 'number' && typeof c?.lng === 'number') {
          coords = { lat: c.lat, lng: c.lng };
        }
      } catch {
        // No position is a state the screen can say out loud.
      }
      const members = await repo.familyMembers(userId).catch(() => []);
      const audience = [userId, ...members.map((m) => m.memberUserId)];
      const seen = new Set<string>();
      for (const recipient of audience) {
        if (seen.has(recipient)) continue;
        seen.add(recipient);
        const { tokens, locale } = await repo.guardianPushTokensForUser(recipient);
        // NO EARLY `continue` FOR AN EMPTY TOKEN LIST. A relative with no live
        // token is the most important row this ledger can hold: the alarm was
        // raised and reached nobody. Skipping the dispatcher wrote no row at
        // all, so frame 25 had no `sos` line — and its footer reads a missing
        // line as «за 30 дней SOS не отправляли», which is the opposite of what
        // happened. sendPush answers `error:'no_tokens'` for an empty list, so
        // the attempt lands in «Нет устройства» where it belongs.
        //
        // Through the same dispatcher as everything else, and held by nothing.
        // Routing SOS around the gate «to be safe» is how the exemption stops
        // being tested: it is one rule, in gate.ts, and this is the call that
        // proves it holds.
        await push.deliver(
          'sos',
          recipient,
          tokens,
          sosCopy(
            {
              childId: alert.childId,
              childName: child?.name ?? '',
              at: alert.at,
              zoneName: alert.zoneName,
              coords,
            },
            toPushLocale(locale),
          ),
        );
      }
    },
    // Frame 43 — an operator answered. In HER language, from the locale on the
    // profile, and not critical: a support answer must not break Do Not Disturb
    // at three in the morning.
    //
    // afterPush REPORTS rather than throws, and the admin route swallows a
    // throw besides: a reply that saved must never come back to an operator as
    // a failure because a phone had a dead token.
    //
    // Gated by «Новости и ответы». Holding it is safe in a way holding a zone
    // alert is not: the answer is already in the thread, so a muted mother
    // finds it the next time she opens the screen rather than losing it.
    notifySupportReply: async (userId, ticket, body) => {
      const { tokens, locale } = await repo.guardianPushTokensForUser(userId);
      await push.deliver(
        'support',
        userId,
        tokens,
        supportReplyCopy(ticket.subject, body, toPushLocale(locale), ticket.id),
      );
    },
    // Frame 06 — a рассылка reaches the phones the ledger accepted.
    //
    // Per recipient, in HER language, off her own `users.locale`. One send per
    // woman rather than one multicast for everybody, because the two language
    // versions are different messages — and because a mother with no token is
    // then simply a mother with no token rather than a silent hole in a batch.
    //
    // The ids come from publishBroadcast, never from re-running the segment:
    // the weekly gap was decided in the database, and asking a second time is
    // how somebody receives two messages in one afternoon.
    notifyBroadcast: async (userIds, message) => {
      let sent = 0;
      let noTokens = 0;
      let held = 0;
      for (const userId of userIds) {
        const { tokens, locale } = await repo.guardianPushTokensForUser(userId);
        const text = toPushLocale(locale) === 'kk' ? message.kk : message.ru;
        // NO early `continue` for an empty token list. Sixty women out of a
        // hundred with no registered device used to leave the panel showing
        // «попыток 40 · нет устройства 0» — the gap the frame exists to explain
        // missing from precisely the column built to explain it. The dispatcher
        // records the attempt (`error:'no_tokens'`) instead.
        //
        // Gated by «Новости и ответы». The delivery ledger row was already
        // written by publishBroadcast, and that is right: the message IS in her
        // notification centre either way. What the switch decides is whether her
        // phone lights up, which is the only part she asked about.
        const out = await push.deliver(
          'broadcast', userId, tokens, announcementCopy(text.title, text.body, message.id));
        sent += out.sent;
        // Counted off the OUTCOME, not off `tokens`, so this log line and the
        // ledger behind frame 25 can never disagree: a muted mother with no
        // device is held, not «нет устройства», and is counted once.
        if (out.held) held += 1;
        else if (out.error === 'no_tokens') noTokens += 1;
      }
      // Said out loud. «Доставлено 40» on the panel counts ledger rows — what
      // reached a phone is this number, and the gap between them is people who
      // have never opened the app on a device we can reach, plus the ones who
      // asked us not to buzz them.
      console.warn(
        `broadcast ${message.id}: ${sent} push(es) delivered to ${userIds.length} recipient(s)` +
        (noTokens ? `, ${noTokens} with no registered device` : '') +
        (held ? `, ${held} held by notification settings` : ''),
      );
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
    // Off unless explicitly switched on WITH a gateway. Both, because turning
    // it on without a sender would lock everybody out instead of protecting
    // them.
    //
    // On THIS branch there is never a sender — smsSender() returns undefined
    // whenever DATABASE_URL is set — so this is always false and
    // REQUIRE_PHONE_CODE cannot do anything here. buildServer says so at boot
    // rather than leaving the variable looking like a mitigation.
    requirePhoneCode: phoneCode.effective,
    phoneCodeRequested: phoneCode.requested,
    // Frame 24 «Интеграции». firebase-admin authenticates with
    // applicationDefault(), which on this server means the service-account JSON
    // named by GOOGLE_APPLICATION_CREDENTIALS. Without it every send fails at
    // the point of use — an SOS reaches nobody whose app is closed — and
    // nothing anywhere said so. Reported as a fact rather than inferred from
    // the push module being importable.
    pushIsReal: !!process.env.GOOGLE_APPLICATION_CREDENTIALS,
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
  const phoneCode = phoneCodePosture(process.env, !!smsSender());
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
    // Off unless explicitly switched on WITH a gateway. Both, because turning
    // it on without a sender would lock everybody out instead of protecting
    // them. Here — and ONLY here, on a dev box — the log-only sender counts,
    // so REQUIRE_PHONE_CODE=1 really does turn the flow on and the code is
    // printed to the server log.
    requirePhoneCode: phoneCode.effective,
    phoneCodeRequested: phoneCode.requested,
    // Frame 24 «Интеграции». firebase-admin authenticates with
    // applicationDefault(), which on this server means the service-account JSON
    // named by GOOGLE_APPLICATION_CREDENTIALS. Without it every send fails at
    // the point of use — an SOS reaches nobody whose app is closed — and
    // nothing anywhere said so. Reported as a fact rather than inferred from
    // the push module being importable.
    pushIsReal: !!process.env.GOOGLE_APPLICATION_CREDENTIALS,
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
