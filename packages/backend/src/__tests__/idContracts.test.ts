/**
 * Does each client-supplied id match the column it lands in?
 *
 * Every route that takes an id from the app writes it into a specific column,
 * and that column is either UUID or TEXT. Get the pairing wrong in either
 * direction and it fails in production, on one endpoint, silently:
 *
 *   - a zod schema LOOSER than a UUID column lets a bad id through to
 *     Postgres, which raises 22P02 and answers 500. Registering a band did
 *     exactly this: the id is the MAC printed on the hardware and the column
 *     was UUID, so pairing a tracker — the thing the hardware is sold for —
 *     could not reach the server at all;
 *   - a schema STRICTER than a TEXT column refuses ids that would have been
 *     perfectly storable, with a 400 the fire-and-forget push never surfaces.
 *     Onboarding's 'child-1' was the other side of the same coin.
 *
 * Neither shows up in a unit test, because each half is correct on its own.
 * So the pairing itself is written down here, and the test fails if the schema
 * and the validator stop agreeing.
 *
 * This reads the FILES, so it needs no database — the same trade pgSchema.test
 * makes, and it catches the same class of thing before a deploy rather than
 * after one.
 */

import { describe, it, expect } from 'vitest';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../../', import.meta.url));
const schema = readFileSync(`${root}db/schema.sql`, 'utf8');
const routes = readFileSync(`${root}src/routes/crud.ts`, 'utf8');

/** The declared type of `table.column`, uppercased ('UUID' | 'TEXT' | …). */
function columnType(table: string, column: string): string | null {
  const create = new RegExp(
    `CREATE TABLE (?:IF NOT EXISTS )?${table}\\s*\\(([\\s\\S]*?)\\n\\);`, 'i');
  const body = schema.match(create)?.[1];
  if (!body) return null;
  for (const line of body.split('\n')) {
    const m = line.trim().match(/^(\w+)\s+(\w+)/);
    if (m && m[1].toLowerCase() === column.toLowerCase()) return m[2].toUpperCase();
  }
  return null;
}

/** Whether the named zod object requires its `id` to be a uuid. */
function requiresUuidId(schemaName: string): boolean {
  const m = routes.match(new RegExp(`const ${schemaName} = z\\.object\\(\\{([\\s\\S]*?)\\n\\}\\)`));
  if (!m) throw new Error(`no zod schema named ${schemaName} in crud.ts`);
  const idLine = m[1].split('\n').find((l) => /^\s*id:/.test(l));
  if (!idLine) throw new Error(`${schemaName} has no id field`);
  return /\.uuid\(\)/.test(idLine);
}

/**
 * What the app sends, where it is stored, and therefore what it must be.
 *
 * A row here is a decision, not a description: `devices.ble_mac` is TEXT
 * because the id is physical — a MAC or a serial that somebody reads off the
 * back of a tracker — and `children.id` is UUID because we mint it.
 */
const CONTRACTS: Array<{
  what: string;
  zod: string;
  table: string;
  column: string;
  why: string;
}> = [
  {
    what: 'a child',
    zod: 'childBody',
    table: 'children',
    column: 'id',
    why: 'the app mints it, and geofences reference it',
  },
  {
    what: 'a circle safe zone',
    zod: 'circleGeofence',
    table: 'geofences',
    column: 'id',
    why: 'the app mints it',
  },
  {
    what: 'a polygon safe zone',
    zod: 'polygonGeofence',
    table: 'geofences',
    column: 'id',
    why: 'the app mints it',
  },
  {
    what: 'a device',
    zod: 'deviceBody',
    table: 'devices',
    column: 'ble_mac',
    why: 'the id is PHYSICAL — the MAC printed on the hardware, never a UUID',
  },
  {
    what: 'an appointment',
    zod: 'appointmentBody',
    table: 'appointments',
    column: 'id',
    why: 'a client-local id, stored as text',
  },
  {
    what: 'a medication',
    zod: 'medicationBody',
    table: 'medications',
    column: 'id',
    why: 'a client-local id, stored as text',
  },
];

describe('a client-supplied id and the column it lands in', () => {
  it('found every schema and column it names', () => {
    // Without this the checks below pass vacuously the moment a rename lands.
    for (const c of CONTRACTS) {
      expect(columnType(c.table, c.column), `${c.table}.${c.column} is not in schema.sql`)
        .not.toBeNull();
      expect(() => requiresUuidId(c.zod)).not.toThrow();
    }
  });

  for (const c of CONTRACTS) {
    it(`${c.what}: ${c.zod}.id matches ${c.table}.${c.column}`, () => {
      const type = columnType(c.table, c.column)!;
      const validated = requiresUuidId(c.zod);

      if (type === 'UUID') {
        expect(validated,
          `${c.table}.${c.column} is UUID, so ${c.zod} must require .uuid() — ` +
          'otherwise a bad id reaches Postgres, raises 22P02 and answers 500')
          .toBe(true);
      } else {
        expect(validated,
          `${c.table}.${c.column} is ${type}, so ${c.zod} must NOT require .uuid() — ` +
          `${c.why}. A stricter validator refuses ids that would store perfectly, ` +
          'with a 400 the app never surfaces')
          .toBe(false);
      }
    });
  }
});
