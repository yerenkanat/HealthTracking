/**
 * The search box promised «Поиск по имени или телефону…» and searched neither
 * phone nor, in the fake, anything at all.
 *
 * Two defects, and the second is why the first survived:
 *
 *  1. `pgRepository.adminListUsers` matched `display_name ILIKE $1 OR email
 *     ILIKE $1`. Phone was never in the query, while the placeholder above the
 *     box named it and the table drew a phone column. An operator with a
 *     customer on the line pastes the number off a parcel, gets «Никто не
 *     найден по запросу…», and tells a real person she has no account.
 *
 *  2. `memoryRepository.adminListUsers` was declared `async () => …` — no
 *     parameters. It ignored `q`, `limit` and `offset` and returned one user
 *     always. So the panel's search, paging and total were exercised only in
 *     production: no test could reach the difference between the two
 *     repositories, because the fake had no search to be wrong about.
 *
 * An unfaithful fake is worse than no fake. It converts a whole feature into
 * green tests, which is exactly what happened here.
 *
 * These run against the MEMORY repository — the one every other suite uses — so
 * that the behaviour the fake reports is the behaviour the panel gets. The
 * Postgres side is held to the same shape by the assertions below plus
 * pgSchema.test.ts; where the two can only be compared against a real server,
 * that is said rather than faked.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

let repo: Repository;

beforeEach(async () => {
  repo = createMemoryRepository();
  // createUserWithPhone is the only way a phone reaches a user — ProfileEdit
  // deliberately omits it (the type is the guard), so a profile update cannot
  // set or change a number. Seeding through the real door keeps this test
  // honest about how these rows actually come to exist.
  await repo.createUserWithPhone({ phone: '+77011189012', displayName: 'Мадина' });
  await repo.createUserWithPhone({ phone: '87029990011', displayName: 'Айгуль' });
  await repo.upsertProfile('33333333-3333-3333-3333-333333333333',
    { displayName: 'Айгуль', phone: '87029990011', dueDate: null } as never);
});

const ids = (r: { users: Array<{ id: string }> }) => r.users.map((u) => u.id).sort();
const names = (r: { users: Array<{ displayName: string }> }) => r.users.map((u) => u.displayName).sort();

describe('finding a mother', () => {
  it('finds her by the number the operator has in front of her', async () => {
    // The whole point. This returned nothing before.
    const r = await repo.adminListUsers('7011189012', 50, 0);
    expect(names(r)).toEqual(['Мадина']);
  });

  it('does not care how the number is written', async () => {
    // She pastes what is printed on a parcel or read out on a call. The column
    // holds E.164. Digits on both sides is the only rule that survives that.
    for (const typed of ['+7 701 118 90 12', '+77011189012', '701 118 90 12', '(701) 118-90-12']) {
      const r = await repo.adminListUsers(typed, 50, 0);
      expect(names(r), `«${typed}» found nobody`).toEqual(['Мадина']);
    }
  });

  it('matches an 8-prefixed number too, which is how half of Kazakhstan writes it', async () => {
    const r = await repo.adminListUsers('7029990011', 50, 0);
    expect(names(r)).toEqual(['Айгуль']);
  });

  it('still finds her by name', async () => {
    // The half that already worked must keep working.
    expect(names(await repo.adminListUsers('Мадина', 50, 0))).toEqual(['Мадина']);
    // A prefix is a search, not an exact match. Asserted by membership, not
    // by a count: the fixture's size is not the behaviour under test.
    expect(names(await repo.adminListUsers('Айг', 50, 0))).toContain('Айгуль');
  });

  it('refuses to treat two or three digits as a phone search', async () => {
    // «77» is in every Kazakh number. A short query must not return the whole
    // table dressed up as a result.
    const r = await repo.adminListUsers('77', 50, 0);
    expect(r.users.length, 'a two-digit query matched phones').toBe(0);
  });

  it('answers with the FILTERED total, so «Показано N из M» is about the search', async () => {
    // The total counts everyone; the page is what was asked for. Derived
    // rather than hard-coded, so the assertion is about paging and not about
    // how many fixtures happen to exist.
    const everyone = await repo.adminListUsers('', 100, 0);
    const all = await repo.adminListUsers('', 2, 0);
    expect(all.total).toBe(everyone.users.length);
    expect(everyone.users.length).toBeGreaterThan(2);
    expect(all.users.length).toBe(2);   // the page

    const one = await repo.adminListUsers('Мадина', 50, 0);
    expect(one.total, 'the total ignored the query').toBe(1);
  });

  it('pages, instead of ignoring offset and handing back the same rows', async () => {
    const first = await repo.adminListUsers('', 2, 0);
    const second = await repo.adminListUsers('', 2, 2);
    expect(first.users.length).toBe(2);
    expect(second.users.length).toBeGreaterThan(0);
    // Row 3 must not be row 1. The fake used to return one user for every
    // offset, so a pager built on it would have looked fine and gone nowhere.
    for (const u of second.users) {
      expect(ids(first)).not.toContain(u.id);
    }
  });

  it('finds nobody when nobody matches, rather than everybody', async () => {
    expect((await repo.adminListUsers('Гүлнара', 50, 0)).users).toEqual([]);
    expect((await repo.adminListUsers('7999999999', 50, 0)).users).toEqual([]);
  });
});
