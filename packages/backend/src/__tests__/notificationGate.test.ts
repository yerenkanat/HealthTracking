/**
 * Frame 25 «Уведомления» → app screen 39, driven end to end.
 *
 * WHAT WAS BROKEN. The app has had per-category notification switches and quiet
 * hours since the notification audit. They were honoured by exactly one thing:
 * the notifications the PHONE raised for itself. Every push the SERVER sent — a
 * zone crossing derived from a tracker fix, an operator's answer, a рассылка —
 * went out regardless, because nothing on this side had ever heard of them.
 * `persisted_config.dart` wrote them to SharedPrefs and no ApiClient method
 * sent them anywhere.
 *
 * So the assertions here are deliberately about the JOIN, not about the pure
 * function. A green test for `shouldDeliver` is exactly what this feature
 * already had — twenty-nine of them, in
 * app/tool/verify_notification_prefs.dart — while the product ignored the
 * answer. What is proved below:
 *
 *   * the settings she saves over HTTP come back over HTTP (read-your-writes);
 *   * a server push for a category she muted is NOT sent, and leaves a row
 *     saying why;
 *   * quiet hours are evaluated in HER timezone, not the server's — the same
 *     UTC instant is held for a mother in Almaty and delivered to one in Lisbon;
 *   * an SOS is delivered with every switch off, at 03:00, inside the window.
 *
 * THE LAST ONE IS THE POINT OF THE FILE. It is verified by reverting: remove
 * the `case 'sos': return null` exemption from notifications/gate.ts and this
 * suite must go red on «an SOS is delivered…», not merely stay green. It was
 * run that way before this file was committed.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import type { FastifyInstance, FastifyRequest } from 'fastify';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER, DEV_STAFF_PHONE, DEV_STAFF_PASSWORD } from '../db/memoryRepository';
import type { NotificationPrefsRow, PushDeliveryRecord, Repository } from '../db/repository';
import { hashToken, readSessionCookie } from '../http/staffAuth';
import { createPushDispatch } from '../notifications/dispatch';
import {
  DEFAULT_PREFS, categoryOf, holdReasonFor, inQuietHours, minuteOfDayIn, parsePrefs,
} from '../notifications/gate';

const hm = (h: number, m = 0) => h * 60 + m;

// ---------------------------------------------------------------------------
// The pure gate
// ---------------------------------------------------------------------------
describe('the gate itself', () => {
  it('never has a category for SOS or a medical emergency', () => {
    // Null means "not gated". Both, because they are different events with the
    // same urgency: `sos` is her child pressing a button, `emergency` is her
    // own vitals crossing a threshold.
    expect(categoryOf('sos')).toBeNull();
    expect(categoryOf('emergency')).toBeNull();
  });

  it('maps a рассылка and a support answer to `updates`, never to checkIn', () => {
    // The trap this feature invites: `checkIn` already exists, so hanging
    // marketing off it is one line. It would mean a mother silencing
    // advertisements also silenced «ребёнок на месте», with nothing on the
    // screen to tell her which switch did it.
    expect(categoryOf('broadcast')).toBe('updates');
    expect(categoryOf('support')).toBe('updates');
    expect(categoryOf('geofence')).toBe('zoneEvents');
  });

  it('an unmapped kind is an update, not an emergency', () => {
    // The bias for something we cannot classify is chatter. A new channel must
    // not inherit the SOS exemption by being unrecognised.
    expect(categoryOf('some_new_channel')).toBe('updates');
  });

  it('holds a muted category and says which reason', () => {
    const prefs = { ...DEFAULT_PREFS, zoneEvents: false };
    expect(holdReasonFor('geofence', prefs, hm(12))).toBe('muted');
    expect(holdReasonFor('support', prefs, hm(12))).toBeNull();
  });

  it('holds inside quiet hours, including an overnight window', () => {
    const night = { ...DEFAULT_PREFS, quietStart: hm(22), quietEnd: hm(7) };
    expect(inQuietHours(night, hm(23))).toBe(true);
    expect(inQuietHours(night, hm(3))).toBe(true);
    expect(inQuietHours(night, hm(12))).toBe(false);
    // Exclusive end — 07:00 is when it stops, not the last quiet minute.
    expect(inQuietHours(night, hm(7))).toBe(false);
    expect(holdReasonFor('geofence', night, hm(3))).toBe('quiet_hours');
  });

  it('a zero-length or half-specified window is off', () => {
    expect(inQuietHours({ ...DEFAULT_PREFS, quietStart: 480, quietEnd: 480 }, 480)).toBe(false);
    expect(parsePrefs({ quietStart: 480 }).quietStart).toBeNull();
  });

  it('SOS and emergency pass with every switch off, deep inside quiet hours', () => {
    const off = {
      zoneEvents: false, checkIn: false, lowBattery: false, updates: false,
      quietStart: 0, quietEnd: 1439,
    };
    expect(holdReasonFor('sos', off, hm(3))).toBeNull();
    expect(holdReasonFor('emergency', off, hm(3))).toBeNull();
  });

  it('a missing `updates` key reads as ON, not as muted', () => {
    // A pre-existing install has never been asked about рассылки. Reading
    // "absent" as "off" would silently stop the support answers she is waiting
    // for, on the day this shipped.
    const old = parsePrefs({ zoneEvents: false, checkIn: true, lowBattery: true });
    expect(old.updates).toBe(true);
    expect(old.zoneEvents).toBe(false);
  });

  it('reads the clock in HER zone, not the process one', () => {
    // 2026-08-12T19:30:00Z is 00:30 the next day in Almaty (+5) and 20:30 in
    // Lisbon (+1 in summer). A server reading its own clock would be five hours
    // out — quiet hours exactly wrong rather than merely absent.
    const at = new Date('2026-08-12T19:30:00.000Z');
    expect(minuteOfDayIn('Asia/Almaty', at)).toBe(hm(0, 30));
    expect(minuteOfDayIn('Europe/Lisbon', at)).toBe(hm(20, 30));
    // An unusable zone falls back to the column's default rather than throwing:
    // one bad row must not take the push path down for everybody.
    expect(minuteOfDayIn('Not/AZone', at)).toBe(hm(0, 30));
  });
});

// ---------------------------------------------------------------------------
// The dispatcher — the join between the gate, the sender and the ledger
// ---------------------------------------------------------------------------
describe('the dispatcher every server push goes through', () => {
  /** A repository stub whose only job is to hold one woman's preferences. */
  function repoWith(prefs: Partial<NotificationPrefsRow>) {
    const ledger: PushDeliveryRecord[] = [];
    const forgotten: string[] = [];
    return {
      ledger,
      forgotten,
      repo: {
        getNotificationPrefs: async (): Promise<NotificationPrefsRow> => ({
          ...DEFAULT_PREFS, timezone: 'Asia/Almaty', updatedAt: null, ...prefs,
        }),
        deletePushToken: async (t: string) => void forgotten.push(t),
        recordPushDelivery: async (r: PushDeliveryRecord) => void ledger.push(r),
      },
    };
  }

  function dispatcherOver(
    prefs: Partial<NotificationPrefsRow>,
    now: Date,
    result = { sent: 1, failed: 0, dead: [] as string[] },
  ) {
    const { repo, ledger, forgotten } = repoWith(prefs);
    const sends: string[][] = [];
    const push = createPushDispatch<{ title: string }>({
      repo,
      send: async (tokens) => { sends.push(tokens); return result; },
      now: () => now,
    });
    return { push, sends, ledger, forgotten };
  }

  const NOON_ALMATY = new Date('2026-08-12T07:00:00.000Z'); // 12:00 in Almaty
  const NIGHT_ALMATY = new Date('2026-08-12T22:00:00.000Z'); // 03:00 next day
  /** 23:00 in Almaty (+5), 19:00 in Lisbon (+1 in summer). One instant, two days. */
  const SPLIT = new Date('2026-08-12T18:00:00.000Z');

  it('does not send a geofence push for a mother who muted «Зоны»', async () => {
    const { push, sends, ledger } = dispatcherOver({ zoneEvents: false }, NOON_ALMATY);
    const out = await push.deliver('geofence', DEMO_USER, ['tok'], { title: 'зона' });

    expect(out.held).toBe('muted');
    expect(out.sent).toBe(0);
    // The one that matters: nothing was handed to FCM at all.
    expect(sends, 'a muted category still reached the sender').toEqual([]);
    // …and it is on the record, so «почему мне не пришло» has an answer.
    expect(ledger).toEqual([
      { userId: DEMO_USER, kind: 'geofence', sent: 0, failed: 0, dead: 0, heldReason: 'muted', error: null },
    ]);
  });

  it('holds by HER clock, not the server\'s', async () => {
    const quiet = { quietStart: hm(22), quietEnd: hm(7) };
    // ONE instant — 18:00 UTC. It is 23:00 for the mother in Almaty, who is
    // asleep, and 19:00 for the one in Lisbon, who is not. A server reading its
    // own clock would answer 18:00 for both and hold NEITHER, which is exactly
    // the failure `users.timezone` exists to prevent.
    const almaty = dispatcherOver({ ...quiet, timezone: 'Asia/Almaty' }, SPLIT);
    const lisbon = dispatcherOver({ ...quiet, timezone: 'Europe/Lisbon' }, SPLIT);

    expect((await almaty.push.deliver('geofence', DEMO_USER, ['t'], { title: 'z' })).held).toBe('quiet_hours');
    expect(almaty.sends).toEqual([]);

    const out = await lisbon.push.deliver('geofence', DEMO_USER, ['t'], { title: 'z' });
    expect(out.held, 'her evening was held by somebody else\'s night').toBeNull();
    expect(lisbon.sends).toEqual([['t']]);
  });

  /**
   * THE ONE THAT MUST NOT BREAK.
   *
   * Verified by reverting: delete `case 'sos': return null;` from
   * notifications/gate.ts and this must fail. If it still passes, the exemption
   * is being enforced somewhere this test cannot see, and the next refactor
   * will silently remove it.
   */
  it('delivers an SOS with every switch off, at 03:00, inside her quiet hours', async () => {
    const { push, sends, ledger } = dispatcherOver(
      {
        zoneEvents: false, checkIn: false, lowBattery: false, updates: false,
        quietStart: 0, quietEnd: 1439, timezone: 'Asia/Almaty',
      },
      NIGHT_ALMATY,
    );
    const out = await push.deliver('sos', DEMO_USER, ['tok'], { title: 'SOS' });

    expect(out.held, 'an SOS was held by a preference').toBeNull();
    expect(sends, 'the alarm never reached the sender').toEqual([['tok']]);
    expect(ledger[0].heldReason).toBeNull();
    expect(ledger[0].sent).toBe(1);
  });

  it('delivers a medical emergency under the same conditions', async () => {
    const { push, sends } = dispatcherOver(
      { zoneEvents: false, checkIn: false, lowBattery: false, updates: false, quietStart: 0, quietEnd: 1439 },
      NIGHT_ALMATY,
    );
    expect((await push.deliver('emergency', DEMO_USER, ['t'], { title: '!' })).held).toBeNull();
    expect(sends).toEqual([['t']]);
  });

  it('records «нет устройства» apart from a failure', async () => {
    // sendPush answers `no_tokens` when she has never registered a phone. That
    // is not our sender breaking, and counting the two together would turn
    // «она не установила приложение» into «пуши не работают».
    const { push, ledger } = dispatcherOver({}, NOON_ALMATY, { sent: 0, failed: 0, dead: [], ...{ error: 'no_tokens' } } as never);
    await push.deliver('support', DEMO_USER, [], { title: 'x' });
    expect(ledger[0]).toMatchObject({ error: 'no_tokens', heldReason: null, sent: 0 });
  });

  it('records an SOS that reached nobody rather than writing no row at all', async () => {
    // A child pressed the button; the mother and every family member have no
    // live token — a reinstall, a new phone, permission never granted. The
    // alarm was RAISED and reached nobody, and that is the single most
    // important row this ledger can hold. Frame 25 prints no row for a kind
    // with no attempts and its footer reads that as «SOS за 30 дней не было»,
    // so a skipped dispatcher turns a silent alarm into a positive denial.
    const { push, ledger } = dispatcherOver(
      {}, NIGHT_ALMATY, { sent: 0, failed: 0, dead: [], error: 'no_tokens' } as never);
    const out = await push.deliver('sos', DEMO_USER, [], { title: 'SOS' });
    expect(out.held, 'an SOS was held').toBeNull();
    expect(ledger[0]).toMatchObject({
      kind: 'sos', error: 'no_tokens', heldReason: null, sent: 0, failed: 0,
    });
  });

  it('forgets the tokens FCM declares dead, and counts them', async () => {
    const { push, ledger, forgotten } = dispatcherOver({}, NOON_ALMATY, { sent: 1, failed: 1, dead: ['ghost'] });
    await push.deliver('broadcast', DEMO_USER, ['live', 'ghost'], { title: 'x' });
    expect(forgotten).toEqual(['ghost']);
    expect(ledger[0]).toMatchObject({ dead: 1, failed: 1, sent: 1 });
  });

  it('sends anyway when the preferences cannot be read', async () => {
    // A database blip must not silence everybody at once. The failure mode of
    // the opposite choice is invisible for a week.
    const ledger: PushDeliveryRecord[] = [];
    const sends: string[][] = [];
    const push = createPushDispatch<{ title: string }>({
      repo: {
        getNotificationPrefs: async () => { throw new Error('relation does not exist'); },
        deletePushToken: async () => {},
        recordPushDelivery: async (r) => void ledger.push(r),
      },
      send: async (tokens) => { sends.push(tokens); return { sent: 1, failed: 0, dead: [] }; },
    });
    const out = await push.deliver('geofence', DEMO_USER, ['t'], { title: 'z' });
    expect(out.held).toBeNull();
    expect(sends).toEqual([['t']]);
  });

  it('a ledger that cannot be written never stops a push', async () => {
    // Migration 047 unapplied. Losing the RECORD of an emergency push is bad;
    // not sending it is worse, so the order of those two is asserted.
    const sends: string[][] = [];
    const push = createPushDispatch<{ title: string }>({
      repo: {
        getNotificationPrefs: async () => ({ ...DEFAULT_PREFS, timezone: 'Asia/Almaty', updatedAt: null }),
        deletePushToken: async () => {},
        recordPushDelivery: async () => { throw new Error('relation "push_deliveries" does not exist'); },
      },
      send: async (tokens) => { sends.push(tokens); return { sent: 1, failed: 0, dead: [] }; },
    });
    await expect(push.deliver('sos', DEMO_USER, ['t'], { title: 'SOS' })).resolves.toMatchObject({ sent: 1 });
    expect(sends).toEqual([['t']]);
  });
});

// ---------------------------------------------------------------------------
// Every call site actually goes through it
// ---------------------------------------------------------------------------
//
// The composition root cannot be imported by a test: productionDeps() loads pg,
// Redis, Anthropic and firebase-admin. So the wiring is asserted at the source,
// which is the only place it can be — and it is worth asserting, because a
// dispatcher nothing calls is this repository's dominant defect wearing the
// notification feature's hat. A sixth push added next year with a bare
// `sendPush(...)` beside it would silently escape the gate and the ledger, and
// everything else in this file would stay green.
describe('the composition root has no ungated push', () => {
  const INDEX = readFileSync(fileURLToPath(new URL('../index.ts', import.meta.url)), 'utf8');

  it('calls sendPush nowhere — only hands it to createPushDispatch', () => {
    const calls = [...INDEX.matchAll(/(?<![.\w])sendPush\s*\(/g)];
    expect(calls.map((m) => m[0]), 'a push in index.ts bypasses the gate and the ledger').toEqual([]);
    expect(INDEX, 'the dispatcher is not wired at all').toContain('createPushDispatch({');
    expect(INDEX).toMatch(/send:\s*sendPush/);
  });

  it('names every push kind at a deliver() call', () => {
    // Guards the guard: an index.ts that stopped sending anything would pass
    // the check above trivially. The kind is the first argument, which may sit
    // on the next line when the call is wrapped.
    const delivered = new Set(
      [...INDEX.matchAll(/push\.deliver\(\s*'([a-z_]+)'/g)].map((m) => m[1]),
    );
    expect([...delivered].sort())
      .toEqual(['broadcast', 'emergency', 'geofence', 'sos', 'support']);
  });

  it('never skips the dispatcher for a recipient with no registered device', () => {
    // `if (tokens.length === 0) continue;` before push.deliver() looks like an
    // optimisation and is a hole in the ledger: for `sos` and `broadcast` a
    // woman with no live token produced no push_deliveries row at all, so the
    // «Нет устройства» column was structurally 0 for exactly the two kinds that
    // most need it — while emergency, support and geofence recorded the attempt
    // because sendPush answers `error:'no_tokens'` for an empty list.
    //
    // Asserted at the source for the same reason as the checks above: the
    // composition root cannot be imported by a test.
    expect(
      INDEX.match(/tokens\.length === 0/g) ?? [],
      'a recipient with no device is skipped before the ledger sees the attempt',
    ).toEqual([]);
  });

  it('gives the geofence push an owner to ask about', () => {
    // A GeofenceEvent names a child, not a person. Passing null here would put
    // the gate back where it started: consulted for nobody, so every zone alert
    // goes out regardless of what she switched off.
    expect(INDEX).toMatch(/childOwner\(evt\.childId\)/);
  });
});

// ---------------------------------------------------------------------------
// The routes, over HTTP, against the real memory repository
// ---------------------------------------------------------------------------
describe('the settings she saves reach the server and come back', () => {
  let repo: Repository;
  let app: FastifyInstance;
  let cookie: string;

  beforeEach(async () => {
    repo = createMemoryRepository();
    app = buildServer(
      {
        repo,
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async (req: FastifyRequest) => ({
          userId: String(req.headers['x-test-user'] ?? DEMO_USER),
        }),
        authAdmin: async (req) => {
          const token = readSessionCookie(req.headers.cookie);
          if (!token) return null;
          return repo.staffBySessionToken(hashToken(token));
        },
      },
      { logger: false },
    );
    const res = await app.inject({
      method: 'POST', url: '/admin/login',
      payload: { phone: DEV_STAFF_PHONE, password: DEV_STAFF_PASSWORD },
    });
    cookie = String(res.headers['set-cookie'] ?? '').split(';')[0];
  });

  const get = () => app.inject({ method: 'GET', url: '/notifications/settings' });
  const put = (payload: unknown) =>
    app.inject({ method: 'PUT', url: '/notifications/settings', payload: payload as never });

  const FULL = {
    zoneEvents: true, checkIn: true, lowBattery: true, updates: true,
    quietStart: null, quietEnd: null,
  };

  it('a woman who has never opened the screen gets everything ON', async () => {
    const res = await get();
    expect(res.statusCode).toBe(200);
    const body = res.json();
    expect(body.settings).toEqual(FULL);
    // Null, not a timestamp: these are the defaults, and the screen must not
    // claim she chose them.
    expect(body.updatedAt).toBeNull();
    expect(body.timezone).toBe('Asia/Almaty');
    // The server states the exemption too, so the app's «экстренные отключить
    // нельзя» card and the gate's behaviour are one fact rather than two.
    expect(body.alwaysDelivered).toEqual(['sos', 'emergency']);
  });

  it('round-trips what she chose', async () => {
    const wanted = {
      zoneEvents: false, checkIn: true, lowBattery: false, updates: false,
      quietStart: hm(22), quietEnd: hm(7),
    };
    expect((await put(wanted)).statusCode).toBe(200);
    const body = (await get()).json();
    expect(body.settings).toEqual(wanted);
    expect(body.updatedAt, 'a saved row still looks like the defaults').not.toBeNull();
  });

  it('refuses a quiet minute outside a day rather than storing it', async () => {
    // 1440 is the commonest off-by-one here and would be a boundary nobody can
    // ever be inside — a quiet window that silently never fires.
    expect((await put({ ...FULL, quietStart: 1440, quietEnd: 0 })).statusCode).toBe(400);
  });

  it('drops half a window rather than storing a period nobody can clear', async () => {
    await put({ ...FULL, quietStart: hm(22) });
    expect((await get()).json().settings).toMatchObject({ quietStart: null, quietEnd: null });
  });

  // -------------------------------------------------------------------------
  // The clock the window is read against — `users.timezone`
  // -------------------------------------------------------------------------
  //
  // That column was READ by the gate and written by nothing: no route accepted
  // a zone, no INSERT supplied one, and the app sent none. So every woman in
  // the product was evaluated as if she lived in Almaty, and the done-criterion
  // «quiet hours hold it by HER timezone» was proved only by the hand-built
  // stub above. These drive it over HTTP, where a real row has to carry it.
  it('stores the zone she is actually in and reads her window against it', async () => {
    const wanted = { ...FULL, quietStart: hm(22), quietEnd: hm(7), timezone: 'Europe/Berlin' };
    expect((await put(wanted)).statusCode).toBe(200);
    // It comes back on the read side, so the app can SAY which clock applies.
    expect((await get()).json().timezone).toBe('Europe/Berlin');

    const prefs = await repo.getNotificationPrefs(DEMO_USER);
    expect(prefs.timezone, 'the column the gate reads was not written').toBe('Europe/Berlin');

    // 04:00 UTC is 06:00 in Berlin — inside her window — and 09:00 in Almaty,
    // which is not. Under the old fallback her 06:00 geofence push went out.
    const early = new Date('2026-08-12T04:00:00.000Z');
    expect(holdReasonFor('geofence', prefs, minuteOfDayIn(prefs.timezone, early))).toBe('quiet_hours');
    expect(holdReasonFor('geofence', prefs, minuteOfDayIn('Asia/Almaty', early))).toBeNull();

    // 19:00 UTC is 21:00 in Berlin — she is awake — and midnight in Almaty.
    // Under the old fallback her 21:00 notification was held.
    const evening = new Date('2026-08-12T19:00:00.000Z');
    expect(holdReasonFor('geofence', prefs, minuteOfDayIn(prefs.timezone, evening))).toBeNull();
    expect(holdReasonFor('geofence', prefs, minuteOfDayIn('Asia/Almaty', evening))).toBe('quiet_hours');
  });

  it('refuses a zone this server cannot resolve rather than storing it', async () => {
    // Same posture as quietStart 1440 above: a stored name that falls back at
    // read time is quiet hours read against a zone she never chose, with
    // nothing on the screen to say so.
    expect((await put({ ...FULL, timezone: 'Not/AZone' })).statusCode).toBe(400);
    expect((await put({ ...FULL, timezone: '+05:00' })).statusCode).toBe(400);
    expect((await get()).json().timezone).toBe('Asia/Almaty');
  });

  it('leaves the stored zone alone when an older app sends none', async () => {
    // Absent must never mean Asia/Almaty — that is the assumption being fixed.
    await put({ ...FULL, timezone: 'Europe/Berlin' });
    expect((await put(FULL)).statusCode).toBe(200);
    expect((await get()).json().timezone, 'a build with no timezone field reset hers').toBe('Europe/Berlin');
  });

  it('has no field that could switch an SOS off', async () => {
    // Extra keys are ignored by the schema; what matters is that no accepted
    // key silences an alarm. Asserted through the gate, not through the shape.
    await put({ ...FULL, sos: false, emergency: false } as never);
    const prefs = await repo.getNotificationPrefs(DEMO_USER);
    expect(holdReasonFor('sos', prefs, hm(3))).toBeNull();
    expect(holdReasonFor('emergency', prefs, hm(3))).toBeNull();
  });

  it('is scoped to the caller — one mother\'s switches are not another\'s', async () => {
    const OTHER = '99999999-9999-9999-9999-999999999999';
    await put({ ...FULL, zoneEvents: false });
    const theirs = await app.inject({
      method: 'GET', url: '/notifications/settings', headers: { 'x-test-user': OTHER },
    });
    expect(theirs.json().settings.zoneEvents, 'her switch reached somebody else').toBe(true);
  });

  it('401s without a session', async () => {
    const anon = buildServer(
      {
        repo,
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => null,
        authAdmin: async () => null,
      },
      { logger: false },
    );
    expect((await anon.inject({ method: 'GET', url: '/notifications/settings' })).statusCode).toBe(401);
    expect((await anon.inject({ method: 'PUT', url: '/notifications/settings', payload: FULL })).statusCode).toBe(401);
  });

  // -------------------------------------------------------------------------
  // The back office reads the same rows
  // -------------------------------------------------------------------------
  const adminNotifications = () =>
    app.inject({ method: 'GET', url: '/admin/notifications', headers: { cookie } });

  it('prints only counted rows — a kind nothing happened to is absent', async () => {
    const empty = (await adminNotifications()).json();
    expect(empty.kinds, 'the panel was handed a row of zeros to draw').toEqual([]);

    await repo.recordPushDelivery({
      userId: DEMO_USER, kind: 'geofence', sent: 2, failed: 1, dead: 1, heldReason: null, error: null,
    });
    await repo.recordPushDelivery({
      userId: DEMO_USER, kind: 'geofence', sent: 0, failed: 0, dead: 0, heldReason: 'muted', error: null,
    });
    await repo.recordPushDelivery({
      userId: DEMO_USER, kind: 'support', sent: 0, failed: 0, dead: 0, heldReason: null, error: 'no_tokens',
    });

    const body = (await adminNotifications()).json();
    expect(body.kinds.map((k: { kind: string }) => k.kind)).toEqual(['geofence', 'support']);
    const geo = body.kinds.find((k: { kind: string }) => k.kind === 'geofence');
    expect(geo).toMatchObject({ attempts: 2, delivered: 2, failed: 1, held: 1, heldMuted: 1, heldQuiet: 0, dead: 1 });
    // «Нет устройства» is its own column, never folded into failures.
    expect(body.kinds.find((k: { kind: string }) => k.kind === 'support')).toMatchObject({ noTokens: 1, errors: 0, failed: 0 });
    expect(body.deadTokens).toBe(1);
  });

  it('counts how many mothers muted each category, and nobody\'s name', async () => {
    await put({ ...FULL, zoneEvents: false, updates: false, quietStart: hm(22), quietEnd: hm(7) });
    const body = (await adminNotifications()).json();
    expect(body.muted).toMatchObject({ zoneEvents: 1, checkIn: 0, lowBattery: 0, updates: 1, quietHours: 1, configured: 1 });
    // A back office does not need a list of women who muted advertisements.
    expect(JSON.stringify(body)).not.toContain(DEMO_USER);
  });

  it('carries no open rate, in any spelling', async () => {
    // The number this screen is most likely to grow. FCM accepted ≠ read, and
    // there is nothing in this product that records an open.
    const raw = JSON.stringify((await adminNotifications()).json());
    for (const forbidden of ['openRate', 'opened', 'readRate', 'ctr']) {
      expect(raw, `frame 25 invented ${forbidden}`).not.toContain(forbidden);
    }
  });

  it('refuses the panel to a role without `content`', async () => {
    const limited = buildServer(
      {
        repo,
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => ({ userId: DEMO_USER }),
        authAdmin: async () => ({ staffId: 's-wh', role: 'warehouse' as never }),
      },
      { logger: false },
    );
    expect((await limited.inject({ method: 'GET', url: '/admin/notifications' })).statusCode).toBe(403);
  });
});
