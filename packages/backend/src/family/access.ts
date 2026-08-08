/**
 * Screen 40 — «Семейный доступ».
 *
 * docs/CLAUDE-app-design.md: «список близких с уровнем доступа → карточка
 * приглашения со ссылкой (24 ч, одноразовая) → зелёная плашка «здоровье и цикл
 * не видит никто» → «Пригласить».»
 *
 * A father, a grandmother and an aunt all want to know the child got to school.
 * None of them is entitled to the mother's blood pressure, her cycle, her
 * pregnancy or her diary — and the green banner on that screen promises exactly
 * that.
 *
 * THE PROMISE IS ARCHITECTURAL, NOT TEXTUAL. This module grants access to
 * CHILD-scoped things only. There is no level that reaches the mother's own
 * record, and there is deliberately no way to express one: [SHAREABLE] lists
 * what a grant can cover, and it does not contain her health, her cycle, her
 * appointments or her medications. A banner that says «здоровье и цикл не видит
 * никто» while a level exists that could is a lie waiting for a bug to tell it.
 *
 * The routes enforce this by using a DIFFERENT guard from the owner-only one:
 * `requireOwned` stays owner-only and remains the default, so a route added
 * next year is private until somebody deliberately opens it. Widening the
 * shared guard is a visible act; forgetting to narrow one is not.
 *
 * PURE: no repository, no clock beyond the instant it is given.
 */

/**
 * What a relative may do. Ordered from least to most.
 *
 * Two, not five. Every extra level is a question the mother has to answer about
 * a person she already trusts enough to invite, and the honest distinction is
 * "can they only look" versus "can they act".
 */
export const ACCESS_LEVELS = ['viewer', 'guardian'] as const;
export type AccessLevel = (typeof ACCESS_LEVELS)[number];

export function isAccessLevel(v: unknown): v is AccessLevel {
  return typeof v === 'string' && (ACCESS_LEVELS as readonly string[]).includes(v);
}

/**
 * The only things a family grant can ever cover.
 *
 * Read this as the enforcement of the green banner. Adding a member of the
 * mother's own record to this list is the one change that would break the
 * promise, and it is a change somebody has to make on purpose, in a file whose
 * whole subject is that promise.
 */
export const SHAREABLE = [
  /** Where the child is, and the trail — screens 12 and 47. */
  'child_location',
  /** Zones and their crossings. */
  'child_zones',
  /** The alert feed: SOS, check-ins, low battery. */
  'child_alerts',
  /** The tracker itself — battery, last seen. */
  'child_device',
] as const;
export type Shareable = (typeof SHAREABLE)[number];

/** Level → what it may do. `viewer` reads; `guardian` also acts. */
const LEVEL_READS: Readonly<Record<AccessLevel, readonly Shareable[]>> = {
  viewer: SHAREABLE,
  guardian: SHAREABLE,
};

/**
 * Writing is what separates the two levels: a guardian can add a zone, log a
 * check-in and acknowledge an alert. A viewer — the aunt who wants to know the
 * child arrived — cannot change anything on somebody else's account.
 */
const LEVEL_WRITES: Readonly<Record<AccessLevel, readonly Shareable[]>> = {
  viewer: [],
  guardian: SHAREABLE,
};

export function canRead(level: AccessLevel, what: Shareable): boolean {
  return LEVEL_READS[level]?.includes(what) ?? false;
}

export function canWrite(level: AccessLevel, what: Shareable): boolean {
  return LEVEL_WRITES[level]?.includes(what) ?? false;
}

/**
 * Never true for anything outside [SHAREABLE].
 *
 * The function the guard calls. An unknown subject fails closed, so a route
 * that asks about `maternal_health` — a string this module does not know — is
 * refused rather than defaulting to permitted.
 */
export function grantCovers(level: string, what: string): boolean {
  if (!isAccessLevel(level)) return false;
  if (!(SHAREABLE as readonly string[]).includes(what)) return false;
  return canRead(level, what as Shareable);
}

// ---------------------------------------------------------------------------
// Invitations
// ---------------------------------------------------------------------------

/** «24 ч» — how long an invitation link is good for. */
export const INVITE_TTL_MS = 24 * 60 * 60 * 1000;

/** How many invitations one account may have outstanding at once. */
export const MAX_OPEN_INVITES = 10;

export interface InviteRow {
  /** Hash of the token. The token itself is in the link and never stored. */
  tokenHash: string;
  ownerUserId: string;
  level: AccessLevel;
  createdAt: string;
  expiresAt: string;
  /** When it was accepted. A used invitation is spent, not deleted. */
  usedAt: string | null;
  usedBy: string | null;
  /** Revoked by the mother before anyone used it. */
  revokedAt: string | null;
}

export type InviteRefusal =
  | 'not_found'
  | 'expired'
  | 'already_used'
  | 'revoked'
  | 'own_invite';

/**
 * May this invitation be accepted, by this person, at this instant?
 *
 * «одноразовая» is the whole point: a link forwarded to a family group chat
 * must let in exactly one person. Reasons are distinct because they call for
 * different words on screen — an expired link needs a new one, a used one
 * probably means somebody else already joined.
 */
export function checkInvite(
  invite: InviteRow | null,
  byUserId: string,
  now: Date,
): { ok: true; level: AccessLevel } | { ok: false; reason: InviteRefusal } {
  if (!invite) return { ok: false, reason: 'not_found' };
  if (invite.revokedAt) return { ok: false, reason: 'revoked' };
  if (invite.usedAt) return { ok: false, reason: 'already_used' };
  // Accepting your own invitation would make you a relative of yourself, and
  // then removing that grant would take away your own children.
  if (invite.ownerUserId === byUserId) return { ok: false, reason: 'own_invite' };
  if (Date.parse(invite.expiresAt) <= now.getTime()) {
    return { ok: false, reason: 'expired' };
  }
  return { ok: true, level: invite.level };
}

/** When an invitation created now would stop working. */
export function inviteExpiry(now: Date, ttlMs = INVITE_TTL_MS): string {
  return new Date(now.getTime() + ttlMs).toISOString();
}

/**
 * Still worth showing on the list.
 *
 * An expired invitation is dropped from «карточка приглашения» rather than
 * shown as a dead link: a mother reading a link that no longer works and not
 * being told is worse than not seeing it at all.
 */
export function isOpen(invite: InviteRow, now: Date): boolean {
  return (
    !invite.usedAt &&
    !invite.revokedAt &&
    Date.parse(invite.expiresAt) > now.getTime()
  );
}
