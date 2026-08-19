/**
 * Frame 22 — «Безопасность»: who has been reading special-category data.
 *
 * Every part of this existed and none of it was on a screen. The audit log
 * records who opened whose record and why, the capability matrix decides who
 * may, the retention sweep deletes routes at 90 days — and there was no page
 * that let anybody ASK whether it was being abused. A log nobody can query is
 * evidence after the fact and nothing before it.
 *
 * The number that matters is not the total. It is how many reads touched health
 * or a child's location, and how many of those went unexplained.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { readFileSync, readdirSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve, join } from 'node:path';
import { PROTECTED_ACTIONS, summarizeSecurity, type AuditRow } from '../admin/security';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import {
  AUDIT_RETENTION_YEARS,
  RETENTION_KEPT,
  RETENTION_SWEEPS,
  ROUTE_RETENTION_DAYS,
  retentionCutoff,
} from '../privacy/retention';
import type { StaffRole } from '../auth/capabilities';

const NOW = new Date('2026-08-08T12:00:00.000Z');
const daysAgo = (d: number) => new Date(NOW.getTime() - d * 86_400_000).toISOString();

const row = (over: Partial<AuditRow> = {}): AuditRow => ({
  staffId: 's1',
  staffName: 'Ерен',
  action: 'view_health',
  target: 'u1',
  targetName: 'Айгерім',
  reason: 'Обращение клиента',
  at: daysAgo(1),
  ...over,
});

const ROUTES_DIR = resolve(dirname(fileURLToPath(import.meta.url)), '../routes');

/**
 * Every audit action written by a route that ASKS WHY — read out of the routes
 * themselves, not re-typed here.
 *
 * A hand-written list of memberships is a list that goes stale silently, and
 * the way it goes stale is the worst one available: `view_wearable` shipped
 * demanding the `health` capability and a mandatory reason, wrote its row to
 * the log, and was absent from PROTECTED_ACTIONS — so the security page counted
 * every open of a named woman's heart rate, SpO2, blood pressure, stress and
 * breathing as nothing at all. Frame 22 could report `protectedReads: 0` while
 * a clinician read her vitals all month, and `withoutReason` — the one number
 * the page exists to make non-zero — structurally could not see the route.
 *
 * The gate IS the definition: `readReason` refuses the request unless the
 * person says why, and nothing is made to say why except a read of somebody's
 * record. So every action written under it is by construction a protected read,
 * and the NEXT such route fails this test on the day it is written rather than
 * vanishing from the security page for a year.
 *
 * One direction only. PROTECTED_ACTIONS legitimately holds more than this —
 * the feeds (`view_safety_feed`, `view_devices`, `view_device_registry`) are
 * polled lists that are audited WITHOUT a reason on purpose, because prompting
 * on a poll trains everyone to click through the prompt, and `view_health` is
 * kept for rows written before that route was deleted. Requiring the reverse
 * would delete those.
 */
function reasonGatedActions(): Array<{ file: string; route: string; action: string }> {
  const found: Array<{ file: string; route: string; action: string }> = [];
  for (const file of readdirSync(ROUTES_DIR).filter((f) => f.endsWith('.ts'))) {
    const src = readFileSync(join(ROUTES_DIR, file), 'utf8');
    const heads = [...src.matchAll(/app\.(?:get|post|put|patch|delete)\(\s*'([^']+)'/g)];
    for (let i = 0; i < heads.length; i++) {
      const start = heads[i].index!;
      const end = i + 1 < heads.length ? heads[i + 1].index! : src.length;
      // Declaring the gate is not passing through it.
      const body = src.slice(start, end).replace(/function\s+readReason\s*\(/g, 'function DEFINITION(');
      if (!/readReason\(/.test(body)) continue;
      for (const m of body.matchAll(/action:\s*'([a-z0-9_]+)'/g)) {
        found.push({ file, route: heads[i][1], action: m[1] });
      }
    }
  }
  return found;
}

describe('every reason-gated route is counted as a protected read', () => {
  it('finds the routes at all', () => {
    // Non-vacuity. If the scan silently matched nothing — a refactor to
    // `app.route({...})`, a rename of `readReason` — the check below would
    // pass over an empty list and this whole guard would be decoration.
    const actions = reasonGatedActions().map((a) => a.action);
    expect(actions.length, 'the route scan found no reason-gated reads at all').toBeGreaterThanOrEqual(3);
    // The three that exist today, named, so a scan that drifts to matching
    // something else is caught rather than accepted.
    expect(new Set(actions)).toEqual(
      new Set(['view_wellness', 'view_wearable', 'view_user_detail']),
    );
  });

  it('and every one of them is in PROTECTED_ACTIONS', () => {
    const missing = reasonGatedActions().filter((a) => !(a.action in PROTECTED_ACTIONS));
    expect(
      missing,
      missing.map((m) => `${m.file} ${m.route} writes '${m.action}' under a mandatory reason ` +
        'but PROTECTED_ACTIONS does not list it, so frame 22 counts that read as nothing — ' +
        `add ${missing.map((x) => x.action).join(', ')} to src/admin/security.ts`).join(' | '),
    ).toEqual([]);
  });

  it('the wearable route is one of them', () => {
    // The regression this class of check was written for: it demanded the health capability
    // and a reason from the day it shipped, and counted for nothing.
    expect(PROTECTED_ACTIONS.view_wearable).toBe('health');
  });
});

describe('what counts as a protected read', () => {
  it('health and location, and nothing else', () => {
    expect(PROTECTED_ACTIONS.view_health).toBe('health');
    expect(PROTECTED_ACTIONS.view_wellness).toBe('health');
    expect(PROTECTED_ACTIONS.view_safety_feed).toBe('location');
    expect(PROTECTED_ACTIONS.view_devices).toBe('location');
    // Ordinary back-office work is not a privacy event, and counting it here
    // would bury the reads that are.
    expect(PROTECTED_ACTIONS.list_users).toBeUndefined();
    expect(PROTECTED_ACTIONS.edit_content).toBeUndefined();
    expect(PROTECTED_ACTIONS.stock_move).toBeUndefined();
  });

  it('separates the two kinds, because they answer to different rules', () => {
    const s = summarizeSecurity(
      [row(), row({ action: 'view_devices' }), row({ action: 'view_wellness' })],
      NOW,
    );
    expect(s.protectedReads).toBe(3);
    expect(s.health).toBe(2);
    expect(s.location).toBe(1);
  });

  it('ignores everything outside the window', () => {
    const s = summarizeSecurity([row({ at: daysAgo(40) }), row({ at: daysAgo(3) })], NOW, 30);
    expect(s.protectedReads).toBe(1);
  });
});

describe('the number that should be zero', () => {
  it('counts reads with no reason recorded', () => {
    // Either a row from before the reason became mandatory, or a route that
    // reached protected data without going through readReason — which is the
    // hole this page exists to make visible.
    const s = summarizeSecurity([row(), row({ reason: null }), row({ reason: '  ' })], NOW);
    expect(s.withoutReason).toBe(2);
  });

  it('treats an empty reason as no reason', () => {
    // Otherwise the number that should be zero stays zero while the log fills
    // with blanks.
    expect(summarizeSecurity([row({ reason: '' })], NOW).withoutReason).toBe(1);
  });
});

describe('who has been looking', () => {
  it('ranks staff by how much they read, and names them', () => {
    const s = summarizeSecurity(
      [
        row({ staffId: 'a', staffName: 'Айгерім' }),
        row({ staffId: 'b', staffName: 'Ерен' }),
        row({ staffId: 'b', staffName: 'Ерен' }),
        row({ staffId: 'b', staffName: 'Ерен' }),
      ],
      NOW,
    );
    expect(s.byStaff[0]).toEqual({ staffId: 'b', staffName: 'Ерен', reads: 3 });
    expect(s.byStaff[1].staffId).toBe('a');
  });

  it('the log itself comes back newest first', () => {
    // It is read from the top by somebody checking what just happened.
    const s = summarizeSecurity(
      [row({ at: daysAgo(5), target: 'old' }), row({ at: daysAgo(1), target: 'new' })],
      NOW,
    );
    expect(s.recent[0].target).toBe('new');
  });
});

// ---------------------------------------------------------------------------

let app: FastifyInstance;

function makeApp(role: StaffRole) {
  return buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {}, resolveTransition: async () => null,
        sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => ({ userId: DEMO_USER }),
      authAdmin: async () => ({ staffId: 's1', role }),
    },
    { logger: false },
  );
}

beforeEach(() => { app = makeApp('owner'); });

describe('GET /admin/security', () => {
  it('reports a real read end to end', async () => {
    // Open a health record with a reason, then ask the security page about it.
    //
    // `/detail` rather than the deleted `/health` (docs/BACKLOG.md §3): it is
    // the read the panel makes, it carries the same guard and reason gate, and
    // `view_user_detail` is a `health` action in PROTECTED_ACTIONS — so this
    // still exercises the health counter, through the route that is used.
    await app.inject({
      method: 'GET',
      url: `/admin/users/${DEMO_USER}/detail?reason=${encodeURIComponent('Разбор жалобы')}`,
    });
    const body = (await app.inject({ method: 'GET', url: '/admin/security' })).json();
    expect(body.protectedReads).toBeGreaterThanOrEqual(1);
    expect(body.health).toBeGreaterThanOrEqual(1);
    expect(body.withoutReason).toBe(0);
    expect(body.recent[0].reason).toBe('Разбор жалобы');
    await app.close();
  });

  it('quotes the retention promises from where they are defined', async () => {
    // The screen reports these to a regulator. Re-typing 90 here is how the
    // page ends up claiming something the sweep does not do.
    const body = (await app.inject({ method: 'GET', url: '/admin/security' })).json();
    expect(body.retention.routeDays).toBe(ROUTE_RETENTION_DAYS);
    expect(body.retention.auditSweep).toBe(AUDIT_RETENTION_YEARS);
    await app.close();
  });

  it('reports EVERY enforced period, derived from the schedule', async () => {
    // The card reported two of eight. `routeDays` and `auditSweep` were typed
    // into this route by hand while geofence crossings, safety alerts, phone
    // codes, login attempts, shop leads and support threads were all being
    // deleted on periods nobody could see. This is the page a reviewer opens to
    // ask «what does this product keep, and for how long», and a page showing
    // two periods reads as a page showing all of them.
    //
    // The length is asserted against RETENTION_SWEEPS itself, so a ninth sweep
    // fails HERE until it reaches the panel — which it does without this file
    // or the route being edited, because the payload is derived, not listed.
    const body = (await app.inject({ method: 'GET', url: '/admin/security' })).json();
    expect(
      body.retention.swept?.length,
      'the security card is served a hand-kept list of periods, not the schedule',
    ).toBe(RETENTION_SWEEPS.length);
    expect(body.retention.swept.map((s: { table: string }) => s.table))
      .toEqual(RETENTION_SWEEPS.map((s) => s.table));
    for (const [i, s] of RETENTION_SWEEPS.entries()) {
      // The period served is the period the cutoff uses. Nothing is rounded on
      // the way to the screen.
      expect(body.retention.swept[i].days, `${s.table} is served a period the sweep does not use`)
        .toBe(s.days);
      expect(body.retention.swept[i].label).toBe(s.labelRu);
      expect(body.retention.swept[i].why).toBe(s.whyRu);
    }
    await app.close();
  });

  it('reports what is deliberately kept, so an absence is a decision', async () => {
    // An order kept as an accounting record is something a reviewer should be
    // TOLD, not left to infer from a table's absence from the swept list.
    const body = (await app.inject({ method: 'GET', url: '/admin/security' })).json();
    expect(
      body.retention.kept?.length,
      'nothing on the page says what is kept on purpose',
    ).toBe(RETENTION_KEPT.length);
    const orders = body.retention.kept
      .find((k: { table: string }) => k.table.includes('shop_orders'));
    expect(orders, 'the accounting decision is not on the page').toBeDefined();
    expect(orders.why).toBe(RETENTION_KEPT.find((k) => k.table.includes('shop_orders'))!.whyRu);
    // No period is served for a kept table: there is none, and a number here
    // would be a promise nothing enforces.
    expect(orders.days).toBeUndefined();
    await app.close();
  });

  it('states each period in the language of the panel that prints it', async () => {
    // The admin panel is Russian-only. `why` in privacy/retention.ts is written
    // in English for the reader of that file; `whyRu` is the same decision for
    // the reviewer reading the screen, and it lives beside it there rather than
    // being re-authored in the panel's HTML — a second set of explanations is a
    // second set that can drift. 1e25233 shipped English audit keys at a
    // Russian reviewer; this is the same trap one file along.
    const body = (await app.inject({ method: 'GET', url: '/admin/security' })).json();
    const lines = [...(body.retention.swept ?? []), ...(body.retention.kept ?? [])];
    expect(lines.length, 'the card is served no periods to state at all').toBeGreaterThan(0);
    for (const line of lines) {
      expect(line.label, `${line.table} has no Russian name`).toMatch(/[А-Яа-яЁё]/);
      expect(line.why, `${line.table} has no Russian reason`).toMatch(/[А-Яа-яЁё]/);
      expect(line.why.length, `${line.table} has no stated reason`).toBeGreaterThan(10);
    }
    await app.close();
  });

  it('the audit period is a SWEEP, not a number on a screen', async () => {
    // This is the assertion that matters, and the one that was missing when
    // the page printed «3 года» for months with nothing deleting a row. A
    // number is cheap; the scheduled DELETE behind it is the claim.
    //
    // b8aac0c corrected the page to «срок не задан» and pinned that with the
    // inverse assertion. The period exists now, so the pin moves to where it
    // should always have been: the entry in RETENTION_SWEEPS, the cutoff it
    // computes, and a row actually disappearing.
    const sweep = RETENTION_SWEEPS.find((s) => s.table === 'audit_log');
    expect(sweep, 'audit_log is not on the retention schedule').toBeDefined();
    expect(sweep!.days).toBe(AUDIT_RETENTION_YEARS * 365);

    // And it deletes. An old row goes; a row inside the window stays, which is
    // the half that matters more — a sweep that over-deletes cannot be undone,
    // and this table is the evidence that nobody read a record unexplained.
    const repo = createMemoryRepository();
    const now = new Date('2026-08-19T12:00:00.000Z');
    const cutoff = retentionCutoff(now, sweep!.days);
    await repo.writeAudit({ staffId: 's1', action: 'view_user_detail', target: 'u1', reason: 'Разбор жалобы' });
    const before = (await repo.listAudit(50)).entries.length;
    expect(before).toBeGreaterThan(0);
    // Nothing in this fresh repository is three years old.
    expect(await repo.pruneAuditLog(cutoff)).toBe(0);
    expect((await repo.listAudit(50)).entries.length).toBe(before);
    // Everything is, once the cutoff moves past today.
    expect(await repo.pruneAuditLog(new Date(now.getTime() + 86_400_000).toISOString()))
      .toBe(before);
    expect((await repo.listAudit(50)).entries).toEqual([]);
  });

  it('is the `staff` capability, not `health`', async () => {
    // Being able to read health records is not the same as being able to read
    // the record of everyone reading them.
    const clinician = makeApp('clinician');
    expect((await clinician.inject({ method: 'GET', url: '/admin/security' })).statusCode).toBe(403);
    await clinician.close();
    await app.close();
  });

  it('bounds the window rather than trusting the query', async () => {
    const body = (await app.inject({ method: 'GET', url: '/admin/security?days=99999' })).json();
    expect(body.windowDays).toBeLessThanOrEqual(365);
    await app.close();
  });
});

describe('the window is asked of the database, not of the newest few thousand rows', () => {
  /**
   * The regulator's question, and the answer this page used to give.
   *
   * It fetched the newest 5 000 rows of the WHOLE log and filtered them here
   * against a window of up to a year. audit_log is dominated by ordinary
   * traffic — `list_users` and `view_support` on every open, the throttled
   * emergency feed from every open tab — so 5 000 rows is days. Ask for twelve
   * months and the page answered «Защищённых просмотров: 0» over last week,
   * with nothing on screen to say the query had never looked further.
   *
   * One protected read, buried under more ordinary rows than the old slice
   * could hold. Every row is written at the same instant, so nothing here
   * depends on a clock: the ONLY reason to miss the read is slicing the log by
   * row count before filtering it.
   */
  it('finds a protected read buried under more traffic than the old slice held', async () => {
    const repo = createMemoryRepository();
    await repo.writeAudit({
      staffId: 's1', action: 'view_wellness', target: 'u1', reason: 'Разбор жалобы',
    });
    for (let i = 0; i < 5200; i++) {
      await repo.writeAudit({ staffId: 's1', action: 'list_users' });
    }

    const server = buildServer(
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
        authAdmin: async () => ({ staffId: 's1', role: 'owner' as const }),
      },
      { logger: false },
    );

    const body = (await server.inject({ method: 'GET', url: '/admin/security?days=365' })).json();
    expect(body.protectedReads, 'a year was asked for and only the newest rows were read').toBe(1);
    expect(body.health).toBe(1);
    // And she is named, which is what the page is for.
    expect(body.recent[0].action).toBe('view_wellness');
    expect(body.recent[0].reason).toBe('Разбор жалобы');
    await server.close();
  });

  it('says so on the answer when the count stopped at the row cap', async () => {
    // Even a filtered query has a ceiling. What must never happen is the
    // ceiling being hit silently — that is the original bug with a smaller
    // number. `hasMore` came back from the repository before this fix too, and
    // was discarded at the call site.
    const repo = createMemoryRepository();
    const capped = {
      ...repo,
      listProtectedAudit: async () => ({
        entries: [{
          staffId: 's1', staffName: 'Ерен', staffPhone: null, action: 'view_wellness',
          target: 'u1', targetName: 'Айгерім', reason: 'Разбор жалобы',
          at: new Date().toISOString(),
        }],
        hasMore: true,
      }),
    } as unknown as ReturnType<typeof createMemoryRepository>;

    const server = buildServer(
      {
        repo: capped,
        guardrail: { callLLM: async () => 'ok' },
        ingest: {
          cacheLocation: async () => {}, resolveTransition: async () => null,
          sendEmergencyPush: async () => {}, sendGeofencePush: async () => {},
        },
        cacheLastLocation: async () => null,
        setBpCalibration: async () => {},
        authUser: async () => ({ userId: DEMO_USER }),
        authAdmin: async () => ({ staffId: 's1', role: 'owner' as const }),
      },
      { logger: false },
    );

    const body = (await server.inject({ method: 'GET', url: '/admin/security?days=365' })).json();
    expect(body.truncated, 'a partial count was reported as a total').toBe(true);
    expect(body.rowCap).toBeGreaterThan(0);
    await server.close();
  });

  it("the owner's «что горит» sees an unexplained read behind the same traffic", async () => {
    // Same defect, second call site: the signal was fed the newest 2 000 rows
    // of the whole log filtered to 30 days. It only fires above zero, so a
    // count that cannot rise is a permanently reassuring blank on the one card
    // the owner actually reads.
    const repo = createMemoryRepository();
    // A protected read with no reason at all — the row this signal exists for.
    await repo.writeAudit({ staffId: 's1', action: 'view_wellness', target: 'u1' });
    for (let i = 0; i < 2200; i++) {
      await repo.writeAudit({ staffId: 's1', action: 'list_users' });
    }

    const server = buildServer(
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
        authAdmin: async () => ({ staffId: 's1', role: 'owner' as const }),
      },
      { logger: false },
    );

    const body = (await server.inject({ method: 'GET', url: '/admin/owner' })).json();
    const fire = (body.burning as Array<{ key: string; count: number }>)
      .find((b) => b.key === 'access_without_reason');
    expect(fire, 'an unexplained read of a health record did not reach «что горит»').toBeDefined();
    expect(fire!.count).toBe(1);
    await server.close();
  });

  it('a whole slice is not labelled incomplete', async () => {
    // The flag has to mean something. Always-true is as useless as always-false.
    const body = (await app.inject({ method: 'GET', url: '/admin/security?days=365' })).json();
    expect(body.truncated).toBe(false);
    await app.close();
  });
});
