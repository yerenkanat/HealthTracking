/**
 * Screen 40 — «Семейный доступ».
 *
 * The green banner says «здоровье и цикл не видит никто». These tests are
 * mostly there to make that a property of the code rather than a sentence on a
 * screen: the tests below fail if any level ever reaches the mother's own
 * record, however the reaching is spelled.
 */

import { describe, it, expect } from 'vitest';
import {
  ACCESS_LEVELS, canRead, canWrite, checkInvite, grantCovers, INVITE_TTL_MS,
  inviteExpiry, isAccessLevel, isOpen, SHAREABLE,
  type InviteRow,
} from '../family/access';

const NOW = new Date('2026-08-08T12:00:00.000Z');
const hoursFromNow = (h: number) =>
  new Date(NOW.getTime() + h * 3_600_000).toISOString();

const invite = (over: Partial<InviteRow> = {}): InviteRow => ({
  tokenHash: 'h',
  ownerUserId: 'mother',
  level: 'viewer',
  createdAt: hoursFromNow(-1),
  expiresAt: hoursFromNow(23),
  usedAt: null,
  usedBy: null,
  revokedAt: null,
  ...over,
});

describe('the green banner, as code', () => {
  it('no level reaches the mother\'s own record', () => {
    // The one test this file exists for. If somebody adds a level that can see
    // her health, her cycle, her pregnancy or her diary, this fails — and the
    // banner on screen 40 stops being a lie.
    const forbidden = [
      'maternal_health', 'health', 'cycle', 'pregnancy', 'diary',
      'appointments', 'medications', 'weight', 'sleep', 'day_logs',
    ];
    for (const level of ACCESS_LEVELS) {
      for (const subject of forbidden) {
        expect(grantCovers(level, subject), `${level} could see ${subject}`)
          .toBe(false);
      }
    }
  });

  it('everything shareable is about the child, by name', () => {
    // A second guard on the same promise: the list itself cannot quietly grow
    // a member that is not the child's.
    for (const s of SHAREABLE) expect(s.startsWith('child_')).toBe(true);
  });

  it('fails closed on a subject it has never heard of', () => {
    // A route asking about something this module does not know is refused
    // rather than permitted by default.
    expect(grantCovers('guardian', 'something_new')).toBe(false);
    expect(grantCovers('guardian', '')).toBe(false);
  });

  it('fails closed on a level it has never heard of', () => {
    expect(grantCovers('admin', 'child_location')).toBe(false);
    expect(grantCovers('owner', 'child_location')).toBe(false);
    expect(isAccessLevel('guardian')).toBe(true);
    expect(isAccessLevel('anything')).toBe(false);
  });
});

describe('the two levels', () => {
  it('both can see the child', () => {
    for (const level of ACCESS_LEVELS) {
      expect(canRead(level, 'child_location')).toBe(true);
      expect(canRead(level, 'child_alerts')).toBe(true);
    }
  });

  it('only a guardian can change anything', () => {
    // The aunt who wants to know the child arrived does not get to move the
    // school zone on somebody else's account.
    expect(canWrite('viewer', 'child_zones')).toBe(false);
    expect(canWrite('guardian', 'child_zones')).toBe(true);
  });
});

describe('an invitation', () => {
  it('lasts a day', () => {
    expect(INVITE_TTL_MS).toBe(24 * 60 * 60 * 1000);
    expect(inviteExpiry(NOW)).toBe('2026-08-09T12:00:00.000Z');
  });

  it('is accepted once, and then spent', () => {
    // «одноразовая» — a link forwarded to a family group chat lets in exactly
    // one person.
    expect(checkInvite(invite(), 'father', NOW)).toEqual({ ok: true, level: 'viewer' });
    expect(checkInvite(invite({ usedAt: hoursFromNow(-1), usedBy: 'father' }), 'aunt', NOW))
      .toEqual({ ok: false, reason: 'already_used' });
  });

  it('stops working after twenty-four hours', () => {
    expect(checkInvite(invite({ expiresAt: hoursFromNow(-1) }), 'father', NOW))
      .toEqual({ ok: false, reason: 'expired' });
    // Exactly at the boundary is expired: a link is good FOR 24 hours, not
    // through the instant it runs out.
    expect(checkInvite(invite({ expiresAt: NOW.toISOString() }), 'father', NOW).ok)
      .toBe(false);
  });

  it('can be called back before anyone uses it', () => {
    expect(checkInvite(invite({ revokedAt: hoursFromNow(-1) }), 'father', NOW))
      .toEqual({ ok: false, reason: 'revoked' });
  });

  it('cannot be accepted by the person who sent it', () => {
    // Otherwise she becomes a relative of herself, and removing that grant
    // takes away her own children.
    expect(checkInvite(invite(), 'mother', NOW))
      .toEqual({ ok: false, reason: 'own_invite' });
  });

  it('distinguishes its refusals, because they need different words', () => {
    // An expired link needs a new one; a used one probably means somebody else
    // already joined. «Ссылка не работает» for both helps nobody.
    const reasons = new Set([
      checkInvite(null, 'x', NOW),
      checkInvite(invite({ expiresAt: hoursFromNow(-1) }), 'x', NOW),
      checkInvite(invite({ usedAt: hoursFromNow(-1) }), 'x', NOW),
      checkInvite(invite({ revokedAt: hoursFromNow(-1) }), 'x', NOW),
    ].map((r) => (r.ok ? 'ok' : r.reason)));
    expect(reasons.size).toBe(4);
  });

  it('drops an expired link off the list rather than showing a dead one', () => {
    expect(isOpen(invite(), NOW)).toBe(true);
    expect(isOpen(invite({ expiresAt: hoursFromNow(-1) }), NOW)).toBe(false);
    expect(isOpen(invite({ usedAt: hoursFromNow(-1) }), NOW)).toBe(false);
    expect(isOpen(invite({ revokedAt: hoursFromNow(-1) }), NOW)).toBe(false);
  });
});
