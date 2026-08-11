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
import { randomBytes, createHash } from 'node:crypto';
import { buildServer, redactPathIds } from '../server';
import { createMemoryRepository } from '../db/memoryRepository';

/// Drive the REAL logger and read the bytes it wrote.
///
/// Every test below this used to call redactPathIds directly, which is why two
/// live leaks survived a green suite: Fastify's built-in 404 handler logs the
/// URL inside a message STRING that no serializer touches, and the path rules
/// were case-sensitive. Neither is visible from the pure function. This injects
/// a capturing destination into buildServer and asserts on the stream.
async function captureLog(
  requests: ReadonlyArray<{ method: 'GET' | 'POST' | 'DELETE'; url: string }>,
): Promise<string> {
  const lines: string[] = [];
  const app = buildServer(
    {
      repo: createMemoryRepository(),
      guardrail: { callLLM: async () => 'ok' },
      ingest: {
        cacheLocation: async () => {},
        resolveTransition: async () => null,
        sendEmergencyPush: async () => {},
        sendGeofencePush: async () => {},
      },
      cacheLastLocation: async () => null,
      setBpCalibration: async () => {},
      authUser: async () => null,
      authAdmin: async () => null,
    },
    { logStream: { write: (msg: string) => void lines.push(msg) } },
  );
  try {
    for (const r of requests) await app.inject(r);
  } finally {
    await app.close();
  }
  return lines.join('');
}

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

  it('drops the family invite token, which IS the grant', () => {
    // Shaped exactly as routes/crud.ts mints it: base64url of randomBytes(32).
    // No dashes and no query string, so neither the uuid rule nor the query
    // rule ever touched it — and for 24 hours it opens a child's live location
    // and day trail for anyone holding it.
    const token = randomBytes(32).toString('base64url');
    const out = redactPathIds(`/join/${token}`);
    expect(out).not.toContain(token);
    expect(out).toBe('/join/:token');
  });

  it('drops the invite token even when the link carries a query string', () => {
    const token = randomBytes(32).toString('base64url');
    const out = redactPathIds(`/join/${token}?src=whatsapp`);
    expect(out).not.toContain(token);
    expect(out).toBe('/join/:token?…');
  });

  it('drops the invite hash a revoke names, but keeps the accept route', () => {
    const hash = createHash('sha256').update(randomBytes(32)).digest('hex');
    const out = redactPathIds(`/family/invites/${hash}`);
    expect(out).not.toContain(hash);
    expect(out).toBe('/family/invites/:tokenHash');
    // `accept` is a literal segment, not a hash — the shape stays debuggable.
    expect(redactPathIds('/family/invites/accept')).toBe('/family/invites/accept');
  });

  it('drops the customer phone from an entitlement revoke, keeping the feature', () => {
    const out = redactPathIds('/admin/entitlements/course/+77015551234');
    expect(out).not.toContain('7701');
    expect(out).toBe('/admin/entitlements/course/:phone');
    // Normalised digits are the same phone number.
    expect(redactPathIds('/admin/entitlements/course/77015551234')).toBe(
      '/admin/entitlements/course/:phone',
    );
    // The list route names no one and is left alone.
    expect(redactPathIds('/admin/entitlements')).toBe('/admin/entitlements');
  });

  it('drops a device serial, which resolves to a named customer', () => {
    // device_registry stores activated_by_phone beside the serial.
    const out = redactPathIds('/admin/device-registry/A4C138F0B1E2/status');
    expect(out).not.toContain('A4C138F0B1E2');
    expect(out).toBe('/admin/device-registry/:serial/status');
    expect(redactPathIds('/admin/device-registry')).toBe('/admin/device-registry');
  });

  it('keeps the route shape, which is what debugging needs', () => {
    expect(redactPathIds('/ingest/batch')).toBe('/ingest/batch');
    expect(redactPathIds('/admin/bi')).toBe('/admin/bi');
    expect(redactPathIds('/health')).toBe('/health');
    // Content paths whose last segment is a week or a track, not a person.
    expect(redactPathIds('/pregnancy/weeks/32')).toBe('/pregnancy/weeks/32');
    expect(redactPathIds('/audio/lullaby/1/ru')).toBe('/audio/lullaby/1/ru');
  });

  it('leaves a stage key alone — it identifies content, not a person', () => {
    expect(redactPathIds('/admin/content/w20')).toBe('/admin/content/w20');
  });

  it('is case-insensitive about hex', () => {
    expect(redactPathIds('/children/AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE/location')).toBe(
      '/children/:id/location',
    );
  });

  it('redacts a path whose case does not match the route', () => {
    // Nothing lowercases an incoming URL before it is logged, and every rule
    // is anchored — so /JOIN/<token> matched nothing and printed in full.
    const token = randomBytes(32).toString('base64url');
    expect(redactPathIds(`/JOIN/${token}`)).not.toContain(token);
    expect(redactPathIds('/Admin/Device-Registry/A4C138F0B1E2')).toBe(
      '/admin/device-registry/:serial',
    );
    expect(redactPathIds('/Family/Invites/' + 'a'.repeat(64))).toBe('/family/invites/:tokenHash');
  });

  it('redacts a near miss — a trailing slash still resolves to no route', () => {
    // Caddy passes `/join/<token>/` through unnormalised, so this reaches us.
    const token = randomBytes(32).toString('base64url');
    expect(redactPathIds(`/join/${token}/`)).not.toContain(token);
  });
});

describe('what the logger actually writes', () => {
  it('never writes an invitation token, even for a URL that matches no route', async () => {
    // One trailing slash: the serializer line was already correct, and
    // Fastify's 404 message string beside it carried the live token.
    const token = randomBytes(32).toString('base64url');
    const out = await captureLog([{ method: 'GET', url: `/join/${token}/` }]);
    expect(out).not.toContain(token);
    expect(out).toContain('/join/:token');
    expect(out).toContain('not found');
  });

  it('never writes an invitation token for a case-variant path', async () => {
    const token = randomBytes(32).toString('base64url');
    const out = await captureLog([{ method: 'GET', url: `/JOIN/${token}` }]);
    expect(out).not.toContain(token);
  });

  it('never writes a customer phone when the verb is wrong for the route', async () => {
    // The route is DELETE; a GET falls through to the 404 handler.
    const out = await captureLog([
      { method: 'GET', url: '/admin/entitlements/course/+77019998877' },
    ]);
    expect(out).not.toContain('77019998877');
    expect(out).toContain('/admin/entitlements/course/:phone');
  });

  it('never writes a child id, matched route or not', async () => {
    const id = '33333333-3333-3333-3333-333333333333';
    const out = await captureLog([
      { method: 'GET', url: `/children/${id}/location` },
      { method: 'GET', url: `/children/${id}/no-such-thing` },
    ]);
    expect(out).not.toContain(id);
    expect(out).toContain('/children/:id/location');
  });

  it('still logs the route shape, which is what debugging needs', async () => {
    const out = await captureLog([{ method: 'GET', url: '/health' }]);
    expect(out).toContain('incoming request');
    expect(out).toContain('/health');
  });
});
