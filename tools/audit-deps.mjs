// Invoked as `node tools/audit-deps.mjs` (see .github/workflows/ci.yml).
// NO SHEBANG: this module is also IMPORTED by dependencyAudit.test.ts, and a
// leading #! makes the test transform fail with SyntaxError pointing at an
// unrelated line in the importing file. Node does not need it here.
/**
 * The dependency gate: fail on a HIGH or CRITICAL advisory nobody has looked at.
 *
 *     node tools/audit-deps.mjs
 *
 * WHY NOT JUST `npm audit --audit-level=high`. Because it is red today and
 * would be red every day after, and a check that is always red is a check
 * everybody learns to scroll past — which is worse than not having one. The
 * tree currently carries eight advisories at high or above, and the fix for the
 * two that matter most is a MAJOR upgrade of the web framework and of the test
 * runner. Those are real pieces of work with their own risk, not something to
 * slip into an unrelated change.
 *
 * So: every high/critical advisory must be either FIXED or NAMED HERE, with a
 * reason and a date by which it must be gone. Anything new fails the build the
 * day it appears, which is the whole point. And the list cannot rot:
 *
 *   · an entry that no longer matches any advisory fails too — delete it
 *   · an entry past its `until` date fails — upgrade it, or write down why not
 *
 * Moderate and low are not gated. They are still reported, and dependabot still
 * opens the pull request; a build that goes red over a moderate advisory in a
 * dev dependency is exactly the check people stop reading.
 */

import { spawnSync } from 'node:child_process';

/** Severities that stop a build. */
const GATED = new Set(['high', 'critical']);

/**
 * Advisories that are known, judged, and waiting on work that is scheduled.
 *
 * Keyed by the vulnerable PACKAGE name as npm reports it. Every entry needs a
 * `why` a stranger can act on and an `until` that is close enough to be a
 * commitment. Adding one is a decision; leaving one to expire is not.
 */
export const ACCEPTED = {
  fastify: {
    until: '2026-10-01',
    why: 'HIGH ×3 (sendWebStream DoS, Content-Type tab body-validation bypass, ' +
      'X-Forwarded-Proto/Host spoofing). Installed 4.29.1; the fix is fastify 5.12.1, ' +
      'a major migration of the framework every route in the product is built on. ' +
      'Scheduled separately. The X-Forwarded item is partly mitigated here: the edge ' +
      'overwrites X-Forwarded-For (deploy/landing-takeover.sh) and the app trusts one ' +
      'hop only (server.ts trustProxy: 1).',
  },
  'find-my-way': {
    until: '2026-10-01',
    why: 'HIGH, HTTP/2 DDoS. Fastify 4.29.1 pins it; it goes away with the fastify ' +
      'upgrade above. The edge terminates HTTP/2 and speaks HTTP/1.1 to the app, so ' +
      'the reachable path is Caddy, not this router.',
  },
  vitest: {
    until: '2026-10-01',
    why: 'CRITICAL, and dev-only: vitest is not installed on the server (update.sh ' +
      'runs `npm ci --omit=dev`). The fix is vitest 4, a major upgrade of the runner ' +
      'for 2 800 tests. Scheduled separately.',
  },
  vite: {
    until: '2026-10-01',
    why: 'HIGH, pulled in by vitest and dev-only for the same reason. Goes away with ' +
      'the vitest upgrade above.',
  },
  'fast-uri': { until: '2026-09-15', why: 'HIGH, transitive under fastify/ajv. A non-major fix exists — `npm audit fix` — which needs a full test run and a deploy of its own.' },
  'fast-xml-parser': { until: '2026-09-15', why: 'HIGH, transitive under firebase-admin. Non-major fix available; same batch as fast-uri.' },
  nanoid: { until: '2026-09-15', why: 'HIGH, transitive and dev-only (vite). Non-major fix available.' },
  undici: { until: '2026-09-15', why: 'HIGH, transitive under firebase-admin. Non-major fix available; same batch as fast-uri.' },
};

/**
 * Decide, from an `npm audit --json` document, what should stop the build.
 *
 * Pure, so it can be tested against fixtures instead of against whatever the
 * registry happens to say today — a gate whose behaviour nobody can reproduce
 * is a gate nobody trusts. See __tests__/dependencyAudit.test.ts.
 *
 * @param audit parsed `npm audit --json`
 * @param accepted the exception list, keyed by package name
 * @param today ISO date, injected so the expiry rule is testable
 * @returns { failures, reported, stale, expired, ok }
 */
export function triage(audit, accepted = ACCEPTED, today = new Date().toISOString().slice(0, 10)) {
  const vulns = Object.values(audit?.vulnerabilities ?? {});
  const reported = vulns
    .filter((v) => GATED.has(v.severity))
    .map((v) => ({ name: v.name, severity: v.severity, range: v.range, direct: !!v.isDirect }));

  const seen = new Set(reported.map((r) => r.name));
  // Not on the list: the build stops. This is the case the gate exists for.
  const failures = reported.filter((r) => !(r.name in accepted));
  // On the list but no longer reported: the exception outlived the advisory.
  // Left alone, the list slowly becomes a set of permanent blind spots.
  const stale = Object.keys(accepted).filter((name) => !seen.has(name));
  // On the list, still reported, and out of time.
  const expired = Object.entries(accepted)
    .filter(([name, e]) => seen.has(name) && e.until < today)
    .map(([name, e]) => ({ name, until: e.until }));

  return {
    reported,
    failures,
    stale,
    expired,
    ok: failures.length === 0 && stale.length === 0 && expired.length === 0,
  };
}

function main() {
  // `npm audit` exits non-zero WHENEVER it finds anything, so its status is
  // read here and deliberately not used as the verdict — the verdict is
  // triage(). Captured, never piped: a pipeline into grep is inverted by
  // SIGPIPE under pipefail, which has cost this repo two days already.
  // npm.cmd on Windows rather than `shell: true`: passing arguments through a
  // shell concatenates rather than escapes them, and node deprecates it for
  // that reason.
  const npm = process.platform === 'win32' ? 'npm.cmd' : 'npm';
  const run = spawnSync(npm, ['audit', '--json'], { encoding: 'utf8', maxBuffer: 1 << 28 });
  let audit;
  try {
    audit = JSON.parse(run.stdout);
  } catch {
    console.error('npm audit produced no JSON. It could not run, which is not the same as "no vulnerabilities".');
    console.error(run.stdout?.slice(0, 800) ?? '');
    console.error(run.stderr?.slice(0, 800) ?? '');
    process.exit(2);
  }
  if (audit.error) {
    console.error('npm audit failed:', audit.error.summary ?? JSON.stringify(audit.error));
    process.exit(2);
  }

  const t = triage(audit);
  const counts = audit.metadata?.vulnerabilities ?? {};
  console.log(`advisories: ${counts.critical ?? 0} critical, ${counts.high ?? 0} high, ` +
    `${counts.moderate ?? 0} moderate, ${counts.low ?? 0} low`);

  for (const r of t.reported) {
    const note = r.name in ACCEPTED ? `accepted until ${ACCEPTED[r.name].until}` : 'NOT ACCEPTED';
    console.log(`  ${r.severity.toUpperCase().padEnd(8)} ${r.name} ${r.range}${r.direct ? ' (direct)' : ''} — ${note}`);
  }

  for (const f of t.failures) {
    console.error(`\n!! ${f.severity.toUpperCase()} in ${f.name} (${f.range}) is new.`);
    console.error('   Upgrade it, or add it to ACCEPTED in tools/audit-deps.mjs with a reason and a date.');
  }
  for (const name of t.stale) {
    console.error(`\n!! ${name} is on the ACCEPTED list but no longer reported. Delete the entry —`);
    console.error('   an exception nobody removes is a hole nobody can see.');
  }
  for (const e of t.expired) {
    console.error(`\n!! the exception for ${e.name} expired on ${e.until}. Upgrade it, or write down why not and re-date it.`);
  }

  if (!t.ok) process.exit(1);
  console.log('\nNothing at high or critical that has not been looked at.');
}

// Run only as a CLI, so the test can import triage() without shelling out.
if (import.meta.url === `file://${process.argv[1]}` || process.argv[1]?.endsWith('audit-deps.mjs')) main();
