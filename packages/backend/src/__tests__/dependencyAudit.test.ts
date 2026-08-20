/**
 * The dependency gate, tested against fixtures rather than against the registry.
 *
 * `tools/audit-deps.mjs` decides whether a build stops. What it must never do is
 * pass because it failed to look -- the same failure shape as a deploy check that
 * reports success on a config nobody applied. So its decision is a pure function
 * and this drives it with audit documents that are made up on purpose.
 *
 * The rules it encodes, and why each one is there:
 *
 *   · a NEW high or critical advisory stops the build -- the whole point
 *   · a moderate one does NOT -- a build that goes red over a moderate advisory
 *     in a dev dependency is the check people stop reading
 *   · an exception that no longer matches anything stops the build -- otherwise
 *     the list quietly becomes a set of permanent blind spots
 *   · an exception past its date stops the build -- otherwise "until" is decoration
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
// @ts-expect-error - plain ESM tooling script, no types
import { triage, ACCEPTED } from '../../../../tools/audit-deps.mjs';

const here = dirname(fileURLToPath(import.meta.url));
const CI = readFileSync(resolve(here, '../../../../.github/workflows/ci.yml'), 'utf8');
const DEPENDABOT = readFileSync(resolve(here, '../../../../.github/dependabot.yml'), 'utf8');

const audit = (...vulns: Array<{ name: string; severity: string; isDirect?: boolean }>) => ({
  vulnerabilities: Object.fromEntries(
    vulns.map((v) => [v.name, { name: v.name, severity: v.severity, range: '<1.0.0', isDirect: !!v.isDirect }]),
  ),
});

const TODAY = '2026-08-20';

describe('what stops a build', () => {
  it('a new critical advisory does', () => {
    const t = triage(audit({ name: 'pg', severity: 'critical' }), {}, TODAY);
    expect(t.ok).toBe(false);
    expect(t.failures.map((f: { name: string }) => f.name)).toEqual(['pg']);
  });

  it('a new high advisory does', () => {
    const t = triage(audit({ name: 'ioredis', severity: 'high' }), {}, TODAY);
    expect(t.ok).toBe(false);
  });

  it('a moderate or low one does not', () => {
    const t = triage(
      audit({ name: 'somelib', severity: 'moderate' }, { name: 'other', severity: 'low' }),
      {}, TODAY,
    );
    expect(t.ok, 'red over a moderate advisory is how a check gets ignored').toBe(true);
    expect(t.reported).toEqual([]);
  });

  it('nothing at all does not', () => {
    expect(triage({ vulnerabilities: {} }, {}, TODAY).ok).toBe(true);
  });
});

describe('the exception list cannot rot', () => {
  const accepted = { fastify: { until: '2026-10-01', why: 'major upgrade, scheduled' } };

  it('an accepted advisory passes, and is still reported out loud', () => {
    const t = triage(audit({ name: 'fastify', severity: 'high', isDirect: true }), accepted, TODAY);
    expect(t.ok).toBe(true);
    // Accepted is not the same as invisible. It must still be printed, or the
    // list becomes a way of never seeing the thing again.
    expect(t.reported.map((r: { name: string }) => r.name)).toEqual(['fastify']);
  });

  it('an exception for something no longer reported fails', () => {
    const t = triage({ vulnerabilities: {} }, accepted, TODAY);
    expect(t.ok).toBe(false);
    expect(t.stale).toEqual(['fastify']);
  });

  it('an exception past its date fails', () => {
    const t = triage(audit({ name: 'fastify', severity: 'high' }), accepted, '2026-10-02');
    expect(t.ok).toBe(false);
    expect(t.expired.map((e: { name: string }) => e.name)).toEqual(['fastify']);
  });

  it('and passes on the last day it is valid', () => {
    // A boundary written down, because "until" read as exclusive by one person
    // and inclusive by the next is a build that fails for a reason nobody
    // predicted.
    expect(triage(audit({ name: 'fastify', severity: 'high' }), accepted, '2026-10-01').ok).toBe(true);
  });
});

describe('the list that is actually shipped', () => {
  it('gives every exception a reason and a date', () => {
    expect(Object.keys(ACCEPTED).length, 'nothing accepted at all -- is this list still wired up?')
      .toBeGreaterThan(0);
    for (const [name, e] of Object.entries(ACCEPTED as Record<string, { until: string; why: string }>)) {
      expect(e.until, `${name} has no expiry`).toMatch(/^\d{4}-\d{2}-\d{2}$/);
      // Long enough to be an argument rather than a shrug. "known issue" is not
      // something the next person can act on.
      expect(e.why.length, `${name}'s reason is too short to act on`).toBeGreaterThan(60);
    }
  });

  it('does not accept anything for longer than a quarter', () => {
    // An exception with a distant date is a permanent exception wearing a
    // deadline. Six weeks was the judgement when this was written.
    for (const [name, e] of Object.entries(ACCEPTED as Record<string, { until: string }>)) {
      expect(e.until < '2026-12-01', `${name} is accepted until ${e.until}, which is not a deadline`).toBe(true);
    }
  });
});

describe('it is wired into CI and dependabot', () => {
  // The repo's own dominant defect: finished code with no caller. A gate that
  // nothing runs is decoration.
  it('CI runs the gate', () => {
    expect(CI).toContain('tools/audit-deps.mjs');
  });

  it('CI audits the Python service too', () => {
    // packages/cry-classifier parses audio a caller uploaded, through
    // libsndfile and librosa. It is the least boring parser in the product.
    expect(CI).toContain('pip-audit');
    expect(CI).toContain('packages/cry-classifier/requirements.txt');
  });

  it('dependabot watches npm, pip and the workflows', () => {
    for (const eco of ['npm', 'pip', 'github-actions']) {
      expect(DEPENDABOT, `${eco} is not watched`).toMatch(new RegExp(`package-ecosystem:\\s*${eco}\\b`));
    }
  });
});
