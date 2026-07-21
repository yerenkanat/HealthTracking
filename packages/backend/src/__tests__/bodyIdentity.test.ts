/**
 * Identity comes from authentication, never from the payload.
 *
 * Two routes take a `userId` in the request body — /ai/chat and
 * /calibration/bp — because the schema they share with the app carries one.
 * Both compare it to the authenticated caller and answer 403 otherwise, and
 * both say why in a comment. Neither is wrong today.
 *
 * The check is hand-written in each handler, though, and the cost of omitting
 * it is not obvious from reading the handler that omits it: a body userId
 * flows straight into repo.emergencyContacts() and the guardrail, so a caller
 * could read another woman's emergency contacts, or write blood-pressure
 * calibration offsets that shift every later reading she takes — suppressing a
 * real preeclampsia emergency or manufacturing a false one.
 *
 * So this reads the routes out of the source: a route that accepts a userId in
 * its body and does not compare it fails, and a NEW one fails by default.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const src = readFileSync(fileURLToPath(new URL('../server.ts', import.meta.url)), 'utf8');

interface Route {
  key: string;
  body: string;
}

/** Every app-facing route in server.ts, with its handler body. */
function routes(): Route[] {
  const lines = src.split('\n');
  const starts: Array<{ i: number; key: string }> = [];
  lines.forEach((line, i) => {
    const m = line.match(/app\.(get|put|post|delete|patch)\('([^']+)'/);
    if (m) starts.push({ i, key: `${m[1].toUpperCase()} ${m[2]}` });
  });
  return starts.map((s, n) => ({
    key: s.key,
    body: lines.slice(s.i, n + 1 < starts.length ? starts[n + 1].i : lines.length).join('\n'),
  }));
}

/** Schemas that carry a userId field, so a route parsing one accepts an identity. */
function schemasWithUserId(): string[] {
  const out: string[] = [];
  for (const m of src.matchAll(/const (\w+) = z\.object\(\{([\s\S]*?)\n\}\);/g)) {
    if (/^\s*userId:/m.test(m[2])) out.push(m[1]);
  }
  return out;
}

describe('a userId in the body is never trusted', () => {
  it('found the routes and the schemas to check', () => {
    // Both halves must actually match something, or every check below passes
    // by finding nothing — the failure mode of any source-reading guard.
    expect(routes().length).toBeGreaterThan(4);
    expect(schemasWithUserId()).toContain('chatSchema');
    expect(schemasWithUserId()).toContain('bpCalSchema');
  });

  it('every route parsing such a schema compares it to the caller', () => {
    const withUserId = schemasWithUserId();
    const accepting = routes().filter((r) => withUserId.some((s) => r.body.includes(`${s}.safeParse`)));
    expect(accepting.length, 'no route parses a userId body — has the schema moved?').toBeGreaterThan(0);

    const unchecked = accepting
      .filter((r) => !/parsed\.data\.userId !== caller\.userId/.test(r.body))
      .map((r) => r.key);
    expect(
      unchecked,
      `these take a userId from the body and never compare it: ${unchecked.join(', ')}. ` +
        'Add `if (parsed.data.userId !== caller.userId) return reply.code(403)...`',
    ).toEqual([]);
  });

  it('and refuses before doing any work', () => {
    // A check placed after the lookup has already done the lookup — and the
    // lookup here is what reads another user's emergency contacts.
    for (const r of routes().filter((x) => /parsed\.data\.userId !== caller\.userId/.test(x.body))) {
      const guardAt = r.body.indexOf('parsed.data.userId !== caller.userId');
      for (const call of ['emergencyContacts(', 'setBpCalibration(', 'processWithGuardrails(']) {
        const useAt = r.body.indexOf(call);
        if (useAt === -1) continue;
        expect(guardAt, `${r.key} uses ${call} before checking the body userId`).toBeLessThan(useAt);
      }
    }
  });

  it('the rate limit is spent by the caller, not by whoever the body names', () => {
    // Taking a token before knowing who is asking would let one client exhaust
    // another's budget; taking it keyed on the body would do the same.
    for (const r of routes().filter((x) => /Limiter\.take\(/.test(x.body))) {
      expect(r.body, `${r.key} should rate-limit by the authenticated caller`).toMatch(
        /Limiter\.take\(caller\.userId\)/,
      );
    }
  });
});
