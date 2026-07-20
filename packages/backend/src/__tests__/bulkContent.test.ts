/**
 * Bulk catalogue import.
 *
 * Authoring 101 stages one at a time is the bottleneck in filling this
 * catalogue, so a whole file lands in one request. Two things matter more than
 * throughput: a bad file must change NOTHING, and a file covering ten stages
 * must not silently wipe the other ninety-one.
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import Fastify from 'fastify';
import { registerAdminRoutes } from '../routes/admin';
import type { Repository, ContentItemRow } from '../db/repository';

const lesson = (id: string): ContentItemRow => ({
  id,
  kind: 'lesson',
  title: { ru: 'Урок' },
  summary: { ru: 'Описание' },
});

function makeRepo() {
  const catalog: Record<string, ContentItemRow[]> = {};
  const audit: Array<{ action: string; target: string | null }> = [];

  const repo = {
    contentCatalog: async () => JSON.parse(JSON.stringify(catalog)),
    putStageContent: async (stage: string, items: ContentItemRow[]) => {
      if (items.length === 0) delete catalog[stage];
      else catalog[stage] = items;
    },
    writeAudit: async (e: { action: string; target?: string | null }) =>
      void audit.push({ action: e.action, target: e.target ?? null }),
  } as unknown as Repository;

  return { repo, catalog, audit };
}

function makeApp() {
  const { repo, catalog, audit } = makeRepo();
  const app: FastifyInstance = Fastify({ logger: false });
  registerAdminRoutes(app, repo, async () => ({ staffId: 's1', role: 'admin' }));
  return { app, catalog, audit };
}

describe('PUT /admin/content (bulk)', () => {
  let app: FastifyInstance;
  let catalog: Record<string, ContentItemRow[]>;
  let audit: Array<{ action: string; target: string | null }>;

  beforeEach(async () => {
    ({ app, catalog, audit } = makeApp());
    await app.ready();
  });

  const put = (payload: unknown) =>
    app.inject({ method: 'PUT', url: '/admin/content', payload: payload as never });

  it('writes every stage in the file', async () => {
    const r = await put({ stages: { w1: [lesson('a')], m0: [lesson('b'), lesson('c')] } });
    expect(r.statusCode).toBe(200);
    expect(r.json()).toMatchObject({ stagesWritten: 2, items: 3, mode: 'merge' });
    expect(catalog.w1).toHaveLength(1);
    expect(catalog.m0).toHaveLength(2);
  });

  it('leaves stages the file does not mention alone', async () => {
    // A file covering ten stages must not wipe the other ninety-one.
    await put({ stages: { w1: [lesson('a')] } });
    await put({ stages: { w2: [lesson('b')] } });
    expect(catalog.w1).toHaveLength(1);
    expect(catalog.w2).toHaveLength(1);
  });

  it('clears the rest only when replace is asked for by name', async () => {
    await put({ stages: { w1: [lesson('a')], w2: [lesson('b')] } });
    const r = await put({ stages: { w1: [lesson('a2')] }, mode: 'replace' });
    expect(r.json().stagesCleared).toBe(1);
    expect(catalog.w1).toHaveLength(1);
    expect(catalog.w2).toBeUndefined();
  });

  it('rejects an unknown stage key and writes NOTHING', async () => {
    // All-or-nothing: a partial apply across a hundred stages leaves the
    // catalogue in a state nobody can reason about, and the importer cannot
    // tell how far it got.
    const r = await put({ stages: { w1: [lesson('a')], w99: [lesson('b')] } });
    expect(r.statusCode).toBe(400);
    expect(r.json().error).toContain('w99');
    expect(catalog.w1).toBeUndefined();
  });

  it('rejects a duplicate id and writes NOTHING', async () => {
    const r = await put({ stages: { w1: [lesson('dup'), lesson('dup')] } });
    expect(r.statusCode).toBe(400);
    expect(r.json().error).toContain('dup');
    expect(Object.keys(catalog)).toHaveLength(0);
  });

  it('names the offending stage so a hundred-stage file is debuggable', async () => {
    const r = await put({ stages: { w1: [lesson('a')], m5: [lesson('x'), lesson('x')] } });
    expect(r.json().error).toContain('m5');
  });

  it('a malformed item rejects the file rather than being dropped', async () => {
    const r = await put({ stages: { w1: [{ id: 'a', kind: 'not-a-kind' }] } });
    expect(r.statusCode).toBe(400);
    expect(Object.keys(catalog)).toHaveLength(0);
  });

  it('records who imported what', async () => {
    await put({ stages: { w1: [lesson('a')] } });
    expect(audit.at(-1)).toMatchObject({ action: 'bulk_import_content' });
    expect(audit.at(-1)!.target).toContain('merge');
  });

  it('takes a whole 101-stage catalogue in one request', async () => {
    const stages: Record<string, ContentItemRow[]> = {};
    for (let w = 1; w <= 40; w++) stages[`w${w}`] = [lesson(`w${w}-1`)];
    for (let m = 0; m <= 60; m++) stages[`m${m}`] = [lesson(`m${m}-1`)];
    const r = await put({ stages });
    expect(r.statusCode).toBe(200);
    expect(r.json().stagesWritten).toBe(101);
    expect(Object.keys(catalog)).toHaveLength(101);
  });

  it('is refused for a non-admin, before the catalogue is touched', async () => {
    // Support staff can read the back-office but must not rewrite what a
    // hundred thousand phones will show.
    const { repo, catalog: theirs } = makeRepo();
    const staffApp: FastifyInstance = Fastify({ logger: false });
    registerAdminRoutes(staffApp, repo, async () => ({ staffId: 's2', role: 'support' }));
    await staffApp.ready();

    const r = await staffApp.inject({
      method: 'PUT',
      url: '/admin/content',
      payload: { stages: { w1: [lesson('a')] } } as never,
    });
    expect(r.statusCode).toBe(403);
    expect(Object.keys(theirs)).toHaveLength(0);
    await staffApp.close();
  });
});
