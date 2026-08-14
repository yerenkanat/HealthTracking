/**
 * The gate every SERVER-SENT push passes through — the port of the app's
 * `lib/domain/notification_prefs.dart` to the side that actually sends.
 *
 * WHY THIS EXISTS AT ALL. The app has had per-category switches and quiet hours
 * since the notification audit, and they were honoured by exactly one thing: the
 * notifications the PHONE raises for itself (app_controller.shouldDeliverAlert).
 * Every push the server sends — a geofence crossing detected from a tracker fix,
 * an operator's answer, a рассылка — went out regardless. So a mother who turned
 * «Зоны» off and set quiet hours 22:00–07:00 still had her phone light up at
 * three in the morning because her child's tag drifted past a fence, and the
 * screen that promised otherwise was telling her the truth about a switch that
 * reached nothing.
 *
 * THE ONE RULE THAT MUST NOT BREAK, in the same words as the Dart file: an
 * SOS or a medical emergency is ALWAYS delivered. No toggle turns it off and
 * quiet hours never hold it. [categoryOf] returns null for those two kinds, and
 * null means "not gated" everywhere in this module — the exemption is one
 * function rather than a condition repeated at five call sites, because a rule
 * written five times is a rule that will one day be written four.
 *
 * PURE. No database, no clock of its own, no Fastify. The only I/O-shaped thing
 * is [minuteOfDayIn], and that is a calendar calculation over a timestamp the
 * caller supplies.
 */

/** What a mother can switch off. SOS/emergency deliberately has no member. */
export type NotifyCategory = 'zoneEvents' | 'checkIn' | 'lowBattery' | 'updates';

export const NOTIFY_CATEGORIES: readonly NotifyCategory[] = [
  'zoneEvents',
  'checkIn',
  'lowBattery',
  'updates',
] as const;

/**
 * The kinds of push this server sends. These are the `kind` strings that were
 * already being passed to afterPush(), kept identical so the delivery ledger and
 * the log lines agree with each other.
 */
export type PushKind = 'emergency' | 'geofence' | 'sos' | 'support' | 'broadcast';

export const PUSH_KINDS: readonly PushKind[] = [
  'emergency',
  'geofence',
  'sos',
  'support',
  'broadcast',
] as const;

/** Why a push was not sent. Recorded, so «не пришло» has an answer. */
export type HoldReason = 'muted' | 'quiet_hours';

export interface NotificationPrefs {
  /** Child entered / left a zone. */
  zoneEvents: boolean;
  /** Child checked in («я на месте»). */
  checkIn: boolean;
  /** Tracker battery low. */
  lowBattery: boolean;
  /**
   * Рассылки and support answers — everything the PRODUCT says to her rather
   * than something her child's tracker did.
   *
   * A separate category on purpose. The obvious shortcut is to hang a marketing
   * broadcast off `checkIn` or off the zone switch because those already exist;
   * that would mean a mother silencing advertisements also silenced the
   * notification that her child arrived at school, and she would never find out
   * which switch did it.
   */
  updates: boolean;
  /**
   * Quiet-hours window in minutes since midnight IN HER TIMEZONE (inclusive
   * start, exclusive end). Null/null = off. An overnight window (22:00 → 07:00)
   * is normal and wraps.
   */
  quietStart: number | null;
  quietEnd: number | null;
}

/**
 * What a woman who has never opened the screen gets.
 *
 * Everything ON. That is the same default as the app's `NotificationPrefs()`
 * and it is the safe direction: an install that predates this table must not
 * lose the alerts it was already receiving because a row is missing.
 */
export const DEFAULT_PREFS: NotificationPrefs = {
  zoneEvents: true,
  checkIn: true,
  lowBattery: true,
  updates: true,
  quietStart: null,
  quietEnd: null,
};

/**
 * The timezone used when a row does not name one, or names one this runtime
 * cannot resolve.
 *
 * `users.timezone` is `NOT NULL DEFAULT 'Asia/Almaty'` (db/schema.sql), so this
 * agrees with the column rather than with UTC. Falling back to UTC would put a
 * mother in Almaty five or six hours away from her own quiet hours — the exact
 * failure this feature exists to stop, arriving through the back door.
 */
export const FALLBACK_TZ = 'Asia/Almaty';

/**
 * Which switch controls [kind] — or null when nothing does.
 *
 * `emergency` and `sos` return null. Read that as "not gated", not as "unknown":
 * an unrecognised kind returns `'updates'` below rather than null, because the
 * bias for something we cannot classify is chatter, never an emergency.
 */
export function categoryOf(kind: string): NotifyCategory | null {
  switch (kind) {
    // The two that no preference may ever hold. See the header.
    //
    // Verified by REVERTING: deleting `case 'sos'` here turns
    // __tests__/notificationGate.test.ts red in three places, one of them the
    // end-to-end dispatcher test, rather than leaving a green suite over a
    // product that swallows alarms.
    case 'emergency':
    case 'sos':
      return null;
    case 'geofence':
      return 'zoneEvents';
    case 'check_in':
      return 'checkIn';
    case 'low_battery':
      return 'lowBattery';
    case 'support':
    case 'broadcast':
      return 'updates';
    default:
      // A kind nobody has mapped is treated as an update: it is safer to hold a
      // new marketing channel than to let it claim the emergency exemption by
      // being unrecognised.
      return 'updates';
  }
}

/** Whether the category is switched on. */
export function allows(prefs: NotificationPrefs, c: NotifyCategory): boolean {
  switch (c) {
    case 'zoneEvents':
      return prefs.zoneEvents;
    case 'checkIn':
      return prefs.checkIn;
    case 'lowBattery':
      return prefs.lowBattery;
    case 'updates':
      return prefs.updates;
  }
}

/** Whether the window is set at all. A zero-length window counts as off. */
export function hasQuietHours(prefs: NotificationPrefs): boolean {
  return (
    prefs.quietStart != null && prefs.quietEnd != null && prefs.quietStart !== prefs.quietEnd
  );
}

/** Whether [minute] (0–1439) falls inside the quiet window. Wraps overnight. */
export function inQuietHours(prefs: NotificationPrefs, minute: number): boolean {
  if (!hasQuietHours(prefs)) return false;
  const s = prefs.quietStart as number;
  const e = prefs.quietEnd as number;
  return s < e ? minute >= s && minute < e : minute >= s || minute < e;
}

/**
 * Minutes since midnight in [tz], for the instant [at].
 *
 * SERVER TIME IS NOT HER TIME. The box runs UTC; she is at UTC+5. Reading the
 * clock here and comparing it against a window she set on her phone would hold
 * her 19:00 notifications and let the 02:00 one through — quiet hours that are
 * exactly wrong rather than merely absent.
 *
 * An unusable timezone falls back to [FALLBACK_TZ] rather than throwing: a bad
 * string in one row must not take down the push path for everybody.
 */
export function minuteOfDayIn(tz: string, at: Date = new Date()): number {
  const read = (zone: string) =>
    new Intl.DateTimeFormat('en-GB', {
      timeZone: zone,
      hour: '2-digit',
      minute: '2-digit',
      hour12: false,
    }).formatToParts(at);

  let parts: Intl.DateTimeFormatPart[];
  try {
    parts = read(tz || FALLBACK_TZ);
  } catch {
    parts = read(FALLBACK_TZ);
  }
  const num = (type: string) => Number(parts.find((p) => p.type === type)?.value ?? '0') || 0;
  // `% 24`: some ICU builds render midnight as hour "24" under hour12:false.
  return (num('hour') % 24) * 60 + num('minute');
}

/**
 * Whether this runtime can actually resolve [tz] as an IANA zone.
 *
 * The write side's guard. [minuteOfDayIn] falls back silently when a stored
 * name is unusable, which is right for a push path but wrong for a save: a zone
 * accepted here and unresolvable later is quiet hours read against Almaty for a
 * mother who told us she is in Berlin, with nothing anywhere saying so. Better
 * to refuse the string at the door.
 *
 * `'UTC'` and `'Asia/Almaty'` pass; `'Not/AZone'`, `'+05:00'` and `''` do not.
 */
export function isKnownTimezone(tz: unknown): tz is string {
  if (typeof tz !== 'string' || tz.trim() === '') return false;
  // An OFFSET is not a zone, even though modern ICU resolves '+05:00' happily.
  // A stored offset is frozen: a mother in Berlin who saves in August has her
  // window read an hour wrong from the last Sunday in October, and nothing
  // anywhere would say why. Only a NAME carries the rules.
  if (/^[+-]/.test(tz.trim())) return false;
  try {
    // Constructing is enough — Intl throws RangeError on an unknown timeZone.
    new Intl.DateTimeFormat('en-GB', { timeZone: tz });
    return true;
  } catch {
    return false;
  }
}

/**
 * THE gate. Null means send it; a [HoldReason] means do not, and why.
 *
 * Deliberately returns the reason rather than a boolean. «Не пришло» is the
 * complaint this feature will generate, and «она отключила категорию» and
 * «шли тихие часы» need different answers from support.
 */
export function holdReasonFor(
  kind: string,
  prefs: NotificationPrefs,
  minuteOfDay: number,
): HoldReason | null {
  const category = categoryOf(kind);
  if (category === null) return null; // SOS / emergency — never held.
  if (!allows(prefs, category)) return 'muted';
  if (inQuietHours(prefs, minuteOfDay)) return 'quiet_hours';
  return null;
}

/** The same decision as a boolean, for call sites that only branch. */
export function shouldDeliver(
  kind: string,
  prefs: NotificationPrefs,
  minuteOfDay: number,
): boolean {
  return holdReasonFor(kind, prefs, minuteOfDay) === null;
}

/** Human wording for the back office. */
export const HOLD_REASON_RU: Record<HoldReason, string> = {
  muted: 'категория отключена',
  quiet_hours: 'тихие часы',
};

/**
 * Tolerant decoder — for a database row, a JSON body, or an older row with no
 * `updates` column value.
 *
 * A MISSING FIELD IS ON. An install that predates the `updates` switch has
 * never been asked about рассылки, and reading "absent" as "off" would silently
 * stop the support answers she is waiting for.
 */
export function parsePrefs(raw: unknown): NotificationPrefs {
  const j = (raw ?? {}) as Record<string, unknown>;
  const flag = (k: string) => (typeof j[k] === 'boolean' ? (j[k] as boolean) : true);
  const minute = (k: string) => {
    const v = j[k];
    if (typeof v !== 'number' || !Number.isFinite(v)) return null;
    const n = Math.trunc(v);
    return n >= 0 && n <= 1439 ? n : null;
  };
  const s = minute('quietStart');
  const e = minute('quietEnd');
  return {
    zoneEvents: flag('zoneEvents'),
    checkIn: flag('checkIn'),
    lowBattery: flag('lowBattery'),
    updates: flag('updates'),
    // Half a window is no window — the same tolerance the Dart side has, so a
    // partial write cannot produce a quiet period nobody can see or clear.
    quietStart: s != null && e != null ? s : null,
    quietEnd: s != null && e != null ? e : null,
  };
}
