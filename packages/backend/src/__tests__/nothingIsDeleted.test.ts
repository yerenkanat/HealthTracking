/**
 * «Ничего не удаляется.»
 *
 * docs/CLAUDE-admin-design.md §6: «Товар с историей движений уходит в архив;
 * отменённый заказ — это статус; журнал действий не редактируется … Полное
 * удаление доступно только для сущностей без истории (неопубликованный урок,
 * черновик).»
 *
 * The course lesson was the one place the panel broke this, and it broke it in
 * the way that costs money: DELETE removed a published lesson from a course
 * customers paid 9 200 ₸ over the hardware for, and the progress table cascades
 * — so somebody's «6 из 12 пройдено» silently became 5 of 11, with nothing
 * anywhere recording that a lesson had ever existed.
 *
 * The panel's half of it was the repo's other standing defect: the delete was
 * fire-and-forget inside a `catch {}`, so a refusal redrew an unchanged list
 * and read as "nothing happened because there was nothing to do".
 */

import { describe, it, expect, beforeEach } from 'vitest';
import type { FastifyInstance } from 'fastify';
import { JSDOM, VirtualConsole } from 'jsdom';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, resolve } from 'node:path';
import { buildServer } from '../server';
import { createMemoryRepository, DEMO_USER } from '../db/memoryRepository';
import type { Repository } from '../db/repository';

const here = dirname(fileURLToPath(import.meta.url));
const PANEL = resolve(here, '../../../admin/index.html');

let app: FastifyInstance;
let repo: Repository;

beforeEach(() => {
  repo = createMemoryRepository();
  app = buildServer(
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
});

const save = (body: Record<string, unknown>) =>
  app.inject({ method: 'PUT', url: '/admin/course/lessons', payload: body as never });
const del = (id: string) =>
  app.inject({ method: 'DELETE', url: `/admin/course/lessons/${id}` });
const lessons = async (publishedOnly: boolean) => repo.courseLessons('mama', publishedOnly);

const draft = (over: Record<string, unknown> = {}) => ({
  titleRu: 'Первые дни дома',
  titleKk: 'Үйдегі алғашқы күндер',
  youtubeUrl: 'https://youtu.be/dQw4w9WgXcQ',
  published: false,
  ...over,
});

describe('a lesson with no history can be deleted', () => {
  it('an unpublished draft nobody has opened goes for good', async () => {
    const id = (await save(draft())).json().id;
    const res = await del(id);
    expect(res.statusCode, res.body).toBe(200);
    expect(await lessons(false)).toEqual([]);
  });

  it('and it is recorded, because somebody did it', async () => {
    const id = (await save(draft())).json().id;
    await del(id);
    const audit = (await repo.listAudit(20)).entries;
    expect(audit.some((a) => a.action === 'course_lesson_delete' && a.target === id)).toBe(true);
  });

  it('a lesson that never existed is a 404, not a silent success', async () => {
    const res = await del('00000000-0000-0000-0000-000000000000');
    expect(res.statusCode).toBe(404);
  });
});

describe('a lesson with history cannot', () => {
  it('published: refused, and it says to unpublish instead', async () => {
    const id = (await save(draft({ published: true }))).json().id;
    const res = await del(id);
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ error: 'has_history', published: true });
    // Naming the alternative matters: a refusal with no way forward is how
    // somebody ends up doing it in the database instead.
    expect(res.json().message).toContain('Снимите с публикации');
    expect((await lessons(false)).length).toBe(1);
  });

  it('watched: refused, and it counts the people whose progress it would erase', async () => {
    const id = (await save(draft({ published: true }))).json().id;
    // She has to own the course to have progress recorded at all.
    await app.inject({
      method: 'POST', url: '/admin/entitlements',
      payload: { phone: '+77001112233', feature: 'mama_course' } as never,
    });
    await app.inject({
      method: 'POST', url: '/course/progress',
      payload: { lessonId: id, positionSeconds: 600, completed: true } as never,
    });

    // Unpublished, to isolate the watch rule from the published rule —
    // otherwise this would pass for the wrong reason.
    await save(draft({ id, published: false }));

    const res = await del(id);
    expect(res.statusCode).toBe(409);
    expect(res.json()).toMatchObject({ error: 'has_history', published: false, watchers: 1 });
    expect(res.json().message).toContain('прогресс');
    expect((await lessons(false)).length).toBe(1);
  });

  it('unpublishing is the way out, and it is reversible', async () => {
    const id = (await save(draft({ published: true }))).json().id;
    expect((await lessons(true)).length).toBe(1);

    await save(draft({ id, published: false }));
    expect((await lessons(true)), 'still on sale after unpublishing').toEqual([]);
    // Still there — that is the whole difference from deleting it.
    expect((await lessons(false)).length).toBe(1);

    await save(draft({ id, published: true }));
    expect((await lessons(true)).length).toBe(1);
  });
});

// ---------------------------------------------------------------------------

async function openCourse(deleteAnswers: { ok: boolean; body: unknown }) {
  const html = readFileSync(PANEL, 'utf8');
  const errors: string[] = [];
  const vc = new VirtualConsole();
  vc.on('jsdomError', (e: Error) => errors.push(e.message));

  const LESSONS = {
    lessons: [{
      id: 'l1', titleRu: 'Первые дни дома', titleKk: 'Үйдегі күндер',
      youtubeUrl: 'https://youtu.be/dQw4w9WgXcQ', summaryRu: null, summaryKk: null,
      sort: 10, published: true,
    }],
  };

  const dom = new JSDOM(html, {
    runScripts: 'dangerously',
    pretendToBeVisual: true,
    url: 'http://localhost/admin',
    virtualConsole: vc,
    beforeParse(window) {
      window.HTMLCanvasElement.prototype.getContext = ((): unknown => {
        const noop = () => {};
        return new Proxy(
          { canvas: { width: 600, height: 170 }, createLinearGradient: () => ({ addColorStop: noop }), measureText: () => ({ width: 10 }) },
          { get: (t: Record<string, unknown>, k: string) => (k in t ? t[k] : noop), set: () => true },
        );
      }) as never;
      Object.defineProperty(window.HTMLElement.prototype, 'clientWidth', { get: () => 600 });
      window.scrollTo = () => {};
      Object.defineProperty(window, 'CSS', { value: { escape: (s: string) => s } });
      (window as unknown as { alert: (m: string) => void }).alert = () => {};
      (window as unknown as { confirm: () => boolean }).confirm = () => true;

      window.fetch = (async (path: string, init?: RequestInit) => {
        const p = String(path);
        if ((init?.method ?? 'GET') === 'DELETE') {
          return {
            ok: deleteAnswers.ok, status: deleteAnswers.ok ? 200 : 409,
            text: async () => '', json: async () => deleteAnswers.body,
          };
        }
        const body =
          p.includes('/admin/me') ? { staffId: 's1', role: 'owner', displayName: 'Ерен' }
          : p.includes('/admin/course/lessons') ? LESSONS
          : {};
        return { ok: true, status: 200, text: async () => '', json: async () => body };
      }) as never;
    },
  });

  const { window } = dom;
  await new Promise((r) => setTimeout(r, 250));
  window.document.querySelector('[data-view="course"]')!
    .dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 300));
  const del = window.document.querySelector('.ldel') as HTMLElement | null;
  del?.dispatchEvent(new window.MouseEvent('click', { bubbles: true }));
  await new Promise((r) => setTimeout(r, 250));

  return { window, errors, msg: (window.document.querySelector('#lessonMsg')?.textContent ?? '') };
}

describe('the panel repeats the refusal instead of swallowing it', () => {
  it('shows the server reason on a refused delete', async () => {
    // It was a fire-and-forget inside `catch {}`. A 409 redrew an unchanged
    // list, which reads as "nothing happened because there was nothing to do".
    const { msg, errors } = await openCourse({
      ok: false,
      body: {
        error: 'has_history', published: true, watchers: 0,
        message: 'Опубликованный урок нельзя удалить. Снимите с публикации.',
      },
    });
    expect(errors, errors.join('\n')).toEqual([]);
    expect(msg).toContain('Снимите с публикации');
  });

  it('says so when it really did delete something', async () => {
    const { msg } = await openCourse({ ok: true, body: { ok: true } });
    expect(msg).toContain('удалён');
  });
});
