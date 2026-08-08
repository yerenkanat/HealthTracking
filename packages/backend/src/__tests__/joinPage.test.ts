/**
 * `/join/<token>` — where an invitation link lands.
 *
 * Screen 40 hands a mother a link to send to the father, and until this route
 * existed that link went to a 404: the whole feature built, and the one thing
 * a relative actually touches doing nothing.
 */

import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import Fastify, { type FastifyInstance } from 'fastify';
import { registerJoinPage, joinPageHtml } from '../http/joinPage';

let app: FastifyInstance;

beforeAll(async () => {
  app = Fastify({ logger: false });
  registerJoinPage(app);
  await app.ready();
});
afterAll(async () => { await app.close(); });

const TOKEN = 'abcDEF123_-xyzABC456';

describe('the page', () => {
  it('shows the code, so it can be copied into the app', async () => {
    const r = await app.inject({ method: 'GET', url: `/join/${TOKEN}` });
    expect(r.statusCode).toBe(200);
    expect(r.headers['content-type']).toContain('text/html');
    expect(r.body).toContain(TOKEN);
  });

  it('says what to do with it, in both languages', async () => {
    // Nobody reaches this page except by tapping a link sent by a mother in
    // Kazakhstan, so it is Russian and Kazakh and not English.
    const r = await app.inject({ method: 'GET', url: `/join/${TOKEN}` });
    expect(r.body).toContain('Семейный доступ');
    expect(r.body).toContain('Отбасылық қолжетімділік');
  });

  it('repeats the privacy promise to the person being invited', async () => {
    // He is about to accept. He should know what he is and is not getting,
    // and so should she when she reads the page over his shoulder.
    const r = await app.inject({ method: 'GET', url: `/join/${TOKEN}` });
    expect(r.body).toMatch(/Здоровье, цикл и дневник мамы остаются закрытыми/);
  });

  it('does not accept anything', async () => {
    // The person here is not signed in to anything. A page that "accepted"
    // would be accepting on behalf of nobody.
    const r = await app.inject({ method: 'GET', url: `/join/${TOKEN}` });
    expect(r.body).not.toContain('/family/invites/accept');
    expect(r.body).not.toMatch(/<form/i);
  });

  it('is never cached — the code is in the URL', async () => {
    const r = await app.inject({ method: 'GET', url: `/join/${TOKEN}` });
    expect(r.headers['cache-control']).toContain('no-store');
  });

  it('does not say whether the code is real', async () => {
    // Checking would tell anyone who guessed a token whether it existed, and
    // is worth nothing to somebody holding a real one — they find out in the
    // app, where they are signed in and the refusal can be specific.
    const a = await app.inject({ method: 'GET', url: `/join/${TOKEN}` });
    const b = await app.inject({ method: 'GET', url: '/join/completelyMadeUpToken1' });
    expect(a.statusCode).toBe(b.statusCode);
  });

  it('refuses a shape that is not a token, as a page not as JSON', async () => {
    const r = await app.inject({ method: 'GET', url: '/join/nope' });
    expect(r.statusCode).toBe(404);
    expect(r.headers['content-type']).toContain('text/html');
    // Whoever is here opened a link in a browser; a JSON error is no use.
    expect(r.body).not.toContain('"error"');
  });

  it('escapes what it prints', async () => {
    // The route's pattern already admits only base64url, so this can only be
    // reached by calling the builder directly — which is exactly why the
    // escaping is here as well as the guard. Two mistakes, not one.
    const html = joinPageHtml('<script>alert(1)</script>');
    expect(html).not.toContain('<script>alert(1)</script>');
    expect(html).toContain('&lt;script&gt;');
  });
});
