/**
 * Every back-office route that can reach a family's data must leave a trace.
 *
 * The audit call is written by hand in each handler, so forgetting one is free
 * and invisible: the route works, the data is served, and nothing records who
 * looked. That is how /admin/devices came to be unaudited while
 * /admin/users/:id/detail was — the same names, reached a different way.
 *
 * This reads the routes out of the source rather than checking a list of them,
 * so a NEW route is failed by default. Adding one forces a decision: audit it,
 * or declare here why it does not need to be.
 */

import { describe, it, expect } from 'vitest';
import { adminRoutes, adminSource } from './helpers/adminRoutes.js';

/**
 * Routes that serve ONLY aggregates — counts, rates, series — and name nobody.
 *
 * Deliberately short, and each entry has to be true of the response body, not
 * merely of its name. Auditing these would bury the entries that matter: the
 * dashboard polls them, so every refresh would write rows nobody will read,
 * and the log people actually search would fill with noise.
 */
const AGGREGATES_ONLY = new Set([
  'GET /admin/stats', // active users, devices online, alerts today — counts
  'GET /admin/analytics', // totals and content coverage
  'GET /admin/bi', // DAU/WAU/MAU, retention, engagement — all counts
  'GET /admin/content', // the published catalogue; about content, not people
  // What is waiting on a clinician: stage keys, card ids and titles. The same
  // catalogue as above, filtered — it names staff at most, and only the
  // reviewer whose own signature is on the card.
  'GET /admin/content/review-queue',
  'GET /admin/audit', // the log itself; admin-only, and auditing reads of the
  // audit log makes the log describe mostly itself
  'GET /admin/shop/variants', // product inventory (colours + stock) — names nobody
  // The product catalogue: names, stages, age bands, prices. About what is on
  // the shelf, not about who bought it — no customer, child or order reaches
  // the response. Auditing it would write a row every time the tab is opened
  // and bury the entries this log exists for. WRITES are audited
  // (product_update / category_upsert / category_delete), because «кто поменял
  // этап» has to have an answer.
  'GET /admin/shop/products',
  // Which outside services are wired. About the server's own plumbing — no
  // customer, child or order. It returns NO secret either: a stored key comes
  // back as ••••7f2a, so there is nothing here whose reading needs recording.
  // /admin/settings, which does return the real values, stays audited.
  'GET /admin/integrations',
  'GET /admin/audio', // which calendar days have a clip — content coverage, names nobody
  // The two reads about the back office itself rather than about a family.
  // Neither touches PHI, and both are polled: /admin/me runs on every page
  // load, so auditing it would write a row per refresh and bury the entries
  // this log exists for.
  'GET /admin/me', // who am I — the caller reading their own name
  'GET /admin/staff', // the colleague roster; admin-only, contains no patient
  // The permission matrix. ROLE_CAPS and nothing else — no customer, no
  // patient, no order. Auditing it would record who read a table of rules.
  'GET /admin/roles',
  // The owner's dashboard. Reads orders to total them and emits sums, product
  // names and counts — no customer reaches the response. The same category as
  // /admin/dashboard, which it is built from.
  'GET /admin/owner',
  // Published reference data — the MOH antenatal protocol, the vaccination
  // schedule, the pregnancy and child-development calendars. Constants
  // compiled into the server; they name nobody and never change per request.
  'GET /admin/reference/:kind',
  // Stock levels and the movement ledger. About goods on a shelf, not about a
  // family — and the ledger already records who moved what, so auditing a READ
  // of it would only record who looked at the record of who looked.
  'GET /admin/inventory',
  'GET /admin/inventory/moves',
  // Suppliers and purchase orders (frames 07a / 07g). About a company that
  // ships us boxes and about goods on the water — no mother, child, phone or
  // address reaches either response. Both are the landing render of the
  // warehouse screen and are re-fetched after every receipt, so auditing them
  // would write several rows per delivery and bury the ones that matter. The
  // WRITES next door ARE audited — supplier_add / supplier_update / po_draft /
  // po_place / po_cancel — because a purchase order commits the business's
  // money and «кто это заказал» must have an answer.
  'GET /admin/suppliers',
  'GET /admin/purchase-orders',
  // The course catalogue as the panel edits it — lesson titles and YouTube
  // links. Content, not people.
  'GET /admin/course/lessons',
  // The business snapshot behind the Dashboard: counts of users, children,
  // devices and cities, plus shop totals. Every field is an aggregate — no row
  // here identifies anybody — and it is the panel's landing screen, so
  // auditing it would write a row every time somebody opens the back office.
  'GET /admin/dashboard',
  // The pregnancy calendar as it is served, plus each week's edit state and how
  // many mothers are standing in it. Content and counts: the head-count is a
  // GROUP BY over `users.due_date` and no row here identifies a mother. It is
  // also the landing render of the tab and re-fetched after every save, so
  // auditing it would write several rows per edit and bury the one that
  // matters. The WRITES next door are audited — `edit_pregnancy_week` and
  // `pregnancy_week_review` — because «кто поменял неделю 22» and «кто её
  // проверил» must both have an answer.
  'GET /admin/pregnancy/weeks',
  // The emergency-help scenarios as they are served, plus each one's edit
  // state (frame 16b). Content, and less than the calendar above: there is not
  // even a head-count, because nothing in this product records who opened
  // screen 37 and a number here would be invented. It is the landing render of
  // the tab and re-fetched after every save, so auditing it would write
  // several rows per edit and bury the one that matters. The WRITES next door
  // are audited — `edit_emergency_help` and `emergency_help_review` — because
  // «кто поменял инструкцию про ожог» and «кто её проверил» must both have an
  // answer.
  'GET /admin/emergency-help',
  // The рассылка list and its recipient counter. Both are about a MESSAGE and
  // a head-count — the list carries text somebody in this panel wrote, and the
  // preview answers «сколько получателей» with two integers. No customer,
  // child or phone number reaches either response, and the preview is polled
  // on every change of the audience select, so auditing it would write a row
  // per keystroke and bury the entry that matters. The three writes next door
  // ARE audited — broadcast_create / broadcast_edit / broadcast_publish —
  // because «кто отправил это сорока мамам» must have an answer.
  'GET /admin/broadcasts',
  'GET /admin/broadcasts/:id/preview',
  // Frame 15's four reads. Each was checked against what it actually returns,
  // not against its name — «log» in particular sounds like it should be here
  // for the opposite reason.
  //
  //   /schedule — the served national calendar. A constant the server compiles
  //     in, identical for every caller; the same category as
  //     /admin/reference/:kind above.
  //   /coverage — percentages and denominators out of vaccinationCoverageOf().
  //     Note this figure is «охват по отметкам мам», never clinic truth — but
  //     that is an honesty question, not an audit one. No row identifies a
  //     child.
  //   /impact — «скольких детей затронет это изменение»: one integer, computed
  //     before a schedule edit is saved. It is polled as the editor is typed
  //     in, so auditing it would write a row per keystroke.
  //   /log — the append-only history of edits TO THE CALENDAR, with the before
  //     and after text. It names STAFF, and only the one whose own signature
  //     is on the change. Auditing reads of a change log makes the log
  //     describe mostly itself, which is why /admin/audit is already here.
  //
  // The writes next door ARE audited — `edit_vaccination_settings` and the
  // PUT/review pair on /schedule/:id/:dose — because «кто передвинул прививку»
  // must have an answer.
  'GET /admin/vaccination/schedule',
  'GET /admin/vaccination/coverage',
  'GET /admin/vaccination/impact',
  'GET /admin/vaccination/log',
  // Frame 17c. GROUP BY over `cry_results` and one settings row: counts per
  // reason, average confidence, how many mothers said the answer was right.
  // No cry row of any individual family reaches the response — that is a rule
  // of the route, not an accident of its shape — and it is the landing render
  // of the tab, re-fetched after every threshold change, so auditing it would
  // write several rows per edit and bury the one that matters. The write next
  // door IS audited (`edit_cry_threshold`), because «кто поднял порог до 70 %»
  // changes what every phone says and must have an answer.
  'GET /admin/cry',
  // Кадр 25. Counts of pushes by KIND, and counts of how many mothers switched
  // each category off. Deliberately no identity of any sort reaches the
  // response — that is asserted in notificationGate.test.ts, which checks the
  // serialized body contains no user id — so there is no read here whose
  // recording would tell anybody anything. Auditing it would write a row every
  // time somebody opens the tab to check whether last night's рассылка went
  // out, and bury the entries this log exists for.
  'GET /admin/notifications',
]);

// Shared with adminAuthorization.test.ts. Two copies of this parser would be
// two answers to "which routes exist", and a route could then be checked by
// one guard while being invisible to the other.
const routes = adminRoutes;

describe('back-office audit coverage', () => {
  it('found the routes to check', () => {
    // Without this the checks below would pass vacuously if the regex ever
    // stopped matching — the failure mode of every source-reading guard.
    const found = routes();
    expect(found.length).toBeGreaterThan(8);
    expect(found.some((r) => r.path === '/admin/users/:id/detail')).toBe(true);
  });

  it('every route that can reach a family is audited', () => {
    const unaudited = routes()
      .filter((r) => !r.body.includes('writeAudit'))
      .map((r) => `${r.method} ${r.path}`)
      .filter((k) => !AGGREGATES_ONLY.has(k));
    expect(
      unaudited,
      `these serve or change data and record nobody: ${unaudited.join(', ')}. ` +
        'Add repo.writeAudit, or add it to AGGREGATES_ONLY if it truly names nobody.',
    ).toEqual([]);
  });

  it('every write is audited, with no exemption available', () => {
    // A read that names nobody can reasonably go unrecorded. A write cannot:
    // it changes what every user sees, including what is offered for sale.
    const writes = routes().filter((r) => r.method !== 'GET');
    expect(writes.length).toBeGreaterThan(0);
    const silent = writes
      .filter((r) => !r.body.includes('writeAudit'))
      .map((r) => `${r.method} ${r.path}`);
    expect(silent, `unaudited writes: ${silent.join(', ')}`).toEqual([]);
  });

  it('the exemption list does not name routes that no longer exist', () => {
    // A stale exemption is an exemption nobody reviewed. If a route is renamed,
    // the old entry would sit here quietly excusing something that is gone —
    // and the renamed route would be caught, which is the point.
    const live = new Set(routes().map((r) => `${r.method} ${r.path}`));
    const stale = [...AGGREGATES_ONLY].filter((k) => !live.has(k));
    expect(stale, `AGGREGATES_ONLY names routes that do not exist: ${stale.join(', ')}`).toEqual([]);
  });

  it('audit actions are distinct per route', () => {
    // Two routes logging the same action makes the log ambiguous about what was
    // actually opened.
    const actions = [...adminSource().matchAll(/action:\s*'([a-z_]+)'/g)].map((m) => m[1]);
    expect(actions.length).toBeGreaterThan(5);
    expect(new Set(actions).size).toBe(actions.length);
  });
});
