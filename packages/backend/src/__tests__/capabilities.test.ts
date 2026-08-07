/**
 * Who may do what.
 *
 * The panel had three roles and one real check — "are you admin?". The spec
 * describes five, and the two it adds are the ones that bound exposure: a
 * SELLER must not see margin or anybody's children, and a WAREHOUSE hand has
 * no business in a health record at all.
 *
 * The matrix is data, so it is tested as data rather than through 68 routes.
 */

import { describe, it, expect } from 'vitest';
import { can, capsOf, isStaffRole, ROLE_CAPS, STAFF_ROLES } from '../auth/capabilities';

describe('the two roles the spec adds', () => {
  it('a seller sees orders, contacts and stock', () => {
    for (const cap of ['orders', 'customers', 'stock'] as const) {
      expect(can('seller', cap), cap).toBe(true);
    }
  });

  it('a seller never sees margin', () => {
    // «без маржи». Cost and revenue are the owner's, and a seller who can read
    // them can price against us.
    expect(can('seller', 'finance')).toBe(false);
  });

  it('a seller never sees anybody\'s children', () => {
    // «без детей». This is the one that matters: a shop assistant does not get
    // a live map of a customer's child.
    expect(can('seller', 'health')).toBe(false);
  });

  it('a warehouse hand gets stock and nothing else', () => {
    expect(capsOf('warehouse')).toEqual(['stock']);
  });

  it('a content editor gets content and nothing else', () => {
    // «описания товаров без цен» — copy, not pricing.
    expect(capsOf('content')).toEqual(['content']);
    expect(can('content', 'finance')).toBe(false);
  });
});

describe('the roles that already exist keep working', () => {
  it('admin still has everything', () => {
    // Every real owner account carries `admin`. Migrating the live staff table
    // on deploy is how somebody loses access at the moment they need it.
    for (const cap of ROLE_CAPS.owner) expect(can('admin', cap), cap).toBe(true);
  });

  it('support has what it always did, and no more', () => {
    expect(capsOf('support')).toEqual(['orders', 'customers', 'emergencies']);
    expect(can('support', 'finance')).toBe(false);
    expect(can('support', 'staff')).toBe(false);
  });

  it('a clinician reads the medical side, never the money', () => {
    expect(can('clinician', 'health')).toBe(true);
    expect(can('clinician', 'finance')).toBe(false);
    expect(can('clinician', 'stock')).toBe(false);
  });
});

describe('failing closed', () => {
  it('an unknown role can do nothing at all', () => {
    // A typo in a role column must never read as permission. Staff seeing an
    // empty panel go and ask somebody, which is the right outcome.
    expect(can('superuser', 'orders')).toBe(false);
    expect(can('', 'orders')).toBe(false);
    expect(capsOf('nonsense')).toEqual([]);
  });

  it('rejects a role it does not know', () => {
    expect(isStaffRole('owner')).toBe(true);
    expect(isStaffRole('root')).toBe(false);
    expect(isStaffRole(undefined)).toBe(false);
  });
});

describe('the matrix itself', () => {
  it('every role is mapped — a missing entry would fail open or crash', () => {
    for (const r of STAFF_ROLES) expect(ROLE_CAPS[r], r).toBeDefined();
  });

  it('only the owner may manage staff', () => {
    const withStaff = STAFF_ROLES.filter((r) => can(r, 'staff'));
    expect(withStaff.sort()).toEqual(['admin', 'owner']);
  });

  it('health is reachable by exactly the roles that should have it', () => {
    // The list somebody will check after a support call. Kept explicit so
    // adding a role cannot quietly widen it.
    expect(STAFF_ROLES.filter((r) => can(r, 'health')).sort())
      .toEqual(['admin', 'clinician', 'owner']);
  });
});
