/**
 * An id we do not have is not a server fault.
 *
 * Every ownership check compares a CLIENT-SUPPLIED id against a UUID column.
 * Postgres parses the parameter before comparing anything, so a non-UUID id
 * raises 22P02 rather than returning no rows — and nothing caught it. The
 * answer to "may I see this child's location" was a 500.
 *
 * Found by signing the app into production and reading the log: the app
 * creates children locally during onboarding with ids like `child-1` and polls
 * their location every few seconds, so one fresh install is a 500 generator.
 * It is reachable by anybody: any string in the path does it.
 *
 * These run against the in-memory repository, which cannot reproduce the
 * Postgres parse error — so the guard itself is asserted directly against the
 * pg implementation, with a pool that FAILS if a query is ever attempted. A
 * query that never runs cannot throw.
 */

import { describe, it, expect } from 'vitest';
import type { Pool } from 'pg';
import { createPgRepository } from '../db/pgRepository';

/** A pool that refuses to be used. Reaching it is the failure. */
const forbiddenPool = {
  query: () => {
    throw new Error('the database was queried with an id that cannot be a UUID');
  },
} as unknown as Pool;

const repo = createPgRepository(forbiddenPool);

const MALFORMED = [
  'child-1', // what our own onboarding creates
  '', // an empty path segment
  'null',
  '1; DROP TABLE children',
  '../../etc/passwd',
  '11111111-1111-1111-1111', // a truncated UUID
  '11111111-1111-1111-1111-11111111111g', // one bad character
];

describe('ownership lookups with an id that cannot exist', () => {
  for (const id of MALFORMED) {
    it(`answers "not ours" for ${JSON.stringify(id)} without touching the database`, async () => {
      // Every one of these gates a route: a throw here is a 500 on
      // /children/:id/location, /devices/:id, /geofences/:id and the rest.
      expect(await repo.childOwner(id)).toBeNull();
      expect(await repo.deviceOwner(id)).toBeNull();
      expect(await repo.geofenceOwner(id)).toBeNull();
      expect(await repo.appointmentOwner(id)).toBeNull();
      expect(await repo.medicationOwner(id)).toBeNull();
    });
  }

  it('still asks the database about a well-formed id', async () => {
    // The guard must not swallow real lookups — if it did, every ownership
    // check would answer "not yours" and the whole app would 403.
    await expect(repo.childOwner('11111111-2222-3333-4444-555555555555'))
      .rejects.toThrow(/database was queried/);
  });

  it('accepts a UUID in either case', async () => {
    await expect(repo.childOwner('AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE'))
      .rejects.toThrow(/database was queried/);
  });
});
