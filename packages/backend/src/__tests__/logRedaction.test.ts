/**
 * Access logs must not become a second, less controlled audit trail.
 *
 * Request logging is pino's default, which records neither headers nor bodies
 * — so no readings, names, phone numbers or chat messages reach it. It did
 * record the URL verbatim, and these URLs carry identifiers:
 * `/admin/users/{uuid}/health` states which staff member opened which
 * patient's record.
 *
 * That question has a deliberate home already — the audit log, written on
 * purpose and behind admin auth. Access logs are the thing most likely to be
 * shipped wholesale to a third-party aggregator, so the same fact there sits
 * somewhere with weaker controls and no retention policy.
 */

import { describe, it, expect } from 'vitest';
import { redactPathIds } from '../server';

describe('what reaches the request log', () => {
  it('drops the user id from a health drilldown', () => {
    expect(redactPathIds('/admin/users/11111111-1111-1111-1111-111111111111/health')).toBe(
      '/admin/users/:id/health',
    );
  });

  it('drops the child id from a location lookup', () => {
    expect(redactPathIds('/children/33333333-3333-3333-3333-333333333333/location')).toBe(
      '/children/:id/location',
    );
  });

  it('drops every id when a path carries more than one', () => {
    const out = redactPathIds(
      '/children/33333333-3333-3333-3333-333333333333/geofences/44444444-4444-4444-4444-444444444444',
    );
    expect(out).toBe('/children/:id/geofences/:id');
    expect(out).not.toMatch(/[0-9a-f]{8}-/i);
  });

  it('drops a search query, which carries a name or a phone number', () => {
    // The back-office user search puts whatever was typed in ?q=.
    const out = redactPathIds('/admin/users?q=Айгерим&limit=25');
    expect(out).not.toContain('Айгерим');
    expect(out).toBe('/admin/users?…');
  });

  it('keeps the route shape, which is what debugging needs', () => {
    expect(redactPathIds('/ingest/batch')).toBe('/ingest/batch');
    expect(redactPathIds('/admin/bi')).toBe('/admin/bi');
    expect(redactPathIds('/health')).toBe('/health');
  });

  it('leaves a stage key alone — it identifies content, not a person', () => {
    expect(redactPathIds('/admin/content/w20')).toBe('/admin/content/w20');
  });

  it('is case-insensitive about hex', () => {
    expect(redactPathIds('/children/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/location')).toBe(
      '/children/:id/location',
    );
  });
});
