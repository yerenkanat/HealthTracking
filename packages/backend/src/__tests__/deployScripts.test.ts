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
import { spawnSync } from 'node:child_process';
import { existsSync, readFileSync, readdirSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { STAFF_ROLES } from '../auth/capabilities';

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

  it('an unquoted heredoc contains no unescaped backticks or $( )', () => {
    // The second way a deploy script has lied about what it wrote.
    //
    // landing-takeover.sh builds the live Caddyfile with `cat > "$F" <<EOF`.
    // Unquoted, because the body genuinely needs ${BACKEND} and $ADMIN_BLOCK.
    // But an unquoted heredoc also expands backticks — including ones inside
    // *comments* — so on 2026-08-12 writing the config ran three commands off
    // the box's own documentation:
    //
    //     `curl -H 'x-user-id: <any uuid>' /children`  -> curl: (3) missing URL
    //     `handle /auth/phone`                         -> handle: command not found
    //     `preload`                                    -> preload: command not found
    //
    // Harmless words, this time. The mechanism is not harmless: it is arbitrary
    // command execution from a comment, running as root, in the script that
    // rewrites the proxy config for the whole domain. It also silently deleted
    // those words from the config Caddy actually got, so the file's own
    // explanation of why /auth/phone needs a glob was gone from the box.
    //
    // Escaping (\`) keeps the text and stops the expansion. Quoting the whole
    // heredoc would too, but then ${BACKEND} would not interpolate.
    const offenders: string[] = [];
    for (const { name, body } of scripts) {
      const lines = body.split('\n');
      let end: string | null = null;
      lines.forEach((line, i) => {
        if (end === null) {
          // Only UNQUOTED heredocs expand. <<'EOF' and <<"EOF" are literal.
          const open = line.match(/<<-?\s*([A-Za-z_][A-Za-z0-9_]*)\s*$/);
          if (open) end = open[1];
          return;
        }
        if (line.trim() === end) { end = null; return; }
        const bare = line.replace(/\\[`$]/g, '');
        if (bare.includes('`') || /\$\(/.test(bare)) {
          offenders.push(`${name}:${i + 1}: ${line.trim().slice(0, 90)}`);
        }
      });
    }
    expect(
      offenders,
      'An unquoted heredoc expands backticks and $( ) anywhere in its body, ' +
        'comments included, and the expansion runs as root. Escape them (\\`) ' +
        'or quote the heredoc if nothing in it needs interpolating.\n',
    ).toEqual([]);
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

  it('never hides a check inside a `docker run … sh -c` block', () => {
    // The third way a deploy script has reported success it had not earned,
    // and the one that reaches furthest: `set -euo pipefail` in the outer
    // script does NOT reach into a child shell, and `sh -c`'s exit status is
    // its LAST command's.
    //
    // landing-stack.sh ended such a block with a `printf` of the byte count.
    // printf always succeeds. So the whole landing self-check was decorative:
    // a page served WITHOUT landing/wire.js — the lead form's entire callback
    // path, on the monetisation surface — printed three OK lines instead of
    // four, printed a byte count, said «Backend is up» and exited 0.
    // Reproduced against a real page with wire.js stripped: exit 0.
    //
    // The rule is not "don't use sh -c"; fetching inside a container is often
    // the only way to reach a private network. The rule is that the VERDICT
    // must be reached in the outer shell, where set -e and the script's own
    // failure counter can act on it. A POSIX single-quoted string cannot
    // contain a single quote, so `sh -c '…'` bodies delimit exactly.
    const CHECKS = /\bgrep\s+-q\b|^\s*\[\s|\btest\s+-[a-z]\b/m;
    const offenders: string[] = [];
    for (const { name, body } of scripts) {
      for (const m of body.matchAll(/sh\s+-c\s+'([^']*)'/g)) {
        if (CHECKS.test(m[1]!)) {
          const line = body.slice(0, m.index).split('\n').length;
          offenders.push(`${name}:${line}: check inside sh -c`);
        }
      }
    }
    expect(
      offenders,
      'A check inside `docker run … sh -c` is outside the outer set -e, and the ' +
        "block's exit status is its last command's — usually an echo or a printf, " +
        'which always succeeds. Fetch in the container, capture the body in the ' +
        'outer shell, and decide there.\n',
    ).toEqual([]);
  });

  it('landing-stack.sh fails the run when the landing self-check fails', () => {
    const s = scripts.find((x) => x.name === 'landing-stack.sh');
    expect(s, 'deploy/landing-stack.sh is missing').toBeDefined();
    // Checked out with CRLF on Windows, LF on the box. Normalise, or the
    // assertions below pass or fail depending on whose machine ran them.
    const body = s!.body.replace(/\r\n/g, '\n');
    // Pins the fix itself, not just the absence of the bad shape: the markers
    // must be matched with a `case` (no pipeline to invert — this page is
    // ~130 KB, twice the 64 KB pipe buffer where the SIGPIPE bug bites), the
    // failures must be counted, and the count must decide the exit status.
    expect(body, 'the landing markers are no longer matched with a bash case')
      .toMatch(/case "\$LANDING_BODY" in\s*\n\s*\*"\$1"\*\)/);
    expect(body, 'the landing failures are no longer counted')
      .toMatch(/LANDING_FAILURES=\$\(\(LANDING_FAILURES \+ 1\)\)/);
    expect(body, 'landing-stack.sh no longer exits non-zero on a failed landing check')
      .toMatch(/if \[ "\$LANDING_FAILURES" -ne 0 \]; then[\s\S]{0,900}?\n {2}exit 1\n/);
  });

  it('every landing marker landing-stack.sh checks for is in the built landing', () => {
    // The other half, exactly as for the panel markers above: a marker that
    // cannot be found fails every deploy for ever, and a marker that drifts
    // when the landing is re-exported does the same. `/` is an EXPORTED
    // ARTIFACT — tools/build-landing.mjs unpacks it — so the names in it move
    // without anybody editing this script.
    const body = scripts.find((x) => x.name === 'landing-stack.sh')!.body;
    const landing = readFileSync(resolve(here, '../../landing/index.html'), 'utf8');
    const markers = [...body.matchAll(/^landing_check "([^"]+)"/gm)].map((m) => m[1]!);
    expect(markers.length, 'landing-stack.sh checks no landing markers at all')
      .toBeGreaterThanOrEqual(3);
    expect(
      markers,
      'the lead form is the monetisation surface; its script must be checked for',
    ).toContain('landing/wire.js');
    expect(markers.filter((m) => !landing.includes(m))).toEqual([]);
  });
});

/**
 * db/seed-staff.mjs is not in deploy/, but it is a deploy-time script and
 * src/routes/staffAdmin.ts names it as THE recovery route out of a lockout —
 * the same category as everything above: code a person runs under pressure,
 * whose failure they cannot debug from inside the product.
 */
describe('db/seed-staff.mjs (the lockout recovery path)', () => {
  const SEED = resolve(here, '../../db/seed-staff.mjs');
  // A port nothing can be listening on, so the connection is refused
  // immediately. Every assertion here is about the ROLE CHECK, which runs
  // before any query — so "reached the database" is the pass condition.
  const DEAD_DB = 'postgres://x:x@127.0.0.1:1/x';
  const REJECTED = 2;

  function seed(role: string) {
    return spawnSync(process.execPath, [SEED], {
      encoding: 'utf8',
      env: {
        ...process.env,
        DATABASE_URL: DEAD_DB,
        STAFF_PHONE: '7071112233',
        STAFF_PASSWORD: 'longenough1',
        STAFF_ROLE: role,
      },
    });
  }

  it('carries no role list of its own', () => {
    // It used to validate against a literal ['admin','clinician','support']
    // while staffAdmin.ts had already moved to the shared STAFF_ROLES. Two
    // lists is the defect; one list is the fix, and this is what keeps it one.
    const src = readFileSync(SEED, 'utf8');
    expect(src, 'seed-staff.mjs must read STAFF_ROLES, not restate the roles')
      .toMatch(/STAFF_ROLES\.includes\(role\)/);
    // Comments are where the old list is *explained*, verbatim, so the next
    // reader knows what not to write — exactly as in the grep -q rule above.
    // Scan the code only, or the file's own documentation fails the test.
    const code = src.replace(/\/\*[\s\S]*?\*\//g, '').replace(/^\s*\/\/.*$/gm, '');
    for (const literal of [/\[\s*'admin'\s*,\s*'clinician'/, /\[\s*"admin"\s*,\s*"clinician"/]) {
      expect(code, 'a second, hardcoded role list is back in seed-staff.mjs')
        .not.toMatch(literal);
    }
  });

  it('accepts every role the panel can assign', { timeout: 60_000 }, () => {
    // The concrete failure this replaces: after a lockout the owner SSHes in,
    // runs STAFF_ROLE=warehouse, and gets exit 2. The only role the script
    // still accepted was `admin` — every capability there is. So a warehouse
    // hand seeded from the shell came out holding `health` and `finance`: a
    // mother's medical record and a child's location.
    const rejected: string[] = [];
    for (const role of STAFF_ROLES) {
      const r = seed(role);
      // Not `=== 0`: there is no database here, so a role that passes
      // validation dies later, on the query. Exit 2 is the role check itself.
      if (r.status === REJECTED) rejected.push(`${role}: ${r.stderr.trim().split('\n')[0]}`);
    }
    expect(
      rejected,
      'These roles exist in the capability matrix and can be assigned in the ' +
        'panel, but the shell recovery path refuses them — so the only account ' +
        'it can mint for that person is a full-power admin.\n',
    ).toEqual([]);
  });

  it('still rejects a role that does not exist, and says which ones do', () => {
    const r = seed('warehousee');
    expect(r.status, 'an unknown role must not be written to staff_accounts')
      .toBe(REJECTED);
    // The message has to be actionable at 3am, so it lists the real options
    // rather than three of them.
    for (const role of STAFF_ROLES) expect(r.stderr).toContain(role);
  });
});

/**
 * The nightly dump is the only portable copy of the database, and nothing in
 * the database is encrypted — not a mother's blood pressure, not a child's
 * location trail, not a child's allergy list (db/schema.sql says so plainly
 * now; it used to claim the opposite). So the dump is where that copy is either
 * protected or not.
 *
 * Until 2026-08-20 it was `pg_dump -Fc > "$out"`, fourteen plaintext copies of
 * every family's health record sitting beside the database they came from.
 *
 * These are text checks on purpose, like the rest of this file: the script is
 * only ever run on the server, and the property worth guarding is structural —
 * that no path through it leaves a readable dump behind.
 */
describe('deploy/backup.sh keeps no plaintext copy', () => {
  const backup = scripts.find((s) => s.name === 'backup.sh');
  const install = scripts.find((s) => s.name === 'backup-install.sh');

  it('both scripts are here to check', () => {
    // Guards the guard: a renamed file would make every assertion below vacuous.
    expect(backup, 'deploy/backup.sh not found').toBeTruthy();
    expect(install, 'deploy/backup-install.sh not found').toBeTruthy();
  });

  it('the file it keeps is encrypted, and the plaintext never lands in daily/', () => {
    const b = backup!.body;
    // The kept artefact is the age file.
    expect(b).toMatch(/out="\$DEST\/daily\/umay-\$stamp\.dump\.age"/);
    // pg_dump writes to the staging path, never to $out. `> "$out"` anywhere on
    // a pg_dump line is the old bug returning.
    expect(b).toMatch(/pg_dump[^\n]*> "\$plain"/);
    expect(b, 'pg_dump must not write the file that is kept').not.toMatch(/pg_dump[^\n]*> "\$out"/);
    // Something has to remove the plaintext even when the run dies halfway.
    expect(b).toMatch(/trap cleanup EXIT/);
    expect(b).toMatch(/shred -u "\$plain"/);
    // Rotation and the monthly copy both operate on ciphertext; a glob left on
    // *.dump would silently stop rotating and grow forever.
    expect(b).toMatch(/umay-\*\.dump\.age/);
    expect(b).toMatch(/cp -a "\$out" "\$DEST\/monthly\/umay-\$stamp\.dump\.age"/);
  });

  it('RUN with no key: exits non-zero, says why, and writes nothing', () => {
    // Not a text check — the script is actually executed. The no-key path
    // returns before it touches docker, so this is hermetic, and it is the one
    // property worth proving by running: that there is no branch, however it is
    // later refactored, in which a missing key still produces a dump.
    //
    // A warn-and-carry-on fallback would pass every string assertion in this
    // file and still write a plaintext copy of every family's health record.
    // It cannot pass this.
    const dest = join(tmpdir(), `umay-backup-test-${process.pid}-${Date.now()}`);
    const run = spawnSync('bash', [join(DEPLOY, 'backup.sh')], {
      encoding: 'utf8',
      env: { ...process.env, BACKUP_RECIPIENT: '', RECIPIENT_FILE: join(dest, 'absent.pub'), DEST: dest },
    });

    // Guards the guard: if bash could not be found, `status` is null and every
    // assertion below would be meaningless. Say so rather than pass.
    expect(run.error, `could not run bash: ${run.error?.message ?? ''}`).toBeUndefined();

    expect(run.status, 'a run with no encryption key must fail').toBe(1);
    expect(run.stderr).toContain('REFUSING TO BACK UP');
    // And it stopped early enough that it created nothing at all — no staging
    // directory, no daily/, and above all no dump.
    expect(existsSync(dest), `${dest} was created despite refusing to run`).toBe(false);
  });

  it('has no escape hatch that turns encryption off', () => {
    // An env var that disables it is the one that gets set during an incident
    // at 2 a.m. and is never unset.
    expect(backup!.body).not.toMatch(/ALLOW_PLAINTEXT|SKIP_ENCRYPT|NO_ENCRYPT/i);
  });

  it('proves the file it kept is really ciphertext before deleting the plaintext', () => {
    const b = backup!.body;
    // "age exited 0" is not "the file on disk is encrypted". PGDMP is pg_dump's
    // custom-format magic: if the kept file starts with it, the plaintext came
    // through and the script must throw the file away rather than keep it.
    expect(b).toMatch(/age-encryption\.org/);
    expect(b).toMatch(/PGDMP/);
    const check = b.indexOf('PGDMP');
    const drop = b.indexOf('cleanup            # the plaintext goes now');
    expect(check, 'the ciphertext check must run before the plaintext is shredded')
      .toBeLessThan(drop);
  });

  it('backup-install.sh will not install a timer that cannot encrypt', () => {
    const i = install!.body;
    // Otherwise the failure lands at 03:20 in a journal nobody reads, instead
    // of in front of the person who just ran the installer.
    expect(i).toMatch(/grep -qs '\^age1'/);
    expect(i).toMatch(/Not installing the timer: no backup encryption key/);
    const refuse = i.indexOf('Not installing the timer');
    const unit = i.indexOf('/etc/systemd/system/umay-backup.service');
    expect(refuse, 'the refusal must come before the unit file is written')
      .toBeLessThan(unit);
  });
});
