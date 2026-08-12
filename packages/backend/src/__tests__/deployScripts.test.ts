/**
 * The deploy scripts are the only code in this repo that nothing else tests,
 * and they are the code whose failures cost the most: they are read by a person
 * under time pressure who is deciding whether the site is broken.
 *
 * This file exists because of one bug, found twice.
 *
 *     printf '%s' "$body" | grep -q "$marker"
 *
 * Under `set -o pipefail` — which every script here sets — `grep -q` exits the
 * instant it matches. The writer's next write to the closed pipe raises
 * SIGPIPE, the writer dies with 141, and pipefail makes the PIPELINE's status
 * that 141. So the condition is false precisely when the marker was found.
 *
 * It only misfires past the 64 KB pipe buffer: below that the writer finishes
 * before grep can close anything, and the check passes. That threshold is what
 * made it so expensive. On 2026-08-12 a deploy that had correctly shipped every
 * one of its 22 panel markers reported
 *
 *     !!  the panel serves the new Dashboard FAILED — /admin did not contain dashKpis
 *
 * because /admin is 467 KB, while /shop/products (a few hundred bytes) passed
 * two lines earlier. It reads exactly like a stale container serving old markup
 * — the one failure mode update.sh was written to catch — and a session went
 * into hunting a container that was serving the right file the whole time.
 *
 * The same bug had already been diagnosed and fixed in verify-live.sh days
 * earlier, where it had claimed fabricated testimonials were gone from the live
 * landing while they were still on it. Fixing one copy and leaving the other is
 * what this test is here to stop.
 *
 * The rule: never pipe a response body into `grep -q`. Use a bash `case`, which
 * matches in the shell with no pipeline and no exit status to invert.
 */

import { describe, expect, it } from 'vitest';
import { readFileSync, readdirSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const here = dirname(fileURLToPath(import.meta.url));
const DEPLOY = resolve(here, '../../../../deploy');

const scripts = readdirSync(DEPLOY)
  .filter((f) => f.endsWith('.sh'))
  .map((f) => ({ name: f, body: readFileSync(join(DEPLOY, f), 'utf8') }));

/**
 * Commands that can emit a whole HTTP response. `docker ps`, `psql -tc` and
 * `docker logs --tail N` are deliberately absent: their output is bounded well
 * under the pipe buffer, so piping those into `grep -q` is safe and there is no
 * reason to churn them.
 */
const UNBOUNDED = /(^|[;&|(]\s*|\$\()\s*(printf|echo|cat|curl|wget)\b[^|\n]*\|\s*grep\s+-q/;

describe('deploy scripts', () => {
  it('has scripts to check', () => {
    expect(scripts.length).toBeGreaterThan(5);
  });

  it('never pipes a response body into grep -q', () => {
    const offenders: string[] = [];
    for (const { name, body } of scripts) {
      body.split('\n').forEach((line, i) => {
        // Comments are where this bug is *explained*; both fixes carry a note
        // containing the offending snippet verbatim so the next reader knows
        // what not to write.
        if (/^\s*#/.test(line)) return;
        if (UNBOUNDED.test(line)) offenders.push(`${name}:${i + 1}: ${line.trim()}`);
      });
    }
    expect(
      offenders,
      'A pipeline into `grep -q` is inverted by SIGPIPE under `set -o pipefail` ' +
        'once the body exceeds the 64 KB pipe buffer: the check fails because it ' +
        'succeeded. Capture the body in a variable and match it with a bash ' +
        '`case "$body" in *"$marker"*)` instead.\n',
    ).toEqual([]);
  });

  it('update.sh matches panel markers with case, not a pipeline', () => {
    const update = scripts.find((s) => s.name === 'update.sh');
    expect(update, 'deploy/update.sh is missing').toBeDefined();
    // Pins the fix itself, not just the absence of the bad shape: a rewrite
    // that dropped the `case` for some third mechanism would otherwise sail
    // through the rule above.
    expect(update!.body).toMatch(/case "\$body" in\s*\n\s*\*"\$2"\*\)/);
  });

  it('every panel marker update.sh checks for is actually in the panel', () => {
    // The other half of the same failure. A marker that is checked but never
    // appears in index.html fails every deploy for ever; a marker that drifts
    // when the panel is refactored does the same. Both have happened.
    const update = scripts.find((s) => s.name === 'update.sh')!.body;
    const panel = readFileSync(resolve(here, '../../../admin/index.html'), 'utf8');
    const markers = [...update.matchAll(/^check "\/admin" '([^']+)'/gm)].map((m) => m[1]);
    expect(markers.length, 'update.sh checks no panel markers at all').toBeGreaterThan(15);
    expect(markers.filter((m) => !panel.includes(m))).toEqual([]);
  });
});
